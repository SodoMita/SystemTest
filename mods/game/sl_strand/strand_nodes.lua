-- ================================================================
-- sl_strand / strand_nodes.lua
-- The physical side of the strand: defense sockets/turrets/barricades
-- and the Al Dente Core win node.
-- ================================================================

local S = minetest.get_translator(minetest.get_current_modname())
local modname = "sl_strand"

-- Defense sockets are the three wall anchors (Mo: "scrap on the wall").
-- They are not ores - they are the places where the strand lets the
-- player spend a scrap kit.
local function register_defense_socket(idx)
	minetest.register_node(modname .. ":socket_" .. idx, {
		description = S("Defense Socket " .. idx),
		drawtype = "nodebox",
		node_box = { type = "fixed", fixed = { -0.4, -0.4, -0.4, 0.4, 0.4, 0.4 } },
		tiles = { sl_texgen.texture("sl_hardened_plate.png") },
		paramtype = "light",
		groups = { cracky = 2, not_in_creative_inventory = 0, sl_strand_socket = 1 },
		_strand_socket = idx,
	})
end
for i = 1, 3 do register_defense_socket(i) end

-- A built turret.  Placeable only at a socket after a kit is spent;
-- see strand_items for the crafting that produces the kit.
minetest.register_node(modname .. ":turret", {
	description = S("Scrap Turret"),
	drawtype = "mesh",
	mesh = "monster.obj",
	tiles = { sl_texgen.texture("sl_circuit_board.png") },
	paramtype = "light",
	groups = { cracky = 2, sl_strand_defense = 1, sl_strand_defense_turret = 1 },
	_strand_defense_value = 10,
})

minetest.register_node(modname .. ":barricade", {
	description = S("Scrap Barricade"),
	drawtype = "nodebox",
	node_box = { type = "fixed", fixed = { -0.5, 0, -0.5, 0.5, 1.2, 0.5 } },
	tiles = { sl_texgen.texture("sl_scrap_metal.png") },
	paramtype = "light",
	groups = { cracky = 2, sl_strand_defense = 1, sl_strand_defense_barricade = 1 },
	_strand_defense_value = 6,
})

-- The Al Dente Core: the win objective.  "Firm, yet yielding."
minetest.register_node(modname .. ":al_dente_core", {
	description = S("Al Dente Core"),
	drawtype = "mesh",
	mesh = "beacon.obj",
	tiles = { sl_texgen.texture("sl_energy_crystal.png") },
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { cracky = 3, not_in_creative_inventory = 0 },
	light_source = 8,
})
