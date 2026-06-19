local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Match lifecycle and win conditions
-- ================================================================
-- Win modes:
--   "elimination" — last team standing (default)
--   "objective"   — craft and deliver the Objective Core to beacon
-- ================================================================

-- End match
function game_mode.end_match(winner, reason)
	if not state.match_active then
		return
	end

	state.match_active = false

	-- Restore beacons and spawns from persistent storage
	local storage = game_mode.storage or minetest.get_mod_storage()
	if storage then
		local spawns_str = storage:get_string("spawns")
		if spawns_str and spawns_str ~= "" then
			local data = minetest.deserialize(spawns_str)
			if data then
				if data.beacon_a then
					local bpos = {x=data.beacon_a.x, y=data.beacon_a.y-1, z=data.beacon_a.z}
					minetest.set_node(bpos, {name = "sl_modebase:beacon_a"})
					state.teams.beacon_a.spawn = data.beacon_a
				end
				if data.beacon_b then
					local bpos = {x=data.beacon_b.x, y=data.beacon_b.y-1, z=data.beacon_b.z}
					minetest.set_node(bpos, {name = "sl_modebase:beacon_b"})
					state.teams.beacon_b.spawn = data.beacon_b
				end
			end
		end
	end

	-- Remove all monsters
	for _, obj in pairs(minetest.luaentities) do
		if obj.name == game_mode.MONSTER_NAME then
			obj.object:remove()
		end
	end

	-- Clear Monster Master
	if state.monster_master.player then
		game_mode.set_monster_master(nil)
	end

	-- Teleport all players back to lobby after a short delay to ensure state sync
	minetest.after(0.5, function()
		for _, player in ipairs(minetest.get_connected_players()) do
			game_mode.spawn_player(player)
		end
	end)

	if winner == "beacons" then
		game_mode.broadcast(S("Beacon teams win! (@1)", reason or ""))
	elseif state.teams[winner] then
		game_mode.broadcast(S("@1 wins! (@2)",
			game_mode.get_team_label(winner), reason or ""))

		-- Grant win achievements to winning team members
		if achievement_progress then
			for pname, pdata in pairs(state.players) do
				if pdata.team == winner then
					local player = minetest.get_player_by_name(pname)
					if player then
						achievement_progress(player, "win_match", 1)
						achievement_progress(player, "win_5_matches", 1)
						-- Survivor check: not eliminated
						if not pdata.eliminated then
							achievement_progress(player, "survive_match", 1)
						end
					end
				end
			end
		end
	else
		game_mode.broadcast(S("Match ended. (@1)", reason or ""))
	end
end

-- Reset for new match
local function reset_players_for_new_match()
	for name, pl in pairs(state.players) do
		pl.lives = game_mode.LIVES_PER_PLAYER
		pl.eliminated = false
		pl.phase = "alive"
		
		-- Clear inventory at start of match too
		local player = minetest.get_player_by_name(name)
		if player and not minetest.settings:get_bool("creative_mode") then
			player:get_inventory():set_list("main", {})
		end
	end
end

