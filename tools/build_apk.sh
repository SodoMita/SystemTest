#!/bin/bash
# Build a SystemLoot-branded APK from an official Luanti APK.
#
#   build_apk.sh <base_official.apk> <game_dir> <keystore> <out.apk>
#
# Chain: inject game into nested assets/assets.zip (repack_apk.py)
#      -> apktool decode
#      -> label "SystemLoot", launcher icon from <game_dir>/menu/icon.png,
#         package/authorities renamed to io.itch.delatel.systemloot
#         (installs side-by-side with official Luanti/Minetest)
#      -> apktool build (--use-aapt2), zipalign, debug-sign, verify.
#
# Validated locally end-to-end: apksigner verify passes, aapt badging shows
# the SystemLoot label/package, all game files present in the signed APK.
set -eu

BASE_APK="$1"
GAME_DIR="$2"
KEYSTORE="$3"
OUT_APK="$4"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/repack_apk.py" "$BASE_APK" "$GAME_DIR" "$WORK/injected.apk"

apktool d -q -f "$WORK/injected.apk" -o "$WORK/work"

# Identity: label, package, authorities
sed -i 's|<string name="label">[^<]*</string>|<string name="label">SystemLoot</string>|' \
    "$WORK/work/res/values/strings.xml"
sed -i \
    -e 's|package="net.minetest.minetest"|package="io.itch.delatel.systemloot"|' \
    -e 's|net.minetest.minetest.fileprovider|io.itch.delatel.systemloot.fileprovider|g' \
    -e 's|net.minetest.minetest.androidx-startup|io.itch.delatel.systemloot.androidx-startup|' \
    -e 's|net.minetest.minetest.documents|io.itch.delatel.systemloot.documents|' \
    "$WORK/work/AndroidManifest.xml"

# Icon: repo menu icon resized to the launcher icon dimensions
python3 - "$GAME_DIR" "$WORK/work" <<'PYEOF'
import sys
from PIL import Image
game_dir, work = sys.argv[1], sys.argv[2]
import glob
for icon in glob.glob(f"{work}/res/mipmap*/ic_launcher.png"):
    old = Image.open(icon)
    Image.open(f"{game_dir}/menu/icon.png").convert("RGBA").resize(old.size, Image.LANCZOS).save(icon)
    print("icon swapped:", icon)
PYEOF

apktool b "$WORK/work" -o "$WORK/rebuilt.apk" --use-aapt2

audit_sizes() {
    python3 - "$1" <<'PYAUDIT'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
total = 0
for i in sorted(z.infolist(), key=lambda x: -x.compress_size)[:6]:
    m = {0: "STORED", 8: "DEFLATED"}.get(i.compress_type, str(i.compress_type))
    print(f"  {i.filename}: {m} raw={i.file_size//1048576}MB packed={i.compress_size//1048576}MB")
    total += i.compress_size
print(f"  top6 packed total: {total//1048576}MB")
PYAUDIT
}
echo "[audit] rebuilt.apk ($(stat -c%s "$WORK/rebuilt.apk") bytes):"; audit_sizes "$WORK/rebuilt.apk"
python3 "$SCRIPT_DIR/slim_apk.py" "$WORK/rebuilt.apk" "$WORK/slim.apk"
echo "[audit] slim.apk ($(stat -c%s "$WORK/slim.apk") bytes):"; audit_sizes "$WORK/slim.apk"
zipalign -f 4 "$WORK/slim.apk" "$WORK/aligned.apk"
echo "[audit] aligned.apk: $(stat -c%s "$WORK/aligned.apk") bytes"

apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android \
    --out "$OUT_APK" "$WORK/aligned.apk"
apksigner verify "$OUT_APK"
echo "[audit] final: $(stat -c%s "$OUT_APK") bytes"

# Assert the identity actually took
BADGING="$(aapt dump badging "$OUT_APK" 2>/dev/null)"
echo "$BADGING" | grep -q "package: name='io.itch.delatel.systemloot'" || { echo "package rename failed"; exit 1; }
echo "$BADGING" | grep -q "application-label:'SystemLoot'" || { echo "label change failed"; exit 1; }

# Size guard: official base is 15-17 MB + ~8 MB game. Anything past 60 MB
# means compression regressed again.
SIZE_MB=$(( $(stat -c%s "$OUT_APK") / 1048576 ))
[ "$SIZE_MB" -le 60 ] || { echo "APK unexpectedly large: ${SIZE_MB} MB (compression regression?)"; exit 1; }
echo "built $(basename "$OUT_APK"): SystemLoot / io.itch.delatel.systemloot / ${SIZE_MB} MB"
