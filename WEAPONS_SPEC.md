# System Looting — Ranged Weapons & Sentry Towers Specification

**Status:** Design only (owner-approved direction 2026-08-28: Quake/UT arena
feel, player-deployable sentry turrets). No implementation yet — this document
is the review gate for Phase W.
**Priority:** P1 — after the Phase A remainder (hand-built arena map), before
Phase B crafting expansion. Ranged combat is additive content, not a blocker.

**Owner decisions already made (do not relitigate in this doc):**

| Decision | Choice |
|---|---|
| Delivery | Spec first, implementation after review |
| Towers | Player-deployable sentry turrets from loot — tower defense inside the arena |
| Feel | Quake/UT: weapon pads, per-weapon ammo pools, no reloads, fast TTK, movement tech |

---

## 1. Core fantasy: the duel economy

System Looting is single-life, identity-ambiguous, and about reading people.
Quake is respawn-driven, anonymous, and about controlling items. The overlap is
larger than it looks: **both games are about sound, space, and resource
denial.** This spec imports the Quake *duel* — two players orbiting a weapon
spawner, listening for the pickup chime — into a game where dying once sends
you to the cloud cage.

The tension (arena lethality vs. single life) resolves as:

- **Lethal but readable.** Hitscan alpha is capped; sustained damage comes
  from *dodgeable* projectiles. You die because you were outplayed or
  outpositioned, not because someone held a trigger across the map.
- **Sound is information.** Every weapon has a loud signature and a pad chime.
  In a game with no nametags, "who picked up the mortar" heard through a wall
  *is* the social deduction loop wearing an arena-shooter costume.
- **Ammo is the loot.** The name of the game is System Looting. Guns without
  ammunition are clubs; ammunition without guns is trade bait. Ammo scarcity
  feeds the existing scavenge/betrayal economy; it does not replace it.

Melee stays relevant: guns kill players, blades crack cores (see §8 — ranged
beacon damage is deliberately weak).

## 2. Design pillars

1. **Dodgeability beats accuracy.** Projectiles carry the DPS; hitscan carries
   the punctuation. Nothing kills a healthy player from full HP in under ~1 s
   of *dodgeable* exposure.
2. **No reloads, ever.** Ammo pools + refire delays, Quake-style. The only
   resource decision is *what to spend and when to stop shooting*.
3. **Movement tech is free.** Mortar-jump knockback, pulse-juggle push, and
   the existing crouch-walk speed quirk (`movement_speed_crouch = 5.5`) form
   the movement vocabulary. No hook, no dash item — footwork comes from maps.
4. **Identity stays neutral.** No team-colored tracers, no kill attributions.
   A turret cannot be used as a team oracle (§7, §10).
5. **Everything routes through the existing rule engine.** All weapon damage
   flows through `object:punch()`, so the lobby guard, ghost-attacker block,
   creative-mode block, and immortal-armor ghosts all apply unmodified.

## 3. The arsenal (Phase W1: six weapons)

All TTK math against the standard **20 HP** player (current `hp_max`),
no armor in scope. `n/s` = nodes per second.

| Weapon | Analog | Type | Dmg | Refire | DPS | TTK vs 20 HP | Ammo (max) | Quirk |
|---|---|---|---|---|---|---|---|---|
| **Pulsar Pistol** | Blaster/Enforcer | Hitscan | 4 | 0.35 s | 11.4 | 5 hits ≈ 1.75 s | ∞ (internal cell) | Everyone's spawn weapon; perfect accuracy |
| **Chatter SMG** | Machinegun | Hitscan | 2 | 0.09 s | 22.2 | 10 hits ≈ 0.9 s (bloom pushes real TTK ≥ 1.5 s) | Bullets (150) | First shot exact; bloom 0.5°→4° while held, resets in 0.6 s |
| **Riot Scatter** | Shotgun | Hitscan ×8 pellets | 1.5/pellet = 12 point-blank | 0.9 s | 13.3 | 2 shots ≈ 0.9 s (point-blank) | Shells (30) | 9° cone, pellets expire at 24 m, damage falls with pellet spread |
| **Arc Lance** | Railgun | Hitscan | 18 | 1.6 s | 11.25 | 2 hits ≈ 1.6 s — **or one lance + one pistol tap** | Cells (60) | RMB zoom ×2.5; beam tracer; report audible 48 m |
| **Fusion Mortar** | Rocket launcher | Projectile, 18 n/s | 14 direct + splash 6→0 over 3 m | 0.9 s | ~22 | 2 directs ≈ 0.9 s — both dodgeable | Rockets (15) | 50 % self-damage; mortar-jump (§9); splash damages beacons 1 |
| **Pulse Driver** | Plasma gun | Projectile, 26 n/s | 5 | 0.15 s | 33.3 | 4 bolts ≈ 0.6 s theoretical; slow bolts make real TTK ~1.5–2 s | Cells (60) | Bolts apply 0.4 n/s knockback — target juggling; best monster-clearer |

