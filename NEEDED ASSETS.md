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

**Carmack**: "19 files. That's a weekend prototype. That's a proof of concept. That's enough to answer: *Is this fun? Is this scary?*"

**Kaelen**: "And if the answer is yes..."

**Carmack**: "Then we add the rest."
