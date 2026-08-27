local S = game_mode.S

local state = {
	-- beacon teams
	teams = {
		beacon_a = {
			label = "Beacon A",
			color = "#ff5555",
			spawn = { x = 0, y = 10, z = 0 },
			hp = 100,
		},
		beacon_b = {
			label = "Beacon B",
			color = "#5555ff",
			spawn = { x = 40, y = 10, z = 0 },
			hp = 100,
		},
	},

	monster_master = {
		base_spawn = { x = 0, y = 25, z = 0 },
		player = nil, -- name of current monster master
	},

	-- Cloud cage: intentionally far above the playable arena.
	ghost_spawn = { x = 0, y = 100, z = 0 },
	lobby_spawn = { x = 0, y = 10, z = 0 },

	players = {}, -- [name] = { team=..., lives=..., eliminated=bool, role=..., phase=... }

	match_active = false,
	match_count = 0,
	match_started_at = 0,
	match_ended_at = 0,

	-- Ready check / insertion sequencing (LOBBY -> READY CHECK -> COUNTDOWN -> INSERTION)
	ready_check = {
		active = false,
		initiator = nil,
		ready = {},         -- [name] = true
		started_at = 0,
		countdown_left = 0, -- > 0 while counting down to insertion
		last_announced = -1,
	},

	-- Active sabotages: [pos_hash] = { pos, kind = "node"|"beacon", team_id, until_time }
	sabotage = {},

	-- Active evil-ghost possessions: [pos_hash] = { pos, owner, until_time }
	possession = {},

	-- Win Conditions (Options)
	win_conditions = {
		elimination = true,
		objective = false,
	},

	-- Match Settings
	settings = {
		lives = 5,
		beacon_hp = 100,
		mm_auto_assign = true,
		match_duration = 600,   -- seconds; 0 disables the match timer
		ready_timeout = 60,     -- seconds to collect /sl_ready confirmations
		countdown = 5,          -- insertion countdown length in seconds
		sabotage_duration = 30, -- seconds a sabotage charge corrupts its target
		possession_duration = 20, -- seconds an evil ghost holds a vessel
	}
}

-- Load persistent spawns from world storage
game_mode.storage = minetest.get_mod_storage()
local function load_spawns()
	local storage = game_mode.storage
	if not storage then return end
	local spawns_str = storage:get_string("spawns")
	if spawns_str ~= "" then
		local data = minetest.deserialize(spawns_str)
		if data then
			if data.beacon_a then state.teams.beacon_a.spawn = data.beacon_a end
			if data.beacon_b then state.teams.beacon_b.spawn = data.beacon_b end
			if data.mm then state.monster_master.base_spawn = data.mm end
			if data.ghost then state.ghost_spawn = data.ghost end
			if data.lobby then state.lobby_spawn = data.lobby end
		end
	end
end
load_spawns()

function game_mode.save_spawns()
	local storage = game_mode.storage
	if not storage then return end
	local data = {
		beacon_a = state.teams.beacon_a.spawn,
		beacon_b = state.teams.beacon_b.spawn,
		mm = state.monster_master.base_spawn,
		ghost = state.ghost_spawn,
		lobby = state.lobby_spawn,
	}
	storage:set_string("spawns", minetest.serialize(data))
end

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
			phase = "alive", -- alive, ghost (cloud cage), evil_ghost, monster, master_monster
			points = 0,
			ghost_summoned_by = nil,
			ghost_summon_pos = nil,
			last_death_pos = nil,
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

-- ================================================================
-- Shared utilities: clock, position hashing, sabotage registry
-- ================================================================

function game_mode.now()
	return minetest.get_us_time() / 1000000
end

function game_mode.pos_hash(pos)
	return string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
end

function game_mode.get_sabotage(pos)
	return state.sabotage[game_mode.pos_hash(pos)]
end

function game_mode.is_sabotaged(pos)
	return game_mode.get_sabotage(pos) ~= nil
end

-- Clears one sabotage entry and restores the node's original infotext.
function game_mode.clear_sabotage_at(pos)
	local hash = game_mode.pos_hash(pos)
	local entry = state.sabotage[hash]
	if not entry then return false end
	state.sabotage[hash] = nil
	local meta = minetest.get_meta(pos)
	meta:set_int("sl_sabotaged_until", 0)
	meta:set_string("infotext", meta:get_string("sl_prev_infotext") or "")
	meta:set_string("sl_prev_infotext", "")
	return true
end

function game_mode.clear_all_sabotage()
	for _, entry in pairs(state.sabotage) do
		game_mode.clear_sabotage_at(entry.pos)
	end
	state.sabotage = {}
end

-- ================================================================
-- Possession registry (evil ghosts): bounded, discoverable, with
-- an information channel to the possessing ghost and an exorcism
-- counterplay for the living.
-- ================================================================

function game_mode.get_possession(pos)
	return state.possession[game_mode.pos_hash(pos)]
end

function game_mode.is_possessed(pos)
	return game_mode.get_possession(pos) ~= nil
end

function game_mode.clear_possession_at(pos)
	local hash = game_mode.pos_hash(pos)
	local entry = state.possession[hash]
	if not entry then return false end
	state.possession[hash] = nil
	local meta = minetest.get_meta(pos)
	meta:set_string("infotext", meta:get_string("sl_prev_infotext") or "")
	meta:set_string("sl_prev_infotext", "")
	return true
end

function game_mode.clear_all_possession()
	for _, entry in pairs(state.possession) do
		game_mode.clear_possession_at(entry.pos)
	end
	state.possession = {}
end

