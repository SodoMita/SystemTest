# System Looting — Match Loop Specification

**Status:** Phase A partially implemented on `feat/ghost-altar-ritual` — see Implementation Status below
**Priority:** P0 — build this before expanding crafting

## Implementation Status (August 2026)

Implemented and covered by `tests/smoke_test.lua` (66 assertions, run with
`lua5.1 tests/smoke_test.lua` against the headless engine stub in
`tests/minetest_stub.lua`):

- Match sequencing: ready check (`/sl_ready`) -> countdown -> insertion;
  `/sl_match_start now` bypasses for admins; roster requires >= 2 players on
  both beacon teams.
- Cloud cage: ghosts are held at `ghost_spawn`, immortal, invisible,
  untargetable, flight-enabled, and a containment platform is materialized
  around the spawn on load (`/sl_build_cage` to rebuild).
- Communication seal: ghost chat is blocked, and every registered chat
  command (including `/msg`, `/w`, `/tell`) is wrapped with a phase guard.
  Allowlist: `/sl_ghost_offer`, `/sl_state`, `/help` only.
- Ghost Altar ritual: consumes Ashen Relic + Soul Shard + Signal Ink, summons
  one random contained ghost for 30 s; creative-only dev commands
  `/sl_summon_ghost` and `/sl_ghost_offer`.
- Evil ghost revival: voluntary via the revival item, burns all match points,
  targetable (purgeable), one bounded sabotage charge per revival.
- Sabotage: 30 s corruption with a visible marker; sabotaged beacons take
  corrosion damage; sabotaged interactables refuse use; living players repair
  by punching; everything is purged on match end/restart.
- Match timer + result screen (formspec scoreboard + chat log) + clean reset:
  phases, lives, points, inventories, sabotages, and ghost privileges are all
  normalized before the next match.
- Identity-neutral HUD: phase, clock, own lives, public beacon integrity.
  No team names, colors, or other players' private state.

Still open (Phase A remainder):

- Hand-built arena map committed to the repo (two beacons, lobby, cage,
  routes, cover, hand-placed pickups).
- Scripted AI player harness with the 10 deterministic scenarios below.
- Direct-message UI polish and reconnect hardening pass.
- Evil ghost possession of objects (only node sabotage exists so far).

## Core fantasy

System Looting is a social competitive survival simulation. Players are visually identical. Identity is discovered through speech, movement, decisions, alliances, betrayals, and observed actions — not permanent team uniforms or nametags.

## Match state machine

```text
LOBBY
  -> READY CHECK
  -> TEAM ASSIGNMENT
  -> INSERTION
  -> ACTIVE MATCH
  -> EXTRACTION / OBJECTIVE RESOLUTION
  -> RESULT SCREEN
  -> CLEAN RESET
```

A match must be completable by 2–4 human or AI players without administrator intervention after setup.

### Lobby

- Players gather in a shared lobby.
- Match settings are selected before launch.
- Players can choose a role only where the ruleset permits it.
- A minimum player count and minimum viable team composition are required.
- Countdown begins only after the roster is valid.
- All inventories and temporary match state are reset on insertion.

### Active match

The first playable loop should be deliberately small:

```text
SPAWN AT BEACON
  -> SCAVENGE / MOVE
  -> READ THE OTHER PLAYERS
  -> DEFEND OR PRESSURE THE OPPOSING BEACON
  -> SURVIVE LIVES / DEATH TRANSITIONS
  -> ELIMINATION OR OBJECTIVE RESOLUTION
  -> RESULTS
```

Crafting is not a prerequisite for this milestone. The match must already be fun and testable with fixed starting equipment, hand-placed resources, and simple beacon combat.

## Player identity and communication

- All living players use the same visual model and readable silhouette.
- No persistent team colors, uniforms, nametags, or overhead role indicators should reveal identity.
- Players identify one another through chat, movement, timing, decisions, visible actions, and social memory.
- Global chat is allowed for living players unless a specific ruleset says otherwise.
- There is no team chat.
- Direct messages are an intentional feature and may create trust, deception, and information asymmetry.
- Ghost chat is locked for all ghosts. Ghosts cannot communicate with living players through chat.
- UI must never silently leak team or role information that the visual design intentionally hides.

## Ghost cloud cage

A player who reaches the ghost phase is transferred to a **cloud cage far above the map**.

The cloud cage is a containment / observation space, not a second combat team.

Ghosts:

- Cannot directly affect either team.
- Cannot damage, heal, mark, block, or communicate with living players.
- Cannot freely return to the map during ordinary ghost state.
- May observe the match only through intentionally limited, designed channels.
- May craft only information items, if the information system is active.
- May use crafted information items after revival.
- May provide information to an alive player only when that alive player deliberately summons them.

