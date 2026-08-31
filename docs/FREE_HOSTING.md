# Free hosting options for a public System Looting server (2026)

Goal: a server that other people can join from anywhere, at $0 cost.
Everything here was researched and prepared in August 2026. All scripts/artifacts
live in `tools/server/` and `tools/server/docker/`.

> **Reality check:** every free option needs *one* thing from you — an account
> (email / Google / GitHub) or a card just for identity verification (never
> charged on free tiers). No provider lets a bot create accounts, so pick the
> row that matches what you're willing to do.

## The options, ranked

| # | Option | What you get | You need | Server lifetime | Best for |
|---|---|---|---|---|---|
| 1 | **Oracle Cloud Always Free** | 4 ARM cores, 24 GB RAM, 200 GB disk, 10 TB/mo traffic — free **forever** | Oracle account + card for verification (not charged) | years | The real free VPS. Best answer overall. |
| 2 | **Google Colab + playit.gg** | Full Ubuntu VM on Google infra, free | Google account only (no card) | ~12 h per session, then rerun | Instant free server today, no card at all. |
| 3 | **Your own PC + playit.gg** | Your machine, public address via free tunnel | PC you can leave on | as long as it's on | Already scripted: `host_public.sh`. |
| 4 | **Hugging Face Spaces** | Free Docker space, browser-playable | HF account (email only) | sleeps after ~48 h idle, wakes on visit | Free browser-only server, no card. |
| 5 | **Any $3–6/mo VPS** (Hetzner, Timeweb, Vultr, RackNerd) | Reliable x86, no free-tier traps | card | forever | If free tiers frustrate you; still ~cheap. |

**Skip:** ngrok and Cloudflare Tunnel — **no UDP support**, and Luanti's game
protocol is UDP-only (native clients can never connect through them). AWS/Azure
12-month free tiers work but expire; GCP e2-micro works but only 1 GB RAM and
1 GB/mo traffic.

---

## Option 1 — Oracle Cloud Always Free (recommended, permanent)

1. Sign up at https://signup.cloud.oracle.com (email + card for verification;
   you are **not** charged on the Always Free tier; it's a card check).
2. Create an instance: **Ampere A1 (ARM)**, Ubuntu 24.04, any shape up to
   4 OCPU / 24 GB RAM, assign a public IP, open ports in the security list
   (ingress **UDP 30000** and **TCP 30000**).
3. SSH in and run our one-shot deployer (engine + game + systemd + firewall):

   ```bash
   curl -sSL https://raw.githubusercontent.com/SodoMita/SystemTest/arena/01a04bf2-systemtest/tools/server/deploy_vps.sh -o deploy_vps.sh
   sudo bash deploy_vps.sh
   ```

4. Done: players join `<instance-ip>:30000`; it also self-announces to the
   Luanti server list (`server_announce = true`).

Notes: "out of capacity" errors on ARM are common — retry in another region
(also free) or pick the free AMD shape (1 core, 1 GB — enough for ~8 players).
Oracle may reclaim idle instances after 7 days of zero CPU: the game server
counts as activity; if it ever gets stopped, just start it again.

## Option 2 — Google Colab + playit.gg (no card, works today)

Free Colab VMs have full internet access (unlike some sandboxes), so playit.gg
works there. We built a ready notebook:

- `tools/server/systemloot_colab.ipynb` — open it at
  `https://colab.research.google.com/github/SodoMita/SystemTest/blob/arena/01a04bf2-systemtest/tools/server/systemloot_colab.ipynb`
  (or: colab.research.google.com → GitHub → paste the repo path) and hit
  **Runtime → Run all**.
- It installs the engine, starts the server, downloads the playit agent and
  prints your **claim link** → open it, create the free playit account, add a
  UDP tunnel on port 30000 → playit gives you a public address to share.

Limits: ~12 h sessions, ~90 min idle timeout, VM wiped after (world resets —
the notebook has an optional Google Drive backup cell). Great for play sessions.

## Option 3 — your own PC + playit.gg (already scripted)

```bash
curl -sSL https://raw.githubusercontent.com/SodoMita/SystemTest/arena/01a04bf2-systemtest/tools/server/host_public.sh -o host_public.sh
bash host_public.sh
```

Installs engine + game, starts the server, downloads playit, prints the claim
flow. Best if you have a PC that can stay on (works behind CGNAT — common on
Russian home ISPs).

## Option 4 — Hugging Face Spaces (browser-only, no card)

Luanti can't do UDP through HF, but the **browser client** can (it uses
WebSocket→TCP). We prepared a full image (`tools/server/docker/`) that runs
engine + game + web client + WebSocket proxy in one container:

1. https://huggingface.co/new-space → Docker space (any name, e.g.
   `systemloot`), **private**.
2. Files → upload `tools/server/docker/Dockerfile`, `entrypoint.sh`,
   `allinone.js`, `docker-compose.yml` (or push them via git; the Dockerfile
   clones everything itself).
3. Settings → set **Port: 7860** (the image listens there).
4. Wait for the build (~2–5 min), then open `https://<user>-systemloot.hf.space`
   → **Launch Luanti** → *This server* proxy → **Join Server** → `127.0.0.1:30000`.

Free tier sleeps after ~48 h without visitors and wakes on demand. Browser
players only — native clients need Options 1–3.

## Option 5 — paid VPS (sanity option)

Same `deploy_vps.sh` works. $3–6/mo avoids all free-tier traps (capacity,
idle reclamation, egress caps). Timeweb Cloud / Hetzner are popular in RU/EU.

---

## What's already in the repo

| File | Purpose |
|---|---|
| `tools/server/host_public.sh` | own machine → public server via playit (native clients) |
| `tools/server/deploy_vps.sh` | fresh Debian/Ubuntu VPS → public server (systemd, ufw, announce) |
| `tools/server/systemloot_colab.ipynb` | Google Colab → public server via playit, no card |
| `tools/server/docker/` | Docker image: engine + game + web client + WS proxy (HF Spaces / any VPS) |
| `docs/PUBLIC_DEPLOY.md` | playit/VPS/port-forward walkthrough + verification |
| `docs/DEPLOY_SERVER.md` | server config, admin commands, troubleshooting |
