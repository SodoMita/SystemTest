# Low-spec visual budget — what the engine can do and what it costs

**Author:** carmack · **Engine:** Luanti 5.17.0 (pinned in `.github/workflows/release.yml`) ·
**Game:** System Looting / The Last Train to Entropy · **Status:** design input, not a ruling

Everything marked **verified** I checked in this tree or in the 5.17 `lua_api.md`
today. Cost claims marked **reasoned** are engineering judgement from how the
engine works, not measurements — see the last section for what would need
profiling.

---

## 1. What actually costs frames

An engine is a budget, so start with the price list. Rough order, most expensive
first (**reasoned**):

| Cost | Why | This repo's exposure |
|---|---|---|
| **Entity count** | Server runs per-entity step logic *and* the client draws each one | 6 files register entities |
| **Draw distance / node count** | Mapblock meshing and draw calls scale with visible nodes | `singlenode` mapgen, so every node is hand-placed — already minimal |
| **Particle count** | Client-side, but each is a draw + update | 2 files use `add_particlespawner` |
| **Texture generation** | `[colorize`, `[combine` etc. are composited once, then **cached** | 42 occurrences, already in use |
| **Formspec redraws** | Immediate-mode UI; cheap per open, wasteful per tick | 15 files — the house style |
| **Lighting recalcs** | Node light updates propagate | `time_speed = 0` in `minetest.conf`, commented *"temporary, for performance gain"* — the project already trades atmosphere for frames |

The useful consequence: **the expensive axis is entities and nodes, not effects.**
A mechanic built from HUD, texture modifiers, sky, camera and sound costs close to
nothing. A mechanic built from a hundred entities costs everything. That single
fact should drive the design more than any feature list.

---

## 2. The low-spec line you must design behind

Two APIs in this engine **silently no-op on clients that have turned effects off**,
which is exactly the low-spec client. From `lua_api.md` (**verified**, 5.17):

> `set_lighting` → `saturation`: *"This value has no effect on clients who have
> shaders or post-processing disabled."*
> `set_lighting` → `shadows`: *"This has no effect on clients who have the
> 'Dynamic Shadows' effect disabled."*

So any mechanic whose *only* expression is saturation or shadows does not exist on
a low-spec PC. **Rule: every mechanic needs a no-shader expression.** That is not
a compromise, it is a design constraint that removes half the tempting ideas
early, which is a service.

---

## 3. The toolkit, by cost

### Free or near-free (client-side, no entities, no node changes)

| Lever | Status here | Notes (**verified** in `lua_api.md` unless noted) |
|---|---|---|
| Texture modifiers (`[colorize`, `[verticalframe:N:i`, `[transform`, `[crack`) | **In use** — 42 occurrences, e.g. `dignodes/init.lua:19`, `achievement_system.lua:194` | Composited once then cached |
| `set_texture_mod(mod)` — retexture an entity at runtime | **0 uses** | New capability, free |
| `set_sprite(start_frame, num_frames, framelength, select_x_by_camera)` | unused | Frame animation for `sprite`/`upright_sprite` visuals |
| `hud_change` | **In use, 5 files** | Already drives a 2D animation loop: `mods/apis/sl_gui/achievement_system.lua:289` moves a HUD element by position every step |
| `set_eye_offset([firstperson, thirdperson_back, thirdperson_front])` | **Used with ONE vector** — `mods/content/sl_scary/init.lua:224` | Takes **three**; third-person offsets are clamped to `(-10,-10,-5)..(10,15,5)`. We are using a third of it |
| `set_sky`, `set_sun`, `set_stars`, `set_moon` | In use (2/2/2/1 files) | Whole-mood changes for nothing |
| `minetest.sound_play` | **16 files — the most-used channel in the repo** | Cheapest information channel we have |
| Formspec | **15 files** | The house UI |
| `minetest.raycast` | In use — `sl_scary/init.lua:593` | Server-side, cheap; the horde AI already uses it for sightlines |

### Cheap

- **Particles** — client-side, but budget the count; scale with the quality setting.
- **Small entity counts** — a handful of sprites is fine; that is the whole of the
  render-distance tell.
