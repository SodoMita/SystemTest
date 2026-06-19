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
		end

		for _, name in ipairs(connected) do
			local pl = game_mode.get_player_state(name)
			if pl.team == biggest_team then
				pl.role = "monster_master"
				pl.team = nil
				state.monster_master.player = name
				game_mode.broadcast(S("@1 has been chosen as the Monster Master!", name))
				break
			end
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

-- Protection override to prevent ghosts from digging/placing
local old_is_protected = minetest.is_protected
function minetest.is_protected(pos, name)
	local pl = game_mode.get_player_state(name)
	if pl and pl.phase == "ghost" then
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

-- Death handling
minetest.register_on_dieplayer(function(player, reason)
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)

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
