# System Looting — Ranged Weapons & Sentry Towers Specification

**Status:** v1.2 — design only, no implementation yet. v1.0 written 2026-08-28;
amended 2026-08-29 after the Weapons Council session (`WEAPONS_COUNCIL.md`)
and two team reviews. This document is the review gate for Phase W.
**Priority:** P1 — after the Phase A remainder (hand-built arena map), before
Phase B crafting expansion. Ranged combat is additive content, not a blocker.

**Team decisions already locked (do not relitigate in this doc):**

| Decision | Choice |
|---|---|
| Delivery | Spec first, implementation after review |
| Towers | Player-deployable sentry turrets from loot — tower defense inside the arena |
| Feel | Quake/UT: weapon pads, per-weapon ammo pools, no reloads, fast TTK, movement tech |
| Corpses | Death spawns a persistent corpse entity; stays until match end or explicit destruction — and destruction itself leaves observable traces (§7) |
| Grapple | No casino: never rolled as loot — fabricated at hard-to-reach workshops from ordinary materials; the rare part is the tool, the Precision Fabricator station (§10.1) |
| Mortar arc | Safe variant: flat 2 n/s² drop kept; revisit only with hands-on data (§17.3) |
| Corpse possession | Approved 2026-08-29, safe variant: evil ghosts may puppet their own corpse as a *visibly dead*, capability-limited decoy (§7.4) |
| Cremation relics | On par with ritual-sourced Ashen Relics — a Relic is a Relic (§7.3) |
| Monster Master | Never deploys towers, never uses ranged weapons. MM melee is bare hands evolved through the skill tree — never items (§6.1) |
| Achievements | Reset at match end; persistent lifetime counters record how many times each was earned (§12.1) |
| Western set | Revolver/lever-action sidegrades as sci-fi neon weapons, Phase W2 (§3.1) |

*Terminology note: this is a public project of equals. Earlier drafts said
"owner"; v1.1 replaces it with "team" everywhere in this file.*

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
- **Bodies are evidence.** A death is not an event that vanishes — it is a
  document that stays (§7). The match writes its own archaeology.

Melee stays relevant: guns kill players, blades crack cores (see §9 — ranged
beacon damage is deliberately weak).

## 2. Design pillars

1. **Dodgeability beats accuracy.** Projectiles carry the DPS; hitscan carries
   the punctuation. Nothing kills a healthy player from full HP in under ~1 s
   of *dodgeable* exposure.
