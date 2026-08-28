#!/usr/bin/env python3
"""Recompress lib/*.so entries in an APK (deflate).

apktool/aapt2 rebuilds store native libraries UNCOMPRESSED, inflating
SystemLoot APKs far beyond the official bases (armeabi 15->53 MB,
x86_64 17->102 MB). The manifest declares extractNativeLibs="true", so
compressed libs are the original shipping format and are valid at
runtime. Everything else in the archive is copied verbatim.
Usage: slim_apk.py <in.apk> <out.apk>
"""
import sys
import zipfile


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src_path, dst_path = sys.argv[1], sys.argv[2]
    src = zipfile.ZipFile(src_path)
    dst = zipfile.ZipFile(dst_path, "w")
    slimmed = 0
    for item in src.infolist():
        data = src.read(item.filename)
        if item.filename.startswith("lib/") and item.filename.endswith(".so"):
            dst.writestr(item, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
            slimmed += 1
        else:
            dst.writestr(item, data, compress_type=item.compress_type)
    dst.close()
    src.close()
    print(f"slimmed {slimmed} native libs in {dst_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
