local S = game_mode.S
local state = game_mode.state

-- Beacon nodes (visual + spawn anchors)
minetest.register_node(game_mode.modname .. ":beacon_a", {
	description = S("Beacon A"),
	drawtype = "mesh",
	mesh = "beacon.obj",
	tiles = {"default_mese_block.png"},
	paramtype = "light",
	light_source = 10,
	groups = {cracky = 1, oddly_breakable_by_hand = 1},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},

	after_place_node = function(pos, placer)
		-- Use top of node as spawn to avoid suffocation
		state.teams.beacon_a.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		game_mode.broadcast(S("Beacon A spawn set to @1, @2, @3",
			tostring(pos.x), tostring(pos.y + 1), tostring(pos.z)))
	end,
})

minetest.register_node(game_mode.modname .. ":beacon_b", {
	description = S("Beacon B"),
	drawtype = "mesh",
	mesh = "beacon.obj",
	tiles = {"default_steel_block.png"},
	paramtype = "light",
	light_source = 10,
	groups = {cracky = 1, oddly_breakable_by_hand = 1},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},

	after_place_node = function(pos, placer)
		state.teams.beacon_b.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		game_mode.broadcast(S("Beacon B spawn set to @1, @2, @3",
			tostring(pos.x), tostring(pos.y + 1), tostring(pos.z)))
	end,
})

