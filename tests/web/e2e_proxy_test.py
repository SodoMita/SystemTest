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
        with wsclient.connect(proxy_url, open_timeout=10) as conn:
            print(f"PROXY reachable ({(time.time()-t0)*1000:.0f} ms)")
            conn.send(encapsulate(server_ip, server_port, peer_init))
            # Luanti clients retry peer-init a few times; mimic that.
            deadline = time.time() + 12
            attempts = 0
            while time.time() < deadline:
                try:
                    msg = conn.recv(timeout=2)
                except TimeoutError:
                    attempts += 1
                    if attempts < 4:
                        conn.send(encapsulate(server_ip, server_port, peer_init))
                    continue
                if isinstance(msg, (bytes, bytearray)) and len(msg) >= 12:
                    magic, src_ip_raw, src_port, pktlen = struct.unpack(">I4sHH", msg[:12])
                    if magic == EP_MAGIC:
                        src_ip = socket.inet_ntoa(src_ip_raw)
                        payload = msg[12:]
                        print(f"SERVER REPLIED via proxy: {src_ip}:{src_port} "
                              f"({len(payload)} bytes, first bytes {payload[:12].hex()})")
                        if payload[:4] == struct.pack(">I", LUANTI_PROTOCOL_ID):
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