-- Start match
function game_mode.start_new_match(initiator)
	if state.match_active then
		return false, S("Match is already running.")
	end

	-- Verify at least one win condition is set
	if not state.win_conditions.elimination and not state.win_conditions.objective then
		return false, S("Cannot start match: No win conditions enabled.")
	end

	local connected = game_mode.get_connected_player_names()
	if #connected < 1 then
		return false, S("Need at least 1 player to start a match.")
	end

	-- Auto-assign Monster Master if nobody has the role
	local mm_exists = false
	for _, name in ipairs(connected) do
		local pl = game_mode.get_player_state(name)
		if pl.role == "monster_master" then
			mm_exists = true
			state.monster_master.player = name
			break
		end
	end

	if not mm_exists then
		-- Pick player from the biggest team
		local team_counts = { beacon_a = 0, beacon_b = 0 }
		for _, name in ipairs(connected) do
			local pl = game_mode.get_player_state(name)
			if pl.team then
				team_counts[pl.team] = (team_counts[pl.team] or 0) + 1
			end
		end

		local biggest_team = "beacon_a"
		if team_counts.beacon_b > team_counts.beacon_a then
			biggest_team = "beacon_b"
		elseif team_counts.beacon_a == 0 and team_counts.beacon_b == 0 then
			-- If no teams (all in lobby), pick from everyone
			biggest_team = nil
		end

		local candidates = {}
		for _, name in ipairs(connected) do
			local pl = game_mode.get_player_state(name)
			if not biggest_team or pl.team == biggest_team then
				table.insert(candidates, name)
			end
		end

		if #candidates > 0 then
			local chosen_name = candidates[math.random(1, #candidates)]
			game_mode.set_monster_master(chosen_name)
			game_mode.broadcast(S("@1 has been chosen as the Monster Master!", chosen_name))
		end
	end

	state.match_count = (state.match_count or 0) + 1
	state.match_active = true

	reset_players_for_new_match()

	for _, name in ipairs(connected) do
		local player = minetest.get_player_by_name(name)
		if player then
			local pl = game_mode.get_player_state(name)
			if not pl.team and pl.role ~= "monster_master" then
				game_mode.assign_beacon_team(name)
			end
			game_mode.spawn_player(player)
		end
	end

	local cond_list = {}
	if state.win_conditions.elimination then table.insert(cond_list, S("Elimination")) end
	if state.win_conditions.objective then table.insert(cond_list, S("Objective Delivery")) end
	local mode_label = table.concat(cond_list, " + ")

	if initiator then
		game_mode.broadcast(S("Match #@1 started by @2. Mode: @3",
			tostring(state.match_count), initiator, mode_label))
	else
		game_mode.broadcast(S("Match #@1 started. Mode: @2",
			tostring(state.match_count), mode_label))
	end

	return true
end

-- Protection override to prevent ghosts and lobby players from digging/placing
local old_is_protected = minetest.is_protected
function minetest.is_protected(pos, name)
	local pl = game_mode.get_player_state(name)
	local is_creative = minetest.settings:get_bool("creative_mode") or minetest.check_player_privs(name, {all=true})
	
	if is_creative then
		return false -- Creative/Admins can always build
	end
	
	if pl and (pl.phase == "ghost" or not state.match_active) then
		return true
	end
	return old_is_protected(pos, name)
end

-- Elimination check
local function check_team_elimination()
	if not state.win_conditions.elimination then return end

	for _, team_id in ipairs(state.teams_order) do
		local has_active = false
		for name, pl in pairs(state.players) do
			if pl.team == team_id and pl.phase == "alive" and not pl.eliminated then
				local player = minetest.get_player_by_name(name)
				if player then
					has_active = true
					break
				end
			end
		end

		if not has_active then
			local other = (team_id == "beacon_a") and "beacon_b" or "beacon_a"
			if state.teams[other] then
				game_mode.end_match(other,
					S("All players from @1 are out", game_mode.get_team_label(team_id)))
				return
			end
		end
	end
end

minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	local is_creative = minetest.settings:get_bool("creative_mode")
	if is_creative then
		return true -- No damage in creative mode
	end

	if not state.match_active then
		return true -- Block damage in lobby
	end
	
	if hitter and hitter:is_player() then
		local hname = hitter:get_player_name()
		local hpl = game_mode.get_player_state(hname)
		if hpl and hpl.phase == "ghost" then
			return true -- Ghosts can't attack
		end
	end
end)

-- Chat restriction for ghosts
minetest.register_on_chat_message(function(name, message)
	local pl = game_mode.get_player_state(name)
	if pl and pl.phase == "ghost" then
		minetest.chat_send_player(name, S("Ghosts cannot speak to the living."))
		return true -- Block message
	end
end)

-- Death handling
minetest.register_on_dieplayer(function(player, reason)
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)

	-- Drop items on death
	local pos = player:get_pos()
	local inv = player:get_inventory()
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		if not stack:is_empty() then
			-- Don't drop MM summoning tool
			if stack:get_name() ~= game_mode.modname .. ":summon_monster" then
				local obj = minetest.add_item(pos, stack)
				if obj then
					-- Random direction "fountain" effect
					local rx = (math.random() - 0.5) * 4
					local rz = (math.random() - 0.5) * 4
					local ry = math.random() * 5
					obj:set_velocity({x=rx, y=ry, z=rz})
				end
				inv:set_stack("main", i, ItemStack(""))
			end
		end
	end

	if not state.match_active then
		return
	end

	if pl.role == "monster_master" then
		game_mode.end_match("beacons", S("Monster master @1 was slain", name))
		return
	end

	if pl.eliminated then
		return
	end

	-- Phase-based transition
	if pl.phase == "alive" then
		pl.lives = math.max(0, pl.lives - 1)
		if pl.lives <= 0 then
			pl.phase = "ghost"
			player:set_armor_groups({immortal = 1})
			game_mode.broadcast(S("@1 has fallen and returned as a Ghost!", name))
		else
			minetest.chat_send_player(name,
				S("You have @1 lives remaining.", tostring(pl.lives)))
		end
	elseif pl.phase == "ghost" then
		pl.phase = "monster"
		player:set_armor_groups({fleshy = 100})
		game_mode.broadcast(S("@1's spirit has mutated into a Neutral Monster!", name))
	elseif pl.phase == "monster" then
		pl.phase = "master_monster"
		player:set_armor_groups({fleshy = 100})
		game_mode.broadcast(S("@1 has been bound to the Monster Master's will!", name))
	elseif pl.phase == "master_monster" then
		pl.eliminated = true
		game_mode.broadcast(S("@1 is fully eliminated from the simulation!", name))
	end

	check_team_elimination()
end)
