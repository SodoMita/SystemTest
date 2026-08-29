local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Match lifecycle and win conditions
-- ================================================================

-- End match
function game_mode.end_match(winner, reason)
	if not state.match_active then
		return
	end

	state.match_active = false
	state.match_ended_at = minetest.get_us_time() / 1000000

	-- Clean reset: cancel any pending ready check and neutralize live sabotages.
	game_mode.cancel_ready_check()
	game_mode.clear_all_sabotage()
	game_mode.clear_all_possession()

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

	-- Result screen for all connected players (chat scoreboard + formspec).
	game_mode.send_results(winner, reason)

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

	-- CLEAN RESET: normalize per-player phases so the lobby holds no stale
	-- ghost / evil-ghost identities. Without this, a player who ended the
	-- match as a ghost would keep the communication seal in the lobby and
	-- could never run match-control commands again (soft-lock).
	for _, pl in pairs(state.players) do
		pl.phase = "alive"
		pl.eliminated = false
		pl.ghost_summoned_by = nil
		pl.ghost_summon_pos = nil
	end

	-- Tournament bookkeeping (v1.3.5): the tournament runs a fixed number
	-- of matches. Each finished match banks its points into the roster's
	-- season score; when the last planned match ends, the ranking form
	-- pops out and one clean reset follows (see end_tournament).
	if state.tournament then
		for name, pl in pairs(state.players) do
			if state.tournament_roster[name] then
				state.tournament_scores[name] =
					(state.tournament_scores[name] or 0) + (pl.points or 0)
			end
		end
		state.tournament_matches_left = math.max(0,
			(state.tournament_matches_left or 1) - 1)
		if state.tournament_matches_left <= 0 then
			local planned = state.tournament_planned or 0
			minetest.after(2.0, function()
				game_mode.end_tournament(
					S("all @1 matches played", tostring(planned)))
			end)
		else
			game_mode.broadcast(S("Tournament: @1 match(es) remaining.",
				tostring(state.tournament_matches_left)))
		end
	end
end

-- End the tournament (v1.3.5): ranking form first, then the one clean
-- reset — progression and achievements were on loan while it ran.
function game_mode.end_tournament(reason)
	if not state.tournament then return end
	local ranked = {}
	for name in pairs(state.tournament_roster) do
		table.insert(ranked, { name = name, pts = state.tournament_scores[name] or 0 })
	end
	table.sort(ranked, function(a, b)
		if a.pts ~= b.pts then return a.pts > b.pts end
		return a.name < b.name
	end)
	local rows = {}
	for i, entry in ipairs(ranked) do
		table.insert(rows, { tostring(i), entry.name, tostring(entry.pts) })
	end
	local champion = ranked[1] and ranked[1].name or S("nobody")
	game_mode.show_rank_formspec("sl_modebase:tournament_results",
		S("TOURNAMENT RESULTS"),
		S("Champion: @1 (@2)", champion, reason or ""),
		{ "#", S("Operator"), S("Points") }, rows)
	if ranked[1] then
		game_mode.broadcast(S("TOURNAMENT OVER — champion: @1 with @2 points",
			ranked[1].name, tostring(ranked[1].pts)))
	end
	-- The loan ends: progression, achievements and Monster Master grip
	-- return to per-match rules with one clean reset (v1.3.4 semantics).
	for _, player in ipairs(minetest.get_connected_players()) do
		if reset_player_progression then
			pcall(reset_player_progression, player)
		end
		if reset_match_achievements then
			pcall(reset_match_achievements, player)
		end
	end
	state.tournament = false
	state.tournament_planned = 0
	state.tournament_matches_left = 0
	state.tournament_scores = {}
	state.tournament_roster = {}
	for _, pl in pairs(state.players) do
		pl.tournament_spectator = nil
	end
end

