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
| `android` | debug-signed APK rebuilt from engine source with the game embedded | needs `gettext` (msgfmt) on the runner; `continue-on-error` until it has a long green streak |
| `web`     | placeholder page | Luanti has **no official wasm port** (as of 5.17) — the page says so honestly instead of shipping a broken build |

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
5. Engine Android build needs `msgfmt` (`apt-get install gettext`).
6. `broth.itch.ovh` may not resolve from runners — butler comes from
   GitHub releases.
