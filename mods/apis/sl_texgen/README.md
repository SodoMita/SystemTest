# sl_texgen — runtime procedural textures via `[png:` modifiers

Placeholder art in this game (node effect spritesheets, mob strips,
labelled panels, noise, dither icons) is **not shipped as PNG files**.
This mod renders all of it in Lua at server startup and hands it to
clients embedded in texture strings:

```lua
"[png:" .. core.encode_base64(core.encode_png(w, h, pixels))
```

`[png:` is a base texture generator (see the [texture modifier
docs](https://docs.luanti.org/for-creators/api/texture-modifiers/)).
The string travels inside the node/item/entity definitions mods send
anyway, so there is no media-push step, no disk I/O and no client
media-cache writes; each client decodes a modifier once into its
texture-modifier cache and reuses it.

## API (load time, after `depends = sl_texgen`)

```lua
sl_texgen.texture("tech_fire_30frames.png")  -- "[png:..." string
sl_texgen.T("sl_medkit.png")                 -- short alias
sl_texgen.icon("sl_scary_dredger_strip.png", 16)
                       -- -> texture .. "^[resize:16x16"
sl_texgen.sheet("tech_fire_30frames.png", 30, 0.05)
                       -- -> { name = ..., animation = sheet_2d ... }
sl_texgen.vframes("sus_nodes_white_noise_anim_4n.png", 64, 64, 1.2)
                       -- -> { name = ..., animation = vertical_frames }
```

`sl_texgen.texture` errors on unregistered names, so typos fail at
load time instead of showing the "unknown node" texture.

## Determinism

Generators (gen/*.lua) draw only through `canvas.lua` primitives with
a seeded LCG, so output is byte-stable across runs, platforms and
engine versions. `tests/texgen_test.lua` re-renders everything and
asserts byte equality; `tools/texgen_check.py --verify` (CI) runs the
same generators under embedded Lua 5.1 and cross-checks every PNG
against Python's zlib.

## Layout

- `canvas.lua` — 2D software rasterizer + 3x5 micro font (pure Lua 5.1)
- `png.lua` — PNG encoder (engine `core.encode_png` preferred, pure-Lua
  stored-deflate fallback), base64 encoder, CRC32/Adler32
- `gen/*.lua` — one module per art family, each returns texture defs:

| module        | replaces                                                              |
|---------------|-----------------------------------------------------------------------|
| construction  | tech/forest/cave fire, smoke, plasma, water, bubbles, ice, sparks, snowflake sheets |
| forest        | forest biome block textures                                            |
| ground        | sus_nodes TV noise (+anim strips), neon squares / x / rhombus          |
| scary         | dredger / wraith / containment 9-frame strips, hide spots, body textures |
| workshops     | 50 labelled node facades                                               |
| modebase      | 26 `sl_*` item icons                                                   |
| weapons       | 37 two-tone dither weapon/entity textures                              |
| mvp           | neon cube, cursor, HUD panels, font sheet, model panels                |
| clothing      | 11 `character_tool_*` icons                                            |
| formspec      | tz_formspec skin                                                       |
| dignodes      | dig-test overlay glyphs                                                |
| gui           | `gui_category_*` icons                                                 |

## Modes

`sl_texgen.mode` (settingtypes): `runtime` (default) generates; `stock`
makes every accessor return the plain filename, for bisecting against
restored files (`git checkout <sha> -- '**/textures/**'`).

## Guardrails

CI runs `tests/texgen_test.lua` + `tools/texgen_check.py --verify`,
which fail when a registered texture reappears as a file, when a file
inside a governed directory is not registered, when game code
references a registered name without `sl_texgen.texture()`, or when a
mod uses `sl_texgen` without declaring the dependency.
