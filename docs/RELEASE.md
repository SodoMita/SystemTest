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
