#!/usr/bin/env python3
"""End-to-end web-multiplayer path test for System Looting.

Replicates exactly what the browser WASM client does:
  1. open WebSocket to the relay proxy (default wss://luanti.dustlabs.io/proxy)
  2. send a Luanti connection-request encapsulated in the emsocket
     12-byte header (magic 0x778B4CF3, dest IP, dest port, length)
  3. wait for an encapsulated reply relayed from the game server

Verdict:
  PROXY reachable + SERVER replies  -> web multiplayer WILL work in browser
  PROXY reachable + SERVER silent   -> server/firewall problem (fix server)
  PROXY unreachable                 -> proxy outage / network block

Usage: python3 tests/web/e2e_proxy_test.py [server_ip] [port] [proxy_url]
"""
import socket
import struct
import sys
import time

try:
    import websockets.sync.client as wsclient
except ImportError:
    print("pip install websockets  (required)")
    sys.exit(2)

EP_MAGIC = 0x778B4CF3
LUANTI_PROTOCOL_ID = 0x4F454445  # "OEDE"


def encapsulate(ip: str, port: int, payload: bytes) -> bytes:
    return (
        struct.pack(">I", EP_MAGIC)
        + socket.inet_aton(ip)
        + struct.pack(">HH", port, len(payload))
        + payload
    )


def main() -> int:
    server_ip = sys.argv[1] if len(sys.argv) > 1 else "147.185.221.230"
    server_port = int(sys.argv[2]) if len(sys.argv) > 2 else 6323
    proxy_url = sys.argv[3] if len(sys.argv) > 3 else "wss://luanti.dustlabs.io/proxy"

    # Luanti connection request: protocol id, peer 0, channel 0, CONNECTION_REQUEST
    peer_init = struct.pack(">IHBb", LUANTI_PROTOCOL_ID, 0, 0, 0)

    print(f"proxy : {proxy_url}")
    print(f"server: {server_ip}:{server_port} (udp, relayed)")

    t0 = time.time()
    try:
        headers = {
            "Origin": "https://sodomita.github.io",
            "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                           "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"),
        }
        with wsclient.connect(proxy_url, open_timeout=10, additional_headers=headers) as conn:
            print(f"PROXY reachable ({(time.time()-t0)*1000:.0f} ms)")
            # Handshake REQUIRED before the proxy relays anything:
            # text request 'PROXY IPV4 UDP <ip> <port>', expect 'PROXY OK'.
            conn.send(f"PROXY IPV4 UDP {server_ip} {server_port}")
            hs = conn.recv(timeout=10)
            hs_text = hs.decode(errors="replace") if isinstance(hs, (bytes, bytearray)) else str(hs)
            print(f"handshake: {hs_text.strip()!r}")
            if "PROXY OK" not in hs_text:
                print(f"VERDICT: PROXY REFUSED RELAY ({hs_text.strip()!r})")
                return 2
            # PROXY mode relays RAW payloads (the 12-byte EP_MAGIC header is
            # VPN-mode only) — send the bare Luanti peer-init.
            conn.send(peer_init)
            # Luanti clients retry peer-init a few times; mimic that.
            deadline = time.time() + 12
            attempts = 0
            while time.time() < deadline:
                try:
                    msg = conn.recv(timeout=2)
                except TimeoutError:
                    attempts += 1
                    if attempts < 4:
                        conn.send(peer_init)
                    continue
                if isinstance(msg, (bytes, bytearray)) and len(msg) >= 8:
                    print(f"SERVER REPLIED via proxy: {len(msg)} bytes, "
                          f"first bytes {msg[:12].hex()}")
                    if msg[:4] == struct.pack(">I", LUANTI_PROTOCOL_ID):
                        print("VERDICT: FULL CHAIN OK — browser web multiplayer WILL work "
                              f"against {server_ip}:{server_port}")
                        return 0
                    print("VERDICT: reply received but not Luanti protocol — check server type")
                    return 1
    except Exception as e:
        print(f"VERDICT: PROXY UNREACHABLE/CHANNEL ERROR ({e})")
        return 2
    print(f"VERDICT: PROXY OK, SERVER SILENT — {server_ip}:{server_port} is not "
          "answering Luanti UDP. Fix the server: process running? UDP port open "
          "in firewall/security group? correct port?")
    return 1


if __name__ == "__main__":
    sys.exit(main())
