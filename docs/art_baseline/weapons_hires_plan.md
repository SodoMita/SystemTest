# sl_weapons hi-res textures — queue & plan (owner 2026-09-03)

Owner: *Weapons need new hi-res textures. Keep assets small — below 1MB
per asset.* All 37 files on master are 16×16 placeholders (solid 2-colour
icons) — every tree (master + the four art passes) has them, so there is
nothing to cherry-pick; this is a fresh art task.

Style (owner 2026-09-03): **generate realistic pics WITHOUT neon, then
turn into neon flatcolored** (same as the mob art, rev G). The AI only
renders photorealistic dark industrial items on a plain near-black
background; `matte_sheet.py` / `weapon_icons.py` then flatten the body
to a single flat colour, recolour saturated features to per-item neon
accents, and stroke a neon rim + glow around the silhouette.

## Categories

| Batch | Files | What | Technique |
|---|---|---|---|
| A icons (13) | pistol, chatter, scatter, lance, mortar, driver, neon_six, repeater, severance, ammo_bullets, ammo_shells, ammo_cells, ammo_rockets | inventory/tool icons: 45° view of the weapon | **DONE rev H**: realistic black grid + white twin (2 AI calls), `weapon_icons.py` → 256×256 transparent RGBA |
| A icons (3) | grapple, sentry_kit, targeting_log | same as icons (grapple = hook gun, sentry kit = deployable, targeting log = datapad item) | **DONE rev H** (same grids) |
| B node faces (7) | fabricator_top, fabricator_side, fabricator_base; turret_top, turret_side, turret_base, turret_head | full-block face textures (top/side/base tiles; turret_head doubles as the rotating cube-entity skin, so it must look right from every side: centred glowing lens design) | AI 1024 full-bleed (no keying) → 256 · **queued (7 AI calls, next turn)** |
| C top-down rings (2) | pad_ring, pad_ammo_ring | ground pad decal (node tile shown with `^[opacity:60` when depleted); centred neon ring emblem | **DONE rev H** AI 1024 full-bleed → 256 |
| D trace decals (3) | residue, mound, scorch | small ground node tiles ("Residue" wet glow puddle, "Grave Mound" dirt pile, "Scorch" burn mark) | **DONE rev H** AI 1024 full-bleed → 128 |
| E effects (9) | blast, grit, hit, spark, tracer, lash_hook, lash_line, mortar_shell, pulse_bolt | particles/entity sprites (additive-ish, `glow` 10-14) — **procedural** radial/burst glows at 256 (no AI needed; deterministic) | **DONE rev H** `tools/gen_weapon_fx.py` (stdlib) |

Order of execution: A + C + D + E done (rev H; 9 AI calls — two 3×3
grids + twins for icons, 5 full-bleed tiles); only **B (7 node faces)**
remains (7 AI calls, next turn).

Per-item neon accents are provisional constants in
`mods/content/sl_scary/pipeline/weapon_icons.py` (`ICON_STYLES`) — ammo
crates follow pool colours (bullets cyan, shells amber, cells magenta,
rockets green); guns have signature hues. Palette tweaks need no
regeneration, just a re-run.

## Carried TODOs

- [ ] batch B node faces (fabricator/turret) — next art batch.
      Preview sheets: `cs_weapons_v1.png` (icons), `cs_weapons_tiles_v1.png`
      (pad rings + trace decals).
- [ ] verify every new icon/tile in-engine (soak + visual pass) once the
      engine/lua gates run in CI.
