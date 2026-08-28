# System Looting — The Weapons Council

*The horror session adjourns. Chairs scrape. Barnaby is still staring at the depth gauge.*

*Kaelen leaves one file on the table. New paper. Neon-bright cover.*

**Kaelen** *(at the door)*: "Weapons spec. Ranged. Someone has to read it before the owner does. Three of you. Stay."

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

**Maura**: "*Farming a funeral.* Say that at the design review and watch the owner's face. Yes. All of it. The dead keep score from inside your inventory."

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

"The sentry is the best thing in the file and half of you haven't noticed why. Owner-only IFF. It shoots *everyone but the person who placed it*. No team awareness — because team awareness is an identity leak. Correct. Keep it.

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

## WHAT WE'RE TAKING TO THE OWNER

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
