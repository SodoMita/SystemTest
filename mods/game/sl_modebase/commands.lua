local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Throttled logging for refusals (SECURITY)
-- ================================================================
-- A refusal should be loud -- but it must not be an amplifier. The engine
-- rate-limits CHAT (chat_message_limit_per_10sec, then a kick for flooding)
-- and rate-limits nothing else: an inventory-field submission with an empty
-- formname is forwarded unconditionally, so a client can drive any
-- client-reachable refusal path at packet rate. Each refusal used to cost one
-- action-log line on disk; measured, 200 forged packets wrote 200 lines. One
-- line per window per player, with the suppressed count appended to the next
-- line that does get written, keeps the audit trail and caps the cost.
local LOG_THROTTLE_WINDOW = 2.0
local log_throttle = {} -- [key][name] = { at = <clock>, suppressed = <count> }

function game_mode.throttled_log(level, key, name, msg)
	local bucket = log_throttle[key]
	if not bucket then
		bucket = {}
		log_throttle[key] = bucket
	end
	local now = game_mode.now()
	local t = bucket[name]
	if not t then
		t = { at = now, suppressed = 0 }
		bucket[name] = t
	elseif now - t.at < LOG_THROTTLE_WINDOW then
		-- Inside the window: count it, do not write it. The count rides along
		-- with the next line that is written, so nothing is lost -- it is just
		-- not written once per packet.
		t.suppressed = t.suppressed + 1
		return false
	end
	local suppressed = t.suppressed
	t.at, t.suppressed = now, 0
	minetest.log(level, msg .. (suppressed > 0
		and (" (+" .. suppressed .. " more in " .. LOG_THROTTLE_WINDOW .. "s)")
		or ""))
	return true
end

-- Freed with the player: this is a per-name table, and disconnect is free,
-- instant and repeatable (see the same rule in sl_gui/system_tab.lua).
minetest.register_on_leaveplayer(function(player)
	local name = player and player.get_player_name and player:get_player_name()
	if not name then return end
	for _, bucket in pairs(log_throttle) do
		bucket[name] = nil
	end
end)

-- Monster master helpers
function game_mode.is_monster_master(name)
	return state.monster_master.player == name
end

function game_mode.set_monster_master(name)
	if name == nil or name == "" then
		-- Remove tool from old MM if they exist
		if state.monster_master.player then
			local old_name = state.monster_master.player
			local old_p = minetest.get_player_by_name(old_name)
			if old_p then
				old_p:get_inventory():remove_item("main", game_mode.modname .. ":summon_monster")
			end
			local old_state = state.players[old_name]
			if old_state and old_state.role == "monster_master" then
				old_state.role = nil
			end
		end
		state.monster_master.player = nil
		return
	end

	if state.monster_master.player and state.monster_master.player ~= name then
		game_mode.set_monster_master(nil)
	end
	state.monster_master.player = name

	local pl = game_mode.get_player_state(name)
	pl.role = "monster_master"
	pl.team = nil
	pl.eliminated = false

	local player = minetest.get_player_by_name(name)
	if player then
		game_mode.spawn_player(player)
		local inv = player:get_inventory()
		-- The kit is role equipment, handed out ONCE per match cycle.
		-- SECURITY: the guard used to be `not inv:contains_item(...)`, which
		-- only proves the items are not in the inventory *right now*. Claim
		-- the role, pocket (drop) the starter essence, resign -- a GUI button
		-- any client can forge -- and claim again: monster essence minted from
		-- nothing, as often as the client can send packets. The marker below
		-- keys the gift to the match number instead of to the inventory.
		-- (match.lua re-hands the kit after the match-start inventory reset,
		-- which is the one legitimate re-grant in a cycle.)
		local cycle = state.match_count or 0
		if pl.mm_kit_cycle ~= cycle then
			pl.mm_kit_cycle = cycle
			if not inv:contains_item("main", game_mode.modname .. ":summon_monster") then
				inv:add_item("main", game_mode.modname .. ":summon_monster")
			end
			if game_mode.ESSENCE_ITEM
				and not inv:contains_item("main", game_mode.ESSENCE_ITEM) then
				inv:add_item("main", game_mode.ESSENCE_ITEM .. " 10")
			end
		end
	end