-- Reset for new match
local function reset_players_for_new_match()
	for name, pl in pairs(state.players) do
		pl.eliminated = false
		pl.phase = "alive"
		pl.points = 0
		pl.ghost_summoned_by = nil
		pl.last_death_pos = nil

		local player = minetest.get_player_by_name(name)
		if player then
			-- Every match starts from zero: inventories clear
			-- unconditionally (the old creative-mode skip leaked whole
			-- arsenals from match to match in creative testing), and
			-- levels reset through the sl_gui hook when present.
			local inv = player:get_inventory()
			inv:set_list("main", {})
			if inv.set_list and inv:get_list("craft") then
				inv:set_list("craft", {})
			end
			if reset_player_progression and not state.tournament then
				-- Tournament mode (v1.3.4): levels and abilities ride
				-- across matches; only inventories reset.
				local ok, err = pcall(reset_player_progression, player)
				if not ok then
					minetest.log("error", "[game_mode] progression reset for "
						.. name .. ": " .. tostring(err))
				end
			end
		end
	end

	-- The Monster Master's kit was gifted at role assignment, BEFORE
	-- this reset ran — hand it back (it is role equipment, not loot).
	local mm_name = state.monster_master.player
	if mm_name then
		local mm = minetest.get_player_by_name(mm_name)
		if mm then
			local inv = mm:get_inventory()
			inv:add_item("main", game_mode.modname .. ":summon_monster")
			if game_mode.ESSENCE_ITEM then
				inv:add_item("main", game_mode.ESSENCE_ITEM .. " 10")
			end
		end
	end
end

-- Result screen: chat scoreboard plus a formspec summary shown to everyone.
-- Deliberately identity-neutral: it reports each player's own phase and public
-- match facts only, never hidden team or role information.
function game_mode.send_results(winner, reason)
	local winner_label
	if winner == "beacons" then
		winner_label = S("BEACON TEAMS")
	elseif winner and state.teams[winner] then
		winner_label = game_mode.get_team_label(winner)
	else
		winner_label = S("DRAW")
	end

	-- Chat scoreboard (persists in the console log)
	game_mode.broadcast(S("=== MATCH #@1 RESULTS: @2 (@3) ===",
		tostring(state.match_count or 0), winner_label, reason or ""))
	local score_rows = {}
	for name, pl in pairs(state.players) do
		if minetest.get_player_by_name(name) then
			local row = string.format("%s | %s | pts %d",
				name, tostring(pl.phase), pl.points or 0)
			table.insert(score_rows, row)
			game_mode.broadcast(row)
		end
	end

	-- Formspec result screen
	local fs = {
		"formspec_version[4]",
		"size[8,6.5]",
		"bgcolor[#0a0a12ee;true]",
		"label[0.5,0.4;" .. minetest.formspec_escape(S("MATCH RESULTS")) .. "]",
		"label[0.5,0.9;" .. minetest.formspec_escape(
			string.format("%s — %s", winner_label, reason or "")) .. "]",
		"tablecolumns[text;text;text]",
	}
	local rows = {}
	for name, pl in pairs(state.players) do
		if minetest.get_player_by_name(name) then
			table.insert(rows, { minetest.formspec_escape(name),
				tostring(pl.phase), tostring(pl.points or 0) })
		end
	end
	game_mode.show_rank_formspec("sl_modebase:results", S("MATCH RESULTS"),
		string.format("%s — %s", winner_label, reason or ""),
		{ S("Player"), S("Phase"), S("Points") }, rows)
end

