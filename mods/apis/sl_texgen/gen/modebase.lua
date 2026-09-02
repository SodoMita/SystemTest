-- ================================================================
-- sl_texgen/gen/modebase.lua — sl_modebase placeholder item icons
--
-- Ports the sl_* prototype item icons: dark rounded plate, colored
-- box outline/fill, and the item label in the micro font (exactly
-- what generate_content_assets.py produced as stock files).
-- sl_warning_sign.png and sl_objective_core_icon.png are AI-drawn
-- art and stay as real files — this generator claims only the
-- generated placeholders.
-- ================================================================
local C = sl_texgen.canvas

local S = 64

local SPECS = {
	{ "sl_scrap_metal.png", "scrap", { 150, 155, 160 } },
	{ "sl_electronic_waste.png", "e-waste", { 80, 165, 80 } },
	{ "sl_raw_crystal.png", "crystal", { 0, 210, 230 } },
	{ "sl_plastic_scrap.png", "plastic", { 200, 120, 200 } },
	{ "sl_metal_ingot.png", "ingot", { 185, 185, 195 } },
	{ "sl_circuit_board.png", "circuit", { 0, 190, 100 } },
	{ "sl_energy_crystal.png", "energy", { 0, 230, 255 } },
	{ "sl_hardened_plate.png", "plate", { 100, 105, 115 } },
	{ "sl_reinforced_glass.png", "glass", { 160, 200, 220 } },
	{ "sl_combat_blade.png", "blade", { 220, 220, 230 } },
	{ "sl_breaching_pick.png", "pick", { 180, 180, 190 } },
	{ "sl_tactical_axe.png", "axe", { 180, 140, 80 } },
	{ "sl_trench_shovel.png", "shovel", { 140, 120, 100 } },
	{ "sl_energy_blade.png", "e-blade", { 0, 220, 255 } },
	{ "sl_power_drill.png", "drill", { 200, 180, 60 } },
	{ "sl_flare.png", "flare", { 255, 140, 0 } },
	{ "sl_medkit.png", "medkit", { 220, 40, 40 } },
	{ "sl_power_cell.png", "cell", { 0, 220, 255 } },
	{ "sl_blast_shield.png", "shield", { 80, 120, 160 } },
	{ "sl_barricade.png", "wall", { 120, 120, 130 } },
	{ "sl_signal_relay.png", "relay", { 200, 160, 0 } },
	{ "sl_sensor_array.png", "sensor", { 0, 180, 220 } },
	{ "sl_objective_core.png", "core", { 0, 255, 100 } },
	{ "sl_loot_crate.png", "loot", { 80, 140, 80 } },
	{ "sl_monster_spawner.png", "spawner", { 226, 88, 30 } },
	{ "sl_monster_essence.png", "essence", { 170, 60, 230 } },
}

local function draw_icon(label, color)
	return function(c)
		C.round_rect(c, 0, 0, S, S, 6, { 20, 22, 26, 255 })
		C.frame(c, 2, 2, S - 4, S - 4, { color[1], color[2], color[3], 230 })
		-- thicken the outline
		C.frame(c, 3, 3, S - 6, S - 6, { color[1], color[2], color[3], 160 })
		C.rect(c, 8, 8, S - 16, S - 16, { color[1], color[2], color[3], 55 })
		-- label, up to 3 lines of ~7 chars, like the python layout
		C.text(c, 4, S - 8, label, { 240, 245, 255, 255 })
	end
end

local defs = {}
for _, spec in ipairs(SPECS) do
	defs[#defs + 1] = {
		name = spec[1], w = S, h = S, seed = 0,
		draw = draw_icon(spec[2], spec[3]),
	}
end
return defs