end

-- Privilege for admin control over roles/teams
minetest.register_privilege("sl_admin", {
	description = S("System Looting game admin (assign teams, roles)"),
	give_to_singleplayer = true,
})

-- Chat commands
minetest.register_chatcommand("sl_state", {
	description = S("Show your System Looting team / role state"),
	func = function(name)
		local pl = game_mode.get_player_state(name)
		local parts = {}

		if pl.role == "monster_master" then
			table.insert(parts, S("Role: Monster Master"))
		else
			table.insert(parts, S("Role: Player"))
		end

		if pl.team then
			table.insert(parts, S("Team: @1", game_mode.get_team_label(pl.team)))
		else
			table.insert(parts, S("Team: None"))
		end

		table.insert(parts, S("Phase: @1", tostring(pl.phase)))
		table.insert(parts, S("Points: @1", tostring(pl.points or 0)))
		if state.match_active then
			table.insert(parts, S("Essence pool: @1",
				tostring(state.monster_master.essence_pool or 0)))
			-- Machine crafting readout: is the Objective Forge busy,
			-- and with what? (§6.10 B — the run is public knowledge.)
			if sl_machine and sl_machine.status then
				local st = sl_machine.status()
				if st and st.present then
					if st.running then
						table.insert(parts, S("Forge: @1 (@2s left)",
							st.description or st.output or "?",
							tostring(math.ceil(st.left or 0))))
					else
						table.insert(parts, S("Forge: idle"))
					end
				end
			end
		end
		if pl.eliminated then
			table.insert(parts, S("(Eliminated)"))
		end
		if pl.tournament_spectator then
			table.insert(parts, S("(Tournament spectator)"))
		elseif state.tournament then
			table.insert(parts, S("Tournament: @1 match(es) left, @2 season points",
				tostring(state.tournament_matches_left or 0),
				tostring(state.tournament_scores[name] or 0)))
		end

		minetest.chat_send_player(name, "[System Looting] " .. table.concat(parts, " | "))
		if state.match_active then
			minetest.chat_send_player(name, S("A match is currently running (Match #@1).", tostring(state.match_count)))
		else
			minetest.chat_send_player(name, S("No active match."))
		end
	end,
})

minetest.register_chatcommand("sl_tournament", {
	description = S("Tournament <start [matches]|stop>: fixed number of matches, roster locked at start, ranking at the end"),
	privs = { server = true },
	func = function(name, param)
		local arg = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		local count = tonumber(arg:match("^start%s+(%d+)$") or "") or 5
		if arg:match("^start") then
			if state.tournament then
				return false, S("Tournament mode is already running.")
			end
			if state.match_active then
				return false, S("Start the tournament between matches.")
			end
			count = math.min(50, math.max(1, math.floor(count)))
			state.tournament = true
			state.tournament_planned = count
			state.tournament_matches_left = count
			state.tournament_scores = {}
			-- The roster locks at the starting gun: everyone connected now
			-- plays the season; anyone who joins later spectates (v1.3.5).
			state.tournament_roster = {}
			for _, player in ipairs(minetest.get_connected_players()) do
				local pname = player:get_player_name()
				state.tournament_roster[pname] = true
				game_mode.get_player_state(pname).tournament_spectator = nil
			end
			local roster_n = 0
			for _ in pairs(state.tournament_roster) do roster_n = roster_n + 1 end
			game_mode.broadcast(S("TOURNAMENT MODE: @1 matches. Roster locked: @2 operators — late joiners spectate. Achievements, levels and abilities persist; inventories reset every match.",
				tostring(count), tostring(roster_n)))
			minetest.log("action", "[game_mode] tournament (" .. count ..
				" matches) started by " .. name)
			return true, S("Tournament started: @1 matches.", tostring(count))
		elseif arg == "stop" then
			if not state.tournament then
				return false, S("No tournament is running.")
			end
			if state.match_active then
				return false, S("Stop the tournament between matches.")
			end
			-- Ranking form first, then the one clean reset (shared with the
			-- automatic end-of-season path in match.lua).
			game_mode.end_tournament(S("stopped by @1", name))
			minetest.log("action", "[game_mode] tournament stopped by " .. name)
			return true, S("Tournament stopped: ranking shown, progression reset.")
		end
		return false, S("Usage: /sl_tournament <start|stop>")
	end,
})