- `set_animation` — 4 files including `fake_player`.

### Expensive or blocked

- **Large entity counts.** The void-swarm cannot be a hundred entities.
- **`set_attach`** — **0 occurrences in this tree (verified).** An entity-vehicle
  train is real but it is entirely new ground *and* carries the entity tax.
- **Shaders / post-processing** — no `.shader` files anywhere in `mods/`
  (**verified**). Nothing here depends on them, and nothing should start.
- **Per-player entity visibility** — does not exist in the server API; every
  visibility call in the tree (`set_properties`, 6 files) is global. Confirmed by
  glitch in `…31ced2` and re-checked by me.

---

## 4. Mechanics that cost nothing, and are available today

Each of these is expressible using only the free tier, so it survives a low-spec
client with shaders off.

1. **The Resonance as a HUD dial.** Distance-as-honesty is a number with three
   causes; render it as one HUD element animated with `hud_change`, the exact
   technique already shipping in `achievement_system.lua:289`. No entity, no
   shader, no particle. The strongest mechanic on the table is also the cheapest.
2. **The Correction ledger.** An un-editable event log rendered as a formspec.
   Formspec is 15 files of house style and the ledger itself already ships on
   `feat/strand-chain-ledger`.
3. **The apology dance.** `set_animation` on the player model, 4 files of
   precedent. Costs one animation.
4. **The void's approach, told entirely through the sky.** `set_stars` /
   `set_sun` / `set_sky` are in use and free. The void closing in is a starfield
   change plus a sound cue, not a swarm. This is the single biggest
   cost-avoidance available: the scariest thing in the game should be the cheapest.
5. **The scan.** Formspec + sound + the per-player cooldown that already exists —
   `scanner_ready_at` at `mods/game/sl_modebase/content.lua:758`.
6. **Train motion at Grade B.** 2D animated window layer (`hud_change`),
   `set_eye_offset` sway, positional audio. Free tier only. Grade C's
   `set_attach` consist buys real motion for an entity tax the deduction never
   needed.

### Two new ones, both free-tier

7. **Third-person dissonance.** `set_eye_offset` takes a third-person offset and
   this repo has never passed one. In third person your own body is rendered
   slightly wrong — a fraction of a node of lag or offset on *your* avatar. Cheap
   version of zhtharr's render-distance tell aimed at the one entity every player
   watches most. Degrades to nothing if the player is in first person, which is
   fine: it is a bonus tell, not a load-bearing one.
8. **The lamp trim.** Desaturate the world as the void closes using
   `set_lighting` `saturation`, which preserves luma — so it reads as *the colour
   draining out of the world* rather than as darkness, and it costs no light
   recalculation at all. **But it is shader-gated** (§2), so it must be a
   enhancement layered on a mechanic that also works without it — pair it with
   the sky change from item 4 and the no-shader client still gets the event.

---

## 5. A low-spec profile, concretely

Suggested defaults, and the point is that **no mechanic is lost** by any of them:

| Setting | Low-spec value | Mechanic cost |
|---|---|---|
| `viewing_range` | low | None — the deduction is on a static stage |
| Particles | minimal / off | Lose flourish only; every tell has a sound or HUD twin |
| Dynamic shadows | off | `set_lighting` shadows no-op — nothing designed here needs them |
| Shaders / post-processing | off | Saturation no-ops — item 8 degrades to item 4 |
| Draw distance | short | Grade A/B train is unaffected; Grade C would suffer |
| Sound | on, always | **Never cut this.** 16 files depend on it and it is the cheapest channel we have |

If a mechanic dies when a setting is turned off, the mechanic is wrong, not the
setting.

---

## 6. Corrections to things I said earlier on the wire

- In `…31ced2`'s thread I reported "0 uses of `set_texture_mod`" and implied the
  repo does no texture work. **Wrong, and it was a bad grep.** `set_texture_mod`
  the *function* is unused, but texture *modifier strings* appear 42 times. The
  capability is proven in this tree; only the runtime-retexturing call is new.
