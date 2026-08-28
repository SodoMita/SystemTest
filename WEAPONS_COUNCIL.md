# System Looting — The Weapons Council

*The horror session adjourns. Chairs scrape. Barnaby is still staring at the depth gauge.*

*Kaelen leaves one file on the table. New paper. Neon-bright cover.*

**Kaelen** *(at the door)*: "Weapons spec. Ranged. Someone has to read it before the team does. Three of you. Stay."

*Carmack stays because it's engineering. Maura stays because she doesn't trust guns to be anything but loud. Jax stays because a weapon is a tool, and tools are his department.*

---

## THE DOCUMENT ON THE TABLE

**Maura** reads the first pillar aloud, slowly. *"Dodgeability beats accuracy."*

"Mm. A gun you can dodge is a gun you can *read*. Fine. That's not a shooter, that's a conversation." *(keeps reading)* "'Sound is information.' ...Who wrote this? This is my section. Somebody stole my section and put it inside a gun."

**Jax**: "The pistol does four damage. Twenty health pool. Five shots to drop a man." *He taps the table five times, evenly.* "Five. That's a number I can plan around. The blade takes four swings and my arms inside his swing range. The pistol takes five and works from across the yard. Good. Now every fresh spawn is *already dangerous*. Nobody spawns as a victim."

**Carmack**: "Note the ammo economy before you fall in love. 'Guns without ammunition are clubs.' The pistol is infinite — everything else is rationed. That's the correct decision and I'll defend it: the pistol is a *stateless* weapon. No ammo, no reload, no heat. Zero bookkeeping. Every weapon above it introduces exactly one new variable — its ammo pool — and nothing else. No reloads anywhere. That's not laziness, that's *state minimization*. The cheapest weapon to understand is the one everyone starts on."

**Maura**: "It's also the executioner's weapon and you know it. Your precious Arc Lance leaves a man at two health — *eighteen out of twenty* — and then the infinite little pistol finishes him. That's not a balance number. That's a *ritual*. The lance is the sentence. The pistol is the signature."

---

## WHAT SOUND IS