2. **Magazines you load, reserves you carry** (v1.3 — team decision
   2026-08-29, reversing the v1.0 "no reloads, ever" pillar). Rounds live
   in the weapon stack; firing eats the magazine; the per-ammo pools are
   the *reserve*, and loading is one convenient action: right-click the
   weapon, or use a cache — a cache click even tops up the wielded
   matching weapon. Every weapon needs ammo, the Pulsar Pistol included
   (12-round magazine; no free guns). **The ammo indicator is the item's
   own durability bar** (v1.3.2, exactly MT CTF's `rawf` model): wear 0
   is a full magazine, 65535 is empty — the engine draws the bar in the
   hotbar, the inventory, and over the wield item; there is no custom
   ammo HUD. (The Neon Six's auto-spin still
   belongs to the gun, never a button the player presses. §3.1.) Melee is
   consumable: the Combat Blade wears on landed hits (~40) and breaks;
   a spare edge is 2 ingots through the inventory crafting menu.
3. **Movement tech is free by default — earned when paid.** Mortar-jump
   knockback, pulse-juggle push, and the existing crouch-walk quirk
   (`movement_speed_crouch = 5.5`) cost nothing and belong to everyone. The
   Grapple Lash (§10.1) is the single expensive, *dangerous* exception — and
   it is never a dice roll: it is fabricated at remote workshops, never
   dropped, never rolled (§10.1).
4. **Identity stays neutral.** No team-colored tracers, no kill attributions.
   A turret cannot be used as a team oracle (§6, §11).
5. **Everything routes through the existing rule engine.** All weapon damage
   flows through `object:punch()`, so the lobby guard, ghost-attacker block,
   creative-mode block, and immortal-armor ghosts all apply unmodified.
6. **Nothing vanishes.** Every violent act leaves something readable behind —
   a corpse, a stain, a mound, a scorch. Destruction of evidence is itself an
   observable act (§7).

## 3. The arsenal (Phase W1: six weapons)

All TTK math against the standard **20 HP** player (current `hp_max`),
no armor in scope. `n/s` = nodes per second.

| Weapon | Analog | Type | Dmg | Refire | DPS | TTK vs 20 HP | Ammo (max) | Quirk |
|---|---|---|---|---|---|---|---|---|
| **Pulsar Pistol** | Blaster/Enforcer | Hitscan | 4 | 0.35 s | 11.4 | 5 hits ≈ 1.75 s | Bullets, 12-rd magazine | Everyone's spawn weapon; arrives loaded with two magazines of reserve (v1.3: it eats ammo like everything else); perfect accuracy |
| **Chatter SMG** | Machinegun | Hitscan | 2 | 0.09 s | 22.2 | 10 hits ≈ 0.9 s (bloom pushes real TTK ≥ 1.5 s) | Bullets (150) | First shot exact; bloom 0.5°→4° while held, resets in 0.6 s. Bloom is a published function, never a die roll |
| **Riot Scatter** | Shotgun | Hitscan ×8 pellets | 1.5/pellet = 12 point-blank | 0.9 s | 13.3 | 2 shots ≈ 0.9 s (point-blank) | Shells (30) | 9° cone, pellets expire at 24 m, damage falls with pellet spread |
| **Arc Lance** | Railgun | Hitscan | 18 | 1.6 s | 11.25 | 2 hits ≈ 1.6 s — **or one lance + one pistol tap** | Cells (60) | RMB zoom ×2.5; beam tracer; report audible 48 m; one shot breaks a possession (§7.3) |
| **Fusion Mortar** | Rocket launcher | Projectile, 24 n/s, engine gravity (lobbed parabola) | 28 direct + splash 10→0 over 3 m | 0.9 s | ~22 | 1 direct kills — the counterplay is the arc, not the duel | Rockets (15) | 50 % self-damage; mortar-jump (§10); splash damages beacons 2; cremates corpses (§7.3) |
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

### 3.1 The Neon Frontier (western sidegrades, Phase W2)

*For a man who looks like he owned pistols in another life. Six shots of
light, a lever you work like a promise, and a spin-up hum that tells the whole
corridor what you just became. Frontier classics rebuilt as system-era neon.*

| Weapon | Analog | Type | Dmg | Refire | TTK vs 20 HP | Ammo | Quirk |
|---|---|---|---|---|---|---|---|
| **Neon Six** | Cap-and-ball revolver | Hitscan | 7 | 0.55 s | 3 hits ≈ 1.65 s | Bullets, 6-shot cylinder | Perfect accuracy; after the 6th shot the cylinder auto-spins for 2.5 s, refilling from the Bullets pool — the pause belongs to the gun, never a button for the player (pillar 2 kept in spirit). The spin hum is audible 16 m: a Neon Six running dry is a public event |
| **Neon Repeater** | Lever-action rifle | Hitscan | 6 | 0.8 s | 4 hits ≈ 2.4 s | Bullets | RMB ×2 zoom; lever cycle is a distinctive two-note clack audible 24 m; the mid-range slot between Chatter and Lance with zero bloom |

Design intent: the Frontier set is *sidegrade* — dueling weapons with perfect
accuracy and telltale sounds, for players who want the duel-economy metagame
louder, not stronger. No cylinder exceptions beyond the auto-spin, no new ammo
type (both feed the Bullets pool, competing with the Chatter).

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
  (slight 2 n/s² drop for arc flavor), and **velocity inheritance** from the
  shooter (a shell fired from a sprint carries the sprint; mortar-jumping is
  grammar, not a trick). Direct hit punches the first swept object; splash
  does a radius search with linear falloff and applies knockback via
  `add_player_velocity`.
- **Out of ammo** → dry-click sound, audible room-wide (emptiness is
  information; ghosts gossip about it) + auto-switch to pistol after 0.2 s.
- **Ghost/lobby/creative gates**: firing is additionally refused directly at
  input time (ghost hands can't even dry-fire), while the punch-guard remains
  the backstop for anything spawned before a phase change.
- **Monster Master gate**: a player whose role is `monster_master` cannot fire
  any ranged weapon — refused at input with *"Your hands are the doctrine."*
  MM ranged items are stripped on role grant and on pickup (§6.1).

## 5. Weapon pads & pickups

Quake item pads, in System Looting's ownership-neutral clothing:

- **`sl_weapons:pad_weapon`** — a 1×1 floor pad node (neon ring), holding one
  weapon definition; map builders place them by hand (WP1 arena tooling).
  Respawn timer **30 s** (setting `sl_weapons_pad_respawn`), pickup chime
  audible 32 m. Empty pad shows a dim ring; chime on re-arm.
- **`sl_weapons:pad_ammo`** — same node with an ammo item, 20 s respawn.
- **Chimes identify the weapon by pitch** (council resolution #1): mortar low
  and long, cells high and quick. The arena is a radio station; the chime is
  the headline. A player with three matches of ears knows what was taken
  through a wall. The Grapple Lash spawns on no pad, in no crate (§10.1) —
  acquiring it is a *hunt*: mapgen places no workshops, so the Precision
  Fabricator is assembled by hand from monster spoils (§5.1), and every
  ingot in it was carried home from a kill.
- **Killfeed is an incident report, not a joke** (council resolution #2):
  `0347  @1 — cause: arc discharge — range: long — witnesses: unknown`.
  Cause, time, circumstance — never an adjective, never an attacker name.
- **Loot crates** may roll weapon + ammo bundles (crate loot tables get a
  `weapons` section; Sentry Kit weight ≈ 10 %, §6). The Grapple Lash is
  **excluded from every random table** — no casino. Four rolls in a hundred
  is still a slot machine, and slot machines teach grinding, not reading.
  The Lash is fabricated at remote workshops instead (§10.1).
- **Recovered weapons keep state** (council resolution #3): every weapon
  stack carries its remaining-ammo count in metadata; a gun lifted from a
  body shows the dead man's last number, frozen. You pick up the mortar with
  two rockets gone and you know: he shot twice at something, and the
  something won.
- **Killing shots smash ammunition** (council resolution #4): the shot that
  kills destroys a third of the victim's loose ammo. Kills inherit scraps,
  not arsenals; kill-chain snowballing breaks; you cannot farm a funeral.
- **Scavenging the dead** now routes through the corpse (§7): the death
  fountain lands *in the body*, not on the floor. Looting is audible.
  The pistol is `on_drop`-locked — a dropped loadout pistol vanishes instead
  of disarming ammo-less newcomers completely.
- **Placement rules for arena authors**: no pad inside beacon LoS of the
  opposite beacon; minimum 16 m between major pads; each major pad visible
  from at least two blind-spot-free angles (no free ambush racks).
- Pads are `possessable` (join `POSSESSABLE_NODES`-style group handling,
  nodes.lua:552) — an evil ghost may possess a pad to *disable* it
  (refuse dispensing, `OBJECT POSSESSED` infotext), living players exorcise
  with two punches **or two weapon hits at range** (council resolution #5 —
  the lance becomes a key), standard 20 s / 45 s cooldown economy.

### 5.1 Monster spoils — where station parts come from

Mapgen places no workshops, so the workshops are *built*: every station
recipe is assembled in the inventory crafting menu and every ingredient
is obtainable from monsters (team decision 2026-08-29). The payout is
deterministic and published — a kill is worth exactly what it is worth,
no rolls, no casino. Spoils land beside the wreck as loose items: the
kill is public, the scramble is the tax.

| Creature | Pays out |
|---|---|
| Stalker | Metal Ingot × 1, Plastic Scrap × 1 |
| Scout | Circuit Board × 1, Plastic Scrap × 1 |
| Brute | Metal Ingot × 2, Energy Crystal × 1 |
| Dredger | Energy Crystal × 1, Circuit Board × 1 |
| Signal Wraith | Circuit Board × 1 |
| Containment Horror | Metal Ingot × 2, Circuit Board × 2, Energy Crystal × 1 |

Stations this funds (inventory crafting menu, **Tactical** tab):

| Station | Cost | Unlocks |
|---|---|---|
| **Precision Fabricator** | Ingot × 6, Circuit × 4, Crystal × 2, Plastic × 3 | The Grapple Lash, Sentry Kits, and the entire arsenal (below; §10.1, §6) |

The Fabricator's catalog (every job 10 s, mob spoils only — pads are map
furniture and mapgen places none, so the machine is the floor under the
arsenal):

| Job | Cost |
|---|---|
| Grapple Lash | Ingot × 2, Circuit × 2, Crystal × 2, Plastic × 1 |
| Sentry Kit | Ingot × 3, Circuit × 1, Crystal × 1 |
| Chatter SMG | Ingot × 2, Circuit × 1, Plastic × 1 |
| Riot Scatter | Ingot × 3, Crystal × 1 |
| Pulse Driver | Crystal × 2, Circuit × 2, Ingot × 1 |
| Arc Lance | Crystal × 3, Circuit × 2 |
| Fusion Mortar | Ingot × 4, Circuit × 2, Crystal × 2 |
| Neon Six | Ingot × 2, Crystal × 2, Plastic × 1 |
| Neon Repeater | Ingot × 3, Crystal × 2, Circuit × 1 |
| **Severance** (single use) | Ingot × 3, Crystal × 2 — melee, 200 damage on a landed hit, consumed on it. The executioner's receipt: one guaranteed kill on anything that bleeds (players 20 HP, horrors up to 80), priced so the buyer means it |
| **Ghost Altar** | Ingot × 2, Crystal × 2, Circuit × 1 | The revival ritual (summons a contained ghost for a relic) |

Ambient monsters (anything not deployed through the Monster Master's
catalog) carry nothing — the economy belongs to the match, not to the
wandering dead.

## 6. Turrets: the "Sentry Kit"

Player-deployable tower defense, tuned for a single-life game: turrets are
*zone deniers and information leaks*, not farming machines.

| Property | Value |
|---|---|
| Deployment | `sl_weapons:sentry_kit` item → RMB on a solid node top |
| Who may deploy | **Living non-MM players only.** The Monster Master is refused with *"The system does not take your orders twice."* (§6.1) |
| Structure HP | 25 (5 blade hits / 13 pistol shots / 1 lance + tap) |
| Limit | 1 deployed per player, 3 per beacon team (deployment refuses politely) |
| Battery | 90 s lifetime (team decision 2026-08-29: **kept** — a timer is a decision, a permanent turret is furniture), then powers down and self-dismantles into scrap |
| Range / tracking | 12 m, 360° sweep at 60°/s, 1.5 s target loss after LoS break |
| Fire | 0.4 s acquire chirp → hitscan 2 dmg every 0.8 s, laser guide line while tracking |
| IFF | **Targets every living player except the deployer, plus all monsters.** Never the Monster Master's role, never teams |
| Killfeed | Incident-report format: "cause: sentry fire" — never the deployer's name (§11) |
| Beacon damage | 0 — turrets cannot siege objectives, ever |
| On death | Drops a **targeting log** (council resolution #9): readable item, last 30 s — who walked the arc, who it fired at, when. The sentry is a witness; destroying it acquires its testimony |

Why deployer-only immunity instead of team-awareness: any team-aware turret is a
walking identity oracle (walk past it, learn a team). Deployer-only IFF leaks
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

### 6.1 The Monster Master: hands, not ordnance

Team decision 2026-08-29, three clauses:

1. **No towers.** The MM can never deploy or operate sentry equipment. The
   deploy path refuses by role; possessed turrets do not take MM commands
   either — they target MM like anyone else.
2. **No ranged weapons.** The MM cannot fire, wield, or benefit from any
   `sl_weapons` ranged item. Refusal at input (*"Your hands are the doctrine"*),
   stripped on role grant, stripped on pickup. The MM's answer to a gunfight
   is geometry: close the distance or leave.
3. **Hands evolve; items never do.** MM melee is bare-hand only, and it grows
   through the existing skill tree (`mods/apis/sl_gui/ability_system.lua`,
   `combat` branch — leveled unlocks, `requires` chains), gated to the MM role:

| Ability | Levels | Cost | Effect per level |
|---|---|---|---|
| **Tyrant Grip** (requires combat root) | 3 | 1/2/3 | Unarmed fleshy damage 4 → 7 → 10 (baseline hand 3) |
| **Long Arm** (requires Tyrant Grip I) | 2 | 2 | Punch reach +1 node per level, via a short raycast assist — the MM hits from the far side of a doorway |
| **Tremor Palm** (requires Tyrant Grip II) | 1 | 3 | Heavy punch: 3 m AoE, 8 n/s knockback, 6 s cooldown — the crowd-control the MM lacks in ranged |

Numbers vs. the 20 HP pool: Tyrant Grip III is a two-punch kill on an
outpositioned player — strong, but the MM must first *arrive*, against six
guns, with no ranged answer of its own. That asymmetry is the point: the MM
is the pressure the arsenal exists to answer. All tier numbers go through the
soak harness (§14) before anything is sacred. The MM's existing physics
(speed 1.3, gravity 0.1 — the float) are the closing tools and are unchanged.

## 7. Corpses, traces & the archaeology of a match

*Team decision 2026-08-29, escalated from council resolutions #3/#4: a death
is not an event that vanishes. It is a document that stays.*

### 7.1 The corpse

On `on_dieplayer`, a **corpse entity** spawns at the death position:

- Visual: the standard boxman, recumbent (reuses the player model laid flat —
  identical silhouettes apply in death as in life; no role or team markers).
- **Persistent by default.** No despawn timer. Removed only by match end
  (cleanup joins the existing end-of-match normalization) or by an explicit
  destruction action (§7.3). Single-life design bounds the count to the
  roster — corpse spam is structurally impossible.
- **The inventory lands in the body.** The existing death fountain
  (match.lua:544) is redirected into the corpse's 32-slot inventory instead
  of the floor. Weapons inside keep their frozen ammo state (§5); the
  smash-a-third rule applies at death, as v1.0.
- **Examining** (RMB) opens the incident report, formspec, same format as the
  killfeed: time of death, cause (`arc discharge`, `sentry fire`,
  `seal failure`…), and the inventory. Never an attacker's name (§11).
- **Looting is audible**: a distinct neon hum, 16 m. Taking a dead man's
  mortar is loud enough to be a decision. (Kaelen's law applies: looting is a
  *visible action* — now an *audible* one too.)

### 7.2 The residue

Under every corpse, a **residue node** (dark stain, walkable, non-diggable).
It survives the corpse's destruction and is only cleaned at match reset.
The floor remembers. A map reader can walk a finished arena and reconstruct
the order of deaths from stains, mounds, and scorch marks — the match writes
its own incident scene, exactly as `EVENT IDEAS.md` demands of its horror.

### 7.3 Explicit destruction — every method leaves a trace

| Action | How | What remains |
|---|---|---|
| **Burial** | Trench Shovel (existing item — *"earthworks and graves"*) on a corpse placed on/in diggable ground | **Grave mound** node: anonymous, permanent until reset. A decent burial. Some players will perform it for strangers; that is roleplay, and it is free |
| **Cremation** | One flare burned on the body, or one mortar splash across it | **Scorch** node + an **Ashen Relic** drops — the existing altar-ritual component, **on par with ritual-sourced Relics** (team decision 2026-08-29: burned evidence is not secondhand evidence; a Relic is a Relic). Kill → cremate → summon trades at full par. Burning the dead feeds the ghost economy: a player who wants the ritual *needs* the bodies. Desecration as a designed choice, exactly the weight class of `EVENT IDEAS.md` #6 |
| **Match end** | Normal cleanup | Nothing — the next match starts with a clean scene |

There is **no silent removal**. Destroying evidence is loud, visible, or
laborious — and the residue node stays regardless. Ghost-cage ghosts cannot
interact with corpses at all; evil ghosts follow §7.4.

### 7.4 The Deadwalk Puppet (approved 2026-08-29 — safe variant)

*The team approved corpse possession, deliberately choosing the safe variant
first: ship the constrained decoy, watch what it does to real matches, and
only then consider escalation. Every number below is provisional pending
hands-on.*

An evil ghost may possess **its own corpse** (own body only — one puppet, one
corpse, no impersonating the other dead) through the existing Possession
Focus, under the standard possession economy: 20 s duration, 45 s cooldown,
+30 s when exorcised.

**Visible distinction is a hard rule.** The puppet may bait a shot at a
glance, but it must never pass as one of the living:

- **Deadwalk corruption**: ashen, desaturated texture variant of the boxman
  (no new mesh), glitch-flicker opacity pulses, a slow drip of dark particles.
- **Wrong movement**: speed ×0.8, no sprint, weak jump, occasional
  half-second animation stutter — the gait reads *broken* at mid range.
- Ambiguous in the dark and at distance; unmistakable on inspection. That
  band — *could fool a nervous marksman, cannot fool anyone who looks* — is
  the design target.

**Capability limits (mandated by the team: health, crafting, building,
inventory — all limited):**

| Ability | Puppet |
|---|---|
| Health | 8 HP, no healing, no medkits |
| Attacking | None — evil-ghost damage ban holds; the puppet is a decoy, not a fighter |
| Firing weapons / using items | Refused |
| Crafting | Refused (no inventory craft, no workshop use) |
| Building / digging | Refused — cannot place or break nodes |
| Inventory | Locked and empty: carries nothing, cannot loot corpses, crates, or pads |
| Movement | Walk, weak jump |
| Interactions | Doors and hatches only (standard possessed-door slam behavior) |

**Ends and counterplay:**

- **Shot apart** (8 HP: one lance overkill, two scatter pellets-plus, four
  pistol taps) → corpse consumed, residue remains, feed logs
  `cause: puppet collapse` — never a name.
- **Exorcised** (two punches, or two weapon hits — §5) → ghost ejected,
  corpse remains but the strings are burned: one puppet per body.
- Match end sweeps everything, as always.

**Why anyone would want it**: the puppet is an ammo sink in an economy where
the killing shot smashes a third of the victim's ammo. It eats a lance round
worth 18 damage by existing. It soaks sentry batteries and exposes turret
positions. It triggers ambushes meant for the living. And it is harmless by
statute — the horror is the *deception*, and the deception costs the
deceived, never the deceived's health bar.

**Escalation parking lot** (only if the safe variant proves boring in play):
puppeting *other* corpses, longer duration, a single Tremor-grade shove.
None of these are approved; all of them are written down so we remember the
safe variant was a choice.

## 8. Rules integration matrix

| Rule system | Weapon behavior |
|---|---|
| Lobby / no active match | Firing refused at input; punch-guard backstop |
| Creative mode | Damage blocked (existing guard) |
| Ghost (contained) | Cannot fire; immortal — cannot be damaged; no corpse interaction |
| Evil ghost | Cannot fire weapons; may possess pads/turrets; may puppet its own corpse as a visibly-dead, capability-limited decoy (§7.4) |
| Single death | Weapons never bypass `on_dieplayer` transitions; splash deaths included; every death leaves a corpse (§7) |
| Friendly fire | Always on (all players are `fleshy`) — intentional: betrayal is a designed social mechanic |
| Monster Master | Cannot fire ranged, cannot deploy turrets (§6.1); `fleshy = 100` armor stands vs. the chip damage that still leaks through; mortars still shove monsters |
| MM bare hands | Skill-tree evolution only (§6.1); never items, never ranged |
| Monsters | Full weapon damage; mortars/pulse are the intended anti-swarm tools; corpses do not exist for monsters (entities die as today) |
| Beacons | Ranged damage deliberately poor (§9): mortar direct 4 / splash 2, lance 3, everything else 1, turret 0 — via `game_mode.damage_beacon()` |
| Possessed objects | Two weapon hits at range break a possession, same as two punches (§5, council #5) |
| Match reset | Turrets dismantled, pads rearmed, ammo cleared, **corpses/mounds/scorch/residue swept**, achievement match-state reset (§12.1) |
| Identity | See §11 audit |

## 9. Why ranged beacon damage is weak

Beacon sieging at range would let one player shred the win condition from
safety. Melee (punch = 5) stays the pressure tool: **closing distance is the
cost of objective damage.** Guns create the space in which the runner moves.
This keeps the blade equipped all match and preserves the read-the-room
gameplay instead of turning matches into artillery exchanges.

## 10. Movement tech

- **Mortar-jump**: mortar explosion within 3 m applies up to 11 n/s velocity
  away from blast (7.5 % of self-damage at direct feet-shot ≈ 1 HP cost with
  50 % self-damage falloff). Horizontal mortar-hops cost more HP, go farther.
  Arc drop stays at the safe flat 2 n/s² (team decision 2026-08-29, §17.3).
- **Pulse-juggle**: consecutive bolt hits nudge 0.4 n/s — enough to harass a
  runner's rhythm, not enough to lift a player.
- **Crouch-strafe** (existing config: crouch 5.5 vs walk 4) is already the
  duel sidestep; scatter users crouch-peek doorways. Documented here so
  balance telemetry watches it; no code change.
- Arena authors: mortar-jump reach (≈ +6 nodes vertical) must be considered
  when placing sniper ledges — ledges should be jump-reachable *or* properly
  committed climbs, never accidental.

### 10.1 The Grapple Lash — the one fabricated exception

*Team decision 2026-08-29: a grapple exists, as an expensive, advanced, rare,
and dangerous-to-use movement item. Frontier silhouette, system-era body: a
lasso of light.* (Reverses v1.0's blanket "no grapple" — this is the designed
exception, and the only one.)

| Property | Value |
|---|---|
| Item | `sl_weapons:grapple` — "Grapple Lash" |
| Acquisition | **Fabricated only** (§10.1 "The hunt"): ordinary materials + a Precision Fabricator — and since mapgen places no workshops, the Fabricator itself is assembled in the inventory crafting menu from **monster spoils** (Metal Ingot × 6, Circuit Board × 4, Energy Crystal × 2, Plastic Scrap × 3 — every part torn out of the Monster Master's machines, loot table in §5.1). Never on pads, never in crates, never a roll |
| Cost per launch | 5 Cells from the shared pool + 2.0 s cooldown. Expensive by design — the Lash competes with your Lance and Driver for the same battery |
| Mechanics | Hook is a slow projectile (30 n/s, inherits shooter velocity), attaches to **solid node faces only**, max 24 m; reel-in at 14 n/s, momentum conserved; jump detaches at full swing speed |
| **Danger 1 — loud** | Launch crack audible 32 m; the glowing line is visible to everyone. Grappling is broadcasting your position and intent |
| **Danger 2 — hands full** | While the Lash is out and attached you cannot fire any weapon. You are a parcel, not a gunner |
| **Danger 3 — fragile** | Taking *any* damage detaches the line — mid-swing, at altitude, above a stain that will be yours |
| **Danger 4 — cut lines** | The line is a hittable micro-entity: one weapon hit from anyone severs it. Spectators can execute you from the ground |
| **Danger 5 — bad anchoring** | Hooking a monster does not pull it to you. It reels *you* to *it* |
| Fall damage | Unmitigated. The Lash moves you; it does not forgive you |

Design intent: the Lash is a skill item whose floor is death and whose
ceiling is route domination — slingshot rotations, pad-to-pad verticality,
escapes nobody else can make. Every clause above exists so that using it is a
*published bet*, not a free upgrade. If soak telemetry (§14) shows Lash
holders dying more often than non-holders, the item is correctly tuned.

#### The pilgrimage (acquisition, per team decision 2026-08-29)

*0.04 was still a lot. Four rolls in a hundred is a slot machine, and slot
machines teach grinding, not reading. The rarity moved from the dice to the
map: the materials are ordinary, the **tools are rare**, and the tool is a
place.*

- **The station, not the recipe, is the treasure.** A Lash is fabricated only
  at a workshop carrying a **Precision Fabricator** — a bolted-down machine
  head that cannot be crafted, moved, or bought. Digging one loose destroys
  it (level 2, `sl_weapons:fabricator`). Map authors place **1–3 per map**,
  deliberately far: deep underground cubes where the monsters live, sealed
  sections, the far corners nobody patrols.
- **The recipe is deliberately mundane** — existing `CRAFTING_GUIDE`
  materials, nothing exotic: Metal Ingot ×2 + Circuit Board ×2 + Energy
  Crystal ×2 + Plastic Scrap ×1. Any team that *reaches* a Fabricator can
  usually afford the Lash. The gate was never the shopping list.
- **The job takes 10 s** with a machine hum audible 12 m — an eternity to
  stand still in a bad neighborhood, which is exactly where the workshops
  are.
- **Compatibility**: this revives the workshops concept
  (`mods/content/sl_workshops`, currently fully commented out — ROADMAP
  already calls to "revive ONE station"). The Fabricator is self-contained in
  `sl_weapons` (WP9 ownership) but its node contract matches the planned
  Assembly Table so WP6 can adopt it later.
- **Soak note**: bot telemetry must treat the trip as the cost — track
  deaths-in-transit-to-fabricator as a first-class counter.

## 11. Identity-neutrality audit

- Tracers/beams: one palette (system cyan/white) for everyone — no team tints.
- Kill attribution: incident-report format only — cause, time, circumstance.
  Attacker names are never emitted by weapons, turrets, corpses, or logs.
- Turret IFF: deployer-only immunity — zero team information emitted.
- Corpse reports: cause of death and inventory, never the killer's name. A
  grave mound is anonymous — the burial is decent *because* nobody signs it.
- Deadwalk puppets are visibly corrupt by hard rule (§7.4): a decoy may bait
  a shot at a glance, but never impersonate the living to anyone who looks.
- Pad chimes and weapon reports are *global* positional audio: everyone with
  ears gets the same intel. Sound advantage must never be private.
- Achievement lifetime counters (§12.1) are public reputation — a *player*
  skill tell is allowed; a *team* tell never is.
- HUD: ammo readout, turret battery, Lash state show the local player's own
  state only (same policy as the stamina HUD, hud.lua header).

## 12. Mod architecture (implementation sketch, Phase W)

```text
mods/game/sl_weapons/
  init.lua        -- include_files pattern, global table sl_weapons
  api.lua         -- sl_weapons.register_weapon(def), shared fire pipeline
  hitscan.lua     -- raycast, spread/bloom, tracer, punch routing
  projectiles.lua -- mortar/pulse/hook entities, swept collision, splash+knockback
  weapons.lua     -- the six registrations + Frontier set + ammo items & pools
  grapple.lua     -- the Lash: hook entity, line entity, reel physics
  fabricator.lua  -- Precision Fabricator station node + 10 s Lash job
  pads.lua        -- weapon/ammo pad nodes, respawn timers, possession hooks
  turret.lua      -- sentry kit item, turret node + head entity, targeting log
  corpses.lua     -- corpse entity, incident reports, residue/mound/scorch, burial & cremation
  mm_hands.lua    -- role-gated MM ability registrations (Tyrant Grip & co.)
  hud.lua         -- ammo readout, dry-fire feedback
  sounds/, textures/  -- generated assets (see §13)
mod.conf: name = sl_weapons, depends = sl_modebase, default, sl_gui
```

Settings (settingtypes.txt, matching repo conventions):
`sl_weapons_enabled` (bool true) · `sl_weapons_spawn_loadout` (bool true —
pistol + 1 blade) · `sl_weapons_pad_respawn` (int 30) ·
`sl_weapons_turret_max_player` (int 1) · `sl_weapons_turret_max_team` (int 3) ·
`sl_weapons_turret_lifetime` (int 90) · `sl_weapons_raise_delay` (float 0.3) ·
`sl_weapons_grapple` (bool true) · `sl_weapons_corpses` (bool true) ·
`sl_weapons_mm_hands` (bool true).

Integration touch points outside the new mod (all additive, WP3/WP5 files):

- `sl_modebase/content.lua`: crate loot table gains a `weapons` section
  (Grapple Lash explicitly excluded — it is fabricated, never rolled).
- `mods/content/sl_workshops` (commented-out plan): the Fabricator's node
  contract matches its planned Assembly Table so WP6 can adopt it later.
- `sl_modebase/match.lua`: death-fountain redirect into the corpse (§7.1).
- `sl_modebase/nodes.lua`: pads/turret/corpse-trace nodes join the possessable
  group; turret gets sabotage refusal. No edits to the punch guard — by design.
- `sl_modebase/hud.lua`: nothing (weapons own their HUD elements).
- `sl_modebase/test_harness.lua` + `tests/minetest_stub.lua`: raycast shim +
  entity step loop extension (additive).
- `AGENT_PARALLEL_PLAN.md`: new row — WP9 owns `mods/game/sl_weapons/**`.

### 12.1 Achievement lifecycle — reset the match, keep the memory

Team decision 2026-08-29, built on `mods/apis/sl_gui/achievement_system.lua`:

- **Match-scoped reset.** Every achievement's *earned/unlocked* state resets
  at match end, joining the existing end-of-match normalization (inventories,
  phases, sabotages, possessions). A new match is a clean record — the same
  principle as the corpse sweep: the next scene starts clean.
- **Tournament exception (v1.3.4, season format v1.3.5).** While a
  tournament runs, achievements persist across match ends along with levels
  and abilities (inventories still reset every match). A tournament is a
  **season of N matches**: `/sl_tournament start [N]` (default 5, capped at
  50) locks the roster to everyone connected at the starting gun — anyone
  joining mid-season is flagged a **tournament spectator**: no team
  assignment, never the Monster Master, never a targeting candidate. Each
  finished match banks its points into the roster's season score; when the
  last planned match ends, the **ranking form** (shared match-results
  layout, sorted by season points) pops out and the one clean reset follows
  automatically. `/sl_tournament stop` ends a season early through the same
  ranking-then-reset path.
- **Lifetime counters persist.** Each award also increments a per-player,
  per-achievement **`times_earned`** counter in mod storage, which survives
  every reset (and `/resetachievements` resets it explicitly, admin-intent
  only). The counter is surfaced in the achievements UI as a tally —
  *"First Blood × 12"* — and is public reputation (§11).
- *Rita's rule, made mechanical: the game forgets the match, the record
  remembers the player.* What was earned is gone next match; that it was
  earned twelve times before is forever.

## 13. Assets (generated, zero external files)

Matching the existing pipeline (`GENERATED_ASSETS.md`, `generate_sounds.py`):

- **Textures**: 16×16 neon-system icons — 6 weapons + Neon Six + Neon
  Repeater, 4 ammo items, Grapple Lash, Sentry Kit, targeting log, pad ring
  (armed/dim), turret node, Precision Fabricator station, corpse residue,
  grave mound, scorch, deadwalk boxman texture variant (ashen/desaturated) —
  extend `generate_content_assets.py` with an `sl_weapons` section.
- **Sounds** (procedural, mono, .ogg): pistol crack, chatter burst, scatter
  boom, lance crack-hum (long tail), mortar launch + explosion + flight loop,
  pulse zap, revolver crack + cylinder spin hum, lever two-note clack, dry
  click (loud, room-audible), grapple launch crack + reel whine + line-sever
  snap, 10 s fabrication hum, deadwalk glitch static + puppet collapse, pad
  chime (arm + take, pitched per weapon), turret acquire chirp /
  servo / laser hum / death pop, corpse-examine report chime, loot hum,
  shovel-burial fills, cremation roar.
- **Models**: reuse `sl_mvp_assets` `item_pickup.obj` for pad holograms;
  turret head is a small generated cube-cluster obj; the corpse and the
  deadwalk puppet reuse the player boxman model (no new meshes).

## 14. Test & telemetry plan

- **Stub tests** (`tests/weapons_test.lua`, headless against
  `minetest_stub.lua` extended with a voxel raycast): fire pipeline drains
  ammo, punch-guard blocks lobby/ghost/MM fire, splash falloff curve, mortar
  self-knockback magnitude, projectile velocity inheritance, turret IFF
  (deployer spared, stranger shot, monster shot, MM treated as any target),
  turret limits (1/player, 3/team, MM refused), possession disables pad &
  flips turret IFF, ranged exorcism (2 hits), pads respawn on timer,
  insertion clears ammo/turrets. **Corpse suite:** spawn on death, report
  contents (cause, no attacker), loot is audible, inventory lands in body,
  smash-a-third applied, shovel-burial → mound + residue persists, cremation
  → scorch + Ashen Relic **at ritual par**, no silent removal path, full
  sweep at reset. **Puppet suite:** own-corpse-only, visible corruption flags
  set, 8 HP with no healing, fire/craft/build/dig/loot all refused, doors
  work, shot-apart consumes corpse + logs `puppet collapse` with no name,
  exorcism burns the strings (one puppet per body), standard cooldowns.
  **Lash suite:** craftable only at a Fabricator (recipe consumes mats,
  10 s job), absent from every pad/crate table, digging a Fabricator
  destroys it, launch costs 5 cells, detach-on-damage, line cut by one
  hit, monster-hook reels the shooter. **Achievement
  suite:** award → reset at match end → `times_earned` survives.
- **Soak harness** (`aaa_botmatch` extension, Phase W2): bots learn
  pickup-camping, projectile leading, turret placement near own beacon route,
  turret destruction priority, corpse-looting as a loud action, and Lash
  usage on rotation routes. New telemetry counters feeding
  `tests/soak/run_soak.py` reports: per-weapon kill share, TTK p50/p95,
  ammo-starvation events, pad contention fights, turret deployed/killed/
  friendly-casualty ratios, mortar-jump usage, corpse-loot events per match,
  Lash hold rate vs. holder death rate, MM bare-hand kill share by tier.
- **Balance exit gate (Phase W3)**: no weapon above 30 % kill share across a
  40-match turbo sweep; zero turret-caused team eliminations above 15 % of
  total deaths; TTK p95 ≥ 0.8 s on dodgeable weapons; Lash holders' death
  rate ≥ non-holders' (the danger is real); MM hand-tier kills within the
  MM win-rate band from the pre-weapons baseline.

## 15. Milestones

| Phase | Scope | Exit gate |
|---|---|---|
| **W0** (½ day) | Stub raycast extension + `sl_weapons` skeleton loads clean | smoke tests still green |
| **W1** (2–3 days) | Six weapons, ammo, hitscan/projectile pipeline (with velocity inheritance), HUD readout, incident-report killfeed, generated assets, stub tests | playable duel vs bots; stub suite green |
| **W2** (3 days) | Pads, Sentry Kit + turret + targeting logs, **corpse system + deadwalk puppet**, **Grapple Lash + Precision Fabricator**, **Neon Frontier set**, MM hands + gates, achievement lifecycle, possession/sabotage hooks, bot behaviors, telemetry | soak turbo 40 matches, exit-gate metrics |
| **W3** (1 day) | Balance pass from telemetry, arena pad placement guide for WP1, docs integration (ROADMAP, NEEDED ASSETS) | team sign-off |

## 16. Out of scope (explicitly)

Armor/vest pickups, alt-fire modes beyond lance/repeater zoom, weapon-specific
achievements, dash items (the Lash is the *only* purchased movement tech),
team-aware turrets, and any Monster-Master ranged item or MM-deployable tower
(§6.1 — permanent, not deferred).

## 17. Open questions for the team

1. ~~Spawn loadout~~ — **resolved 2026-08-29: pistol-only.** The walk is the game.
2. ~~Turret battery~~ — **resolved: 90 s kept.** A timer is a decision.
3. ~~Mortar arc drop~~ — **resolved 2026-08-29: safe variant.** Flat
   2 n/s² kept; revisit only with hands-on data.
4. ~~Pad chime identification~~ — **resolved: yes, pitch identifies.** The
   chime is the headline.
5. ~~Corpse possession~~ — **resolved 2026-08-29: approved, safe variant.**
   The Deadwalk Puppet (§7.4): visibly dead, 8 HP, harmless, capability-
   limited; escalation options parked in writing.
6. ~~Ashen Relic economy~~ — **resolved 2026-08-29: full par.** Burned
   evidence is not secondhand evidence; a Relic is a Relic.
7. **Neon Six cylinder pause**: 2.5 s proposed — needs a hands-on duel test;
   it must feel like drama, never like lag.
8. **MM hand tiers (§6.1)**: 4/7/10 proposed — validate against soak before
   W3 freezes numbers.

## 18. Changelog

- **v1.3.9 (2026-08-29, dry fire keeps the gun, "No rockets" becomes
  true)** — two live complaints, one pass. (1) **The dry-fire
  autoswitch is gone**: a dry click used to rip the weapon out of the
  player's hand, park the most-loaded pistol (or a brand-new EMPTY
  pistol) in its slot, and announce "Switched to Pulsar Pistol." —
  while the player was trying to *reload*, not be disarmed. The dry
  click now just does its job: loud click, "Dry. Load it.", weapon
  stays in the hand. `W.autoswitch_pistol` is removed from the tree.
  (2) **"No rockets for the Fusion Mortar" while there actually are
  rockets**: `W.mag_load` only looked at the reserve pool — the
  player's rockets could be sitting in the inventory as a Rocket
  Cache (corpse loot, trade, crate) and the reload still refused. New
  `W.consume_cache`: an empty-reserve reload unpacks one matching
  cache item from the inventory into the pool first, so the refusal
  can only be spoken when there are none anywhere the player can
  touch. Root cause of the empty pool itself: the crate pickup table
  registered only the shell cache, although spec §3 publishes pickup
  yields for all four kinds (bullets 40, shells 8, cells 15, rockets
  4) and spec §1 says "Ammo is the loot" — the mortar, the lance and
  the driver were unresupplyable after the first magazine. All four
  cache kinds now ride the random table (Sentry Kit weight ≈ 10 %
  unchanged). W1c/W1e updated: the dry-fire check asserts the weapon
  stays in hand, and new cache-fallback checks prove the reload
  works from a held Rocket Cache and that the refusal is spoken only
  when there are genuinely no rockets anywhere. Suites: weapons
  304/304, smoke 127/127.

- **v1.3.8 (2026-08-29, the nil-puncher segfault — audit of the
  13:05:43 crash)** — third crash on the same log line
  ("zzt uses sl_weapons:mortar, pointing at [node under=6,0,0
  above=5,0,0]"), and a different beast: not NaN, but an engine
  **null dereference**. The v1.3.7 CTF port changed the self-splash to
  punch with a **nil** puncher (`W.punch_object(nil, obj, …,
  "mortar_self", …)`), whereas MT CTF always punches with the
  thrower's ObjectRef — even against itself. The engine's
  `PlayerSAO::punch` passes a nil puncher to the `on_punchplayer`
  handlers without issue, but the moment **any** handler returns true
  it does `puncher->getType()` with no null check and segfaults the
  whole process — verified present in Luanti 5.15.0, 5.16.1, 5.17.0
  and current master (unfixed upstream; ready-to-file issue text in
  `docs/agent_logs/2026-08-29-mortar-segfault.md`). sl_modebase's
  lobby/creative guards return true unconditionally, so a
  nil-puncher punch in the open test range — exactly where players
  test the mortar — was a guaranteed crash. Fixed at the only funnel:
  `W.punch_object` now never hands the engine a nil puncher (fallback:
  the victim itself); the self-splash punches through the shooter's
  own ObjectRef, CTF-faithful; the sentry — the second
  nil-puncher call site (its rounds punched with nil too; trigger:
  creative-mode servers) — now punches through its own head entity
  (non-nil, non-player, so MM bare-hand doctrine cannot read a sentry
  round as a doctrine strike). The stub now **models the engine flaw**
  (nil puncher + handled damage = process crash), which is why every
  earlier suite run was green while the live engine died — the same
  stub-vs-engine divergence class as v1.3.6.1, in a new location.
  Regression phase **W3f** replays the incident end to end (lobby
  self-mortar: no crash, jump intact, lobby guard still blocks
  damage), proves the stub models the crash (direct nil punch), and
  fires a live sentry under a true-returning guard. The
  `min_minetest_version` floor rises 5.0 → **5.6** — the CTF
  baseline of the ported code (its `vector.offset` et al. do not
  exist below). Suites: weapons 300/300, smoke 127/127, all mod files
  parse under the engine's LuaJIT; W3f fails 3 checks on the
  pre-fix code (verified by revert-and-rerun).

- **v1.3.7 (2026-08-29, mortar knockback = the CTF jump grenade)** —
  after the second point-blank crash, the splash push was rebuilt
  verbatim from MT CTF's knockback grenade
  (`ctf_mode_nade_fight:knockback_grenade`, the nade-fight jump
  grenade): the blast push is `vector.direction(blast, head)` — the
  **engine's** direction function, which is zero-safe on the C++ side
  (a blast centred exactly on the target yields a zero vector, never
  the NaN that Lua-side `normalize` produces) — aimed at the target's
  **head** so point-blank is a pure upward jump, with a **y-clamp** so
  a blast above you shoves you aside instead of pinning you into the
  floor, at flat power (`splash.knock`, default 11 n/s) with damage —
  not velocity — carrying the distance falloff. CTF's gates adopted
  too: the dead (`hp <= 0`) and the unpointable are not blast targets.
  The v1.3.6.1 armor stays as a backstop (`safe_dir`/`finite` refuse
  anything non-finite at the boundaries), but the crash class is now
  structurally absent: no Lua-side normalize touches a player delta
  anywhere in the blast path. Stub: `vector.offset` added; the stub's
  `normalize` divergence from the engine (zero-safe here, NaN there)
  is now documented — it is why every earlier suite run was green
  while the live client crashed. W1g extended: point-blank jump is
  exactly 11 n/s straight up, engine-direction zero-safety parity, and
  the overhead-blast y-clamp. Suites: weapons 288/288, smoke 127/127,
  soak PASS. *(Corrigendum, v1.3.8: the NaN crash class was fixed, but
  this port's nil puncher in the self-splash introduced a different
  crash — the 13:05:43 engine null dereference. See v1.3.8.)*

- **v1.3.6.1 (2026-08-29, the point-blank segfault)** — the second crash
  report ("uses sl_weapons:mortar" at own feet, client segfault) was a
  division by zero: a blast centred exactly on the shooter made the
  self-splash branch normalize a zero-length vector → NaN →
  `add_velocity(NaN)` on the local player → client segfault. The
  mortar-jump at point-blank range is the designed trigger, and the
  grav-8 arc made point-blank blasts routine. Fixed with tree-wide
  **division-by-zero armour**, installed in `sl_modebase`:
  `vector.safe_dir(v, fallback)` (normalize that returns the fallback
  for zero/NaN input) and `vector.finite(v)` (NaN/∞ detector) — every
  direction that feeds a movement write now goes through safe_dir: the
  splash branches (point-blank throws you straight up — the
  mortar-jump survives), pulse juggle, spread (degenerate bloom
  collapses to the plain aim), monster steering (a monster standing on
  its target stands still), bot waypoints, and the sl_scary chase/drag
  loops (a zero-length drag becomes a no-op, never NaN player
  velocity). Boundary guards: `W.knockback` refuses non-finite
  vectors, `W.spawn_projectile` refuses to spawn a shell with a
  poisoned velocity. Also: `sl_weapons:turret_head` now feeds its cube
  visual all six faces (one texture was engine abuse). Regression
  phase **W1g** reproduces the crash three ways — a blast centred on
  the shooter, a victim at ground zero, and the full fire-at-your-own-
  feet pipeline — plus NaN-refusal and spread checks. The turret
  monster-engagement window widened from 2 s to 3 s (the assert must
  see the shot, not the acquisition; 0.2 s tick alignment made 2 s a
  coin flip). Suites: weapons 285/285, smoke 127/127, soak PASS.

- **v1.3.6 (2026-08-29, live-server hardening round 2)** — the second
  field report, resolved against MT CTF as the reference implementation.
  *Deprecations, finished:* `W.knockback` calls `add_velocity` on
  whatever moves — CTF's own knockback (`ctf_mode_nade_fight`) does
  exactly this, no shims; `W.player_velocity` reads `get_velocity`
  directly; the deprecated player-only twins are gone from the tree
  entirely, comments included, and a **W0b source scan** fails the suite
  if they ever come back. The last old-style entity definition
  (`sl_weapons:turret_head`, missed by the v1.3.5 sweep) moved its
  properties into `initial_properties`, and a **W0b entity audit** now
  fails the suite if any registered entity carries engine properties at
  the top of its definition. *Segfault:* the v1.3.5 ranking form shipped
  `tablecolumns[text;text;right]` — the legal column types are `text`,
  `image`, `color`, `indent`, `tree` (alignment is an *option*,
  `align=right`), and the unknown type fed the client formspec parser
  garbage at exactly the moment the results screen appeared. The form
  ships `[text;text;text]`, and a W0b scan validates every emitted
  column list forever. Note: two of the three logged warnings referenced
  a build older than v1.3.5 — redeploy before retesting. CTF itself
  still carries old-style entity definitions and tolerates the warnings;
  we hold the line at zero. Suites: weapons 272/272, smoke 127/127,
  soak PASS (3 seeds × 40 matches).

- **v1.3.5 (2026-08-29, tournament seasons + mortar rework + live-server
  fixes)** — three threads in one sitting. *Tournaments* (team decision
  2026-08-29: "limited quantity of plays or games or matches"):
  `/sl_tournament start [N]` books an N-match season (default 5, 1–50),
  locks the roster at the starting gun — late joiners are flagged
  tournament spectators: no team, no Monster Master slot, they watch —
  banks each match's points into season scores, counts the matches down,
  and when the last one ends pops the ranking form (champion first) and
  performs the one clean progression + achievement reset automatically;
  `/sl_tournament stop` now routes through the same ranking-then-reset
  path. *Mortar rework* (team decision 2026-08-29, reversing the v1.2
  flat-arc): engine-gravity parabola (grav 8) at 24 n/s, direct damage
  doubled to 28 (one shell settles a 20 HP argument), splash 10→0 over
  3 m, knockback up to 11 n/s (the mortar-jump rides higher), splash
  chip on beacons 1→2, and the boom is now a public event — 32-flash
  blast plus a rising smoke column. *Live-server fixes*: the match
  results formspec crashed on `Invalid table element(7)` — a formspec
  `table[]` carries its whole item list as ONE comma-separated element,
  never `;`-joined rows (shared ranking form introduced, both forms
  audited); all `sl_weapons` entities declare visuals through
  `initial_properties` (corpse, deadwalk, lash hook, projectiles — the
  deprecated top-level `physical`/`visual`/`textures` are gone);
  `W.player_velocity` prefers `get_velocity` with the deprecated
  `get_player_velocity` kept as a fallback. Suites: weapons 269/269,
  smoke 127/127, soak PASS (3 seeds × 40 matches).

- **v1.3.4 (2026-08-29, tournament mode)** — `/sl_tournament start|stop`
  (server priv, between matches only): while a tournament runs, match
  start still resets inventories (pools, pads, turret limits, scene
  sweep all unchanged) but achievements, levels, and abilities persist
  across matches — experience, stat points, ability levels, MM grip
  meta, and achievement unlock state all ride through. Stopping the
  tournament performs one clean progression + achievement reset for
  every connected player, returning the server to the per-match
  economy. Progression meta already survives restarts, so a tournament
  persists across server restarts too (the flag itself is re-armed by
  the admin after a restart).

- **v1.3.3 (2026-08-29, the open test range)** — weapons are usable
  outside matches for testing, deliberately and narrowly: `fire_gate`
  lets the living fire any time (the dead and the Monster Master are
  still refused), and the Precision Fabricator serves testers between
  matches. Lobby immortality and the lobby PvP block are untouched by
  design — test fire is loud, not lethal; damage rules apply only
  inside a match.

- **v1.3.2 (2026-08-29, the bar is the magazine)** — the custom ammo HUD
  text is gone. Rounds are stored as item wear, exactly like MT CTF's
  `rawf` (`set_wear` per shot, `65535` = empty): the durability bar in
  the hotbar/inventory/wield IS the ammo indicator — full bar is a full
  magazine, drained bar is an empty gun. The `sl_mag` metadata field is
  retired; `mag_get`/`mag_set` read and write wear. Loading restores the
  bar; looted guns are found with a fully drained bar (empty). The HUD
  text element survives only for weapon-state flags ([LASH] [ZOOM]
  [SPIN]) and disappears when none apply. Melee durability (blade wear,
  v1.3.0) rides the same bar unchanged.

- **v1.3.1 (2026-08-29, the Severance)** — a single-use melee weapon:
  200 `fleshy` damage on a landed hit, consumed by that hit (a swing
  that deals no damage wastes nothing). Fabricated at mob-spoil prices
  (Ingot × 3, Crystal × 2); the incident report names the cause
  ("severance"), never the hand. The Monster Master's doctrine sweep
  strips it — hands only, never items. Shared melee-consequence hook
  (`W.melee_hit`/`W.melee_entity_hit`): the Combat Blade now also wears
  on monster hits, not only player hits.

- **v1.3.0 (2026-08-29, magazines)** — the ammo model rebuilt per team
  decision: rounds live in per-weapon magazines stored on the item stack
  (`sl_mag` metadata); firing consumes the magazine, the pools become the
  visible reserve, and loading is one action (right-click the weapon, or
  use a cache — which also tops up a matching wielded weapon). Every
  weapon now declares a pool and a magazine capacity: pistol 12/bullets
  (its v1.0 infinity is revoked), chatter 30, scatter 8, lance 6, mortar 3,
  driver 20, neon six 6, repeater 8. HUD shows `WEAPON n/cap +reserve` for
  the wielded weapon. Weapons granted by pads, the Fabricator, and the
  loadout arrive loaded; looted corpses' guns are found empty with the
  frozen charge note. Dry-fire autoswitch now hands you your most-loaded
  pistol instead of conjuring an unloaded one. Melee is consumable: the
  Combat Blade wears (~40 landed hits) and breaks; craftable at 2 ingots.
  Abilities/levels reset at match start (v1.2.4) confirmed: progression
  is per-match — experience, stat points, and ability levels all zero.

- **v1.2.4 (2026-08-29, every match starts from zero)** — levels and
  inventories reset at match start, unconditionally. The inventory clear
  in `reset_players_for_new_match` no longer skips creative mode (the
  skip was how whole arsenals leaked from match to match in creative
  testing) and also empties the craft grid; progression resets through
  the exported `reset_player_progression` hook (sl_gui zeroes
  `experience` and `abilities_v2` — levels, stat points, ability
  levels; sl_weapons zeroes the MM grip meta in its match-start hook);
  the Monster Master's kit is role equipment, not loot, and is
  re-granted after the clear (summon tool + starter essence).

- **v1.2.3 (2026-08-29, the fabricable arsenal)** — all seven primaries
  join the Precision Fabricator catalog (§5.1) at mob-spoil prices; the
  formspec is data-driven now (catalog grid + bill of materials). Also
  fixed a race the soak caught: a Lash hook in flight at match end
  anchored *after* the sweep and rode into the next match — hooks now
  carry a match-generation stamp and die if the generation turned.
  *(An "open range outside matches" policy shipped briefly in this
  revision and was reverted the same day: the 0-damage field report was
  a creative-mode setting, not a bug — in creative, no PvP is correct,
  and lobby immortality is the approved design.)*

- **v1.2.2 (2026-08-29, workshops from spoils)** — mapgen places no
  workshops, so both crafting stations are now assembled by hand in the
  inventory crafting menu, entirely from mob-obtainable parts: the
  Precision Fabricator (6 ingots / 4 circuits / 2 crystals / 3 plastic)
  and the Ghost Altar (2 ingots / 2 crystals / 1 circuit). Monsters now
  pay deterministic, published spoils on death (§5.1) — the station is
  rare because its parts are torn out of monsters, which keeps the
  Lash chain expensive, advanced, and dangerous exactly as v1.2
  intended; only the acquisition of the *station* changed (the Lash
  itself is still fabricator-only, never a roll).

- **v1.2.1 (2026-08-29, implementation notes)** — no design changes; records
  how two §5 bullets landed: (1) the "crate loot tables get a weapons
  section" bullet is implemented on the salvage-pickup roll table
  (`game_mode.register_pickup_roll`, weighted): Sentry Kit ≈ 10 %, a 4-shell
  bundle beside it, Grapple Lash on no table, ever; (2) council resolution
  #3 ("a gun lifted from a body shows the dead man's last number") is
  implemented as a read-only charge note stamped on weapon stacks inside the
  corpse — `Recovered — last charge: bullets/shells/cells/rockets` frozen at
  the moment of death. Pools die with the owner: the note is intel, never
  inheritance (a looted gun does not import ammo into the looter's pool).
- **v1.2 (2026-08-29, second review)** — casino removed: Grapple Lash pulled
  from all random tables, now fabricated at hard-to-reach Precision
  Fabricator workshops from ordinary materials (the tool is rare, not the
  mats — §10.1 "The pilgrimage", revives the `sl_workshops` station plan);
  mortar arc resolved to the safe flat 2 n/s²; corpse possession approved as
  the safe-variant Deadwalk Puppet — visibly corrupt, 8 HP, harmless,
  health/crafting/building/inventory all limited (§7.4); cremation Relics on
  full par with ritual Relics (§7.3).
- **v1.1 (2026-08-29)** — team review + Weapons Council deltas: corpse &
  trace system (§7); Grapple Lash (§10.1, reverses v1.0 blanket ban); MM
  clause — no towers, no ranged, bare-hand skill-tree evolutions (§6.1);
  achievement match-reset with lifetime `times_earned` counters (§12.1);
  Neon Frontier western sidegrade set (§3.1); council resolutions folded in
  (chime pitch ID, incident-report killfeed, frozen weapon state, ammo
  smash, ranged exorcism, loud dry click, targeting logs); projectile
  velocity inheritance; terminology de-ownerized — this is a team document.
- **v1.0 (2026-08-28)** — initial spec: six weapons, ammo economy, pads,
  sentry kit, integration matrix, movement tech, test plan.
