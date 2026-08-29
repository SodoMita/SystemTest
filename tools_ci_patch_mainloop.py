#!/usr/bin/env python3
"""SystemLoot CI: patch luanti-wasm engine pack installer.

The engine fork's pack installer aborts when libarchive reports no zstd
filter — and the CI-built wasm libarchive lacks HAVE_ZSTD (configure
silently misses zstd despite --with-zstd). SystemLoot ships its packs as
uncompressed tar, so the zstd branch is downgraded to a warning and tar
registration proceeds.

Handles both known upstream shapes:
  A) fatal early-return form   (pins <= 134d7da, emloop_install_pack)
  B) else-if short-circuit form (pins >= 6162abc, unpack() helper)
Fails loudly if neither shape matches (upstream drifted again).
Becomes a no-op naturally once upstream ships working wasm zstd and the
branches no longer match... (it would then fail loudly instead — adjust
or remove this script at that point).
"""

p = "sources/luanti/src/mainloop.cpp"
s = open(p).read()

# Shape A: fatal early return
old_a = (
    "    if (archive_read_support_filter_zstd(a) != ARCHIVE_OK) {\n"
    '        std::cout << "emloop_install_pack failed: zstd not supported" << std::endl;\n'
    "        return;\n"
    "    }"
)
new_a = (
    "    if (archive_read_support_filter_zstd(a) != ARCHIVE_OK) {\n"
    "        // Patched by SystemLoot CI: continue without zstd; the\n"
    "        // SystemLoot packs are uncompressed tar.\n"
    '        std::cout << "emloop_install_pack: zstd filter unavailable; continuing (tar-only pack)" << std::endl;\n'
    "    }"
)

# Shape B: else-if short-circuit chain
old_b = (
    "    if (archive_read_support_filter_zstd(a) != ARCHIVE_OK) {\n"
    '        std::cout << "emloop_install_pack failed: zstd not supported" << std::endl;\n'
    "    } else if (archive_read_support_format_tar(a) != ARCHIVE_OK) {"
)
new_b = (
    "    if (archive_read_support_filter_zstd(a) != ARCHIVE_OK) {\n"
    "        // Patched by SystemLoot CI: continue without zstd; the\n"
    "        // SystemLoot packs are uncompressed tar.\n"
    '        std::cout << "emloop_install_pack: zstd filter unavailable; continuing (tar-only pack)" << std::endl;\n'
    "    }\n"
    "    if (archive_read_support_format_tar(a) != ARCHIVE_OK) {"
)

if old_a in s:
    s = s.replace(old_a, new_a)
    shape = "A (fatal-return)"
elif old_b in s:
    s = s.replace(old_b, new_b)
    shape = "B (else-if chain)"
elif "zstd not supported" not in s:
    # Upstream removed the check entirely — nothing to patch.
    print("mainloop.cpp has no zstd abort — upstream fixed it; no patch needed")
    raise SystemExit(0)
else:
    raise SystemExit(
        "mainloop.cpp zstd-abort found in unknown shape — upstream drifted; "
        "update tools_ci_patch_mainloop.py"
    )

open(p, "w").write(s)
print(f"mainloop.cpp patched (shape {shape}): tar-only pack install")