-- Shared ranking form (match results and the tournament leaderboard use
-- the same layout). Rows arrive as arrays of cell strings; a formspec
-- table[] carries the whole item list as ONE comma-separated element —
-- ";"-joining rows produced "Invalid table element" on live servers, so
-- never go back to that.
function game_mode.show_rank_formspec(formname, title, subtitle, headers, rows)
	local fs = {
		"formspec_version[4]",
		"size[8,6.5]",
		"bgcolor[#0a0a12ee;true]",
		"label[0.5,0.4;" .. minetest.formspec_escape(title) .. "]",
		"label[0.5,0.9;" .. minetest.formspec_escape(subtitle) .. "]",
		-- Column types are text/image/color/indent/tree and nothing else —
		-- alignment is an option ("text,align=right"), never a type. An
		-- unknown type feeds the client parser garbage: v1.3.5 shipped
		-- 'right' here and the client segfaulted on the form.
		"tablecolumns[text;text;text]",
	}
	local items = { table.concat(headers, ",") }
	for _, row in ipairs(rows) do
		table.insert(items, table.concat(row, ","))
	end
	table.insert(fs, "table[0.4,1.5;7.2,4.2;results;"
		.. table.concat(items, ",") .. ";1]")
	table.insert(fs, "button_exit[3,5.9;2,0.7;close;Close]")
	local fs_str = table.concat(fs, "")
	for _, player in ipairs(minetest.get_connected_players()) do
		minetest.show_formspec(player:get_player_name(), formname, fs_str)
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
	if #connected < 2 then
		return false, S("Need at least 2 players to start a match.")
	end

	-- Auto-assign the Monster Master only when two beacon teams can still exist.
	-- A two-player test match remains a direct team-vs-team simulation.
	local auto_assign_mm = state.settings.mm_auto_assign and #connected >= 3

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

	if not mm_exists and auto_assign_mm then
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
			if (not biggest_team or pl.team == biggest_team)
				and not pl.tournament_spectator then
				table.insert(candidates, name)
			end
		end

		if #candidates > 0 then
			local chosen_name = candidates[math.random(1, #candidates)]
			game_mode.set_monster_master(chosen_name)
			game_mode.broadcast(S("@1 has been chosen as the Monster Master!", chosen_name))
		end
	end

	-- Ensure the active simulation has two actual beacon teams.
	for _, name in ipairs(connected) do
		local pl = game_mode.get_player_state(name)
		if not pl.team and pl.role ~= "monster_master"
			and not pl.tournament_spectator then
			game_mode.assign_beacon_team(name)
		end
	end
	if game_mode.count_team_players("beacon_a") == 0 or game_mode.count_team_players("beacon_b") == 0 then
		return false, S("Need players on both beacon teams before launch.")
	end

	-- Insertion: the ready check is consumed and any stale sabotage is purged
	-- so no previous-match corruption leaks into the new simulation.
	game_mode.cancel_ready_check()
	game_mode.clear_all_sabotage()
	game_mode.clear_all_possession()

	-- Beacons start every match at full integrity. Without this, damage
	-- taken in a previous match persists (stale-state violation of the
	-- "same match started again without stale state" scenario).
	for _, team_id in ipairs(state.teams_order) do
		local tdef = state.teams[team_id]
		tdef.hp = state.settings.beacon_hp or 100
		if tdef.spawn then
			local bpos = { x = tdef.spawn.x, y = tdef.spawn.y - 1, z = tdef.spawn.z }
			if minetest.load_area then minetest.load_area(bpos) end
			local meta = minetest.get_meta(bpos)
			meta:set_int("hp", tdef.hp)
			meta:set_string("infotext", S("@1 (HP: @2)", tdef.label, tostring(tdef.hp)))
		end
	end

	state.match_count = (state.match_count or 0) + 1
	state.match_active = true
	state.match_started_at = minetest.get_us_time() / 1000000

	reset_players_for_new_match()

	for _, name in ipairs(connected) do
		local player = minetest.get_player_by_name(name)
		if player then
			local pl = game_mode.get_player_state(name)
			if not pl.team and pl.role ~= "monster_master"
			and not pl.tournament_spectator then
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

-- ================================================================
-- Ready check -> countdown -> insertion sequencing
-- ================================================================

function game_mode.cancel_ready_check(reason)
	state.ready_check.active = false
	state.ready_check.ready = {}
	state.ready_check.countdown_left = 0
	state.ready_check.last_announced = -1
	state.ready_check.initiator = nil
	if reason then
		game_mode.broadcast(reason)
	end
end

function game_mode.begin_ready_check(initiator)
	if state.match_active then
		return false, S("Match is already running.")
	end
	if state.ready_check.active then
		return false, S("A ready check is already in progress.")
	end
	-- Validate the roster before asking anyone to commit.
	local connected = game_mode.get_connected_player_names()
	if #connected < 2 then
		return false, S("Need at least 2 players to start a match.")
	end

	state.ready_check.active = true
	state.ready_check.initiator = initiator
	state.ready_check.ready = {}
	state.ready_check.started_at = game_mode.now()
	state.ready_check.countdown_left = 0
	state.ready_check.last_announced = -1

	game_mode.broadcast(S("Ready check opened by @1. Type /sl_ready to confirm insertion.",
		initiator or "the system"))
	return true
end

function game_mode.mark_ready(name, silent)
	if not state.ready_check.active then
		return false, S("No ready check is active.")
	end
	if state.ready_check.countdown_left > 0 then
		return false, S("Insertion countdown is already running.")
	end
	state.ready_check.ready[name] = true

	local connected = game_mode.get_connected_player_names()
	local ready_count = 0
	for _, pname in ipairs(connected) do
		if state.ready_check.ready[pname] then
			ready_count = ready_count + 1
		end
	end
	if not silent then
		game_mode.broadcast(S("@1 is ready. (@2/@3)",
			name, tostring(ready_count), tostring(#connected)))
	end

	if ready_count >= #connected then
		state.ready_check.countdown_left = state.settings.countdown or 5
		game_mode.broadcast(S("Roster confirmed. Insertion in @1...",
			tostring(math.ceil(state.ready_check.countdown_left))))
	end
	return true
end

local function ready_check_step(dtime)
	local rc = state.ready_check
	if not rc.active then return end
	if state.match_active then
		game_mode.cancel_ready_check()
		return
	end

	if rc.countdown_left > 0 then
		rc.countdown_left = rc.countdown_left - dtime
		local secs = math.ceil(rc.countdown_left)
		if secs ~= rc.last_announced then
			rc.last_announced = secs
			if secs > 0 then
				game_mode.broadcast(tostring(secs) .. "...")
			end
		end
		if rc.countdown_left <= 0 then
			local initiator = rc.initiator
			game_mode.cancel_ready_check()
			local ok, err = game_mode.start_new_match(initiator)
			if not ok and err then
				game_mode.broadcast(err)
			end
		end
		return
	end

	-- Waiting for confirmations; expire if the roster never completes.
	if game_mode.now() - rc.started_at > (state.settings.ready_timeout or 60) then
		game_mode.cancel_ready_check(S("Ready check expired. Not enough players confirmed."))
	end
end

-- Match timer: bounded matches end in a draw when the clock runs out.
local function match_timer_step()
	if not state.match_active then return end
	local duration = state.settings.match_duration or 0
	if duration <= 0 then return end
	if game_mode.now() - state.match_started_at >= duration then
		game_mode.end_match(nil, S("Time expired"))
	end
end

-- ================================================================
-- Auto-start (sl_auto_start / /sl_autostart): with enough players in
-- the lobby, a match begins on its own after an intermission. It
-- reuses the ready-check countdown so players get the same warnings,
-- but readiness is filled in silently — nobody types /sl_ready.
-- Admin flows (/sl_match_start, /sl_match_start now) keep working and
-- take precedence while a ready check or match is running.
-- ================================================================
local auto_start_accum = 0
local function auto_start_step(dtime)
	if not state.settings.auto_start then
		auto_start_accum = 0
		return
	end
	if state.match_active then
		auto_start_accum = 0
		return
	end
	if state.ready_check.active then
		-- Fill readiness silently so the countdown proceeds.
		for _, pname in ipairs(game_mode.get_connected_player_names()) do
			if not state.ready_check.ready[pname] then
				game_mode.mark_ready(pname, true)
			end
		end
		return
	end
	if #game_mode.get_connected_player_names() < 2 then
		auto_start_accum = 0
		return
	end
	auto_start_accum = auto_start_accum + dtime
	if auto_start_accum >= (state.settings.auto_start_delay or 8) then
		auto_start_accum = 0
		local ok = game_mode.begin_ready_check("auto-start")
		if ok then
			game_mode.broadcast(S("Auto-start: insertion follows the countdown."))
			for _, pname in ipairs(game_mode.get_connected_player_names()) do
				game_mode.mark_ready(pname, true)
			end
		end
	end
end

minetest.register_globalstep(function(dtime)
	ready_check_step(dtime)
	match_timer_step()
	auto_start_step(dtime)
	if game_mode.sabotage_step then
		game_mode.sabotage_step(dtime)
	end
end)

-- Protection override to prevent ghosts and lobby players from digging/placing
local old_is_protected = minetest.is_protected
function minetest.is_protected(pos, name)
	local pl = game_mode.get_player_state(name)
	local is_creative = minetest.settings:get_bool("creative_mode") or minetest.check_player_privs(name, {all=true})
	
	if is_creative then
		return false -- Creative/Admins can always build
	end
	
	if pl and (pl.phase == "ghost" or pl.phase == "evil_ghost" or not state.match_active) then
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
		if hpl and (hpl.phase == "ghost" or hpl.phase == "evil_ghost") then
			return true -- Ghosts cannot directly attack players
		end
	end
end)

-- Restrict ghost chat
minetest.register_on_chat_message(function(name, message)
	local pl = game_mode.get_player_state(name)
	if pl and (pl.phase == "ghost" or pl.phase == "evil_ghost") then
		minetest.chat_send_player(name, minetest.colorize("#ff5555", S("Ghost communications are sealed.")))
		return true -- Block message
	end
end)

-- Death handling
minetest.register_on_dieplayer(function(player, reason)
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)

	-- Drop items on death. When the corpse system is present
	-- (WEAPONS_SPEC §7.1), the fountain is redirected into the body
	-- instead of the floor: the inventory lands in the corpse, a
	-- third of the loose ammo is smashed, and a residue node stays.
	local pos = player:get_pos()
	local inv = player:get_inventory()
	if sl_weapons and sl_weapons.capture_death_items then
		sl_weapons.capture_death_items(player, pos, inv)
	else
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		if not stack:is_empty() then
			-- Don't drop MM summoning tool or Reincarnate item
			if stack:get_name() ~= game_mode.modname .. ":summon_monster" and
			   stack:get_name() ~= game_mode.modname .. ":reincarnate" then
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

	-- Preserve the death location for an eventual evil-ghost insertion.
	pl.last_death_pos = vector.round(pos)

	-- Phase-based transition. Single-life design: the first death sends a
	-- player straight to the cloud cage (owner directive 2026-08: multiple
	-- lives are against the game design).
	if pl.phase == "alive" then
		pl.phase = "ghost"
		player:set_armor_groups({immortal = 1})
		game_mode.broadcast(S("@1 has fallen and returned as a Ghost!", name))
	elseif pl.phase == "ghost" then
		-- Contained ghosts are immortal and should not be damage-transitioned.
		player:set_armor_groups({immortal = 1})
	elseif pl.phase == "evil_ghost" then
		pl.eliminated = true
		game_mode.broadcast(S("A corrupted ghost has been purged from the simulation."))
	elseif pl.phase == "monster" then
		-- Legacy compatibility for old saved state.
		pl.phase = "master_monster"
		player:set_armor_groups({fleshy = 100})
		game_mode.broadcast(S("@1 has been bound to the Monster Master's will!", name))
	elseif pl.phase == "master_monster" then
		pl.eliminated = true
		game_mode.broadcast(S("@1 is fully eliminated from the simulation!", name))
	end

	check_team_elimination()
end)