The summon interaction should be explicit and costly enough to create a decision, for example:

```text
ALIVE PLAYER ACTIVATES SUMMON RITUAL
  -> GHOST IS TEMPORARILY CONTACTABLE
  -> GHOST OFFERS / TRANSMITS INFORMATION
  -> CONTACT ENDS
```

No passive ghost support exists. If no living player summons a ghost, the ghost remains isolated.

## Evil revival state

Revival is not a neutral respawn. A revived player returns as an **evil ghost** and loses all points earned by that player at the end of the match.

The evil ghost may:

- Fly around the map.
- Taunt through non-chat audiovisual means or permitted interaction channels.
- Possess selected items or objects.
- Sabotage systems and interactable objects.
- Create uncertainty without directly joining either team.

The evil ghost must not become an unbounded griefing tool. Every sabotage action requires:

- A visible or discoverable cause.
- A cooldown or resource limit.
- A clear interaction rule.
- A way for living players to detect, prevent, or recover from it.

Recommended separation:

```text
GHOST IN CAGE       = isolated information state
EVIL GHOST          = voluntary revival with a penalty and map access
```

A player should make an informed choice before revival. The UI must explain the point-loss penalty and the allowed powers.

## No crafting in the first match-loop milestone

Crafting is deferred until the match loop is stable. Do not add a large recipe tree yet.

The first match should be tested with:

- Fixed starting equipment.
- Hand-placed pickups.
- Existing weapons/tools.
- Beacon damage and defense.
- Lives and death transitions.
- Ghost cloud cage.
- Optional evil-ghost revival.
- Match end and clean reset.

## Future crafting model

Crafting should be divided into two classes:

### Personal crafting

Allowed in the player inventory only for non-placeable, non-structural outputs, such as:

- Information fragments.
- Consumables.
- Ammunition or charges.
- Repair kits.
- Keys, tokens, or access codes.
- Temporary personal equipment, subject to balance testing.

### Machine crafting

Any placeable, structural, deployable, or world-affecting output must be produced at a machine or station.

Examples:

- Barriers.
- Turrets.
- Traps.
- Doors.
- Platforms.
- Beacon components.
- Power systems.
- Objective machinery.
- World containers.
- Environmental sabotage devices.

The inventory UI must not offer a button that directly creates these items. The machine owns the recipe, input slots, processing time, power requirement, risk, and output.

Possible machine roles:

- Salvage Bench — breaks down recovered material.
- Fabricator — produces personal equipment.
- Assembly Station — produces placeable structures.
- Signal Terminal — creates or decrypts information.
- Objective Forge — produces the final match objective.

## Information crafting

Information is the first crafting branch worth implementing after the match loop. It should not become free omniscience.

Potential information items:

- Partial map fragments.
- Beacon damage records.
- Last-known movement traces.
- Monster activity reports.
- Door / machine access codes.
- Ghost testimony packets.
- Corrupted incident logs.
- False or incomplete data with provenance and reliability.

Information should answer questions, not solve the match automatically.

## Ghost Altar ritual

The `sl_modebase:ghost_altar` node summons one random connected contained ghost when a living player completes the ritual. The ritual consumes one each of:

- Ashen Relic
- Soul Shard
- Signal Ink

The selected ghost is transported from the cloud cage to the altar for 30 seconds, then returned to containment. The altar does not choose a team and does not create a public chat channel.

Developer chat commands are intentionally creative-only:

- `/sl_summon_ghost <ghost_name>`
- `/sl_ghost_offer <living_name> <security|logistics|medical>`

The physical altar is the intended gameplay ritual. The commands are development/testing controls.

## AI player test harness

AI players should be created as a test harness, not as fake content pretending to be human players.

Required AI roles:

- Beacon A survivor.
- Beacon B survivor.
- Monster Master.
- Ghost.
- Evil ghost.

The harness should support deterministic scenarios:

1. Two teams spawn and complete a match.
2. A beacon is damaged and destroyed.
3. A player loses lives and enters the cloud cage.
4. A ghost remains unable to affect teams.
5. An alive player summons a ghost for information.
6. A ghost revives as an evil ghost.
7. Evil ghost sabotage is detected and resolved.
8. A player disconnects and reconnects.
9. A match ends and resets cleanly.
10. The same match is started again without stale state.
11. The objective path collects resources, routes them through a machine-only craft step, creates the Objective Core, and wins by delivery.

Headless objective smoke test command, creative mode only:

```text
/sl_test_objective
```

AI behavior can initially be scripted. Determinism is more valuable than intelligence for the first test pass.

### Machine audio asset

`mods/content/sl_scary/sounds/random_dizz.ogg` is retained as a valid Luanti-compatible machine malfunction / ritual interference sound for the future machine-crafting and sabotage systems.
