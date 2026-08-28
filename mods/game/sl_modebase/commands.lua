local S = game_mode.S
local state = game_mode.state

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
		-- Gift the summoning tool
		local inv = player:get_inventory()
		if not inv:contains_item("main", game_mode.modname .. ":summon_monster") then
			inv:add_item("main", game_mode.modname .. ":summon_monster")
		end
		-- Gift a starter stack of Monster Essence (spawner fuel)
		if game_mode.ESSENCE_ITEM and not inv:contains_item("main", game_mode.ESSENCE_ITEM) then
			inv:add_item("main", game_mode.ESSENCE_ITEM .. " 10")
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
		if pl.eliminated then
			table.insert(parts, S("(Eliminated)"))
		end

		minetest.chat_send_player(name, "[System Looting] " .. table.concat(parts, " | "))
		if state.match_active then
			minetest.chat_send_player(name, S("A match is currently running (Match #@1).", tostring(state.match_count)))
		else
			minetest.chat_send_player(name, S("No active match."))
		end
	end,
})

minetest.register_chatcommand("sl_be_monster_master", {
	description = S("Become the monster master (if none exists yet)"),
	func = function(name)
		if state.monster_master.player and state.monster_master.player ~= name then
			return false, S("Monster master is already @1", state.monster_master.player)
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

minetest.register_chatcommand("sl_mm_spawn", {
	params = "[count]",
	description = S("Monster master: spawn basic monsters near you"),
	func = function(name, param)
		if not game_mode.is_monster_master(name) then
			return false, S("You are not the monster master.")
		end

		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("Player not found.")
		end

		local count = tonumber(param) or 1
		count = math.max(1, math.min(count, 5))

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
			local seed = tonumber(rest or "") or 0
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

