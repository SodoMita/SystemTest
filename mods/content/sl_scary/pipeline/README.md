# Texture pipeline (removed for repo size)

The mob sprite strips in `../textures/` (`sl_scary_dredger_strip.png`,
`sl_scary_wraith_strip.png`, `sl_scary_containment_strip.png`) were
originally generated with the Seirin pipeline: stb_image decode, matte
flood-fill, Mitchell downscale, 3-color palette intended. The ~378 KB
toolchain (stb_image.h, stb_image_write.h, downscale_filter.c,
matte_floodfill.c) was dropped to keep the repo small; it is preserved
on branch `arena/01a0436b-systemtest` in this same directory.

## Layout: strips are VERTICAL

Luanti plays `sprite` visuals with `object:set_sprite(...)`, iterating
frames along the frame **y** position (see `lua_api.md` -> `set_sprite`).
The shipped strips are therefore vertical with
`spritediv = {x=1, y=9}` in `sl_scary/init.lua`:

- `transpose_sprite_strip.py` — converts the Seirin toolchain's 144×16
  horizontal output into 16×144 vertical (pixel-verbatim block
  transpose, deterministic, stdlib only).

## Higher-res re-ink (wire-glow palette)

Owner art-gate rules (2026-09-02): strict palettes, no blur/anti-aliasing
(binary alpha), game surfaces are 32px+, mobs may be higher-res, and mobs
must match the neon "wire glow" theme. `reink_mobs.py` re-inks each 16×16
frame onto a strict palette — pure black silhouette + each mob's two spec
accent colours (dredger rust `#CC6622` + neon-green `#00FF41`; wraith void
purple `#1A0033` + neon-cyan `#00FFFF`; containment crimson `#8B0000` +
neon-amber `#FFBF00`) — and scales 4x (nearest) to 64×64 frames, writing
64×576 strips. Deterministic, stdlib only.

```sh
python3 pipeline/transpose_sprite_strip.py IN_horizontal.png ../textures/sl_scary_X_strip.png --frames 9  # once per regen
python3 pipeline/reink_mobs.py      # 16px -> 64px strict-palette strips
```

Keep the frame order stable (idle rows 0-2, walk 3-5, attack 6-7, death
row 8) — the Lua table in `sl_scary/init.lua` and the `[verticalframe:9:0`
item icons depend on it.
