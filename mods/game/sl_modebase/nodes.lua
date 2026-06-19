local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Beacon nodes (visual + spawn anchors)
-- ================================================================

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

-- ================================================================
-- Objective Core — the crafted win-condition item
-- ================================================================
-- When a player places the Objective Core on or next to their
-- team's beacon, their team wins via "Item Delivery Objective".
-- Can also be held in inventory; placing near beacon is the
-- delivery action.
-- ================================================================

minetest.register_node(game_mode.modname .. ":objective_core", {
	description = S("SYSTEM OBJECTIVE CORE"),
	inventory_image = "sl_objective_core_icon.png",
	tiles = {
		"sl_objective_core_icon.png",
	},
	drawtype = "mesh",
	mesh = "item.obj", -- Use a mesh for the cube if possible
	paramtype = "light",
	light_source = 14,
	groups = {cracky = 1, oddly_breakable_by_hand = 1},
	is_ground_content = false,

	after_place_node = function(pos, placer)
		if not placer or not placer:is_player() then return end

		local name = placer:get_player_name()
		local pl   = game_mode.get_player_state(name)

		if not pl.team or not game_mode.is_beacon_team(pl.team) then
			minetest.chat_send_player(name,
				S("You need to be on a beacon team to deliver the Objective Core."))
			return
		end

		-- Check proximity to own beacon
		local beacon_spawn = state.teams[pl.team].spawn
		if beacon_spawn then
			local dist = vector.distance(pos, beacon_spawn)
			if dist <= 8 then
				-- Delivery successful!
				if state.match_active then
					game_mode.end_match(pl.team,
						S("@1 delivered the Objective Core!", name))
				else
					minetest.chat_send_player(name,
						S("Objective Core placed, but no match is running."))
				end
			else
				minetest.chat_send_player(name,
					S("Place the Objective Core near your team's beacon to win! (within 8 blocks)"))
			end
		end
	end,
})

-- Also register as a craftitem so it appears in inventory properly
-- (the node definition above handles placement)

-- ================================================================
-- Loot Crate — hand-placed loot containers for maps
-- ================================================================
-- Map builders place these; players break them to get random loot.
-- ================================================================

minetest.register_node(game_mode.modname .. ":loot_crate", {
	description = S("Loot Crate"),
	tiles = {"sl_loot_crate.png"},
	paramtype2 = "facedir",
	groups = {choppy = 2, oddly_breakable_by_hand = 1},
	is_ground_content = false,
	sounds = default and default.node_sound_wood_defaults and default.node_sound_wood_defaults() or nil,

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv  = meta:get_inventory()
		inv:set_size("main", 8)
		meta:set_string("infotext", S("Loot Crate"))
	end,

	on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
		local meta = minetest.get_meta(pos)
		local name = clicker:get_player_name()

		minetest.show_formspec(name, "sl_modebase:loot_crate",
			"formspec_version[4]" ..
			"size[8,6]" ..
			"bgcolor[#1a1a1aff;true]" ..
			"label[0.3,0.5;Loot Crate]" ..
			"list[nodemeta:" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ";main;0.3,0.8;8,1;]" ..
			"list[current_player;main;0.3,2.2;8,4;]" ..
			"listring[nodemeta:" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ";main]" ..
			"listring[current_player;main]")
	end,

	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos)
		return meta:get_inventory():is_empty("main")
	end,
})
