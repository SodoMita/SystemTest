# Release process — itch.io (delatel/systemloot)

## Cutting a release

```bash
git checkout build
git merge master        # build branch = release train
git push origin build   # triggers .github/workflows/release.yml
```

Or: GitHub → Actions → **release** → *Run workflow* on the `build` branch.

## Channels

| Channel   | Artifact                                                        | Notes |
|-----------|-----------------------------------------------------------------|-------|
| `windows` | `SystemLoot-Windows.zip` — official Luanti 5.17.0 win64 + game  | game at `games/SystemTest/` |
| `osx`     | arm64 + x86_64 `.app` bundles, game embedded in `Contents/Resources/games/` | `__MACOSX` junk excluded |
| `linux`   | `SystemLoot-Linux.tar.gz` — portable bundle: engine + share data + ldd libs + `run-game.sh` | relocated engine is `--version` smoke-checked before upload |
| `android` | official 5.17 APKs (arm64-v8a, armeabi-v7a, x86_64) repacked with the game injected into the nested `assets/assets.zip`, zipaligned, debug-signed (`tools/repack_apk.py`) | no engine rebuild; repack+sign verified locally with `apksigner verify` |
| `web`     | real WASM client built from [paradust7/luanti-wasm](https://github.com/paradust7/luanti-wasm) (emscripten), game embedded in the virtual FS (`build/fsroot/luanti/games/SystemTest`) | network play runs through the standard WebSocket proxies; a dedicated 24/7 SystemTest server is a separate hosting task |

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
