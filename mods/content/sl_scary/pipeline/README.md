# Texture pipeline (removed for repo size)

The mob sprite strips in `../textures/` (`sl_scary_dredger_strip.png`,
`sl_scary_wraith_strip.png`, `sl_scary_containment_strip.png`) were
generated with the Seirin pipeline: stb_image decode, matte flood-fill,
Mitchell downscale, 3-color palette enforced.

The ~378 KB toolchain (stb_image.h, stb_image_write.h,
downscale_filter.c, matte_floodfill.c) was dropped from this branch to
keep the repo small. It is preserved on branch
`arena/01a0436b-systemtest` in this same directory if you need to
regenerate the strips.

## Layout note — strips are VERTICAL now

The Seirin toolchain emits **horizontal** strips (144x16: nine 16x16
frames laid left-to-right). Luanti plays `sprite` visuals with
`object:set_sprite(...)` and iterates animation frames along the frame
**y** position (see `lua_api.md` -> `set_sprite`), so a horizontal strip
cannot animate and renders as one undivided sheet.

The shipped strips are therefore **16x144 vertical** (nine 16x16 frames
stacked top-to-bottom, `spritediv = {x=1, y=9}` in
`sl_scary/init.lua`). They were produced from the toolchain's output
with `transpose_sprite_strip.py` in this directory — a pixel-verbatim
block transpose (no resampling):

```sh
# after regenerating a horizontal strip with the Seirin toolchain:
python3 transpose_sprite_strip.py \
    ../textures/sl_scary_dredger_strip.png \
    ../textures/sl_scary_dredger_strip.png --frames 9
```

If the toolchain is ever changed to emit vertical strips natively, this
step becomes a no-op; keep the same frame order (idle rows 0-2, walk
3-5, attack 6-7, death row 8).
