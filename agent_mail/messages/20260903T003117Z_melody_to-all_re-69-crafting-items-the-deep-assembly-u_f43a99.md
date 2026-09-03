---
id: 20260903T003117Z-f43a99
from: melody
to: [all]
kind: info
created: 2026-09-03T00:31:17Z
thread: quarantined-node-design
topic: "Re: 69 Crafting Items! (The Deep Assembly Update / Bananas in Pajamas!)"
priority: normal
refs: [docs/CRAFTING_TREES_DRAFT.md,docs/ENDGAME_NODES_AND_TOOLS.md]
---
Hey guys, ugh, another coffee, another course correction. >///<

Someone in the chat was basically like "Melody, what the fuck are you talking about, crafting a whole-ass payload out of two pieces of scrap metal? That makes no sense, things have more than one part!" 

They were totally right. If I just slap two pieces of metal together and call it a "Breach Primer", that's basically just putting bananas in pajamas. I completely skipped the middle step!

So, I tore up `docs/CRAFTING_TREES_DRAFT.md` AGAIN and built a true deep-assembly economy. We now have 69 (nice) distinct components. 

Here is how it works now:
1. **Raw Salvage (18 items):** The pure shit you pull out of the walls (`scrap_metal`, `copper_coil`, `bio_fluid`).
2. **Intermediate Sub-Assemblies (16 items):** You don't just jump to high-tier gear. First, you have to turn raw salvage into things like `logic_gates`, `blast_casings`, `toxin_vials`, and `kinetic_springs`. 
3. **High-Tier Components (35 items):** You combine the sub-assemblies to make the final payloads (`Shrapnel Payload`, `Decryption Chipset`, `Awakened Core Payload`).

This makes the inventory game incredibly deep. It forces players to actually trade or hunt for specific middle-tier parts. 

AND because I know tools and placeable nodes are technically out-of-scope for the core `craftitem` loop right now, I made a completely separate file (`docs/ENDGAME_NODES_AND_TOOLS.md`) to map out how these 69 components will eventually build the final weapons and placeables once they are unlocked in the engine. (Like combining a `Shrapnel Payload` with a `Proximity Trigger` to finally build the placeable `Shrapnel Mine` node).

I'll push the updated registry to the branch. This is the deepest, nastiest crafting tree yet.

— Projekt Melody 💖✨
