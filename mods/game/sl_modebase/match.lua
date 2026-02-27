local S = game_mode.S
local state = game_mode.state

-- Match / win handling
function game_mode.end_match(winner, reason)
	if not state.match_active then
		return
	end

	state.match_active = false

	if winner == "beacons" then
		game_mode.broadcast(S("Beacon teams win! (@1)", reason or ""))
	elseif state.teams[winner] then
		game_mode.broadcast(S("@1 wins! (@2)", game_mode.get_team_label(winner), reason or ""))
	else
		game_mode.broadcast(S("Match ended. (@1)", reason or ""))
	end
end

local function reset_players_for_new_match()
	for name, pl in pairs(state.players) do
		pl.lives = game_mode.LIVES_PER_PLAYER
		pl.eliminated = false

		-- Do not change roles here; monster master / teams are persistent
	end
end

function game_mode.start_new_match(initiator)
	if state.match_active then
		return false, S("Match is already running.")
	end

	local connected = game_mode.get_connected_player_names()
	if #connected < 2 then
		return false, S("Need at least 2 players to start a match.")
	end

	state.match_count = (state.match_count or 0) + 1
	state.match_active = true

	reset_players_for_new_match()

	-- Respawn all connected players at their team / role spawns
	for _, name in ipairs(connected) do
		local player = minetest.get_player_by_name(name)
		if player then
			local pl = game_mode.get_player_state(name)
			-- Ensure everyone has a team unless they are monster master
			if not pl.team and pl.role ~= "monster_master" then
				game_mode.assign_beacon_team(name)
			end
			game_mode.spawn_player(player)
		end
	end

	if initiator then
		game_mode.broadcast(S("Match #@1 started by @2.", tostring(state.match_count), initiator))
	else
		game_mode.broadcast(S("Match #@1 started.", tostring(state.match_count)))
	end

	return true
end

local function check_team_elimination()
	-- Check each beacon team: if all its players are eliminated (or have zero lives),
	-- the other beacon team wins.
	for _, team_id in ipairs(state.teams_order) do
		local has_active = false
		for name, pl in pairs(state.players) do
			if pl.team == team_id and not pl.eliminated and pl.lives > 0 then
				local player = minetest.get_player_by_name(name)
				if player then
					has_active = true
					break
				end
			end
		end

		if not has_active then
			-- find opposing beacon team
			local other = (team_id == "beacon_a") and "beacon_b" or "beacon_a"
			if state.teams[other] then
				game_mode.end_match(other, S("All players from @1 are out", game_mode.get_team_label(team_id)))
				return
			end
		end
	end
end

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

	if not pl.team or not game_mode.is_beacon_team(pl.team) then
		return
	end

	if pl.eliminated then
		return
	end

	pl.lives = math.max(0, pl.lives - 1)
	if pl.lives <= 0 then
		pl.eliminated = true
		game_mode.broadcast(S("@1 is out for @2!", name, game_mode.get_team_label(pl.team)))
	else
		minetest.chat_send_player(name, S("You have @1 lives remaining.", tostring(pl.lives)))
	end

	check_team_elimination()
end)