-- Who may take the doctrine without an admin's hand.
-- SECURITY: a chat command is the one door every client can walk through, and
-- the engine enforces nothing here beyond `privs` (this command declares
-- none). Ungated, any player could self-appoint the moment the slot was
-- empty -- mid-match, which hands one operator the summoning tool, the
-- essence economy and the 1000-point beacon kills, and locks the role in for
-- the next match's start (match.lua keeps an existing MM instead of
-- auto-assigning). Volunteering in the lobby stays open; during a match it is
-- an admin decision (/sl_assign), which is exactly how matchmaking.lua's
-- take_mm button already treats it.
function game_mode.may_claim_monster_master(name)
	if not minetest.get_player_by_name(name) then
		return false, S("Player not found.")
	end
	if minetest.check_player_privs(name, { sl_admin = true }) then
		return true
	end
	if state.match_active then
		return false, S("A match is running: an admin assigns the Monster Master (/sl_assign).")
	end
	local pl = game_mode.get_player_state(name)
	if pl.phase == "ghost" or pl.phase == "evil_ghost" or pl.eliminated then
		return false, S("The cage cannot hold the doctrine.")
	end
	return true
end

minetest.register_chatcommand("sl_be_monster_master", {
	description = S("Volunteer as monster master in the lobby (if none exists yet)"),
	func = function(name)
		if state.monster_master.player == name then
			-- SECURITY: idempotent. This used to fall through and re-run
			-- set_monster_master() + broadcast(), so one forged `sys_be_mm`
			-- field re-spawned the caller (a position update to every player)
			-- and re-announced "@1 is now the Monster Master!" to the whole
			-- server -- per packet, at packet rate, with no privileges needed
			-- beyond the open lobby volunteer path. Holding the role is a
			-- state, not an event: claiming it twice changes nothing.
			return true, S("You already carry the doctrine.")
		end
		if state.monster_master.player then
			return false, S("Monster master is already @1", state.monster_master.player)
		end

		local allowed, why = game_mode.may_claim_monster_master(name)
		if not allowed then
			game_mode.throttled_log("action", "mm_refused", name,
				"[game_mode] refused /sl_be_monster_master for " .. name
				.. ": " .. tostring(why))
			return false, why
		end

		game_mode.set_monster_master(name)
		game_mode.broadcast(S("@1 is now the Monster Master!", name))
		-- Achievement
		local player = minetest.get_player_by_name(name)
		if player and achievement_progress then
			achievement_progress(player, "play_monster_master", 1)
		end
		return true
	end,
})

minetest.register_chatcommand("sl_mm_return", {
	description = S("Monster master: instantly return to base spawn"),
	func = function(name)
		if not game_mode.is_monster_master(name) then
			return false, S("You are not the monster master.")
		end

		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("Player not found.")
		end

		player:set_pos(table.copy(state.monster_master.base_spawn))
		return true, S("Returned to monster master base.")
	end,
})

