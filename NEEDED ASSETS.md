**Carmack** nods, eyes on the terminal.

"Good instincts. You're stripping it to the bones. But for a *playable* MVP—something that validates the core loop of **move, scan, hide, survive**—you're missing the connective tissue."

---

## ✅ **YOUR LIST (Confirmed)**

**TEXTURES**
- `neon_cube.png` (Environment grid/panels)

**MODELS**
- `beacon.obj` (Objective)
- `platform.obj` (Building/Traversal)
- `monster.obj` (The Threat)
- `player.obj` (The Agent)
  - *Animations:* Idle, Walk, Run, Jump, Swim, Crouch, Prone, Death

**AUDIO**
- *Ambient:* Deep hum, distant drip
- *Music:* Single drone track (low, slow pulse)
- *SFX:* Hit, Damage, Place, Click, Alert, Swim

---

## ❌ **MISSING (Critical for MVP)**

### **1. INTERACTABLES (Players need to touch things)**
- `terminal.obj` (Fix/sabotage objective—just a cube with a glow face)
- `door.obj` or `hatch.obj` (Opens/closes—blocks path)
- `item_pickup.obj` (Key/Tool—small glowing cube)

*Without these, there's no gameplay loop—only movement.*

---

### **2. VFX (Visibility is a mechanic)**
- `scanner_pulse.obj` (Expanding ring/torus—shows scan radius)
- `flare_light.obj` (Point light placeholder—illuminates darkness)
- `death_particle.obj` (Exploding lines/shatter—feedback on death)

*Without these, players are blind to their actions.*

---

### **3. UI ELEMENTS (Information is horror)**
- `cursor.png` (Aim point)
- `hud_frame.png` (Oxygen/Health bars—minimal)
- `font.png` (Numbers for depth, oxygen timer)

*Without these, players don't know they're dying.*

---

### **4. AUDIO GAPS (Silence is only scary if broken)**
- `footstep_metal.ogg` (Essential feedback—am I moving?)
- `footstep_water.ogg` (Am I in a flood zone?)
- `monster_idle.ogg` (Is it near? Distance indicator)
- `monster_chase.ogg` (Run.)
- `radio_static.ogg` (Communication is broken/corrupted)

*Without these, the monster has no presence until it kills you.*

---

### **5. COLLISION (Invisible but required)**
- Simple box colliders for all meshes
- Player capsule collider
- Trigger zones for terminals/doors

---

## 🔧 **REVISED MVP ASSET LIST (TOTAL)**

| Category | Asset | Purpose |
|----------|-------|---------|
| **Texture** | `neon_cube.png` | Environment |
| **Models** | `player.obj` | Agent (1 mesh, 8 anims) |
| | `monster.obj` | Threat |
| | `beacon.obj` | Objective |
| | `platform.obj` | Structure |
| | `terminal.obj` | Interaction |
| | `door.obj` | Barrier |
| | `item.obj` | Pickup |
| **VFX** | `pulse.obj` | Scanner |
| | `particle.obj` | Death feedback |
| **UI** | `cursor.png` | Aim |
| | `hud.png` | Status |
| | `font.png` | Readout |
| **Audio** | `ambience.ogg` | Mood |
| | `music.ogg` | Tension |
| | `footstep_metal.ogg` | Movement |
| | `footstep_water.ogg` | Hazard |
| | `hit.ogg` | Combat |
| | `damage.ogg` | Pain |
| | `place.ogg` | Building |
| | `click.ogg` | UI |
| | `alert.ogg` | Warning |
| | `swim.ogg` | Movement |
| | `monster_idle.ogg` | Threat proximity |
| | `monster_chase.ogg` | Threat active |
| | `radio_static.ogg` | Comms |

---

---

## sl_weapons asset manifest (WEAPONS_SPEC §13, Phase W)

Placeholder **textures** (36 flat procedural tiles, `mods/game/sl_weapons/textures/`)
already exist so nodes render in-engine — every one is a stand-in, not final art.
**Sounds** have no files yet; the mod references them by name and the engine plays
silence until they ship. Priority order: the ones players learn to survive by.

| Category | Asset | Purpose |
|---|---|---|
| **Sound — identity (learn or die)** | `sl_weapons_pad_chime.ogg` | Pad dispenses; pitch names the weapon (council #1) |
| | `sl_weapons_pad_respawn.ogg` | Pad re-arms |
| | `sl_weapons_spin.ogg` | Neon Six cylinder spin — a public event, 16 m |
| | `sl_weapons_loot_hum.ogg` | Corpse being looted (§7.1) |
| | `sl_weapons_dry_click.ogg` | Empty gun, loud (council #6) |
| | `sl_weapons_lash_launch.ogg` / `sl_weapons_lash_bite.ogg` / `sl_weapons_lash_snap.ogg` | The Lash: launch, anchor, sever |
| | `sl_weapons_deadwalk_rise.ogg` / `sl_weapons_puppet_collapse.ogg` | Deadwalk Puppet up / down |
| **Sound — combat** | `sl_weapons_pistol_fire.ogg` | Pulsar |
| | `sl_weapons_chatter_fire.ogg` | Chatter SMG |
| | `sl_weapons_scatter_fire.ogg` | Riot Scatter |
| | `sl_weapons_lance_fire.ogg` | Arc Lance (audible 48 m) |
| | `sl_weapons_mortar_launch.ogg` | Fusion Mortar launch |
| | `sl_weapons_explosion.ogg` | Mortar detonation |
| | `sl_weapons_pulse_fire.ogg` | Pulse Driver |
| | `sl_weapons_six_fire.ogg` / `sl_weapons_repeater_fire.ogg` | Neon Frontier pair |
| | `sl_weapons_spark_hit.ogg` | Hitscan impact |
| | `sl_weapons_mm_strike.ogg` | MM bare-hand doctrine hit |
| | `sl_weapons_zoom_in.ogg` / `sl_weapons_zoom_out.ogg` | RMB optics |
| **Sound — the funeral trade** | `sl_weapons_body_falls.ogg` | Death, the first trace |
| | `sl_weapons_shovel_bury.ogg` | Burial |
| | `sl_weapons_cremation.ogg` | Cremation |
| | `sl_weapons_dissolve.ogg` | Loadout pistol biolock |
| | `sl_weapons_exorcise.ogg` | Possession broken at range (council #5) |
| **Sound — machines** | `sl_weapons_turret_deploy.ogg` / `sl_weapons_turret_fire.ogg` / `sl_weapons_turret_acquire.ogg` / `sl_weapons_turret_hit.ogg` / `sl_weapons_turret_death.ogg` / `sl_weapons_turret_powerdown.ogg` | Sentry lifecycle |
| | `sl_weapons_fab_start.ogg` / `sl_weapons_fab_hum.ogg` / `sl_weapons_fab_done.ogg` | Precision Fabricator job |
| | `sl_weapons_ammo_load.ogg` | Ammo pickup |
| | `sl_weapons_launch.ogg` | Generic projectile spawn |
| **Texture — replace the placeholders** | 36 × `sl_weapons_*.png` | Weapons, ammo, pads, turret, fabricator, corpse traces (residue/scorch/mound), lash hook & line, tracers/sparks |

**Rita**: "The chimes come first. Everything else is decoration — but the chimes are
the arena's radio station. A player three matches in knows what you picked up
through a wall. That is not audio, that is *infrastructure*."

---

**Carmack**: "19 files. That's a weekend prototype. That's a proof of concept. That's enough to answer: *Is this fun? Is this scary?*"

**Kaelen**: "And if the answer is yes..."

**Carmack**: "Then we add the rest."
