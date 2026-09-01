local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Beacon nodes (visual + spawn anchors)
-- ================================================================

local function handle_beacon_destruction(team_id, pos, attacker_name)
	game_mode.broadcast(S("@1 has been destroyed by @2! Team eliminated.", 
		game_mode.get_team_label(team_id), attacker_name or "Unknown"))
	state.teams[team_id].spawn = nil -- Disable spawning for this match
	
	if pos then
		minetest.set_node(pos, {name = "sl_modebase:destroyed_beacon"})
	end

	-- Use a list to avoid issues with set_hp triggering end_match recursively
	local to_kill = {}
	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local pl = game_mode.get_player_state(name)
		if pl.team == team_id then
			table.insert(to_kill, player)
		end
	end

	for _, player in ipairs(to_kill) do
		local pl = game_mode.get_player_state(player:get_player_name())
		pl.phase = "ghost"
		player:set_hp(0)
	end
end

minetest.register_node(game_mode.modname .. ":destroyed_beacon", {
	description = S("Destroyed Beacon"),
	drawtype = "mesh",
	mesh = "beacon.obj",
	tiles = {"default_obsidian.png^[colorize:#00ffff:50"}, -- Tinted lobby-style cyan when in lobby? No, let's keep it dark.
	paramtype = "light",
	groups = {cracky = 3, oddly_breakable_by_hand = 1, not_in_creative_inventory = 1},
	selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},
	collision_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}},
})

-- Auto-restore destroyed beacons in lobby
minetest.register_abm({
	label = "Restore Beacons in Lobby",
	nodenames = {"sl_modebase:destroyed_beacon"},
	interval = 5,
	chance = 1,
	action = function(pos, node)
		if not state.match_active then
			-- Identify which beacon this was
			if state.teams.beacon_a.spawn then
				local bpos = {x=state.teams.beacon_a.spawn.x, y=state.teams.beacon_a.spawn.y-1, z=state.teams.beacon_a.spawn.z}
				if vector.equals(pos, bpos) then
					minetest.set_node(pos, {name = "sl_modebase:beacon_a"})
					state.teams.beacon_a.hp = 100
					return
				end
			end
			if state.teams.beacon_b.spawn then
				local bpos = {x=state.teams.beacon_b.spawn.x, y=state.teams.beacon_b.spawn.y-1, z=state.teams.beacon_b.spawn.z}
				if vector.equals(pos, bpos) then
					minetest.set_node(pos, {name = "sl_modebase:beacon_b"})
					state.teams.beacon_b.hp = 100
					return
				end
			end
			-- Fallback: just delete if it doesn't match known spawns
			minetest.remove_node(pos)
		end
	end,
})

function game_mode.damage_beacon(team_id, amount, attacker_name, silent)
	local tdef = state.teams[team_id]
	if not tdef or not tdef.spawn then return end
	
	tdef.hp = (tdef.hp or 100) - (amount or 5)
	
	if not silent then
		game_mode.broadcast(S("@1 damaged @2! (HP: @3)", 
			attacker_name or "A Monster", tdef.label, tostring(tdef.hp)))
	end

	local bpos = {x=tdef.spawn.x, y=tdef.spawn.y-1, z=tdef.spawn.z}
	
	-- Update node meta if loaded
	local node = minetest.get_node_or_nil(bpos)
	if node then
		local meta = minetest.get_meta(bpos)
		meta:set_int("hp", tdef.hp)
		meta:set_string("infotext", S("@1 (HP: @2)", tdef.label, tostring(tdef.hp)))
	end

	if tdef.hp <= 0 then
		handle_beacon_destruction(team_id, node and bpos or nil, attacker_name)
	end
end

-- ================================================================
-- Sabotage registry: bounded corruption with visible cause,
-- a duration limit, and a repair counterplay for the living.
-- ================================================================

function game_mode.register_sabotage(pos, kind, team_id)
	local meta = minetest.get_meta(pos)
	local entry = {
		pos = vector.round(pos),
		kind = kind or "node",
		team_id = team_id,
		until_time = game_mode.now() + (state.settings.sabotage_duration or 30),
	}
	state.sabotage[game_mode.pos_hash(entry.pos)] = entry
	if meta:get_string("sl_prev_infotext") == "" then
		meta:set_string("sl_prev_infotext", meta:get_string("infotext"))
	end
	meta:set_int("sl_sabotaged_until", math.floor(entry.until_time))
	meta:set_string("infotext", S("SIGNAL CORRUPTED"))
	return entry
