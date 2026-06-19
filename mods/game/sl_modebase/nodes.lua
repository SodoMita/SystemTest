local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Beacon nodes (visual + spawn anchors)
-- ================================================================

local function handle_beacon_destruction(team_id)
	game_mode.broadcast(S("@1 has been destroyed! Team eliminated.", game_mode.get_team_label(team_id)))
	state.teams[team_id].spawn = nil -- Disable spawning
	game_mode.save_spawns()

	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local pl = game_mode.get_player_state(name)
		if pl.team == team_id then
			pl.lives = 0
			pl.phase = "ghost"
			player:set_hp(0)
		end
	end
end

minetest.register_node(game_mode.modname .. ":beacon_a", {
	description = S("Beacon A"),
	drawtype = "mesh",
	mesh = "beacon.obj",
	tiles = {"default_mese_block.png"},
	paramtype = "light",
	light_source = 10,
	groups = {cracky = 1, oddly_breakable_by_hand = 1, beacon = 1},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("hp", 100)
		meta:set_string("infotext", S("Beacon A (HP: 100)"))
	end,

	after_place_node = function(pos, placer)
		state.teams.beacon_a.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		game_mode.save_spawns()
		game_mode.broadcast(S("Beacon A spawn set to @1, @2, @3",
			tostring(pos.x), tostring(pos.y + 1), tostring(pos.z)))
	end,

	on_punch = function(pos, node, puncher, pointed_thing)
		if not state.match_active then return end
		local meta = minetest.get_meta(pos)
		local hp = meta:get_int("hp") - 5
		if hp <= 0 then
			minetest.remove_node(pos)
			handle_beacon_destruction("beacon_a")
		else
			meta:set_int("hp", hp)
			meta:set_string("infotext", S("Beacon A (HP: @1)", tostring(hp)))
		end
	end,

	can_dig = function(pos, player)
		return not state.match_active
	end,
})

minetest.register_node(game_mode.modname .. ":beacon_b", {
	description = S("Beacon B"),
	drawtype = "mesh",
	mesh = "beacon.obj",
	tiles = {"default_steel_block.png"},
	paramtype = "light",
	light_source = 10,
	groups = {cracky = 1, oddly_breakable_by_hand = 1, beacon = 1},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("hp", 100)
		meta:set_string("infotext", S("Beacon B (HP: 100)"))
	end,

	after_place_node = function(pos, placer)
		state.teams.beacon_b.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		game_mode.save_spawns()
		game_mode.broadcast(S("Beacon B spawn set to @1, @2, @3",
			tostring(pos.x), tostring(pos.y + 1), tostring(pos.z)))
	end,

	on_punch = function(pos, node, puncher, pointed_thing)
		if not state.match_active then return end
		local meta = minetest.get_meta(pos)
		local hp = meta:get_int("hp") - 5
		if hp <= 0 then
			minetest.remove_node(pos)
			handle_beacon_destruction("beacon_b")
		else
			meta:set_int("hp", hp)
			meta:set_string("infotext", S("Beacon B (HP: @1)", tostring(hp)))
		end
	end,

	can_dig = function(pos, player)
		return not state.match_active
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

		if not state.win_conditions.objective then
			minetest.chat_send_player(name,
				S("Objective Delivery win condition is not enabled for this match."))
			return
		end

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

-- ================================================================
-- Spawn Setting Nodes
-- ================================================================

minetest.register_node(game_mode.modname .. ":spawn_mm", {
	description = S("Monster Master Spawn Point"),
	tiles = {"sl_boxman_neon.png^[colorize:#ff0000:120"},
	groups = {cracky = 1},
	after_place_node = function(pos)
		state.monster_master.base_spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		game_mode.save_spawns()
		game_mode.broadcast(S("Monster Master spawn set to @1, @2, @3", pos.x, pos.y+1, pos.z))
	end,
})

minetest.register_node(game_mode.modname .. ":spawn_ghost", {
	description = S("Ghost Spawn Point"),
	tiles = {"sl_boxman_neon.png^[opacity:100"},
	groups = {cracky = 1},
	after_place_node = function(pos)
		state.ghost_spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		game_mode.save_spawns()
		game_mode.broadcast(S("Ghost spawn set to @1, @2, @3", pos.x, pos.y+1, pos.z))
	end,
})

minetest.register_node(game_mode.modname .. ":spawn_lobby", {
	description = S("Lobby Spawn Point"),
	tiles = {"sl_boxman_neon.png^[colorize:#00ffff:120"},
	groups = {cracky = 1},
	after_place_node = function(pos)
		state.lobby_spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		game_mode.save_spawns()
		game_mode.broadcast(S("Lobby spawn set to @1, @2, @3", pos.x, pos.y+1, pos.z))
	end,
})

-- Ensure existing spawn nodes in the world update the state when loaded
minetest.register_lbm({
	name = "sl_modebase:update_spawns",
	nodenames = {
		"sl_modebase:spawn_mm",
		"sl_modebase:spawn_ghost",
		"sl_modebase:spawn_lobby",
		"sl_modebase:beacon_a",
		"sl_modebase:beacon_b"
	},
	run_at_every_load = true,
	action = function(pos, node)
		if node.name == "sl_modebase:spawn_mm" then
			state.monster_master.base_spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		elseif node.name == "sl_modebase:spawn_ghost" then
			state.ghost_spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		elseif node.name == "sl_modebase:spawn_lobby" then
			state.lobby_spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		elseif node.name == "sl_modebase:beacon_a" then
			state.teams.beacon_a.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		elseif node.name == "sl_modebase:beacon_b" then
			state.teams.beacon_b.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		end
	end,
})
