-- ================================================================
-- sl_texgen/gen/modebase.lua — sl_modebase placeholder item icons
--
-- Dark rounded plate, colored box outline/fill, item label from the
-- shared font atlas — the generate_content_assets.py recipe, now a
-- client-side [combine program.  (sl_warning_sign.png and
-- sl_objective_core_icon.png are AI-drawn art and stay as files.)
-- ================================================================
local stx = sl_texgen.stx
local S = 64

local SPECS = {
	{ "sl_scrap_metal.png", "scrap", "#96A0A0" },
	{ "sl_electronic_waste.png", "e-waste", "#50A550" },
	{ "sl_raw_crystal.png", "crystal", "#00D2E6" },
	{ "sl_plastic_scrap.png", "plastic", "#C878C8" },
	{ "sl_metal_ingot.png", "ingot", "#B9B9C3" },
	{ "sl_circuit_board.png", "circuit", "#00BE64" },
	{ "sl_energy_crystal.png", "energy", "#00E6FF" },
	{ "sl_hardened_plate.png", "plate", "#646973" },
	{ "sl_reinforced_glass.png", "glass", "#A0C8DC" },
	{ "sl_combat_blade.png", "blade", "#DCE0E6" },
	{ "sl_breaching_pick.png", "pick", "#B4B4BE" },
	{ "sl_tactical_axe.png", "axe", "#B48C50" },
	{ "sl_trench_shovel.png", "shovel", "#8C7864" },
	{ "sl_energy_blade.png", "e-blade", "#00DCFF" },
	{ "sl_power_drill.png", "drill", "#C8B43C" },
	{ "sl_flare.png", "flare", "#FF8C00" },
	{ "sl_medkit.png", "medkit", "#DC2828" },
	{ "sl_power_cell.png", "cell", "#00DCFF" },
	{ "sl_blast_shield.png", "shield", "#5078A0" },
	{ "sl_barricade.png", "wall", "#787882" },
	{ "sl_signal_relay.png", "relay", "#C8A000" },
	{ "sl_sensor_array.png", "sensor", "#00B4DC" },
	{ "sl_objective_core.png", "core", "#00FF64" },
	{ "sl_loot_crate.png", "loot", "#508C50" },
	{ "sl_monster_spawner.png", "spawner", "#E2581E" },
	{ "sl_monster_essence.png", "essence", "#AA3CE6" },
}

local function draw_icon(label, color)
	return function(p)
		stx.solid(p, 0, 0, S, S, "#14161A", 255)
		stx.frame(p, 2, 2, S - 4, S - 4, color, 230, 2)
		stx.solid(p, 8, 8, S - 16, S - 16, color, 55)
		stx.glow(p, S / 2, S - 12, 20, 60, color)
		stx.label(p, 4, S - 9, label, "#F0F5FF", 255, 1)
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