end

-- Returns true (and warns the clicker) when the target node is corrupted.
local function refuse_if_sabotaged(pos, clicker)
	if game_mode.is_sabotaged(pos) then
		minetest.chat_send_player(clicker:get_player_name(),
			S("SIGNAL CORRUPTED - this system will not respond. Punch it to repair."))
		return true
	end
	return false
end
game_mode.refuse_if_sabotaged = refuse_if_sabotaged

-- 1 Hz tick: corrode sabotaged beacons, expire sabotages and possessions.
local sabotage_tick_accum = 0
function game_mode.sabotage_step(dtime)
	sabotage_tick_accum = sabotage_tick_accum + dtime
	if sabotage_tick_accum < 1 then return end
	sabotage_tick_accum = 0

	local now = game_mode.now()
	for _, entry in pairs(state.sabotage) do
		if now >= entry.until_time then
			game_mode.clear_sabotage_at(entry.pos)
		elseif entry.kind == "beacon" and entry.team_id and state.match_active then
			-- Bounded corrosion: discoverable, damage-capped, repairable.
			game_mode.damage_beacon(entry.team_id, 2, S("Corrosion"), true)
		end
	end
	-- Possession expiry/slams are driven by game_mode.possession_step,
	-- which WP3's wrapper chains onto this tick below.
end

-- Living players repair corrupted systems by punching them.
-- (Possession exorcism is handled by WP3's dedicated punchnode handler.)
minetest.register_on_punchnode(function(pos, node, puncher, pointed_thing)
	if not puncher or not puncher:is_player() then return end
	local pl = game_mode.get_player_state(puncher:get_player_name())

	if game_mode.is_sabotaged(pos) then
		if pl.phase ~= "alive" then
			minetest.chat_send_player(puncher:get_player_name(),
				S("Only the living can repair corrupted systems."))
			return
		end
		game_mode.clear_sabotage_at(pos)
		minetest.chat_send_player(puncher:get_player_name(),
			S("Corruption neutralized. System restored."))
		minetest.sound_play("default_tool_break", { pos = pos, gain = 0.5, max_hear_distance = 8 })
	end
end)

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
		local hp = state.settings.beacon_hp or 100
		meta:set_int("hp", hp)
		meta:set_string("infotext", S("Beacon A (HP: @1)", tostring(hp)))
	end,

	after_place_node = function(pos, placer)
		state.teams.beacon_a.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		state.teams.beacon_a.hp = state.settings.beacon_hp or 100
		game_mode.save_spawns()
		game_mode.broadcast(S("Beacon A spawn set to @1, @2, @3",
			tostring(pos.x), tostring(pos.y + 1), tostring(pos.z)))
	end,

	on_punch = function(pos, node, puncher, pointed_thing)
		if not state.match_active then return end
		game_mode.damage_beacon("beacon_a", 5, puncher and puncher:get_player_name())
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
		local hp = state.settings.beacon_hp or 100
		meta:set_int("hp", hp)
		meta:set_string("infotext", S("Beacon B (HP: @1)", tostring(hp)))
	end,

	after_place_node = function(pos, placer)
		state.teams.beacon_b.spawn = { x = pos.x, y = pos.y + 1, z = pos.z }
		state.teams.beacon_b.hp = state.settings.beacon_hp or 100
		game_mode.save_spawns()
		game_mode.broadcast(S("Beacon B spawn set to @1, @2, @3",
			tostring(pos.x), tostring(pos.y + 1), tostring(pos.z)))
	end,

	on_punch = function(pos, node, puncher, pointed_thing)
		if not state.match_active then return end
		game_mode.damage_beacon("beacon_b", 5, puncher and puncher:get_player_name())
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
	-- sl_essence_value = 5: destroying a delivered/placed core pays the
	-- MM pool 5 (essence ruling §13.3 rule 1 — the crew's biggest
	-- statement pays out). sl_craft_in_inventory = 1: this node opts
	-- out of the "machine required" gate so the named +3 craft (rule 2)
	-- can actually complete in the button crafting UI until the machine
	-- chain lands (objective-loop turn).
	groups = {cracky = 1, oddly_breakable_by_hand = 1,
		sl_essence_value = 5, sl_craft_in_inventory = 1},
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
				game_mode.deliver_objective(pl.team, name)
			else
				minetest.chat_send_player(name,
					S("Place the Objective Core near your team's beacon to win! (within 8 blocks)"))
			end
		end
	end,
})

