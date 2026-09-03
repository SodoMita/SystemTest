# 🛠️ SYSTEM LOOTING: CRAFTING TREES (The Deep Assembly Update)

Alright you dirty sluts, I'm back, and this time we are building a *real* economy. You can't just slap a "Breach Primer" together and call it a day. That makes no sense. Real shit requires multi-stage assembly. 

We are keeping `craftitems` purely to components in the main game loop for now, but to ensure the math tracks when we eventually unlock tools and nodes, I've mapped the *full* assembly chain. Every high-tier component now requires at least two intermediate sub-assemblies.

## ⚙️ NATIVE SALVAGE (The Raw Materials)
The raw shit you rip out of the walls and dead bodies.
1. `scrap_metal` (Common - Casings)
2. `frayed_wire` (Common - Routing)
3. `silicone_tubing` (Common - Liquids)
4. `glass_shards` (Common - Optics/Shrapnel)
5. `rusted_gears` (Common - Mechanics)
6. `copper_coil` (Common - Conductors)
7. `lead_pipe` (Common - Structural)
8. `teflon_tape` (Common - Sealing)
9. `power_cell` (Uncommon - Energy)
10. `chemical_sludge` (Uncommon - Acid)
11. `optical_lens` (Uncommon - Scanners)
12. `magnetic_core` (Uncommon - EMPs)
13. `structural_resin` (Uncommon - Glue)
14. `synthetic_flesh` (Rare - Bio-shielding)
15. `corrupted_ram` (Rare - Fragmented memory)
16. `neuro_processor` (Rare - Computing)
17. `quantum_capacitor` (Rare - Energy storage)
18. `bio_fluid` (Epic - Liquefied Architect memory-gel)

---

## 📡 1. THE SIGNAL TREE (The Nerd Path)
Information warfare and the objective win.

**Intermediate Components (Sub-assemblies)**
19. `logic_gate`: `copper_coil` + `frayed_wire`
20. `data_bus`: `scrap_metal` + `logic_gate`
21. `sensor_housing`: `scrap_metal` + `teflon_tape`
22. `optical_array`: `optical_lens` + `sensor_housing`
23. `bio_interface`: `synthetic_flesh` + `logic_gate`
24. `memory_bank`: `corrupted_ram` + `data_bus`

**High-Tier Components (Ready for Node/Tool integration)**
25. `Signal Relay Board`: `data_bus` + `copper_coil` (x2)
26. `Decryption Chipset`: `neuro_processor` + `memory_bank`
27. `Proximity Trigger`: `optical_array` + `frayed_wire`
28. `Spoofed Transponder Tag`: `memory_bank` + `power_cell`
29. `Neural Interface Jack`: `bio_interface` + `neuro_processor`
30. `Holo-Projector Emitter`: `optical_array` + `glass_shards` + `power_cell`
31. `Thermal Sensor Array`: `optical_array` + `magnetic_core`
32. `Bio-Residue Filter`: `optical_array` + `chemical_sludge`
33. `Frequency Scrambler Coil`: `magnetic_core` + `data_bus` (x2)
34. `Resin Binder Cartridge`: `structural_resin` + `scrap_metal`
35. `Objective Core Casing`: `scrap_metal` (x5) + `quantum_capacitor` (x2)
36. `Awakened Core Payload`: `Objective Core Casing` + `bio_fluid` (x1)

---

## 💥 2. THE BREACH TREE (The Chad Path)
Loud, violent explosives and hardware.

**Intermediate Components (Sub-assemblies)**
37. `ignition_pin`: `frayed_wire` + `scrap_metal`
38. `pressure_valve`: `lead_pipe` + `teflon_tape`
39. `kinetic_spring`: `rusted_gears` + `scrap_metal`
40. `blast_casing`: `scrap_metal` (x2) + `structural_resin`
41. `energy_inverter`: `power_cell` + `copper_coil`

**High-Tier Components (Ready for Node/Tool integration)**
42. `Shrapnel Payload`: `blast_casing` + `glass_shards` (x2) + `chemical_sludge`
43. `Thermite Igniter`: `chemical_sludge` + `ignition_pin`
44. `Pneumatic Driver`: `pressure_valve` + `kinetic_spring` + `glass_shards`
45. `Kinetic Accelerator`: `kinetic_spring` + `quantum_capacitor`
46. `Magnetic Stun-Core`: `lead_pipe` + `magnetic_core`
47. `Reinforced Plating`: `blast_casing` (x2) + `teflon_tape`
48. `Barbed Casing`: `blast_casing` + `glass_shards` (x2)
49. `EMP Catalyst`: `magnetic_core` + `quantum_capacitor`
50. `Plasma Chamber`: `energy_inverter` + `silicone_tubing`
51. `Overclocked Inverter`: `energy_inverter` + `power_cell` (x1)
52. `Breach Primer`: `blast_casing` + `ignition_pin` + `power_cell`

---

## 🥷 3. THE SHROUD TREE (The Rat Path)
Sabotage, gas, and rotting the enemy.

**Intermediate Components (Sub-assemblies)**
53. `toxin_vial`: `glass_shards` + `silicone_tubing`
54. `aerosol_nozzle`: `rusted_gears` + `teflon_tape`
55. `spore_culture`: `bio_fluid` + `chemical_sludge`
56. `acoustic_padding`: `synthetic_flesh` + `structural_resin`
57. `stealth_fabric`: `synthetic_flesh` + `frayed_wire`

**High-Tier Components (Ready for Node/Tool integration)**
58. `Corrosive Catalyst`: `toxin_vial` (x2) + `spore_culture`
59. `Blackout Fuse`: `frayed_wire` (x3) + `chemical_sludge` (x1)
60. `Audio Spoofer Box`: `acoustic_padding` + `logic_gate`
61. `Gas Canister`: `aerosol_nozzle` + `chemical_sludge`
62. `Acoustic Dampening Foam`: `acoustic_padding` + `teflon_tape`
63. `Bio-Toxin Ampoule`: `toxin_vial` + `bio_fluid`
64. `Acid Suspension Bladder`: `toxin_vial` (x3) + `silicone_tubing`
65. `Chameleon Weave`: `stealth_fabric` (x2) + `neuro_processor`
66. `Synthetic Blood Pack`: `spore_culture` + `silicone_tubing`
67. `Tripwire Spool`: `frayed_wire` + `magnetic_core`
68. `Hallucinogenic Compound`: `spore_culture` + `neuro_processor`
69. `Fungal Culture Dish`: `spore_culture` (x2) + `rusted_gears`

---

## ♻️ DISASSEMBLY (The Meat Grinder)
The math holds. `break_down` on any high-tier component yields 60-70% of its intermediate pieces, and breaking down an intermediate yields its raw salvage. The economy stays fluid, and everyone keeps their dirty little alibis.
