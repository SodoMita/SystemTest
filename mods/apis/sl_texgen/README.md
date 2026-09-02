# sl_texgen — client-rendered procedural textures via `[combine:` programs

Placeholder art in this game (node effect spritesheets, mob strips,
labelled panels, noise, dig overlays) is **not shipped as PNG files**
and is **not rasterized on the server**. Each texture is *compiled* at
server startup into a pure `[combine:` modifier program that blits a
handful of tiny shared base textures. The program string travels inside
the node/item/entity definitions mods send anyway, and the **client**
executes it with its own texture-modifier engine:

```
server:  gen/*.lua  --stx ops-->  "[combine:960x32:0,5=stx_glow.png\^[resize\:8x8\^[opacity\:120:..."
client:  decodes stx_*.png once, blits/resizes/tints per program  ->  final texture
```

So the server never touches pixels: no PNG encoding, no base64, no
media push, no per-texture download — only the ~34 KiB of shared
`textures/stx_*.png` bases ship as ordinary media. 199 textures compile
to ~521 KiB of ASCII programs (mostly escaped numbers), which ride
along in definition strings that are already networked.

Reference: [texture modifiers](https://docs.luanti.org/for-creators/api/texture-modifiers/).
`[combine:` is a base-texture generator: it starts from a transparent
canvas and blits `x,y=<texture [ modifiers>` terms; any further
`^[...` ops appended to the *whole* sheet are grouped with parens
(`([combine:...)^[multiply:#...`).

## API (load time, after `depends = sl_texgen`)

```lua
sl_texgen.texture("tech_fire_30frames.png")  -- "[combine:..." program
sl_texgen.T("sl_medkit.png")                 -- short alias
sl_texgen.icon("sl_scary_dredger_strip.png", 16)
                       -- -> program .. "^[resize:16x16"
sl_texgen.sheet("tech_fire_30frames.png", 30, 0.05)
                       -- -> { name = ..., animation = sheet_2d ... }
sl_texgen.vframes("sus_nodes_white_noise_anim_4n.png", 64, 64, 1.2)
                       -- -> { name = ..., animation = vertical_frames }
```

`sl_texgen.texture` errors on unregistered names, so typos fail at
load time instead of showing the "unknown node" texture.

## The stx mini-language

`stx.lua` is the compiler. A program is a transparent sheet
(`stx.new(w, h, opts)`) plus a blit list built with seeded ops:

| op                                   | effect                                            |
|--------------------------------------|---------------------------------------------------|
| `solid(w,h,color[,alpha])`           | rectangle (`stx_px.png^[resize:WxH^[multiply:#…`) |
| `frame(w,h,color,t)`                 | inset border, thickness t                         |
| `hline/vline`                        | 1px lines                                         |
| `glow(x,y,size,color[,alpha])`       | radial falloff from `stx_glow.png` (quantized)    |
| `ring(x,y,size,color[,alpha])`       | ellipse outline from `stx_ring.png`               |
| `noise(w,h,color[,rgb])`             | LCG dither from `stx_noise*.png`                  |
| `xglyph / rhombus`                   | accent glyphs from `stx_x.png` / `stx_rhombus.png`|
| `label(x,y,text,color[,scale])`      | glyphs blitted from the `stx_font.png` atlas via `^[sheet:8x7:x,y` |
| `text_width(text[,scale])`           | layout helper for centered labels                 |

The client evaluates each blit's `^[` chain once per texture; there are
no loops or pixels on the server side. All ops are deterministic (one
seeded `stx.rng` LCG per frame), so programs are byte-stable across
runs and platforms.

## Shared base textures (~34 KiB total)

`tools/texgen_make_bases.py` writes `textures/stx_*.png`
deterministically (pure stdlib PNG writer): `stx_px` 1×1, `stx_glow`
128², `stx_ring` 128², `stx_noise`/`stx_noise_rgb` 64², `stx_x`,
`stx_rhombus` 64², `stx_font` 64×84 (8×7 atlas, cell 8×12, glyph 6×10,
sorted by byte). Regenerate with `python3 tools/texgen_make_bases.py`.

## Layout

- `stx.lua` — `[combine` compiler + shared bases access (pure Lua 5.1)
- `gen/*.lua` — one module per art family, each returns texture defs:

| module        | replaces                                                              |
|---------------|-----------------------------------------------------------------------|
| construction  | tech/forest/cave fire, smoke, plasma, water, bubbles, ice, sparks, snowflake sheets |
| forest        | forest biome block textures                                            |
| ground        | sus_nodes TV noise (+anim strips), neon squares / x / rhombus          |
| scary         | dredger / wraith / containment 9-frame strips, hide spots, body textures |
| workshops     | 50 labelled node facades                                               |
| modebase      | 26 `sl_*` item icons                                                   |
| weapons       | 37 two-tone weapon/entity textures                                     |
| mvp           | neon cube, cursor, HUD panels, font sheet, model panels                |
| clothing      | 11 `character_tool_*` icons                                            |
| formspec      | tz_formspec skin                                                       |
| dignodes      | dig-test overlay glyphs                                                |
| gui           | `gui_category_*` icons                                                 |

## Modes

`sl_texgen.mode` (settingtypes): `runtime` (default) compiles programs;
`stock` makes every accessor return the plain filename, for bisecting
against restored files (`git checkout <sha> -- '**/textures/**'`).

## Guardrails

- `tests/texgen_test.lua` — stubs the engine, loads the mod under Lua
  5.1, validates every program (header dims, whitelisted bases, escape
  roundtrip, `^[sheet` atlas bounds vs `stx.GLYPH_COUNT`, blit cap,
  no `[png:`), checks determinism (recompile is byte-identical), the
  stock mode, and the `/sl_texgen` chatcommand.
- `tools/texgen_check.py --verify` — CI gate: base textures match
  deterministic regeneration; **every program is executed by a Python
  reference interpreter** (combine/resize/multiply/opacity/sheet) and
  must decode to an in-bounds image; registered textures must not exist
  as files; governed texture directories must contain no unregistered
  PNGs; game code must go through `sl_texgen.texture()/icon()` and
  declare the mod dependency.
- `tools/texgen_check.py --contact docs/texgen_samples.png` renders a
  labelled review sheet of all 199 client-rendered textures.