-- Shared delivery API used by both the physical node and headless tests.
function game_mode.deliver_objective(team_id, actor_name)
	if not state.match_active then return false, "no active match" end
	if not state.win_conditions.objective then return false, "objective mode disabled" end
	if not game_mode.is_beacon_team(team_id) then return false, "invalid team" end
	game_mode.end_match(team_id, S("@1 delivered the Objective Core!", actor_name or "Unknown"))
	return true
end

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
	-- sl_essence_value: price paid to the MM pool when a crew-placed
	-- crate is destroyed (essence ruling §13.3 rule 1).
	groups = {choppy = 2, oddly_breakable_by_hand = 1, sl_essence_value = 1},
	is_ground_content = false,
	sounds = default and default.node_sound_wood_defaults and default.node_sound_wood_defaults() or nil,

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv  = meta:get_inventory()
		inv:set_size("main", 32)
		meta:set_string("infotext", S("Loot Crate"))
	end,

	on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
		local meta = minetest.get_meta(pos)
		local name = clicker:get_player_name()

		if refuse_if_sabotaged(pos, clicker) then return itemstack end

		-- An 8-slot-wide list is 9.75 units across in real coordinates
		-- ((8-1) * 1.25 spacing + 1.0 slot), and 4 slots are 4.75 tall, so the
		-- window has to be at least 10.05 wide and the two grids cannot share
		-- rows. The old size[8,9.5] clipped 2.05 units off the right edge and
		-- stacked the second grid on top of the first.
		minetest.show_formspec(name, "sl_modebase:loot_crate",
			"formspec_version[4]" ..
			"size[10.5,11.0]" ..
			"bgcolor[#1a1a1aff;true]" ..
			"label[0.3,0.5;Loot Crate (32 slots)]" ..
			"list[nodemeta:" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ";main;0.3,0.8;8,4;]" ..
			"list[current_player;main;0.3,5.9;8,4;]" ..
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

-- ================================================================
-- Ghost & Task Nodes
-- ================================================================

minetest.register_node(game_mode.modname .. ":ghost_mutator", {
	description = S("Deprecated Ghost Mutator (Use Ghost Altar)"),
	tiles = {"sl_raw_crystal.png^[colorize:#ff00ff:80"},
	paramtype = "light",
	light_source = 12,
	groups = {cracky = 1},
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local pl = game_mode.get_player_state(name)
		if pl.phase == "ghost" then
			minetest.chat_send_player(name, S("Neutral-monster mutation is disabled. Use a Ghost Altar ritual for revival."))
		else
			minetest.chat_send_player(name, S("Only contained ghosts can interact with this deprecated node."))
		end
	end,
})

minetest.register_node(game_mode.modname .. ":ghost_task_terminal", {
	description = S("Ghost Task Terminal"),
	drawtype = "mesh",
	mesh = "terminal.obj",
	tiles = { "terminal_texture.png^[colorize:#ff00ff:50" },
	paramtype = "light",
	light_source = 8,
	groups = { cracky = 2 },
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()
		local pl = game_mode.get_player_state(name)
		if refuse_if_sabotaged(pos, clicker) then return end
		if pl.phase == "ghost" then
			if not pl.ghost_summoned_by then
				minetest.chat_send_player(name, S("No living player has summoned you."))
				return
			end
			minetest.chat_send_player(name,
				S("Channel active. Use /sl_ghost_offer <summoner> <security|logistics|medical>."))
		else
			minetest.chat_send_player(name, S("This terminal is for contained ghosts only."))
		end
	end,
})

-- ================================================================
-- Ghost Altar — ritual summons one random contained ghost
-- ================================================================
local altar_cost = {
	[game_mode.modname .. ":ritual_ashen_relic"] = 1,
	[game_mode.modname .. ":ritual_soul_shard"] = 1,
	[game_mode.modname .. ":ritual_signal_ink"] = 1,
}

minetest.register_node(game_mode.modname .. ":ghost_altar", {
	description = S("Ghost Altar"),
	drawtype = "mesh",
	mesh = "ghost_altar.obj",
	tiles = { "sl_raw_crystal.png^[colorize:#7700aa:120" },
	paramtype = "light",
	light_source = 12,
	groups = { cracky = 2, oddly_breakable_by_hand = 1 },
	is_ground_content = false,
	selection_box = { type = "fixed", fixed = { -0.55, -0.5, -0.55, 0.55, 0.8, 0.55 } },
	collision_box = { type = "fixed", fixed = { -0.55, -0.5, -0.55, 0.55, 0.8, 0.55 } },

	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker or not clicker:is_player() then return itemstack end
		local name = clicker:get_player_name()
		if refuse_if_sabotaged(pos, clicker) then return itemstack end
		local caller = game_mode.get_player_state(name)
		if not state.match_active or caller.phase ~= "alive" then
			minetest.chat_send_player(name, S("The altar answers only to a living player during an active match."))
			return itemstack
		end

		local inv = clicker:get_inventory()
		for item_name, count in pairs(altar_cost) do
			if not inv:contains_item("main", ItemStack(item_name .. " " .. count)) then
				minetest.chat_send_player(name, S("Ritual incomplete. Three rare components are required."))
				return itemstack
			end
		end

		local ghosts = {}
		for ghost_name, ghost_state in pairs(state.players) do
			if ghost_state.phase == "ghost" and minetest.get_player_by_name(ghost_name) then
				table.insert(ghosts, ghost_name)
			end
		end
		if #ghosts == 0 then
			minetest.chat_send_player(name, S("No contained ghost signal detected."))
			return itemstack
		end

		for item_name, count in pairs(altar_cost) do
			inv:remove_item("main", ItemStack(item_name .. " " .. count))
		end

		local ghost_name = ghosts[math.random(1, #ghosts)]
		local ghost = minetest.get_player_by_name(ghost_name)
		local ghost_state = state.players[ghost_name]
		ghost_state.ghost_summoned_by = name
		ghost_state.ghost_summon_pos = vector.round(pos)
		ghost:set_pos({x = pos.x, y = pos.y + 1.2, z = pos.z})
		minetest.chat_send_player(name, S("The altar has summoned a ghost signal."))
		minetest.chat_send_player(ghost_name, S("You have been summoned to the Ghost Altar. Channel open for 30 seconds."))
		minetest.sound_play("alert", { pos = pos, gain = 0.9, max_hear_distance = 16 })

		minetest.after(30, function()
			local g = minetest.get_player_by_name(ghost_name)
			local gs = state.players[ghost_name]
			if g and gs and gs.phase == "ghost" and gs.ghost_summoned_by == name then
				gs.ghost_summoned_by = nil
				gs.ghost_summon_pos = nil
				g:set_pos(table.copy(state.ghost_spawn))
				minetest.chat_send_player(ghost_name, S("The altar channel has collapsed. You return to the cloud cage."))
			end
		end)
		return itemstack
	end,
})

-- ================================================================
-- Evil-ghost possession of objects  (WP3 — MATCH_LOOP_SPEC
-- "Evil revival state": the evil ghost may possess selected items or
-- objects, but never as an unbounded griefing tool.)
--
-- Bounding rules, one per spec requirement:
--   * visible/discoverable cause -> infotext flips to OBJECT POSSESSED,
--     a broadcast fires, and possessed doors/hatches visibly slam.
--   * cooldown / resource limit  -> one concurrent possession per ghost,
--     a fixed duration, and a per-ghost cooldown afterwards.
--   * clear interaction rule     -> only an evil ghost, only during an
--     active match, only on allowlisted objects (never a beacon, never
--     the Ghost Altar, so no mechanic becomes unreachable).
--   * detect / prevent / recover -> living players exorcise by punching
--     the object twice; expiry and match end also release it.
--
-- Possession deliberately never damages: it denies use and creates
-- uncertainty. Beacon damage stays the sabotage charge's job.
-- ================================================================

local modname = game_mode.modname

game_mode.POSSESSION_DURATION = 20 -- seconds an object stays possessed
game_mode.POSSESSION_COOLDOWN = 45 -- seconds before the same ghost may re-possess
game_mode.POSSESSION_EXORCISM_PENALTY = 30 -- extra cooldown when exorcised
game_mode.POSSESSION_EXORCISM_HITS = 2 -- punches by the living to release
game_mode.POSSESSION_SLAM_INTERVAL = 3 -- seconds between door/hatch slams

-- Active possessions: [pos_hash] = { pos, node_name, ghost, until_time, hits, next_slam }
state.possession = state.possession or {}

-- Objects an evil ghost may seize. Beacons and the Ghost Altar are
-- intentionally excluded (beacons belong to sabotage; the altar must stay
-- usable or the summon ritual becomes unreachable).
local POSSESSABLE_NODES = {
	[modname .. ":door_closed"] = "door",
	[modname .. ":door_open"] = "door",
	[modname .. ":hatch"] = "door",
	[modname .. ":hatch_open"] = "door",
	[modname .. ":terminal"] = "system",
	[modname .. ":ghost_task_terminal"] = "system",
	[modname .. ":loot_crate"] = "system",
	[modname .. ":item_pickup"] = "system",
	[modname .. ":platform"] = "system",
	[modname .. ":monster_spawner"] = "system",
}

local function possession_setting(key, fallback)
	local settings = state.settings or {}
	return tonumber(settings[key]) or fallback
end

function game_mode.is_possessable(node_name)
	if POSSESSABLE_NODES[node_name] then return true end
	local def = minetest.registered_nodes[node_name]
	return (def and def.groups and def.groups.possessable or 0) > 0
end

function game_mode.get_possession(pos)
	return state.possession[game_mode.pos_hash(pos)]
end

function game_mode.is_possessed(pos)
	return game_mode.get_possession(pos) ~= nil
end

-- Restores the object's own infotext and drops the registry entry.
function game_mode.release_possession(pos, reason)
	local hash = game_mode.pos_hash(pos)
	local entry = state.possession[hash]
	if not entry then return false end
	state.possession[hash] = nil

	local meta = minetest.get_meta(entry.pos)
	meta:set_int("sl_possessed_until", 0)
	meta:set_string("infotext", meta:get_string("sl_prev_infotext") or "")
	meta:set_string("sl_prev_infotext", "")

	local ghost = entry.ghost and state.players[entry.ghost]
	if ghost and ghost.possession_pos == hash then
		ghost.possession_pos = nil
	end
	minetest.log("action", string.format("[game_mode] possession released at %s (%s)",
		minetest.pos_to_string(entry.pos), reason or "expired"))
	return true
end

function game_mode.clear_all_possession()
	for _, entry in pairs(state.possession) do
		game_mode.release_possession(entry.pos, "purged")
	end
	state.possession = {}
	-- Clean reset: no cooldown or held-object bookkeeping survives a match.
	for _, pl in pairs(state.players) do
		pl.possession_pos = nil
		pl.possession_ready_at = nil
	end
end

-- Clean reset: WP2 already purges sabotage at match end / insertion, so
-- possession piggybacks on that single call site instead of adding a new
-- cross-package hook. Additive wrapper; the v1 behaviour is preserved.
local base_clear_all_sabotage = game_mode.clear_all_sabotage
function game_mode.clear_all_sabotage()
	base_clear_all_sabotage()
	game_mode.clear_all_possession()
end

-- Attempt a possession. Returns ok, err (err is a player-readable string).
function game_mode.possess_object(pos, ghost_name)
	if not state.match_active then return false, S("Possession only works during an active match.") end

	local pl = game_mode.get_player_state(ghost_name)
	if pl.phase ~= "evil_ghost" then
		return false, S("Only a revived evil ghost can possess objects.")
	end

	local now = game_mode.now()
	if (pl.possession_ready_at or 0) > now then
		return false, S("The focus is still recharging (@1 s).",
			tostring(math.ceil(pl.possession_ready_at - now)))
	end
	if pl.possession_pos and state.possession[pl.possession_pos] then
		return false, S("You already hold one object. Only one at a time.")
	end

	local node = minetest.get_node_or_nil(pos)
	if not node or not game_mode.is_possessable(node.name) then
		return false, S("This object cannot be possessed.")
	end
	if game_mode.is_possessed(pos) then
		return false, S("This object is already possessed.")
	end
	if game_mode.is_sabotaged(pos) then
		return false, S("A corrupted system cannot also be possessed.")
	end

	local rounded = vector.round(pos)
	local hash = game_mode.pos_hash(rounded)
	local entry = {
		pos = rounded,
		node_name = node.name,
		kind = POSSESSABLE_NODES[node.name] or "system",
		ghost = ghost_name,
		until_time = now + possession_setting("possession_duration", game_mode.POSSESSION_DURATION),
		hits = 0,
		next_slam = now + game_mode.POSSESSION_SLAM_INTERVAL,
	}
	state.possession[hash] = entry

	local meta = minetest.get_meta(rounded)
	if meta:get_string("sl_prev_infotext") == "" then
		meta:set_string("sl_prev_infotext", meta:get_string("infotext"))
	end
	meta:set_int("sl_possessed_until", math.floor(entry.until_time))
	meta:set_string("infotext", S("OBJECT POSSESSED"))

	pl.possession_pos = hash
	pl.possession_ready_at = entry.until_time
		+ possession_setting("possession_cooldown", game_mode.POSSESSION_COOLDOWN)

	-- Identity-neutral: the broadcast names no player and no team.
	game_mode.broadcast(S("Something has taken hold of an object."))
	minetest.sound_play("alert", { pos = rounded, gain = 0.7, max_hear_distance = 14 })
	minetest.log("action", string.format("[game_mode] %s possessed %s at %s",
		ghost_name, node.name, minetest.pos_to_string(rounded)))
	return true
end

-- Returns true (and warns the clicker) when the target object is possessed.
local function refuse_if_possessed(pos, clicker)
	if not game_mode.is_possessed(pos) then return false end
	if not clicker or not clicker:is_player() then return true end
	local pl = game_mode.get_player_state(clicker:get_player_name())
	if pl.phase == "evil_ghost" then return true end
	minetest.chat_send_player(clicker:get_player_name(),
		S("Something else is holding this object. Punch it to drive it out."))
	-- WP2 fusion: the possessing ghost learns WHO touched its vessel —
	-- a bounded identity-information channel (no public leak, no damage).
	local entry = game_mode.get_possession(pos)
	if entry and entry.ghost then
		local owner = minetest.get_player_by_name(entry.ghost)
		if owner then
			minetest.chat_send_player(entry.ghost,
				S("Your vessel was touched by @1.", clicker:get_player_name()))
		end
	end
	return true
end
game_mode.refuse_if_possessed = refuse_if_possessed

-- Every possessable object gets the guard wrapped around its on_rightclick
-- once all mods are loaded, so possession denies use without each node
-- definition needing to know the rule.
local function wrap_possession_guards()
	for node_name, def in pairs(minetest.registered_nodes) do
		if def and not def.sl_possession_guarded and game_mode.is_possessable(node_name) then
			def.sl_possession_guarded = true
			local old_rightclick = def.on_rightclick
			if old_rightclick then
				def.on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
					if refuse_if_possessed(pos, clicker) then return itemstack end
					return old_rightclick(pos, node, clicker, itemstack, pointed_thing)
				end
			end
		end
	end
end
minetest.register_on_mods_loaded(wrap_possession_guards)

-- Counterplay: the living punch a possessed object to exorcise it. The
-- ghost pays an extra cooldown, so pressure on the map is self-limiting.
minetest.register_on_punchnode(function(pos, node, puncher, pointed_thing)
	if not puncher or not puncher:is_player() then return end
	local entry = game_mode.get_possession(pos)
	if not entry then return end

	local name = puncher:get_player_name()
	local pl = game_mode.get_player_state(name)
	if pl.phase ~= "alive" then
		minetest.chat_send_player(name, S("Only the living can drive out a possession."))
		return
	end

	entry.hits = (entry.hits or 0) + 1
	local needed = game_mode.POSSESSION_EXORCISM_HITS
	if entry.hits < needed then
		minetest.chat_send_player(name,
			S("The object resists. (@1/@2)", tostring(entry.hits), tostring(needed)))
		minetest.sound_play("click", { pos = pos, gain = 0.5, max_hear_distance = 8 })
		return
	end

	local ghost = entry.ghost and state.players[entry.ghost]
	if ghost then
		ghost.possession_ready_at = game_mode.now() + game_mode.POSSESSION_EXORCISM_PENALTY
	end
	game_mode.release_possession(entry.pos, "exorcised")
	minetest.chat_send_player(name, S("You drive the presence out. The object is yours again."))
	minetest.sound_play("default_tool_break", { pos = pos, gain = 0.5, max_hear_distance = 8 })
end)

-- 1 Hz tick: expire possessions and slam possessed doors/hatches so the
-- cause stays visible to anyone nearby.
local possession_tick_accum = 0
function game_mode.possession_step(dtime)
	possession_tick_accum = possession_tick_accum + dtime
	if possession_tick_accum < 1 then return end
	possession_tick_accum = 0

	local now = game_mode.now()
	for _, entry in pairs(state.possession) do
		if now >= entry.until_time or not state.match_active then
			game_mode.release_possession(entry.pos, "expired")
		elseif entry.kind == "door" and now >= (entry.next_slam or 0) then
			entry.next_slam = now + game_mode.POSSESSION_SLAM_INTERVAL
			local node = minetest.get_node_or_nil(entry.pos)
			if node then
				local flip = {
					[modname .. ":door_closed"] = modname .. ":door_open",
					[modname .. ":door_open"] = modname .. ":door_closed",
					[modname .. ":hatch"] = modname .. ":hatch_open",
					[modname .. ":hatch_open"] = modname .. ":hatch",
				}
				local target = flip[node.name]
				if target then
					minetest.set_node(entry.pos, { name = target, param2 = node.param2 })
					entry.node_name = target
					minetest.sound_play("place", { pos = entry.pos, gain = 0.4, max_hear_distance = 10 })
				end
			end
		end
	end
end

-- Drive the possession clock off the sabotage tick, which WP2's globalstep
-- already calls once per frame. Additive wrapper, same call site.
local base_sabotage_step = game_mode.sabotage_step
function game_mode.sabotage_step(dtime)
	base_sabotage_step(dtime)
	game_mode.possession_step(dtime)
end

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

-- ================================================================
-- Cloud cage: minimal containment structure materialized at ghost_spawn.
-- Only fills air/ignore, so hand-built arenas and admin edits survive.
-- ================================================================

function game_mode.build_cloud_cage()
	if not state.ghost_spawn then return 0 end
	local base = vector.round(state.ghost_spawn)
	local placed = 0

	local function fill(p, node_name)
		local node = minetest.get_node_or_nil(p)
		if node and (node.name == "air" or node.name == "ignore") then
			minetest.set_node(p, { name = node_name })
			placed = placed + 1
		end
	end

	-- Floor slab one node below the spawn point.
	for x = -5, 5 do
		for z = -5, 5 do
			fill({ x = base.x + x, y = base.y - 1, z = base.z + z }, "default:glass")
		end
	end

	-- Corner pylons marking the containment perimeter.
	for _, c in ipairs({ {-5, -5}, {-5, 5}, {5, -5}, {5, 5} }) do
		for y = 0, 3 do
			fill({ x = base.x + c[1], y = base.y + y, z = base.z + c[2] }, "default:obsidianbrick")
		end
	end

	if placed > 0 then
		minetest.log("action", "[game_mode] Cloud cage materialized at "
			.. minetest.pos_to_string(base) .. " (" .. placed .. " nodes)")
	end
	return placed
end

if minetest.load_area then
	minetest.register_on_mods_loaded(function()
		minetest.after(2, function()
			if state.ghost_spawn then
				minetest.load_area(vector.round(state.ghost_spawn))
			end
			game_mode.build_cloud_cage()
		end)
	end)
end

-- ================================================================
-- Containment enforcement  (WP3 — MATCH_LOOP_SPEC "Ghost cloud cage":
-- ghosts "cannot freely return to the map during ordinary ghost state"
-- and "may observe the match only through intentionally limited,
-- designed channels".)
--
-- The cage geometry above is only scenery: a contained ghost holds the
-- fly and noclip privileges it needs to exist up there, which also let
-- it simply descend into the arena and watch the match from overhead.
-- That is a silent information leak — a ghost is barred from *talking*
-- to the living, but unrestricted looking is just as strong a channel
-- when the summon ritual is supposed to be the costly way to buy it.
--
-- Enforcement is a soft leash rather than a wall, so it cannot trap a
-- player or fight the engine:
--   * inside the radius            -> nothing happens.
--   * drifting past the boundary   -> one warning, then a pull back.
--   * summoned to the altar        -> exempt; that is a designed channel.
--   * evil ghosts                  -> exempt; map access is their bargain.
-- ================================================================

game_mode.CAGE_RADIUS = 24        -- horizontal free-roam radius inside the cage
game_mode.CAGE_FLOOR_MARGIN = 12  -- how far below the cage floor is tolerated
game_mode.CAGE_WARN_INTERVAL = 5  -- seconds between containment warnings

-- Distance a contained ghost has strayed outside its cage, or nil when held.
-- Exposed so tests and the soak harness can assert containment directly.
function game_mode.cage_breach_distance(pos)
	if not state.ghost_spawn then return nil end
	local base = state.ghost_spawn
	local dx, dz = pos.x - base.x, pos.z - base.z
	local horizontal = math.sqrt(dx * dx + dz * dz)
	local drop = base.y - pos.y

	if horizontal > game_mode.CAGE_RADIUS then
		return horizontal - game_mode.CAGE_RADIUS, "horizontal"
	end
	if drop > game_mode.CAGE_FLOOR_MARGIN then
		return drop - game_mode.CAGE_FLOOR_MARGIN, "descent"
	end
	return nil
end

-- True when this player's phase/state must be held inside the cloud cage.
function game_mode.is_contained(name)
	local pl = state.players[name]
	if not pl then return false end
	if pl.phase ~= "ghost" then return false end        -- evil ghosts roam by design
	if pl.ghost_summoned_by then return false end       -- designed altar channel
	if pl.role == "monster_master" then return false end
	return true
end

function game_mode.return_to_cage(player, reason)
	if not state.ghost_spawn then return false end
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)
	player:set_pos(table.copy(state.ghost_spawn))
	if player.set_velocity then
		player:set_velocity({ x = 0, y = 0, z = 0 })
	end

	local now = game_mode.now()
	if (pl.cage_warned_at or 0) + game_mode.CAGE_WARN_INTERVAL <= now then
		pl.cage_warned_at = now
		minetest.chat_send_player(name,
			S("Containment holds. You cannot return to the map unaided."))
	end
	minetest.log("action", string.format("[game_mode] %s returned to cloud cage (%s)",
		name, reason or "breach"))
	return true
end

-- 1 Hz sweep; runs on the same tick budget as sabotage/possession.
local cage_tick_accum = 0
function game_mode.containment_step(dtime)
	cage_tick_accum = cage_tick_accum + dtime
	if cage_tick_accum < 1 then return end
	cage_tick_accum = 0
	if not state.match_active then return end

	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		if game_mode.is_contained(name) then
			local pos = player:get_pos()
			if pos then
				local breach, reason = game_mode.cage_breach_distance(pos)
				if breach then
					game_mode.return_to_cage(player, reason)
				end
			end
		end
	end
end

-- Additive wrapper again: reuse WP2's existing globalstep call site.
local base_sabotage_step_cage = game_mode.sabotage_step
function game_mode.sabotage_step(dtime)
	base_sabotage_step_cage(dtime)
	game_mode.containment_step(dtime)
end

-- ================================================================
-- Stations from spoils (team directive 2026-08-29)
-- ================================================================
-- Mapgen places no workshops, so every station needed to craft
-- anything is assembled by hand through the inventory crafting menu,
-- and every ingredient is obtainable from monsters (see
-- game_mode.MONSTER_LOOT in entities.lua).
-- Registered once every mod is loaded (sl_gui loads after sl_modebase,
-- so the crafting menu's global does not exist yet at this file's load).
minetest.register_on_mods_loaded(function()
	if not register_craft_recipe then return end
	register_craft_recipe({
		output = game_mode.modname .. ":ghost_altar",
		output_count = 1,
		ingredients = {
			[game_mode.modname .. ":metal_ingot"] = 2,
			[game_mode.modname .. ":energy_crystal"] = 2,
			[game_mode.modname .. ":circuit_board"] = 1,
		},
		description = S("Ghost Altar (ritual station — summons a contained ghost for a relic)"),
		category = "tactical",
	})
end)
