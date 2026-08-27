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
- Win conditions may include elimination and, later, objective delivery, defense, and point modes.

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
ALIVE -> GHOST IN CLOUD CAGE -> EVIL GHOST AFTER REVIVAL -> ELIMINATED
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

### Evil Ghost

Revival is a voluntary and morally negative choice. The revived player becomes an evil ghost and loses all points earned by that player at the end of the match.

An evil ghost may:

- Fly around the map.
- Taunt through permitted audiovisual interactions, not normal ghost chat.
- Possess selected items or objects.
- Sabotage systems and interactable objects.

Evil ghost powers require cooldowns, discoverable causes, and counterplay. They must create uncertainty, not unrestricted griefing.

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

- Personal inventory crafting may produce non-placeable items such as information, consumables, charges, repair kits, keys, and tokens.
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
