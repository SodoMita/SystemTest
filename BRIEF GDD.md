```md
# SYSTEM LOOTING — CORE DESIGN BRIEF

A competitive survival game inside a hostile cybernetic simulation. Teams fight around beacons while identical-looking players infer identity through chat, movement, choices, and observed actions.

## Core Match

- Players enter a shared lobby and complete a ready check.
- Players are assigned to beacon teams; one player may become the Monster Master.
- The match takes place on a hand-built arena using the `singlenode` mapgen.
- Players scavenge, move, defend, and attack. Single life: the first death sends a player to the cloud cage.
- Initial match gameplay uses fixed equipment and hand-placed pickups.
- Crafting is a later system, not a requirement for the first playable loop.
- Win conditions may include elimination and, later, objective delivery, defense, and point modes (points not yet implemented — see "Points (Challenge)").

## Identity Is Deliberately Ambiguous

All living players use the same visual identity. There are no permanent uniforms, nametags, or obvious team markers. Players identify one another through:

- Chat and direct messages.
- Movement and timing.
- Visible actions.
- Alliances and betrayal.
- Memory of previous decisions.

There is no team chat. Direct messages are an intentional social mechanic.

## Death and Ghosts

Death is a state transition, not an immediate exit.

```text
ALIVE -> GHOST IN CLOUD CAGE -> REVIVAL (FORM CHOICE) -> EVIL GHOST or UNDERGROUND MONSTER -> ELIMINATED
```

### Ghost in Cloud Cage

- The ghost is held in a cloud cage far above the map.
- Ghosts cannot directly affect either team.
- Ghost chat is locked for all ghosts.
- Ghosts cannot damage, heal, mark, block, or communicate with living players.
- Ghosts may craft information items only.
- An alive player may deliberately summon a ghost.
- A summoned ghost may offer information to that player.
- Information can be used after revival.

### Revival Forms
Revival is a voluntary and morally negative choice. Reviving is not a single state: a contained ghost chooses **which form** to come back in.

- **Evil Ghost** (base form) — the reviver stays in a humanoid form and plays the **pure-hate / revenge role**: they forfeit all match points and cannot earn or win on points for the rest of the match. In exchange they play for revenge — hunting the living, possessing, corrupting, and breaking what was lost. Their measure of success is not the scoreboard; it is the damage they leave and the uncertainty they seed.
- **Underground Monster forms** — non-human revival forms drawn from the horror bestiary (the `sl_scary` lineage to start: Dredger, Signal Wraith, Containment Horror, with more underground types added over time). Each form has its own abilities, strengths, and counterplay, distinct from the Evil Ghost and from each other.

**Unlocking by crafting (form items).** Every non-default form is gated by a dedicated **form item**: a non-placeable personal-inventory craft item. Form items are crafted **while alive** (ghosts may craft information items only, so the choice is prepared before death) and **consumed on revival** to take that form. A ghost holding no form item can take only the base Evil Ghost form via the base reincarnation item. Form items are a personal-preparation decision, not a placeable and not a world change.

An evil ghost (base form) may:

- Fly around the map.
- Taunt through permitted audiovisual interactions, not normal ghost chat.
- Possess selected items or objects.
- Sabotage systems and interactable objects.

All revival-form abilities (Evil Ghost and Underground Monster forms) require cooldowns, discoverable causes, and counterplay. They must create uncertainty, not unrestricted griefing. Revenge-specific targets and bounds for the Evil Ghost role are an open design detail, to be defined within that framework.

## Points (Challenge)
Points are the match's challenge currency: they measure what a player accomplished during a match and are public on the result screen. Planned sources include kills, repairs, sabotage survived, beacon pressure, and objective actions; the economy is tuned via soak-test telemetry (per-match point deltas alongside win rates and K/D).

- Points feed the planned **point-based win mode** (see "Core Match").
- **Evil Ghost revival forfeits all points and removes the ability to earn or win on them** — that sacrifice is the price of the revenge role (see "Revival Forms").
- **Status: not implemented.** The per-player points state, the result-screen point column, and the revival forfeit already exist in code; no earn rule is implemented yet, so all scores currently read 0. The point economy must land before point-based win modes (see ROADMAP, Phase 5).

## Monster Master

The Monster Master is an asymmetric commander. The long-term design includes:

- Monster deployment.
- Unit upgrades.
- Command and target priorities.
- Obstacles and traps.
- Income based on monster activity.

The initial milestone may use only basic scripted monster deployment.

Milestone progress: the **Monster Spawner Unit** node implements basic
deployment. The Monster Master crafts and feeds the unit with **Monster
Essence** (one per spawn), clicks it to open the spawner GUI, and chooses
which creature to release from the list — **Stalker** (balanced), **Scout**
(fast, fragile), **Brute** (slow, tanky, heavy hitter), plus the sl_scary
horror mobs **Dredger**, **Signal Wraith** and **Containment Horror**.
Only the Monster Master can operate the unit.

## Crafting Direction

Crafting is deferred until the match loop is stable.

- Personal inventory crafting may produce non-placeable items such as information, consumables, charges, repair kits, keys, tokens, and form items (revival-form keys — see "Revival Forms").
- Placeable, structural, deployable, or world-affecting items may **not** be crafted directly in the player inventory.
- Those items must be produced on dedicated machines or stations with input slots, processing time, and risk.

The first future crafting branch should focus on information items. Information should be partial, contextual, and sometimes unreliable — never automatic omniscience.

## Visual Direction

- 3D cybernetic environment.
- Neon outlines against deep black.
- Realistic silhouettes and readable actions.
- Identical player appearance as a social deduction feature.
- Hand-built arena rather than procedural mapgen.

## First Playable Target

```text
LOBBY -> READY CHECK -> TEAM ASSIGNMENT -> SPAWN
-> MOVE / SCAVENGE -> COMBAT / BEACON PRESSURE
-> DEATH TRANSITIONS -> MATCH RESOLUTION
-> RESULTS -> CLEAN RESET
```

A match must be playable by humans or scripted AI players without administrator intervention after setup.
```
