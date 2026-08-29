#!/usr/bin/env python3
"""SystemLoot CI: patch luanti-wasm engine pack installer.

Upstream src/mainloop.cpp (paradust7/luanti fork) aborts pack
installation when libarchive reports no zstd filter. The CI-built wasm
libarchive lacks HAVE_ZSTD (configure silently misses zstd despite
--with-zstd). SystemLoot ships base.pack as uncompressed tar, so the
abort is replaced with a warning and installation continues (tar-only).
Fails loudly if upstream code changed shape.
"""
p = "sources/luanti/src/mainloop.cpp"
s = open(p).read()
old = (
    "    if (archive_read_support_filter_zstd(a) != ARCHIVE_OK) {\n"
    '        std::cout << "emloop_install_pack failed: zstd not supported" << std::endl;\n'
    "        return;\n"
    "    }"
)
new = (
    "    if (archive_read_support_filter_zstd(a) != ARCHIVE_OK) {\n"
    "        // Patched by SystemLoot CI: continue without zstd; the\n"
    "        // SystemLoot base.pack is uncompressed tar.\n"
    '        std::cout << "emloop_install_pack: zstd filter unavailable; continuing (tar-only pack)" << std::endl;\n'
    "    }"
)
assert old in s, "mainloop.cpp zstd-abort block not found (upstream changed shape?)"
open(p, "w").write(s.replace(old, new))
print("mainloop.cpp patched: tar-only pack install")