Design intent per slot:

- **Pistol** is the floor and the finisher. The lance-leaves-you-at-2-HP →
  pistol-tap combo is the deliberate Quake "RG + mg finish" read.
- **Chatter** punishes predictable strafes at mid range, not corners.
- **Scatter** owns doorways. Its 0.9 s pump is the loudest tempo tell.
- **Arc Lance** is the information weapon: one shot announces you to everyone
  in earshot, and near-lethality makes every hit a story.
- **Fusion Mortar** is the movement key and the siege answer to clustered
  monsters (Brute 60 HP: 2 direct rockets; Containment Horror 80 HP: splash
  kiting). Rocket-vs-rocket duels are the intended spectacle.
- **Pulse Driver** melts Dredgers (40 HP = 8 bolts) and zone-controls pads.

Ammo types: **Bullets, Shells, Cells, Rockets.** Pools are per-type and shared
by weapons using them (Lance and Driver both burn Cells — one pool, real
decisions). Pickup yields: bullets 40, shells 8, cells 15, rockets 4.

## 4. Firing model (shared)

- **LMB (`on_use`) fires.** Weapons have no melee `tool_capabilities` punch of
  their own — the blade in your second slot is the melee answer.
- **No reloads, no mags.** Refire gates only. Switching weapons has a 0.3 s
  raise delay shared globally (prevents lance-tap-chatter instakill combos).
- **Hitscan** = `minetest.raycast` from eye, tracer particles + crack sound;
  damage applied via `object:punch(wielder, …, {damage_groups})` so
  `register_on_punchplayer` guards (match.lua:511) stay authoritative.
- **Projectiles** = small entities, raycast per step (sweep between last and
  current position — no tunneling at 26 n/s), gravityless except mortar
  (slight 2 n/s² drop for arc flavor). Direct hit punches the first swept
  object; splash does a radius search with linear falloff and applies knockback
  via `add_player_velocity`.
