-- ================================================================
-- sl_strand / strand_items.lua
-- Strand craftables: scrap-defense kits, Trust charges, and a revival
-- form item (links back to the ghost -> revival-form pipeline).
-- ================================================================

local S = minetest.get_translator(minetest.get_current_modname())
local modname = "sl_strand"

minetest.register_craftitem(modname .. ":scrap_defense_kit", {
	description = S("Scrap Defense Kit (scrap->horror)"),
	inventory_image = sl_texgen.texture("sl_scrap_metal.png"),
	groups = { sl_strand_kit = 1 },
})

minetest.register_craftitem(modname .. ":trust_charge", {
	description = S("Trust Charge"),
	inventory_image = sl_texgen.texture("sl_sensor_array.png"),
	groups = { sl_strand_kit = 1 },
	_strand_trust = 1,
})

-- Revival form item, consumed on revival to take a strand-specific form.
-- This is the seam to the GDD "form items" (crafted while alive,
-- consumed on revival).  The base Evil Ghost is still the default.
minetest.register_craftitem(modname .. ":form_void_nomad", {
	description = S("Form Item: Void Nomad (revive as the horror)"),
	inventory_image = sl_texgen.texture("sl_monster_essence.png"),
	groups = { sl_strand_form_item = 1 },
})

-- The strand reuses the existing button-crafting system (sl_gui) rather
-- than inventing a parallel one.  These recipes feed that system when
-- sl_gui is present; the recipe gate keeps it a no-op if sl_gui is not.
if type(rawget(_G, "register_craft_recipe")) == "function" then
	register_craft_recipe({
		output = modname .. ":scrap_defense_kit",
		ingredients = {
			["sl_modebase:scrap_metal"] = 2,
			["sl_modebase:circuit_board"] = 1,
		},
		description = "Scrap Defense Kit",
		category = "tactical",
	})
	register_craft_recipe({
		output = modname .. ":trust_charge",
		ingredients = {
			["sl_modebase:sensor_array"] = 1,
			["sl_modebase:electronic_waste"] = 1,
		},
		description = "Trust Charge",
		category = "information",
	})
	register_craft_recipe({
		output = modname .. ":form_void_nomad",
		ingredients = {
			["sl_modebase:monster_essence"] = 3,
			["sl_modebase:energy_crystal"] = 1,
		},
		description = "Form Item: Void Nomad",
		category = "information",
	})
end
