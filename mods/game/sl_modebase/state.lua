local S = game_mode.S

local state = {
	-- beacon teams
	teams = {
		beacon_a = {
			label = "Beacon A",
			color = "#ff5555",
			spawn = { x = 0, y = 10, z = 0 },
		},
		beacon_b = {
			label = "Beacon B",
			color = "#5555ff",
			spawn = { x = 40, y = 10, z = 0 },
		},
	},

	monster_master = {
		base_spawn = { x = 0, y = 25, z = 0 },
		player = nil, -- name of current monster master
	},

	players = {}, -- [name] = { team=..., lives=..., eliminated=bool, role="monster_master"|nil }

	match_active = false,
	match_count = 0,
}

state.teams_order = { "beacon_a", "beacon_b" }

game_mode.state = state

-- Utility helpers shared across files
function game_mode.get_player_state(name)
	local players = state.players
	local pl = players[name]
	if not pl then
		pl = {
			team = nil,
			lives = game_mode.LIVES_PER_PLAYER,
			eliminated = false,
			role = nil,
		}
		players[name] = pl
	end
	return pl
end

function game_mode.count_team_players(team_id)
	local count = 0
	for _, pl in pairs(state.players) do
		if pl.team == team_id then
			count = count + 1
		end
	end
	return count
end

function game_mode.assign_beacon_team(name)
	-- Very simple team balancing: assign to beacon with fewer players
	local count_a = game_mode.count_team_players("beacon_a")
	local count_b = game_mode.count_team_players("beacon_b")

	local team_id = (count_a <= count_b) and "beacon_a" or "beacon_b"
	local pl = game_mode.get_player_state(name)
	pl.team = team_id
	pl.role = nil

	return team_id
end

function game_mode.get_team_color(team_id)
	local tdef = state.teams[team_id]
	return tdef and tdef.color or "#ffffff"
end

function game_mode.get_team_label(team_id)
	local tdef = state.teams[team_id]
	return tdef and tdef.label or team_id or "None"
end

function game_mode.is_beacon_team(team_id)
	return team_id == "beacon_a" or team_id == "beacon_b"
end

function game_mode.broadcast(msg)
	minetest.chat_send_all(minetest.colorize("#ffffaa", "[System Looting] " .. msg))
end

function game_mode.get_connected_player_names()
	local res = {}
	for _, player in ipairs(minetest.get_connected_players()) do
		table.insert(res, player:get_player_name())
	end
	return res
end

