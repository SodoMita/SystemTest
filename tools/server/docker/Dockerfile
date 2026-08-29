# System Looting — full public server image (engine + game + web client + WS proxy)
# Works on: any Debian/Ubuntu VPS (x86_64 or arm64, incl. Oracle Always Free ARM),
# and Hugging Face Spaces (PORT=7860, browser-only play).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      luanti-server nodejs npm git curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

# Game (repo HEAD)
RUN git clone --depth 1 https://github.com/SodoMita/SystemTest /app/game

# Web client (published WASM build from the gh-pages branch) + proxy
RUN git clone --depth 1 --branch gh-pages https://github.com/SodoMita/SystemTest /app/pages \
    && mkdir -p /app/tools && cp /app/game/tools/server/docker/allinone.js /app/tools/ \
    && cd /app/tools && npm install --no-audit --no-fund ws

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 30000/udp 30000/tcp 8080
ENV PORT=8080
ENTRYPOINT ["/app/entrypoint.sh"]
