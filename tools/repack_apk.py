#!/usr/bin/env python3
"""Repack an official Luanti Android APK with the SystemTest game embedded.

Usage: repack_apk.py <base.apk> <game_dir> <out_unsigned.apk>

The Android port stores engine data (builtin/, textures/, fonts/, ...) in a
nested `assets/assets.zip` which is unpacked to app storage on first launch.
The 5.17 APK ships no games at all, so we inject `games/SystemTest/` into
that nested zip and rebuild the APK without the original signature blocks
(META-INF/*). The caller must then zipalign + apksigner-sign the result.

Validated locally: apksigner verify passes and the game is present in the
signed APK's assets.zip (see docs/RELEASE.md).
"""
import os
import sys
import zipfile

EXCLUDE_DIRS = {".git", ".github"}


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    base_apk, game_dir, out_apk = sys.argv[1:4]

    # 1) Rebuild the nested assets.zip with the game injected.
    assets_tmp = out_apk + ".assets.zip"
    src = zipfile.ZipFile(base_apk)
    if "assets/assets.zip" not in src.namelist():
        print("ERROR: base APK has no assets/assets.zip — unexpected layout")
        return 1
    inner = zipfile.ZipFile(src.open("assets/assets.zip"))
    out = zipfile.ZipFile(assets_tmp, "w", zipfile.ZIP_DEFLATED)
    for item in inner.infolist():
        out.writestr(item, inner.read(item.filename))
    count = 0
    for dirpath, dirnames, filenames in os.walk(game_dir):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for f in filenames:
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, game_dir)
            out.write(full, "games/SystemTest/" + rel)
            count += 1
    out.close()
    inner.close()

    # 2) Rebuild the APK: swap assets.zip, drop old signature blocks.
    new = zipfile.ZipFile(out_apk, "w", zipfile.ZIP_DEFLATED)
    for item in src.infolist():
        if item.filename.startswith("META-INF/"):
            continue
        if item.filename == "assets/assets.zip":
            new.write(assets_tmp, "assets/assets.zip")
        else:
            new.writestr(item, src.read(item.filename))
    new.close()
    src.close()
    os.remove(assets_tmp)
    print(f"repacked {base_apk}: {count} game files injected -> {out_apk}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
