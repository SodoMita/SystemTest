# sl_weapons hi-res textures — queue & plan (owner 2026-09-03)

Owner: *Weapons need new hi-res textures. Keep assets small — below 1MB
per asset.* All 37 files on master are 16×16 placeholders (solid 2-colour
icons) — every tree (master + the four art passes) has them, so there is
nothing to cherry-pick; this is a fresh art task. The image generator's
budget is 10 images/turn; the three mob sheets consumed turn 1, so the
remaining work below is queued for the following turns.

Style: same **boxman neon wire-glow** visual language as the mobs
(`docs/art_baseline/boxman_style_render.png`): near-black/very dark
metallic bodies, thin bright neon rims, flat graphic shading, glow in
weapon-accent colors. Follow the existing weapon names/lore in
`mods/game/sl_weapons/weapons.lua` (Pulsar Pistol, Chatter SMG, Riot
Scatter, Arc Lance, Fusion Mortar, Pulse Driver, Neon Six, Neon
Repeater, Severance blade; 4 ammo caches). Accent palette used by the
game's beacon teams / neon set: hot cyan `#00E8FF`, magenta `#E800A8`,
white `#F8F8F8`, neon-green `#00FF41`, amber `#FFBF00`.

## Categories

| Batch | Files | What | Technique |
|---|---|---|---|
| A icons (13) | pistol, chatter, scatter, lance, mortar, driver, neon_six, repeater, severance, ammo_bullets, ammo_shells, ammo_cells, ammo_rockets | inventory/tool icons: 45° side view of the weapon, sticker-style, keyed | AI 1024 → process 256×256 transparent |
| A icons (3) | grapple, sentry_kit, targeting_log | same as icons (grapple = hook gun, sentry kit = deployable, targeting log = datapad item) | AI 1024 → 256 |
| B node faces (7) | fabricator_top, fabricator_side, fabricator_base; turret_top, turret_side, turret_base, turret_head | full-block face textures (top/side/base tiles; turret_head doubles as the rotating cube-entity skin, so it must look right from every side: centred glowing lens design) | AI 1024 full-bleed (no keying) → 256 |
| C top-down rings (2) | pad_ring, pad_ammo_ring | ground pad decal (node tile shown with `^[opacity:60` when depleted); centred neon ring emblem | AI 1024 full-bleed → 256 |
| D trace decals (3) | residue, mound, scorch | small ground node tiles ("Residue" wet glow puddle, "Grave Mound" dirt pile, "Scorch" burn mark) | AI 1024 full-bleed → 128 |
| E effects (9) | blast, grit, hit, spark, tracer, lash_hook, lash_line, mortar_shell, pulse_bolt | particles/entity sprites (additive-ish, `glow` 10-14) — **procedural** radial/burst glows at 256 (no AI needed; deterministic) | ImageMagick gradients |

Order of execution: A (16 calls), B (7), C (2), D (3) = 28 AI calls ≈ 3
turns at the 10-image budget; E is procedural and can land with any
batch.

## Carried TODOs

- [ ] containment mob: replace interim ATTACK×2/DEATH rows (currently
      reused lurch poses) with dedicated claw-slam attack frames and a
      collapse death frame (2 AI calls, next art batch).
- [ ] verify every new icon/tile in-engine (soak + visual pass) once the
      engine/lua gates run in CI.