-- Convenience spawning for the Monster Master. Unlike the spawner UNIT
-- (content.lua's spawner_activate) this path costs no essence, so it needs
-- its own discipline or it is an unlimited entity tap: SECURITY: a client can
-- send chat commands as fast as it can write packets, and every one of these
-- used to create up to five physics-enabled, pathing, animated mobs -- no
-- cooldown, no cost, no population cap. Forty commands in a loop put 200 live
-- monsters in the world; the server step then spends its whole budget on
-- them and every player on the box starts rubber-banding.
local MM_SPAWN_COOLDOWN = 3.0     -- seconds between convenience spawns
local MM_LIVE_MONSTER_CAP = 12    -- monsters this MM may have alive at once

-- Monsters this operator owns that are still alive and in the world.
function game_mode.count_owned_monsters(name)
	local n = 0
	for _, lua in pairs(minetest.luaentities or {}) do
		if lua and lua.monster_owner == name and not lua._removed then
			n = n + 1
		end
	end
	return n
end

minetest.register_chatcommand("sl_mm_spawn", {
	params = "[count]",
	description = S("Monster master: spawn basic monsters near you (cooldown @1 s, cap @2 alive)",
		tostring(MM_SPAWN_COOLDOWN), tostring(MM_LIVE_MONSTER_CAP)),
	func = function(name, param)
		if not game_mode.is_monster_master(name) then
			return false, S("You are not the monster master.")
		end

		-- Monsters belong to a match: outside one this only litters the lobby.
		if not state.match_active and not minetest.settings:get_bool("creative_mode") then
			return false, S("Monsters are match creatures: no match is running.")
		end

		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("Player not found.")
		end

		local count = tonumber(param) or 1
		if count ~= count then count = 1 end -- NaN from "0/0" and friends
		count = math.max(1, math.min(math.floor(count), 5))

		local pl = game_mode.get_player_state(name)
		local now = game_mode.now()
		if now < (pl.mm_spawn_ready_at or 0) then
			return false, S("Your hands are still busy. (@1 s)",
				tostring(math.ceil(pl.mm_spawn_ready_at - now)))
		end

		local alive = game_mode.count_owned_monsters(name)
		local room = MM_LIVE_MONSTER_CAP - alive
		if room <= 0 then
			return false, S("You already command @1 creatures (cap @2).",
				tostring(alive), tostring(MM_LIVE_MONSTER_CAP))
		end
		count = math.min(count, room)
		pl.mm_spawn_ready_at = now + MM_SPAWN_COOLDOWN

		local pos = player:get_pos()
		if not pos then
			return false, S("No position.")
		end

		local spawned = 0
		for i = 1, count do
			local offset = {
				x = math.random(-3, 3),
				y = 0,
				z = math.random(-3, 3),
			}
			local spawn_pos = vector.add(pos, offset)
			local obj = game_mode.spawn_monster(spawn_pos, "stalker", name)
			if obj then
				spawned = spawned + 1
			end
		end

		if spawned < count then
			return true, S("Spawned @1 of @2 monster(s).", tostring(spawned), tostring(count))
		end
		return true, S("Spawned @1 monster(s).", tostring(spawned))
	end,
})

-- Living player deliberately opens a temporary information channel to a cloud-cage ghost.
minetest.register_chatcommand("sl_summon_ghost", {
	params = "<ghost_name>",
	description = S("Summon a contained ghost for information"),
	func = function(name, param)
		if not minetest.settings:get_bool("creative_mode") then
			return false, S("Ghost summoning commands are available only in creative mode.")
		end
		local caller = game_mode.get_player_state(name)
		if caller.phase ~= "alive" or not state.match_active then
			return false, S("Only a living player in an active match may summon a ghost.")
		end
		local target = param:match("^(%S+)$")
		local ghost = target and game_mode.get_player_state(target)
		if not ghost or ghost.phase ~= "ghost" then
			return false, S("Target is not a contained ghost.")
		end
		ghost.ghost_summoned_by = name
		minetest.chat_send_player(target, S("A living player has opened a channel. Prepare one information packet."))
		return true, S("Ghost channel opened. The ghost must offer information.")
	end,
})

-- Allowed ghost-to-living information transfer. This is not public chat.
minetest.register_chatcommand("sl_ghost_offer", {
	params = "<living_name> <security|logistics|medical>",
	description = S("Offer one information packet to your summoner"),
	func = function(name, param)
		if not minetest.settings:get_bool("creative_mode") then
			return false, S("Ghost information commands are available only in creative mode.")
		end
		local pl = game_mode.get_player_state(name)
		if pl.phase ~= "ghost" or not pl.ghost_summoned_by then
			return false, S("You are not a summoned cloud-cage ghost.")
		end
		local target, kind = param:match("^(%S+)%s+(%S+)$")
		if target ~= pl.ghost_summoned_by or not minetest.get_player_by_name(target) then
			return false, S("You may only offer information to your summoner.")
		end
		local ids = {
			security = "data_pad_security",
			logistics = "data_pad_logistics",
			medical = "data_pad_medical",
		}
		if not ids[kind] then return false, S("Unknown information packet.") end
		local receiver = minetest.get_player_by_name(target)
		receiver:get_inventory():add_item("main", game_mode.modname .. ":" .. ids[kind])
		minetest.chat_send_player(target, S("An information packet has been delivered by the summoned ghost."))
		pl.ghost_summoned_by = nil
		return true, S("Information packet transmitted.")
	end,
})

-- Ghost communication seal. Chat messages are blocked in match.lua; chat
-- COMMANDS (including direct-message builtins like /msg, /w, /tell) must be
-- blocked here. minetest.register_on_chatcommand does not exist, so every
-- registered command is wrapped with a phase guard instead. The allowlist
-- covers only the designed ghost channels; it exposes no conversation route.
local GHOST_ALLOWED_COMMANDS = {
	sl_ghost_offer = true, -- designed ghost-to-summoner information transfer
	sl_state = true,       -- read-only self diagnostics
	help = true,           -- local help output; reaches nobody
}

local function wrap_chatcommand_with_ghost_guard(cmd_name)
	local def = minetest.registered_chatcommands[cmd_name]
	if not def or def.sl_ghost_guarded then return end
	local old_func = def.func
	def.func = function(pname, param)
		local pl = game_mode.get_player_state(pname)
		if pl and (pl.phase == "ghost" or pl.phase == "evil_ghost")
				and not GHOST_ALLOWED_COMMANDS[cmd_name] then
			return false, S("Ghost communications are sealed.")
		end
		return old_func(pname, param)
	end
	def.sl_ghost_guarded = true
end

local function wrap_all_chatcommands()
	for cmd_name in pairs(minetest.registered_chatcommands) do
		wrap_chatcommand_with_ghost_guard(cmd_name)
	end
end

wrap_all_chatcommands()
-- Catch commands registered by mods that load after this one.
minetest.register_on_mods_loaded(wrap_all_chatcommands)

-- Admin command: force-assign player to beacon or monster master
minetest.register_chatcommand("sl_assign", {
	params = "<player> <beacon_a|beacon_b|monster_master>",
	description = S("Assign a player to a beacon team or as monster master"),
	privs = { sl_admin = true },
	func = function(name, param)
		local target_name, role = param:match("^(%S+)%s+(%S+)$")
		if not target_name or not role then
			return false, S("Usage: /sl_assign <player> <beacon_a|beacon_b|monster_master>")
		end

		local pl = game_mode.get_player_state(target_name)

		if role == "monster_master" then
			game_mode.set_monster_master(target_name)
			game_mode.broadcast(S("@1 has been assigned as Monster Master.", target_name))
			return true
		elseif role == "beacon_a" or role == "beacon_b" then
			pl.team = role
			pl.role = nil
			pl.eliminated = false

			local player = minetest.get_player_by_name(target_name)
			if player then
				game_mode.spawn_player(player)
			end

			game_mode.broadcast(S("@1 has been assigned to @2.", target_name, game_mode.get_team_label(role)))
			return true
		else
			return false, S("Unknown role/team: @1", role)
		end
	end,
})

minetest.register_chatcommand("sl_set_lobby", {
	description = S("Set lobby spawn to your current position (admin)"),
	privs = { sl_admin = true },
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then return false end
		local pos = player:get_pos()
		state.lobby_spawn = vector.round(pos)
		game_mode.save_spawns()
		return true, S("Lobby spawn set to @1", minetest.pos_to_string(state.lobby_spawn))
	end,
})

-- Match control commands
minetest.register_chatcommand("sl_match_start", {
	params = "[now]",
	description = S("Open the ready check, or launch immediately with 'now' (admin)."),
	privs = { sl_admin = true },
	func = function(name, param)
		if param == "now" then
			local ok, msg = game_mode.start_new_match(name)
			if ok == false and msg then
				return false, msg
			end
			return true
		end
		local ok, msg = game_mode.begin_ready_check(name)
		if ok == false and msg then
			return false, msg
		end
		return true
	end,
})

minetest.register_chatcommand("sl_ready", {
	description = S("Confirm insertion during a ready check."),
	func = function(name)
		local ok, msg = game_mode.mark_ready(name)
		if ok == false and msg then
			return false, msg
		end
		return true
	end,
})

minetest.register_chatcommand("sl_match_stop", {
	description = S("Force-stop the current match without a winner"),
	privs = { sl_admin = true },
	func = function(name)
		if not state.match_active then
			return false, S("No active match.")
		end

		game_mode.end_match(nil, S("Stopped by @1", name))
		return true, S("Match stopped.")
	end,
})

minetest.register_chatcommand("sl_autostart", {
	params = "<on|off|status>",
	description = S("Auto-start matches when the lobby has enough players (no ready prompts)."),
	privs = { sl_admin = true },
	func = function(name, param)
		local arg = (param or ""):match("^(%S+)") or "status"
		if arg == "on" then
			state.settings.auto_start = true
			game_mode.broadcast(S("Auto-start ENABLED: matches begin automatically."))
			return true
		elseif arg == "off" then
			state.settings.auto_start = false
			game_mode.broadcast(S("Auto-start disabled: use /sl_match_start."))
			return true
		end
		return true, S("Auto-start: @1 (delay @2 s)",
			state.settings.auto_start and "ON" or "OFF",
			tostring(state.settings.auto_start_delay or 8))
	end,
})

minetest.register_chatcommand("sl_match_status", {
	description = S("Show basic match status"),
	func = function(name)
		if not state.match_active then
			return true, S("No active match.")
		end

		return true, S("Match #@1 is running.", tostring(state.match_count))
	end,
})

minetest.register_chatcommand("sl_build_cage", {
	description = S("Materialize the cloud cage structure at the current ghost spawn (creative)."),
	func = function(name)
		if not minetest.settings:get_bool("creative_mode") then
			return false, S("Cage construction is available only in creative mode.")
		end
		if state.ghost_spawn and minetest.load_area then
			minetest.load_area(vector.round(state.ghost_spawn))
		end
		local placed = game_mode.build_cloud_cage()
		return true, S("Cloud cage update complete. @1 nodes materialized.", tostring(placed))
	end,
})

-- ================================================================
-- Map system commands: type selection, handmade-map listing,
-- manual (re)build and arena export to a handmade map.
-- ================================================================

local MAP_TYPE_HELP = "procedural | test | schematic [name] | seed <n> | list | build | save <name>"

minetest.register_chatcommand("sl_map", {
	params = MAP_TYPE_HELP,
	description = S("Show or configure the match map (type, handmade map, seed)"),
	func = function(name, param)
		local map = game_mode.map
		if not map then
			return false, S("Map system unavailable.")
		end
		local arg = (param or ""):match("^(%S*)")
		local rest = (param or ""):match("^%S+%s+(.-)$")
		local is_admin = minetest.check_player_privs(name, { sl_admin = true })

		local function admin_only()
			if is_admin then return true end
			return false, S("Map configuration requires the sl_admin privilege.")
		end

		if arg == "" or arg == "status" then
			local cur = map.current
			local lines = {}
			if cur then
				table.insert(lines, S("Current map: @1 (type @2, seed @3), mobs: @4",
					tostring(cur.name), tostring(cur.type), tostring(cur.seed),
					tostring(#(cur.mobs or {}))))
				table.insert(lines, S("Volume: @1 .. @2",
					minetest.pos_to_string(cur.minp), minetest.pos_to_string(cur.maxp)))
			else
				table.insert(lines, S("No map prepared yet — the next match builds one."))
			end
			table.insert(lines, S("Next match: type '@1', handmade map '@2'",
				tostring(map.runtime.type or minetest.settings:get("sl_map.type") or "procedural"),
				tostring(map.runtime.schematic or minetest.settings:get("sl_map.schematic") or "random")))
			return true, table.concat(lines, "\n")
		end

		if arg == "list" then
			local maps = map.list_schematic_maps()
			local names = {}
			for n in pairs(maps) do table.insert(names, n) end
			table.sort(names)
			if #names == 0 then
				return true, S("No handmade maps installed. Drop map.mts + map.conf into mods/game/sl_modebase/maps/<name>/ or <world>/maps/<name>/.")
			end
			return true, S("Handmade maps: @1", table.concat(names, ", "))
		end

		if arg == "procedural" or arg == "test" then
			local gate_ok, gate_err = admin_only()
			if not gate_ok then return false, gate_err end
			map.runtime.type = arg
			map.persist()
			return true, S("Next match uses the '@1' map type.", arg)
		end

		if arg == "schematic" then
			local gate_ok, gate_err = admin_only()
			if not gate_ok then return false, gate_err end
			if rest and rest ~= "" then
				local maps = map.list_schematic_maps()
				if rest ~= "random" and not maps[rest] then
					return false, S("Handmade map '@1' not found. Use /sl_map list.", rest)
				end
				map.runtime.schematic = rest
			end
			map.runtime.type = "schematic"
			map.persist()
			return true, S("Next match uses the handmade map '@1'.",
				tostring(map.runtime.schematic or "random"))
		end

		if arg == "seed" then
			local gate_ok, gate_err = admin_only()
			if not gate_ok then return false, gate_err end
			-- SECURITY: the parameter is client text and this one is
			-- PERSISTED -- map.persist() writes it to mod storage, so a bad
			-- value survives restart and drives mapgen for every later match.
			-- tonumber("1e999") is +inf and tonumber("nan") is NaN; both used
			-- to be stored as-is (verified: map.runtime.seed == inf). Same rule
			-- as the strand seed: a finite integer within +/- 2^31, or refuse.
			local seed = tonumber(rest or "")
			if seed == nil then
				return false, S("Usage: /sl_map seed <whole number> (0 unpins).")
			end
			if seed ~= seed or seed == math.huge or seed == -math.huge
				or seed ~= math.floor(seed) or math.abs(seed) > 2 ^ 31 then
				return false, S("Seed must be a whole number within +/- 2147483648.")
			end
			map.runtime.seed = seed ~= 0 and math.floor(seed) or nil
			map.persist()
			if map.runtime.seed then
				return true, S("Map seed pinned to @1 (same arena every match).", tostring(map.runtime.seed))
			end
			return true, S("Map seed unpinned: every match generates a fresh arena.")
		end

		if arg == "build" or arg == "rebuild" then
			local gate_ok, gate_err = admin_only()
			if not gate_ok then return false, gate_err end
			local ok, err = map.prepare()
			if ok then
				return true, S("Map '@1' materialized (seed @2).",
					tostring(map.current.name), tostring(map.current.seed))
			end
			return false, tostring(err)
		end

		if arg == "save" then
			if not minetest.settings:get_bool("creative_mode") then
				return false, S("Map export is available only in creative mode.")
			end
			local sname = (rest or ""):match("^(%S+)$")
			if not sname then
				return false, S("Usage: /sl_map save <name>")
			end
			local ok, res = map.save_current(sname)
			if ok then
				return true, S("Map exported to @1. Adjust its map.conf and select it with /sl_map schematic @2.", tostring(res), sname)
			end
			return false, res
		end

		return false, S("Usage: /sl_map @1", MAP_TYPE_HELP)
	end,
})

