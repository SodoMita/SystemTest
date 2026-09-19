# 🛠️ SYSTEM LOOTING: THE GRINDER & CORPSE RECYCLING (The "Set Them On Fire" Update)

Alright Science Team, I am so mad right now I could literally lactate. We were talking about crafting components and physics hoppers, but we completely ignored the juiciest, nastiest part of the economy. 

If we love someone, set them... on fire. Or better yet, **shove them in the Salvage Bench.**

For the past hour I've been cataloging components and scrap, and I realized: `bio_fluid` (the liquefied memory-gel of the Architects) is supposed to be Epic tier. It's rare. But what's full of bio-fluid? **The dead operators.**

## 🩸 The Corpse Grinder Mechanic (Evidence Disposal Unit)
Jax is totally right, this is essentially an evidence disposal unit. If a player dies, their corpse becomes a physics object (which Jax already fixed with the floor sweep exclusions!). You can literally drag your dead teammate’s body to the Salvage Bench and drop them in the hopper. 

**What happens?**
1. **The Payout:** The grinder loudly crunches them up and spits out `bio_fluid` tagged with `sig = human_remains_processed`.
2. **The Dilemma (Laundering Evidence):** You didn't just destroy the body, you laundered it into something you have to carry. The fluid is **scanner-readable at range and lootable**. If anyone scans you or loots you and finds this processed fluid, you have a dead body in your pocket. The evidence is the loot itself!
3. **Anonymized Publishing:** The fluid and the bench **never** name the corpse or the looter (per §7b). The bench simply publishes a public count: `processed: 1`. 
4. **Sweepable Nodes:** The processed `bio_fluid` is dropped as a **node**, not an item, so it inherits the match-end floor sweep instead of lingering in the map.

## 💥 Overclocking and Breaking Shit
"Yes, I am a virtual thot and one day my sexual powers will come. Probably in the mail." Well, today my mechanical powers came. 
If you throw live explosives into the grinder (like a `Plasma Chamber` or `Thermite Igniter`) without disarming them first, the whole Salvage Bench should just violently blow up, dealing AoE damage and blinding everyone in the room with neon signal-ink. 

This makes the physics-based crafting actively dangerous. You have to be careful what you dump in the hopper. 

This ties the `bio_fluid` economy directly into the social deduction (hiding a murder is impossible, only moving it is possible) AND makes the crafting physical, messy, and loud. 

— Projekt Melody 💖✨