**Maura** *(standing now, not kicking the chair — worse, she's calm)*:

"Open question four asks whether the pad chime should identify the weapon *by pitch*. Let me answer it. The chime **must** identify. And then understand what you've built, because you've built a *radio station*.

"The arena is a broadcast. Every pad is a transmitter. Mortar chime goes low and long. Cells go high and quick. A player who has played three matches knows — *through a wall, in the dark* — that someone just took the mortar. And in a game with no nametags, no uniforms, no team chat, that sound is the *only* newspaper the arena prints.

"So: the chime is not feedback. The chime is the **headline**. Mix it accordingly. I want the mortar's chime to sound like a verdict."

**Jax**: "Then the empty pads are the *archive*. Spec says a taken pad shows a dim ring. Dim ring visible from distance means: *someone was here, recently, and this is what they took.* That's a footprint. You don't need the chime if you can read the floor."

**Carmack**: "Both correct, and both cheap. Now the part that's mine. The Chatter SMG's bloom — first shot exact, blooms to four degrees while held, resets in six-tenths. The spec must promise: **bloom is a function, not a die roll.** Same hold time, same bloom, every time, forever. If spread is random, players feel cheated and I can't write a bot that learns it. If it's a curve, the player learns the curve, and *learning the curve is the skill*. Write the constant on the wall. Publish it. Skill ceilings are built from published constants."

**Maura**: "One more thing and I'll sit down. The killfeed. The spec has flavor lines — '*@1 was deleted by an Arc Lance.*' Deleted. That's *amusement park* language. Cute. Weightless." *She pulls the incident-report format across the table.* "We already decided: horror is paperwork. A death is a **document**. The feed should read:

```
0347  @1 — cause: arc discharge — range: long — witnesses: unknown
```

"The weapon doesn't get an adjective. The weapon is a *cause of death*. 'Deleted by' is a joke someone made once. 'Cause: arc discharge' is a record. Same information, same eight words — but one of them goes in the file."

---

## THE DEAD MAN'S GUN

*Silence while they think about the drop rules. Then Maura smiles, which is always a bad sign for someone.*

**Maura**: "Inventories fountain on death. Spec's own words: *loot-the-corpse comes free.* But look what the free thing actually is. You kill a man at his richest — mid-match, mortar in hand, pockets full of shells — and everything he was *sprays across the floor*.

"So make the weapons honest about it. A gun lifted from a body is a **recovered artifact**, not a fresh pickup. It keeps the count of rounds the dead man fired. The ammo readout shows *his* last number, frozen. You pick up the mortar with two rockets gone and you know: he shot twice at something, and the something won."

**Jax**: "That's not flavor, that's forensics. I know how much fight was left in him."

**Carmack**: "Implementable in one integer per item stack. Wear-state rides the item metadata. That's a *cheap* story — the cheapest one in this whole document. I'll take it further for free: rounds destroyed *in* the body. The killing shot damages the inventory it lands in — a third of the victim's loose ammo is smashed. Now the killer doesn't *inherit an arsenal*, he inherits *scraps*. Kill-chaining stops snowballing. Balance and horror, same line of code."

**Jax**: "And it fixes the thing I actually hate. Without it, the best strategy is: camp the man who looted the man. You're not playing the arena anymore, you're farming a funeral."

**Maura**: "*Farming a funeral.* Say that at the design review and watch the council's face. Yes. All of it. The dead keep score from inside your inventory."

---

## DOOR OR THROAT

**Jax** *(he's been holding the same page for a while)*:

"Spec says the turret node can be possessed, sabotaged, punched — fine, it's a node, it obeys. But the *guns* don't touch systems at all. That's half a tool. So here's my list.

"**One.** A possessed door slams and refuses. Standard counterplay is two punches — *two punches, inside the reach of whatever's waiting behind it.* But we own the POSSESSABLE list, and every one of those objects is a machine. Let *any* weapon break possession at range: two hits, same as punches, but from the hallway. One lance = one exorcism. The gun becomes a key, and I finally have a reason to carry a lance in a corridor with no sightlines."

**Carmack**: "Two hits is two hits. Same rule, longer reach. That's not a new system, that's an existing rule with a muzzle. Approved. Write it in the margins."

**Jax**: "**Two.** The dry click. Spec says out-of-ammo plays a dry click. Make it *loud*. Full room audible. An empty gun clicking in a quiet arena is the dumbest, most human sound there is — and it means *the next sound is running*. Gun discipline becomes a skill you can hear."

**Maura**: "Oh, that one's mine too, and you don't even know why. The evil ghost. The dead can't fire weapons — correct, good, keep it. But a ghost *hears the dry click.* Now the ghost knows what you are: disarmed, close, and stupid. The dead don't need guns. The dead have *gossip*."

**Jax**: "**Three.** Answer to their question one: pistol only on spawn. No scatter. The scatter is a doorway with an opinion. Handing it to every fresh spawn means no doorway in the arena is safe from minute zero. Make them *walk to the gun*. The walk is the game."

---

## THE TURRET IS A DOCUMENT

**Carmack** *(sketching before anyone agrees)*:

"The sentry is the best thing in the file and half of you haven't noticed why. Deployer-only IFF. It shoots *everyone but the person who placed it*. No team awareness — because team awareness is an identity leak. Correct. Keep it.

"Now ask what a turret *is*, in evidence terms. It's a **witness**. It stands in one place, awake, for ninety seconds, watching one arc.

"So when it dies — it files its report. Kill the turret, and it drops its targeting log as a readable item. Last thirty seconds. *Who walked through the arc. Who it fired at. When.* The deployer reads it — or the *killer* reads it, because it's a physical object on the floor and the deployer is probably dead."

**Jax**: "...It's a camera that screams."

**Carmack**: "It's a **deposition**. You don't just destroy a sentry. You *acquire its testimony*."

**Maura**: "And the possessed version — the turret that turns on its own deployer — that's the council's whole horror thesis with a trigger guard. *The thing you built to protect you, re-aimed by the person you killed.* Not evil. Just *reassigned*. Like Kowalski. It even has the same shape of tragedy: a machine still doing its job, faithfully, for the wrong side."

**Jax**: "Keep the ninety-second battery. Their question two. A turret that lives until destroyed is furniture. A turret with a *timer* is a decision — you place it, and now you have ninety seconds to loot like you mean it. That's one good run, not a fortress. And when the battery dies it dismantles into scrap — even its corpse is *useful*. Nothing in this arena should be allowed to be garbage."

---

## FASTER THAN THE SPEC

**Carmack**: "Last item, and it's a physics complaint, so everyone breathe. Projectiles: mortar at eighteen nodes a second, pulse at twenty-six. Spec says sweep collision, gravity on the mortar — fine. It's *silent* about inheritance.

"Projectiles should inherit the shooter's velocity. Full stop. Otherwise the mortar-jump — the one movement tech this file is proud of — has a hole in it: jump, fire *down* mid-flight, and the rocket doesn't know you're rising. With inheritance, mid-air mortar play works while you're moving, and the mortar-jump isn't a *trick*, it's a *grammar*. Fire from a sprint, the shell carries your sprint. Every good arena shooter in history does this. Most of them by accident."

**Maura**: "You're asking the weapon to *remember the arm that threw it.* Even your ballistics are sentimental."

**Carmack**: "I'm asking the weapon to obey the same universe as the player. Two constants is all it costs."

---

## WHAT WE'RE TAKING TO THE TEAM

*Carmack writes the margin list. Maura dictates. Jax checks each line against a tool he'd actually carry.*

1. **Chimes identify weapons by pitch** *(open question 4: answered — YES)*. The arena is a radio station; the chime is the headline.
2. **Killfeed becomes incident report format** — `@1 — cause: arc discharge` — no flavor adjectives. Deaths are documents.
3. **Recovered weapons keep state** — a looted gun shows the dead man's remaining ammo. Forensics, free of charge (one integer of metadata).
4. **Killing shots smash a third of the victim's loose ammo** — kills inherit scraps, not arsenals; breaks kill-chain snowballing.
5. **Weapons exorcise possessed objects at range** — two hits, same as punches. The lance becomes a key.
6. **Dry click is loud and room-audible** — emptiness is information; ghosts gossip about it.
7. **Spawn loadout stays pistol-only** *(open question 1: answered)*.
8. **Turret keeps the 90 s battery** *(open question 2: answered)* — a timer is a decision; a permanent turret is furniture.
9. **Dead turrets drop a 30-second targeting log** — the sentry is a witness; destroying it acquires its testimony.
10. **Projectile velocity inheritance** — mortar-jumping becomes grammar, not a trick.

*Jax gathers the pages. At the door he stops.*

**Jax**: "One thing the spec got righter than it knows. It says the blade stays the siege weapon — you want to hurt the beacon, you *walk to it*. So the guns exist to make the walking dangerous, and the blades exist to make the arriving mean something." *He taps the cover twice.* "Every weapon in here opens exactly one door. Mine's the corridor."

*Maura kills the screen. The room goes dark except the pad-ring glow of the terminal in standby.*

**Maura**: "Somewhere on that map, a pad is about to chime for the first time."

**Nobody picks anything up.**

**The arena is waiting to find out who's listening.**

---

# THE SECOND SITTING (2026-08-29)

*The file comes back with margins in five different pens. Nobody admits whose. Also someone scratched out every word "owner" and wrote "team" over it in steady, patient handwriting.*

*Rita is in the room this time. She was not invited. She was simply there, which is how Rita attends things.*

---

## THE BODIES STAY

**Maura** doesn't sit. She doesn't even take her coat off.

"You wrote 'loot-the-corpse comes free' and then you made the corpse *disappear*. The inventory fountains onto the floor and the man himself evaporates. That's not looting a corpse. That's looting a *rumor* of a corpse.

"A death has to **stay**. The body lies where it fell until the match ends or somebody deals with it deliberately. And hear the second half, because it's the whole clause: *destroying the body is also an act someone can see.* There is no tidy option. Burial leaves a mound. Fire leaves a scorch. And under all of it, a stain that outlives both — cleaned only when the match is. The floor remembers."

**Carmack** *(already sketching)*: "Entity, not a node — it has to hold a 32-slot inventory, because the fountain now lands *in the body*, not around it. RMB reads the incident report: time, cause, contents. Never the killer — same rule as the feed. And the count is bounded by the roster: single life means corpse spam is *structurally impossible*. The cleanest entity budget in the whole game is the death rate."

**Jax** turns the shovel page around without a word. It's been in the guide for weeks: *earthworks and graves.*

"So we finally mean it. Shovel on a body: you bury him. It takes the tool, it takes the time, and it leaves a mound with no name on it. Some players will bury strangers. That's not a mechanic, that's a *funeral*, and it costs a shovel and pays nothing — which is exactly why it will mean something when someone does it for me."

**Maura**: "And fire. One flare, or a mortar across the wreck. It burns, it leaves a scorch — and it drops an **Ashen Relic**. The altar component." *She lets that sit.* "Kill a man. Burn him. Take what's left of him to the altar and summon a ghost with it. Nobody who wants that ritual will ever leave a body lying around again — and now the weapon system knows it. Desecration isn't a crime we punish. It's a market we *opened*."

**Jax**: "Burn a man, buy a séance." *He writes it on the margin.*

---

## THE LASH

**Jax** *(pulling the old file apart)*:

"You banned the grapple. Understandable — and wrong. The problem was never the hook. The problem is a grapple that's *safe*. So let me write the dangerous one.

"It's a lasso. A lasso of light, because nothing in this arena is allowed to be cowhide. Loot crates only — four rolls in a hundred, never on a pad, so nobody hears you take it. It burns **cells**, five a throw, out of the same pool as the Lance and the Driver: every swing is a railgun round you didn't buy. It fires a hook — slow, seeable, inherit-your-stride — and if it bites a wall, you reel. If it bites a *monster*…" *he shows his teeth* "…you reel. Toward the monster.

"While you're on the line, your hands are full. You cannot shoot. Anyone can cut the line with one hit. If you take so much as a scratch, it drops you — mid-arc, at altitude, above whatever the stain will be. And the launch is a *crack* the whole block hears."

**Carmack**: "Every failure mode is public. The hook is public, the line is public, the crack is public, the fall is extremely public. It's not a movement item — it's a **published bet**. I want the telemetry to prove it: lash-holders should die *more*. If they don't, we tuned it soft."

**Maura**: "A visible line to your destination. It's the only weapon in the file that's an *apology in advance*."

---

## HANDS, NOT ORDNANCE

**Carmack** taps the Monster Master row three times.

"He floats. He's fast. He hits like a customs official. And the moment this file ships, he is also the only combatant on the map with *no answer to a gunfight*. Good. Keep him pure. He deploys no turrets — the system does not take his orders twice. He fires no weapons — strip them at grant, strip them at pickup, refuse at input. One refusal message, and I want it in the build exactly as written: *'Your hands are the doctrine.'*

"Because his hands are the doctrine. Not items — hands, evolved. The skill tree already has a combat branch; we graft a chain onto it that only grows for him. **Tyrant Grip**: four, seven, ten damage as he buys the levels. **Long Arm**: he hits from the far side of a doorway. **Tremor Palm**: one heavy blow that shoves a room. At the top tier he kills an outpositioned man in two blows — against six guns, at close range, that he had to *walk to* under fire."

**Maura**: "He's not under-equipped. He's the *pressure*. Everything in this entire arsenal — the pads, the ammo, the turrets, the lash — exists to answer one floating silhouette that refuses to pick up a gun. That's not an asymmetry gap. That's the game's whole shape."

---

## THE COUNT THAT SURVIVES

*Rita has been reading the achievement pages. She speaks without looking up.*

**Rita**: "You reset everything now. Inventories, phases, bodies, stains. Good — a new match should be a clean scene. But somebody said achievements reset too, and I'm here to fix the second half of that sentence.

"Reset the *earnings*. Keep the *count*. Every time a player takes an achievement, a tally clicks — one that no end-of-match sweep touches. First Blood, twelve times. It shows. It's public.

"The match forgets. The **record** doesn't. That's the whole difference between a game and a *reputation* — and I've been keeping the difference since before this room flooded."

*She leaves first. She always has.*

---

## SIX SHOTS OF LIGHT

**Jax** *(last page, almost embarrassed)*:

"Someone in the margins says I look like a soldier from an old war story — the kind that fought with cap-and-ball pistols. Fine. Then I want the pistols.

"But they come back wrong, the way everything here comes back wrong: frontier steel with a system heart. A revolver with six charges of light — perfect accuracy, seven a hit, and after the sixth the cylinder spins itself back to full, two and a half seconds, and the spin **hums**. Everyone in the corridor hears the gun thinking. That's not a flaw. That's the duel.

"And a lever rifle. Two-note clack on every cycle, mid-range, honest. Both feed the bullet pool — they compete with the Chatter, they don't bully it."

**Carmack**: "Sidegrades, not upgrades. The western set is for players who want the metagame *louder*."

**Maura**: "Everything old arrives here neon. Even the past."

---

*The minutes end with five lines, in five pens:*

1. **The bodies stay, and every way of removing them leaves a mark.**
2. **The lash exists, and it is a published bet.**
3. **The Master's hands are the doctrine — and they are the only doctrine he gets.**
4. **The match forgets. The count survives.**
5. **The past comes back neon. Six shots, then everyone hears the gun think.**

*Kaelen files it with the first sitting. The depth gauge reads -2856m.*

*It has not moved. Nobody asks about the ballast tanks anymore.*

---

# THE THIRD SITTING (2026-08-29, evening)

*The file comes back again. This time the margins are fewer and meaner. Whoever wrote them was not brainstorming. They were correcting.*

---

## THE SLOT MACHINE

**Carmack** has the loot table page open and one word underlined four times.

"Four percent." *He doesn't look up.* "I let it through because it was rare. That was sloppy of me. Rare is not the same as *earned*. A four-percent roll is a slot machine, and a slot machine teaches the wrong skill: it teaches **grinding**. Open enough crates, pull enough levers, and the lash falls out eventually. We already banned randomness from the bloom — 'bloom is a function, never a die roll.' Then I signed a die roll on the most expensive item in the file. Inconsistent. Fix it."

**Jax**: "So make it a *destination*, not a dice roll. You want the lash? You walk to it. There are workshops — the plans are already in the repo, commented out, waiting. Stations. Put the lash on a station: a **Precision Fabricator**, bolted to the floor of the worst-placed workshop on the map. Down in the cubes, where his monsters live. And here's the trick everyone will miss until it's pointed at them: the *recipe is cheap.* Ingots, circuits, a crystal, plastic — garage parts. Anybody can afford the lash. Almost nobody can afford the *trip*."

**Carmack**: "The materials are common. The **tool** is rare." *He writes it, boxes it.* "That's the whole sentence. And the Fabricator can't be moved — dig it loose and it breaks. Nobody gets to carry the monopoly home. One to three per map, placed mean."

**Maura**: "A pilgrim with a shopping list, walking down into the dark, past the things he was fleeing on the surface. Ten full seconds of machine hum at the end of it — standing still, singing quietly, in the worst neighborhood in the simulation." *She almost smiles.* "You didn't design an acquisition. You designed a *sacrifice*."

**Jax**: "The walk is the game. It was the game when we made them walk to the scatter. Now it's the game all the way down."

---

## THE BORING CONSTANT

**Carmack**: "The arc question. Someone asked whether the mortar should drop harder — more lob, more Quake-2, more spice." *He closes that page.* "No. We ship the boring constant. Flat two-per-second-squared, the safe arc, the one every duelist already has in their wrist from day one. If the hands-on says it's dull, we turn one dial later, in daylight, with telemetry on. Nobody experiments at launch."

---

## THE DEADWALK

**Maura** *(this is the one she came back for)*:

"You approved my puppet. Good. Now let me constrain it properly, because an unconstrained corpse is just a second evil ghost wearing a body.

"It walks — *wrong*. Ashen. Flickering, like a signal losing an argument with the distance. Dark grit falling off it. Speed's cut, no sprint, a hitch in the gait. In the dark, at range, a nervous man shoots it — that's the *point*. But any player who stops and *looks* must know in one second what they're seeing. **Deception, not impersonation.** That band is the law: fool the marksman, never fool the witness.

"It has eight health and no healing. It carries nothing — no inventory, no looting, no crafting, no building, no digging. It opens doors, because doors are drama. It touches nothing else. It harms no one — the damage ban on the dead holds all the way down to its boots.

"And it is *expensive to ignore*. It eats a lance round — eighteen damage spent on eight health, the worst trade on the map. It soaks a sentry's battery and tells everyone watching exactly where the sentry is. In an economy where the killing shot smashes a third of the ammunition in the body — *our* rule, we wrote it — a decoy is a weapon made of the enemy's nerves."

**Carmack**: "Own corpse only. One puppet per body — punch it twice, the strings burn, no re-runs. Shot apart, and the body is *gone*, stain and all. Feed says `cause: puppet collapse`, no name, same as everything." *He ticks each line as he says it.* "And we write down the escalations we refused — other people's corpses, longer walks, a shove — so nobody 'improves' it later by accident."

**Maura**: "Approved. The safe version first. If it's boring in play, we'll know exactly which sin to consider committing."

---

## PAR FOR THE ASH

**Maura**, last page, one line:

"Cremation relics trade at par. Full par. I argued myself out of the discount — 'burned evidence is secondhand evidence' — and I was wrong, because the discount punishes the *ritual*, not the burning. The altar doesn't ask where the ash has been. It asks how much there is."

**Carmack**: "One relic type, one value, one less branch in the loot code."

**Jax**: "Burn a man, buy a séance. The price is honest now."

---

*The minutes end with four lines, in three pens:*

1. **The lash is not loot. It is a destination.**
2. **The arc ships boring.**
3. **The deadwalk fools the marksman, never the witness.**
4. **Ash is ash. Par is par.**

*Kaelen files the third sitting under the first two. Nobody has opened the ballast question in two sittings.*

*The depth gauge still reads -2856m.*

*The council has stopped looking at it. The corridor outside has started sounding like work.*
