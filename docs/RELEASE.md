# Release process — itch.io (delatel/systemloot)

## Cutting a release

```bash
git checkout build
git merge master        # build branch = release train
git push origin build   # triggers .github/workflows/release.yml
```

Or: GitHub → Actions → **release** → *Run workflow* on the `build` branch.

## Channels

Engine version is resolved at build time from the latest luanti-org
release (no pinning).

| Channel   | Artifact                                                        | Notes |
|-----------|-----------------------------------------------------------------|-------|
| `windows` | `SystemLoot-Windows.zip` — latest official win64 + game         | game at `games/SystemTest/` |
| `osx`     | arm64 + x86_64 `.app` bundles, game embedded in `Contents/Resources/games/` | `__MACOSX` junk excluded |
| `linux`   | `SystemLoot-Linux.tar.gz` — portable bundle: engine + `builtin/` + `textures/` + `fonts/` + locale + non-glibc libs + game + `run-game.sh` (defaults `--gameid SystemTest`) | CI boots a real headless server from the bundle and requires engine-ready + sl_modebase-loaded before upload. Non-glibc libs only: requires system glibc ≥ 2.39 (built on Ubuntu 24.04 runners) |
| `android-arm64-v8a` / `android-armeabi-v7a` / `android-x86_64` | **one channel per ABI** (separate itch downloads), each a SystemLoot-branded APK | `tools/build_apk.sh`: game injected into nested `assets/assets.zip`, label **SystemLoot**, icon from `menu/icon.png`, package renamed to `io.itch.delatel.systemloot` (installs side-by-side with official Luanti/Minetest; note: renaming means no update path from any older `net.minetest.minetest`-packaged test APK — uninstall those), zipaligned + debug-signed + badging-asserted |
| `web`     | real WASM client built from [paradust7/luanti-wasm](https://github.com/paradust7/luanti-wasm) (emscripten), SystemTest embedded in the virtual FS, **minetest_game removed**, launcher default `gameid` hardcoded to `SystemTest` (`?gameid=` URL param still overrides) | **itch caveat:** inside the itch embed (html.itch.zone iframe) no service worker can isolate the top-level page — the threaded WASM needs cross-origin isolation, so on itch you must tick **SharedArrayBuffer support** (Edit game → Embed options → Frame options) once. Pop-out mode works regardless. |
| GitHub Pages — https://sodomita.github.io/SystemTest/ | same WASM build, published by the `web-pages` job to `gh-pages` | served **top-level**, so the bundled coi-serviceworker provides COOP/COEP automatically — this is the web build that boots with zero manual steps |

## Web multiplayer — architecture reality (read before "it can't connect" reports)

Browser WASM cannot open TCP/UDP sockets. The web client reaches Luanti
servers only through a WebSocket->UDP proxy (default
`wss://luanti.dustlabs.io/proxy`; override per-region with
`?proxy=wss://eu1.dustlabs.io/mtproxy` on the page URL). Consequences:

- A server on your LAN is UNREACHABLE from the web build — the proxy
  lives on the internet and cannot see your home network. `0.0.0.0`
  never works (from the proxy's view that is the proxy's own machine).
- LAN multiplayer works only in the native builds (Linux/Windows/macOS
  tarball+exe, Android APK) — connect by LAN IP there, as usual.
- The in-game public server list will not show SystemTest servers until
  one is publicly hosted (and list fetches through the proxy can be
  flaky; direct-address join is the reliable path).

### Hosting a public SystemTest server (the web-multiplayer prerequisite)

1. Any VPS with a public IP and an open UDP port (e.g. 30000).
2. `SystemLoot-Linux.tar.gz` from the itch linux channel; extract; run:
   `./run-game.sh --server --world /var/lib/systemloot/world --port 30000`
   (world.mt: `gameid = SystemTest`, `mg_name = singlenode`).
3. Web players: join by address `your-vps-ip:30000` (in-game menu, or
   page URL `?go&server&address=your-vps-ip&port=30000`).
4. Optional: `server_announce = true` to appear in the public list for
   native clients.

## Auth

Butler authenticates with the **`ITCH_API_KEY`** repository secret
(itch.io API key, stored encrypted). Rotate via
*repo → Settings → Secrets and variables → Actions*.

## Gotcha ledger (learned the hard way, run 33161682366 → 33162434458)

1. Never extract download artifacts inside the checkout — `rsync ./`
   recurses into itself. Bundle in `mktemp -d`.
2. butler GitHub zips keep the binary under `linux-amd64/` with its `.so`s.
3. macOS zips carry `__MACOSX` AppleDouble entries — exclude on unzip or
   `.app` discovery breaks.
4. Ubuntu runners ship the engine as a real ELF (`/usr/bin`), Debian wraps
   it in a shell script — binary resolution must handle both.
5. `broth.itch.ovh` may not resolve from runners — butler comes from
   GitHub releases.
6. A WASM port DOES exist (paradust7/luanti-wasm, actively maintained) —
   the earlier "no web port" claim was wrong; absence from luanti-org
   release assets is not absence from the ecosystem. Search properly.
7. Android APKs keep engine data in a nested `assets/assets.zip` and ship
   NO games (5.17) — inject `games/<id>/` there, drop `META-INF/*`,
   zipalign, re-sign.
