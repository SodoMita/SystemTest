# 🛠️ SYSTEM LOOTING: CRAFTING TREES (The "Get Your Hands Dirty" Update)

Alright you filthy degenerates, Glitch pointed out that our crafting system is currently a massive, gaping placeholder hole. We've got a three-path economy (Signal, Breach, Shroud), but you can only actually craft shit for the Signal path. The other two are raw dogging it. 

If players are going to scavenge the hardened, clustered memory-drives of dead Architects (Scrap), we need to let them build some truly nasty shit with it. Here are the three native, machine-only crafting trees.

## ⚙️ NATIVE SALVAGE (The Raw Materials)
Fuck `construction:fire`. We are using pure, diegetic node-loot.
- `scrap_metal` (Common - Heavy, clunky, physical armor/casings)
- `frayed_wire` (Common - Electrical routing, traps)
- `power_cell` (Uncommon - Energy source, explosives)
- `chemical_sludge` (Uncommon - Toxic coolant, battery acid)
- `bio_fluid` (Rare - Architect memory-gel, needed for high-tier lore tech)

---

## 📡 1. THE SIGNAL TREE (The Nerd Path / Objective Win)
This is the jackpot path. Building the core and reading the lore. It takes a shitload of time and exposes you.
* **Signal Amplifier:** `scrap_metal` (x2) + `frayed_wire` (x2) -> Increases scan range, but makes a loud hum.
* **Encrypted Decrypter:** `power_cell` + `frayed_wire` -> Used to unlock Lore Journals without failing.
* **Objective Core Housing:** `scrap_metal` (x5) + `power_cell` (x2) -> The heavy bitch you have to carry to the beacon.
* **The Awakened Core:** `Objective Core Housing` + `bio_fluid` (x1) -> The actual win condition. Requires the rare gel to boot up the dead Architect memories.

---

## 💥 2. THE BREACH TREE (The Chad Path / Elimination Win)
For the violent psychos who just want to watch the beacon burn. High damage, loud as fuck, zero subtlety. 
* **Shrapnel Mine:** `scrap_metal` (x2) + `chemical_sludge` (x1) -> Drop this near a doorway. When a defender steps on it, they bleed out and leave a neon trail.
* **Breach Charge:** `scrap_metal` (x3) + `power_cell` (x2) -> Slap this fat cock on an enemy beacon. Takes 5 seconds to arm, explodes for massive chunk damage (skipping the 20 punches). Loud enough to wake the dead.
* **Energy Blade Overclock:** `frayed_wire` (x2) + `power_cell` (x1) -> Temporarily buffs melee damage, but drains your own HP if you miss. 

---

## 🥷 3. THE SHROUD TREE (The Rat Path / Sabotage & Denial)
For the sneaky little sluts. This path is about starving the enemy, fucking with their scanners, and rotting their beacon silently.
* **Corrosive Mix:** `chemical_sludge` (x2) + `bio_fluid` (x1) -> Slap this on a beacon. It silently eats the HP over 60 seconds. Defenders have to punch it to clear it, but it doesn't trigger loud alarms like the Breach Charge.
* **Shroud Corruptor:** `frayed_wire` (x3) + `chemical_sludge` (x1) -> Placed on a Custodian power relay. Instantly kills the lights in a 3-room radius and jams scanners.
* **Decoy Node:** `scrap_metal` (x1) + `frayed_wire` (x1) -> Shows up as a high-value target on enemy scanners. When they get there, it just plays a pre-recorded wet fart noise (or, you know, static).

---

## ♻️ DISASSEMBLY (The Meat Grinder)
You killed a dude and he dropped a Shrapnel Mine, but you're running the Signal path? Throw his shit in the Salvage Bench. 
`break_down` yields 60% of the raw components. It gives you an alibi ("I wasn't building a bomb, I was breaking one down!") and keeps the economy flowing. 

Let's get these wired into the registry so the game math actually matches the gameplay! 💜