- **Out of ammo** → dry-click sound + auto-switch to pistol after 0.2 s.
- **Ghost/lobby/creative gates**: firing is additionally refused directly at
  input time (ghost hands can't even dry-fire), while the punch-guard remains
  the backstop for anything spawned before a phase change.

## 5. Weapon pads & pickups

Quake item pads, in System Looting's ownership-neutral clothing:

- **`sl_weapons:pad_weapon`** — a 1×1 floor pad node (neon ring), holding one
  weapon definition; map builders place them by hand (WP1 arena tooling).
  Respawn timer **30 s** (setting `sl_weapons_pad_respawn`), pickup chime
  audible 32 m. Empty pad shows a dim ring; chime on re-arm.
- **`sl_weapons:pad_ammo`** — same node with an ammo item, 20 s respawn.
- **Loot crates** may roll weapon + ammo bundles (crate loot tables get a
  `weapons` section; Sentry Kit weight ≈ 10 %, §7).
- **Scavenging the dead**: inventories already fountain-drop on death
  (match.lua:544); ammo and weapons are ordinary items, so loot-the-corpse
  comes free. The pistol is `on_drop`-locked to prevent ammo-less newbs being
  fully disarmed — a dropped loadout pistol vanishes instead.
- **Placement rules for arena authors**: no pad inside beacon LoS of the
  opposite beacon; minimum 16 m between major pads; each major pad visible
  from at least two blind-spot-free angles (no free ambush racks).
- Pads are `possessable` (join `POSSESSABLE_NODES`-style group handling,
  nodes.lua:552) — an evil ghost may possess a pad to *disable* it
  (refuse dispensing, `OBJECT POSSESSED` infotext), living players exorcise
  with two punches, standard 20 s / 45 s cooldown economy.

## 6. Turrets: the "Sentry Kit"

Player-deployable tower defense, tuned for a single-life game: turrets are
*zone deniers and information leaks*, not farming machines.

| Property | Value |
|---|---|
| Deployment | `sl_weapons:sentry_kit` item → RMB on a solid node top |
| Structure HP | 25 (5 blade hits / 13 pistol shots / 1 lance + tap) |
| Limit | 1 deployed per player, 3 per beacon team (deployment refuses politely) |
| Battery | 90 s lifetime, then powers down and self-dismantles into scrap |
| Range / tracking | 12 m, 360° sweep at 60°/s, 1.5 s target loss after LoS break |
| Fire | 0.4 s acquire chirp → hitscan 2 dmg every 0.8 s, laser guide line while tracking |
| IFF | **Targets every living player except the deployer, plus all monsters.** |
| Killfeed | "A sentry gunned down @1" — never the owner's name (§10) |
| Beacon damage | 0 — turrets cannot siege objectives, ever |

Why owner-only-immunity instead of team-awareness: any team-aware turret is a
walking identity oracle (walk past it, learn a team). Owner-only IFF leaks
nothing about *teams*, creates betrayal potential (bait a rival into your
turret's arc), and monsters give it a genuine anti-MM role.

Counterplay stack (all existing systems, no new machinery):

- Punch it out (25 HP), or lance it from beyond its 12 m reach.
- Bait its fixed acquire delay; strafe the 60°/s tracking at close range.
- **Evil ghosts may possess a turret** (possessable group): possessed turret
  targets *everyone including the deployer* for the standard 20 s, exorcised
  by two punches — the turret is the most theatrical possession target in the
  game and must ship with possession support on day one.
- Sabotage corrosion disables firing while active; repair by punching, as usual.
- 50 % chance to drop the Kit back when destroyed before battery expiry.

Implementation shape: turret base is a **node** (so possession, sabotage,
punch-repair, and digging all work unmodified); a non-targetable cosmetic
head entity rotates for aim feedback and dies with the node.

## 7. Rules integration matrix

| Rule system | Weapon behavior |
|---|---|
| Lobby / no active match | Firing refused at input; punch-guard backstop |
| Creative mode | Damage blocked (existing guard) |
| Ghost (contained) | Cannot fire; immortal — cannot be damaged |
| Evil ghost | Cannot fire weapons; may possess pads/turrets |
| Single death | Weapons never bypass `on_dieplayer` transitions; splash deaths included |
| Friendly fire | Always on (all players are `fleshy`) — intentional: betrayal is a designed social mechanic |
| Monster Master | `fleshy = 100` armor stands; ranged chip damage mostly futile by design, mortars still shove monsters |
| Monsters | Full weapon damage; mortars/pulse are the intended anti-swarm tools |
| Beacons | Ranged damage deliberately poor (§8): mortar direct 4 / splash 1, lance 3, everything else 1, turret 0 — via `game_mode.damage_beacon()` |
| Match reset | Turrets dismantled, pads rearmed, ammo cleared with the rest of inventory on insertion |
| Identity | See §10 audit |

## 8. Why ranged beacon damage is weak

Beacon sieging at range would let one player shred the win condition from
safety. Melee (punch = 5) stays the pressure tool: **closing distance is the
cost of objective damage.** Guns create the space in which the runner moves.
This keeps the blade equipped all match and preserves the read-the-room
gameplay instead of turning matches into artillery exchanges.

## 9. Movement tech

- **Mortar-jump**: mortar explosion within 3 m applies up to 9 n/s velocity
  away from blast (7.5 % of self-damage at direct feet-shot ≈ 1 HP cost with
  50 % self-damage falloff). Horizontal mortar-hops cost more HP, go farther.
- **Pulse-juggle**: consecutive bolt hits nudge 0.4 n/s — enough to harass a
  runner's rhythm, not enough to lift a player.
- **Crouch-strafe** (existing config: crouch 5.5 vs walk 4) is already the
  duel sidestep; scatter users crouch-peek doorways. Documented here so
  balance telemetry watches it; no code change.
- Arena authors: mortar-jump reach (≈ +6 nodes vertical) must be considered
  when placing sniper ledges — ledges should be jump-reachable *or* properly
  committed climbs, never accidental.

## 10. Identity-neutrality audit

- Tracers/beams: one palette (system cyan/white) for everyone — no team tints.
- Kill attribution: existing neutral broadcasts only; weapon flavor allowed
  ("@1 was deleted by an Arc Lance"), attacker names never shown by weapons.
- Turret IFF: owner-only immunity — zero team information emitted.
- Pad chimes and weapon reports are *global* positional audio: everyone with
  ears gets the same intel. Sound advantage must never be private.
- HUD: ammo readout and turret battery bar show the local player's own state
  only (same policy as the stamina HUD, hud.lua header).

## 11. Mod architecture (implementation sketch, Phase W)

```text
mods/game/sl_weapons/
  init.lua        -- include_files pattern, global table sl_weapons
  api.lua         -- sl_weapons.register_weapon(def), shared fire pipeline
  hitscan.lua     -- raycast, spread/bloom, tracer, punch routing
  projectiles.lua -- mortar/pulse entities, swept collision, splash+knockback
  weapons.lua     -- the six registrations + ammo items & pools
  pads.lua        -- weapon/ammo pad nodes, respawn timers, possession hooks
  turret.lua      -- sentry kit item, turret node + head entity, targeting
  hud.lua         -- ammo readout, dry-fire feedback
  sounds/, textures/  -- generated assets (see §12)
mod.conf: name = sl_weapons, depends = sl_modebase, default
```

Settings (settingtypes.txt, matching repo conventions):
`sl_weapons_enabled` (bool true) · `sl_weapons_spawn_loadout` (bool true —
pistol + 1 blade) · `sl_weapons_pad_respawn` (int 30) ·
`sl_weapons_turret_max_player` (int 1) · `sl_weapons_turret_max_team` (int 3) ·
`sl_weapons_turret_lifetime` (int 90) · `sl_weapons_raise_delay` (float 0.3).

Integration touch points outside the new mod (all additive, WP3/WP5 files):

- `sl_modebase/content.lua`: crate loot table gains a `weapons` section.
- `sl_modebase/nodes.lua`: pads/turret node join the possessable group;
  turret gets sabotage refusal. No edits to the punch guard — by design.
- `sl_modebase/hud.lua`: nothing (weapons own their HUD elements).
- `sl_modebase/test_harness.lua` + `tests/minetest_stub.lua`: raycast shim +
  entity step loop extension (additive).
- `AGENT_PARALLEL_PLAN.md`: new row — WP9 owns `mods/game/sl_weapons/**`.

## 12. Assets (generated, zero external files)

Matching the existing pipeline (`GENERATED_ASSETS.md`, `generate_sounds.py`):

- **Textures**: 16×16 neon-system style icons for 6 weapons, 4 ammo items,
  Sentry Kit, pad ring (armed/dim), turret node — extend
  `generate_content_assets.py` with an `sl_weapons` section.
- **Sounds** (procedural, mono, .ogg): pistol crack, chatter burst, scatter
  boom, lance crack-hum (long tail), mortar launch + explosion + flight loop,
  pulse zap, dry click, pad chime (arm + take), turret acquire chirp / servo /
  laser hum, turret death pop.
- **Models**: reuse `sl_mvp_assets` `item_pickup.obj` for pad holograms;
  turret head is a small generated cube-cluster obj.

## 13. Test & telemetry plan

- **Stub tests** (`tests/weapons_test.lua`, headless against
  `minetest_stub.lua` extended with a voxel raycast): fire pipeline drains
  ammo, punch-guard blocks lobby/ghost fire, splash falloff curve, mortar
  self-knockback magnitude, turret IFF (owner spared, stranger shot, monster
  shot), turret limits (1/player, 3/team), possession disables pad & flips
  turret IFF, pads respawn on timer, insertion clears ammo/turrets.
- **Soak harness** (`aaa_botmatch` extension, Phase W2): bots learn
  pickup-camping, projectile leading, turret placement near own beacon route,
  and turret destruction priority. New telemetry counters feeding
  `tests/soak/run_soak.py` reports: per-weapon kill share, TTK p50/p95,
  ammo-starvation events, pad contention fights, turret deployed/killed/
  friendly-casualty ratios, mortar-jump usage.
- **Balance exit gate (Phase W3)**: no weapon above 30 % kill share across a
  40-match turbo sweep; zero turret-caused team eliminations above 15 % of
  total deaths; TTK p95 ≥ 0.8 s on dodgeable weapons.

## 14. Milestones

| Phase | Scope | Exit gate |
|---|---|---|
| **W0** (½ day) | Stub raycast extension + `sl_weapons` skeleton loads clean | smoke tests still green |
| **W1** (2–3 days) | Six weapons, ammo, hitscan/projectile pipeline, HUD readout, generated assets, stub tests | playable duel vs bots; stub suite green |
| **W2** (2 days) | Pads, Sentry Kit + turret, possession/sabotage hooks, bot behaviors, telemetry | soak turbo 40 matches, exit-gate metrics |
| **W3** (1 day) | Balance pass from telemetry, arena pad placement guide for WP1, docs integration (ROADMAP, NEEDED ASSETS) | owner sign-off |

## 15. Out of scope (explicitly)

Armor/vest pickups, alt-fire modes beyond lance zoom, weapon-specific
achievements, grapple/dash movement items, team-aware turrets, and any
Monster-Master-only tower variant (owner chose player-deployable; revisit only
if MM win rates sag in soak data).

## 16. Open questions for the owner

1. **Spawn loadout**: pistol-only, or pistol + scatter for everyone? (Spec
   says pistol-only; scatter on pads.)
2. **Turret battery 90 s** — or should turrets persist until destroyed, with
   the 3-per-team cap as the only limiter? Soak data will answer; spec ships
   the battery as the conservative default.
3. **Mortar arc drop**: 2 n/s² gives Quake-2-ish arcs at arena scale — confirm
   after first hands-on, it's one constant.
4. Should the **pad chime identify the weapon type** by pitch (more Quake
   item-memory) or stay anonymous (harder deduction)? Spec: identify by
   pitch — sound-memory is the fun part.
