# Texture pipeline (removed for repo size)

The mob sprite strips in `../textures/` (`sl_scary_dredger_strip.png`,
`sl_scary_wraith_strip.png`, `sl_scary_containment_strip.png`,
`sl_scary_signal_wraith.png`) were generated with the Seirin pipeline:
stb_image decode, matte flood-fill, Mitchell downscale, 3-color palette
enforced (144x16 strips, 9 frames: idle/walk/attack/death).

The ~378 KB toolchain (stb_image.h, stb_image_write.h, downscale_filter.c,
matte_floodfill.c) was dropped from this branch to keep the repo small.
It is preserved on branch `arena/01a0436b-systemtest` in this same
directory if you need to regenerate the strips.
