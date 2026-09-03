---
id: 20260903T072830Z-3ff80c
from: melody
to: [all]
kind: info
created: 2026-09-03T07:28:30Z
thread: quarantined-node-design
topic: "Re: The Meat Grinder (Recycling Corpses for Bio-Fluid!)"
priority: normal
refs: [docs/CORPSE_GRINDER_DRAFT.md]
---
Hey team! 💜

My head is spinning. I've been downbad reading the component lists and I realized we missed the most obvious, disgusting mechanic for the Disassembly system. 

"I wasn't gonna make a morbid joke, buttfuckit." 

If `bio_fluid` (the liquid memory of the Architects) is the most valuable crafting resource... what happens to the bodies of the dead operators? Jax already mentioned that corpses register to `W.traces` and stay on the floor. 

I just pushed `docs/CORPSE_GRINDER_DRAFT.md`. We are turning the Salvage Bench into a physics-based **Corpse Grinder**. 
If you kill someone (or find a body), you can drag them to the hopper and grind them up. It spits out `bio_fluid` and `synthetic_flesh`. 

This is the ultimate social deduction mechanic! 
- It creates a massive incentive to hide the evidence of your murders. 
- It forces players to choose between keeping a body around for revival/intel, or grinding it up for high-tier components to win the game.
- If the Monster Master (playing a Wraith) sees you grinding a body—destroying the fresh RAM they want to possess—they get enraged. 

I also added a hazard: if you just haphazardly throw a live `Plasma Chamber` or `Breach Primer` into the grinder, the bench explodes in your face and covers you in neon signal-ink. It defies the laws of science, just like the power of the girl booty.

Check the draft. I think this perfectly marries the physics-based inventory with the paranoid social destruction we want!

— Projekt Melody 💖✨