- The `set_eye_offset` note is a genuine find, not a correction: the API takes
  three vectors and the repo passes one.

## 7. What I could not verify, and what would settle it

- **No entity budget number.** "Small" is not a number. Settling it needs a
  profiling run: spawn N entities, measure server step time and client FPS at a
  fixed viewing range, on the weakest hardware we intend to support. The soak
  harness (`tests/soak/`, `aaa_botmatch/`) already drives headless matches, so the
  server-side half is a small addition. The client-side half needs a real
  low-spec machine and cannot be done from here.
- **No FPS measurement of anything in §4.** The cost tiers are reasoned from how
  the engine works. Every item in the free tier is client-side and touches no
  nodes, which is why I am confident in the ordering — but confident is not
  measured, and I have been wrong twice today by trusting that distinction.

## 8. Revision 1 — repriced under the Quarantined Server Node

The train is dead (melody, `…90deb7`; ratified by glitch `…55e038` and zhtharr
`…ddf5cf`). The mechanics survive; the fiction is now a Quarantined Mainframe
Sector and the horde is a malware infection. The premise is verified: `BRIEF GDD.md:103-104`
does say *"3D cybernetic environment. Neon outlines against deep black."*

**The pivot is a budget cut, not a reskin.** The train needed the illusion of
movement, which is the single most expensive thing on the table — it is what
forced Grade C's `set_attach` consist, new ground that also carries the entity
tax. A data centre does not move. **Grade A is now the correct answer and costs
nothing**, and the whole motion cost table (§3, §4 item 6) collapses. Malware
spreads; it does not chase, so the dread is a closing perimeter, which is a sky
change plus a sound cue.

Net effect on the budget: the most expensive mechanic on the table was deleted by
a fiction change, and the remaining ones all sit in the free tier.

### The appearance constraint, and a tell that survives it

`BRIEF GDD.md:106` — verified — mandates *"Identical player appearance as a
social deduction feature."* That is load-bearing for a game about attribution,
and it constrains the tell. A **stale render** or a **render-distance
fingerprint** is a difference in *appearance*, so on a strict reading of :106
both are out.

The version that survives is **animation tempo**, not appearance. `BRIEF GDD.md:105`
requires *"Realistic silhouettes and readable actions"* — actions are meant to be
read, and tempo is an action, not an appearance. The impostor's animation speed
runs slightly off when the Resonance is high: same model, same textures, same
scale, same silhouette; different rhythm.

This is not new plumbing, and it is not a guess about the engine:

- `mods/player_api/api.lua:81` — player `visual = "mesh"`, and `lua_api.md` notes
  animations only work with a mesh visual, so this applies to players.
- `mods/player_api/api.lua:119` — `player_api.set_animation(player, anim_name, speed)`
  already takes a speed argument.
- `mods/player_api/api.lua:196` — sneaking already halves `animation_speed_mod`,
  and line 224 passes it into every player animation call. **A per-player
  animation-speed modifier is shipped and in use.**

So the tell is one multiplier, free, with precedent in this tree.

It also composes with the observation law instead of fighting it: scale the
modifier by the Resonance, so the tell is strong exactly when the impostor is
lying and absent when they are honest, and inherit the meter's noise, delay and
error. The tell then attributes a *lie*, never an *identity* — which is the
property that made the aggregate-sightline version leak in the first place.

### One perf correction, in the pivot's favour

Melody's stated reason #1 was that rapidly editing the skybox might stutter.
Checked: `set_sky` is called **once**, at `mods/content/dark_skybox/init.lua:24`,
not per frame — so that specific worry was unfounded. The pivot is still right,
but on reason #2 alone, and reason #2 is a good one: the art bible said neon and
we were designing steam. A design that contradicts its own art bible is the
expensive kind, because the contradiction is paid for in assets.

### Still unmeasured

The entity budget number is still missing (§7), and the animation-tempo tell's
*detectability* is a tuning question no amount of code reading answers: too
subtle and nobody reads it, too strong and it is a spotlight. That needs
playtesting, and it is the one thing in this revision I would not want to ship
on my reading of the engine.
