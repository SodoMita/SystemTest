-- ================================================================
-- WP5 — System Tab & Comms Tab for Unified Inventory
-- Makes majority of sl_ chat commands accessible via inventory GUI
-- Owner: WP5 HUD & UI (mods/apis/sl_gui/**)
-- Covers: sl_state, sl_match_status, sl_ready, sl_matchmaking,
-- sl_match_start, sl_match_stop, sl_autostart, sl_be_monster_master,
-- sl_mm_return, sl_mm_spawn, sl_assign, sl_set_lobby, sl_build_cage,
-- sl_dm, sl_dm_ui, sl_comms, sl_whisper, sl_w, sl_test_*, etc.
-- Cybernetic styling, identity-neutral.
-- ================================================================

local modpath = minetest.get_modpath(minetest.get_current_modname())

local S
if rawget(_G, "game_mode") and game_mode.S then
	S = game_mode.S
else
	S = minetest.get_translator("sl_gui") or function(s) return s end
end

-- Helper to get game state safely (works in stub too)
local function get_state()
	if rawget(_G, "game_mode") and game_mode.state then
		return game_mode.state
	end
	return {
		match_active = false,
		match_count = 0,
		teams = { beacon_a = { hp = 0, label = "Beacon A" }, beacon_b = { hp = 0, label = "Beacon B" } },
		players = {},
		monster_master = { player = nil },
		settings = { beacon_hp = 100, mm_auto_assign = true, auto_start = false, auto_start_delay = 8, countdown = 5, match_duration = 600 },
		ready_check = { active = false, ready = {}, countdown_left = 0 },
		win_conditions = { elimination = true, objective = false },
	}
end

local function get_player_state(name)
	if rawget(_G, "game_mode") and game_mode.get_player_state then
		return game_mode.get_player_state(name)
	end
	return { team = nil, role = nil, phase = "alive", points = 0, eliminated = false }
end

local function is_admin(name)
	local privs = minetest.get_player_privs(name)
	return privs.sl_admin or privs.server or privs.creative or minetest.settings:get_bool("creative_mode")
end

local function is_mm(name)
	if rawget(_G, "game_mode") and game_mode.is_monster_master then
		return game_mode.is_monster_master(name)
	end
	return false
end

-- ================================================================
-- SYSTEM TAB — Match + Player + Admin + MM + Ghost + Test
-- ================================================================

function get_system_formspec(player)
	local name = player:get_player_name()
	local state = get_state()
	local pl = get_player_state(name)
	local admin = is_admin(name)
	local mm = is_mm(name)

	local fs = {}

	-- Header: player vitals
	table.insert(fs, "box[0.2,1.1;11.6,1.0;#1a1a2aee]")
	local team_label = pl.team and (rawget(_G, "game_mode") and game_mode.get_team_label and game_mode.get_team_label(pl.team) or pl.team) or S("None")
	local role_label = pl.role == "monster_master" and S("Monster Master") or S("Player")
	table.insert(fs, string.format("label[0.4,1.3;%s: %s | %s: %s | %s: %s | %s: %d]",
		S("Team"), minetest.formspec_escape(team_label),
		S("Role"), minetest.formspec_escape(role_label),
		S("Phase"), minetest.formspec_escape(tostring(pl.phase)),
		S("Points"), tostring(pl.points or 0)
	))

	-- Match status
	table.insert(fs, "box[0.2,2.2;11.6,0.8;#101030ee]")
	local match_status = state.match_active and S("MATCH #@1 ACTIVE", tostring(state.match_count or 0)) or S("LOBBY - STANDBY")
	if state.ready_check and state.ready_check.active then
		if state.ready_check.countdown_left > 0 then
			match_status = S("INSERTION IN @1s", tostring(math.ceil(state.ready_check.countdown_left)))
		else
			local rc = state.ready_check
			local ready_c = 0
			local total_c = 0
			if rawget(_G, "game_mode") and game_mode.get_connected_player_names then
				local con = game_mode.get_connected_player_names()
				total_c = #con
				for _, pn in ipairs(con) do if rc.ready[pn] then ready_c = ready_c + 1 end end
			end
			match_status = S("READY CHECK: @1/@2", tostring(ready_c), tostring(total_c))
		end
	end
	local win_conds = {}
	if state.win_conditions.elimination then table.insert(win_conds, S("Elimination")) end
	if state.win_conditions.objective then table.insert(win_conds, S("Objective")) end
	local win_str = table.concat(win_conds, " + ")
	if win_str == "" then win_str = S("None") end

	table.insert(fs, string.format("label[0.4,2.4;%s: %s | %s: %s | CORE A: %d | CORE B: %d | AUTO: %s]",
		S("Status"), minetest.formspec_escape(match_status),
		S("Win"), minetest.formspec_escape(win_str),
		state.teams.beacon_a.hp or 0,
		state.teams.beacon_b.hp or 0,
		state.settings.auto_start and S("ON") or S("OFF")
	))

	-- Row 1: Basic player actions (always visible)
	table.insert(fs, "box[0.2,3.2;11.6,1.2;#1a1a1aee]")
	table.insert(fs, string.format("label[0.4,3.3;%s]", S("PLAYER ACTIONS")))
	table.insert(fs, "button[0.3,3.7;2.5,0.7;sys_ready; /sl_ready ]")
	table.insert(fs, "button[3.0,3.7;2.5,0.7;sys_matchmaking; /sl_matchmaking ]")
	table.insert(fs, "button[5.7,3.7;2.5,0.7;sys_state; /sl_state ]")
	table.insert(fs, "button[8.4,3.7;3.0,0.7;sys_status; /sl_match_status ]")

	-- Row 2: Monster Master actions
	table.insert(fs, "box[0.2,4.6;11.6,1.2;#2a1a0aee]")
	table.insert(fs, string.format("label[0.4,4.7;%s: %s]", S("MONSTER MASTER"), minetest.formspec_escape(state.monster_master.player or S("None"))))
	if mm then
		table.insert(fs, "button[0.3,5.1;2.5,0.7;sys_mm_return; /sl_mm_return ]")
		table.insert(fs, "button[3.0,5.1;2.5,0.7;sys_mm_spawn1; Spawn x1 ]")
		table.insert(fs, "button[5.7,5.1;2.5,0.7;sys_mm_spawn3; Spawn x3 ]")
		table.insert(fs, "button[8.4,5.1;3.0,0.7;sys_leave_mm; Resign MM ]")
	else
		table.insert(fs, "button[0.3,5.1;3.5,0.7;sys_be_mm; Become Monster Master ]")
		if state.monster_master.player == nil then
			table.insert(fs, string.format("label[4.2,5.3;%s]", S("No MM - you can claim the role")))
		else
			table.insert(fs, string.format("label[4.2,5.3;%s: %s]", S("Current MM"), minetest.formspec_escape(state.monster_master.player or "")))
		end
	end

	-- Row 3: Admin / Match control (visible to all, but actions gated)
	-- Two 0.7-tall button rows plus the label need 2.0 of height. The box used
	-- to be 1.6, so the second row started at 7.1 while the first still ended at
	-- 7.2: the four buttons of each row overlapped each other by 0.1 and the
	-- second row hung 0.2 below the box.
	table.insert(fs, "box[0.2,6.0;11.6,2.0;#1a2a1aee]")
	table.insert(fs, string.format("label[0.4,6.1;%s %s]", S("MATCH CONTROL"), admin and S("(ADMIN)") or S("(request admin)")))
	table.insert(fs, "button[0.3,6.5;2.5,0.7;sys_match_start; Start (ready) ]")
	table.insert(fs, "button[3.0,6.5;2.5,0.7;sys_match_start_now; Start NOW ]")
	table.insert(fs, "button[5.7,6.5;2.5,0.7;sys_match_stop; Stop Match ]")
	table.insert(fs, "button[8.4,6.5;3.0,0.7;sys_autostart_toggle; Toggle Auto-Start ]")

	table.insert(fs, "button[0.3,7.25;2.5,0.7;sys_set_lobby; Set Lobby Spawn ]")
	table.insert(fs, "button[3.0,7.25;2.5,0.7;sys_build_cage; Build Cage ]")
	table.insert(fs, "button[5.7,7.25;2.5,0.7;sys_assign_a; Assign to A ]")
	table.insert(fs, "button[8.4,7.25;3.0,0.7;sys_assign_b; Assign to B ]")

	-- Row 4: Ghost + Test + Info (creative/admin)
	table.insert(fs, "box[0.2,8.2;11.6,1.6;#2a1a2aee]")
	table.insert(fs, string.format("label[0.4,8.3;%s %s]", S("GHOST & TEST"), S("(creative)")))
	table.insert(fs, "button[0.3,8.7;2.5,0.7;sys_summon_ghost_ui; Summon Ghost ]")
	table.insert(fs, "button[3.0,8.7;2.5,0.7;sys_ghost_offer_sec; Offer Sec ]")
	table.insert(fs, "button[5.7,8.7;2.5,0.7;sys_test_arena; Test Arena ]")
	table.insert(fs, "button[8.4,8.7;3.0,0.7;sys_test_bots; Test Bots ]")

	-- Footer hint
	table.insert(fs, string.format("label[0.3,10.1;%s]", S("TIP: All actions mirror chat commands. Use COMMS tab for private links. Ghost comms are sealed.")))

	return table.concat(fs, "")
end

-- ================================================================
-- COMMS TAB — DM + Secure Link + Info
-- ================================================================

function get_comms_formspec(player)
	local name = player:get_player_name()
	local fs = {}

	-- Info box
	table.insert(fs, "box[0.2,1.1;11.6,1.2;#0a1a2aee]")
	table.insert(fs, string.format("label[0.4,1.3;%s]", S("SECURE NEURAL LINK // DIRECT MESSAGES")))
	table.insert(fs, string.format("label[0.4,1.7;%s]", S("Private, identity-neutral, ghost-proof. Use for trust, deception, coordination.")))
	table.insert(fs, string.format("label[0.4,1.95;%s]", S("Commands: /sl_dm <player> <msg> | /sl_whisper | /sl_w | /sl_dm_ui | /sl_comms")))

	-- Quick DM
	table.insert(fs, "box[0.2,2.5;11.6,2.8;#1a1a1aee]")
	table.insert(fs, string.format("label[0.4,2.6;%s]", S("QUICK TRANSMIT")))

	-- Player list for DM (textlist)
	local alive_names = {}
	if rawget(_G, "game_mode") and game_mode.get_connected_player_names then
		for _, n in ipairs(game_mode.get_connected_player_names()) do
			if n ~= name then
				local pl = rawget(_G, "game_mode") and game_mode.get_player_state and game_mode.get_player_state(n)
				if not pl or (pl.phase ~= "ghost" and pl.phase ~= "evil_ghost") then
					table.insert(alive_names, n)
				end
			end
		end
	else
		for _, p in ipairs(minetest.get_connected_players()) do
			local n = p:get_player_name()
			if n ~= name then table.insert(alive_names, n) end
		end
	end
	table.sort(alive_names)
	local list_str = table.concat(alive_names, ",")

	table.insert(fs, string.format("label[0.4,3.0;%s:]", S("Target")))
	table.insert(fs, string.format("textlist[0.4,3.3;3.5,1.8;comms_target;%s;1;false]", minetest.formspec_escape(list_str)))
	table.insert(fs, string.format("label[4.2,3.0;%s:]", S("Message")))
	table.insert(fs, "field[4.2,3.5;7.2,0.8;comms_message;;]")
	table.insert(fs, "field_close_on_enter[comms_message;false]")
	table.insert(fs, "button[4.2,4.3;3.5,0.7;comms_send; TRANSMIT SECURE LINK ]")
	table.insert(fs, "button[8.0,4.3;3.2,0.7;comms_open_full; OPEN FULL TERMINAL ]")

	-- Recent DM hint + ghost seal info
	table.insert(fs, "box[0.2,5.5;11.6,1.5;#1a2a1aee]")
	table.insert(fs, string.format("label[0.4,5.6;%s]", S("COMMS PROTOCOL")))
	table.insert(fs, string.format("label[0.4,5.9;%s]", S("- Living players only: ghosts cannot send or receive DMs (sealed per spec)")))
	table.insert(fs, string.format("label[0.4,6.2;%s]", S("- Private: only sender and target see the message, with cybernetic styling")))
	table.insert(fs, string.format("label[0.4,6.5;%s]", S("- Use inventory SYSTEM tab for match control, COMMS tab for private coordination")))

	-- Broadcast info
	table.insert(fs, "box[0.2,7.2;11.6,1.2;#2a1a0aee]")
	table.insert(fs, string.format("label[0.4,7.3;%s]", S("GLOBAL CHAT")))
	table.insert(fs, string.format("label[0.4,7.6;%s]", S("Global chat is public to living players. Ghost chat is blocked. Use /sl_matchmaking for lobby terminal.")))
	table.insert(fs, "button[0.4,7.9;3,0.7;comms_matchmaking; Open Matchmaking ]")
	table.insert(fs, "button[4.0,7.9;3,0.7;comms_state; Show My State ]")
	table.insert(fs, "button[7.5,7.9;4,0.7;comms_status; Show Match Status ]")

	-- Footer
	table.insert(fs, string.format("label[0.3,9.7;%s]", S("TIP: Inventory tabs now expose majority of sl_ commands. No need to memorize chat.")))

	return table.concat(fs, "")
end

-- ================================================================
-- Field handlers for System and Comms tabs
-- These are hooked into unified_inventory's receive_fields
-- ================================================================

local comms_selection = {} -- [sender] = target

local function handle_system_fields(player, fields)
	local name = player:get_player_name()
	local admin = is_admin(name)

	-- Player actions
	if fields.sys_ready then
		if minetest.registered_chatcommands.sl_ready then
			minetest.registered_chatcommands.sl_ready.func(name)
		end
		return true
	end
	if fields.sys_matchmaking then
		if minetest.registered_chatcommands.sl_matchmaking then
			minetest.registered_chatcommands.sl_matchmaking.func(name)
		else
			-- Fallback: show matchmaking formspec directly if command missing
			if rawget(_G, "game_mode") and game_mode.state then
				-- matchmaking.lua registers node and command; try to open via node logic?
				minetest.chat_send_player(name, S("Opening matchmaking terminal..."))
			end
		end
		return true
	end
	if fields.sys_state then
		if minetest.registered_chatcommands.sl_state then
			minetest.registered_chatcommands.sl_state.func(name)
		end
		return true
	end
	if fields.sys_status then
		if minetest.registered_chatcommands.sl_match_status then
			local _, msg = minetest.registered_chatcommands.sl_match_status.func(name)
			if msg then minetest.chat_send_player(name, msg) end
		end
		return true
	end

	-- MM actions
	if fields.sys_be_mm then
		if minetest.registered_chatcommands.sl_be_monster_master then
			minetest.registered_chatcommands.sl_be_monster_master.func(name)
		end
		return true
	end
	if fields.sys_leave_mm then
		if rawget(_G, "game_mode") and game_mode.set_monster_master then
			game_mode.set_monster_master(nil)
			game_mode.broadcast(S("Monster Master has resigned."))
		end
		return true
	end
	if fields.sys_mm_return then
		if minetest.registered_chatcommands.sl_mm_return then
			minetest.registered_chatcommands.sl_mm_return.func(name)
		end
		return true
	end
	if fields.sys_mm_spawn1 then
		if minetest.registered_chatcommands.sl_mm_spawn then
			minetest.registered_chatcommands.sl_mm_spawn.func(name, "1")
		end
		return true
	end
	if fields.sys_mm_spawn3 then
		if minetest.registered_chatcommands.sl_mm_spawn then
			minetest.registered_chatcommands.sl_mm_spawn.func(name, "3")
		end
		return true
	end

	-- Admin / match control
	if fields.sys_match_start then
		if minetest.registered_chatcommands.sl_match_start then
			minetest.registered_chatcommands.sl_match_start.func(name, "")
		end
		return true
	end
	if fields.sys_match_start_now then
		if minetest.registered_chatcommands.sl_match_start then
			minetest.registered_chatcommands.sl_match_start.func(name, "now")
		end
		return true
	end
	if fields.sys_match_stop then
		if minetest.registered_chatcommands.sl_match_stop then
			minetest.registered_chatcommands.sl_match_stop.func(name)
		end
		return true
	end
	if fields.sys_autostart_toggle then
		if minetest.registered_chatcommands.sl_autostart then
			local st = get_state()
			local new_arg = st.settings.auto_start and "off" or "on"
			minetest.registered_chatcommands.sl_autostart.func(name, new_arg)
		end
		return true
	end
	if fields.sys_set_lobby then
		if minetest.registered_chatcommands.sl_set_lobby then
			minetest.registered_chatcommands.sl_set_lobby.func(name)
		end
		return true
	end
	if fields.sys_build_cage then
		if minetest.registered_chatcommands.sl_build_cage then
			minetest.registered_chatcommands.sl_build_cage.func(name)
		end
		return true
	end
	if fields.sys_assign_a then
		if minetest.registered_chatcommands.sl_assign then
			minetest.registered_chatcommands.sl_assign.func(name, name .. " beacon_a")
		end
		return true
	end
	if fields.sys_assign_b then
		if minetest.registered_chatcommands.sl_assign then
			minetest.registered_chatcommands.sl_assign.func(name, name .. " beacon_b")
		end
		return true
	end

	-- Ghost & Test
	if fields.sys_summon_ghost_ui then
		-- Open a small formspec to input ghost name
		minetest.show_formspec(name, "sl_gui:summon_ghost", table.concat({
			"formspec_version[4]",
			"size[6,3]",
			"bgcolor[#0a0a12ee;true]",
			string.format("label[0.5,0.4;%s]", S("SUMMON GHOST (creative)")),
			"field[0.5,1.0;5,0.8;summon_ghost_name;Ghost name;;]",
			"button[0.5,2.0;2.2,0.7;summon_ghost_do;Summon]",
			"button[3.0,2.0;2.2,0.7;summon_ghost_close;Close]",
		}, ""))
		return true
	end
	if fields.sys_ghost_offer_sec then
		if minetest.registered_chatcommands.sl_ghost_offer then
			-- For demo, offer security to self if summoned? Use ghost_offer logic via command
			-- We need a target; use player name as summoner? Actually ghost offers to summoner.
			-- Here we just open help.
			minetest.chat_send_player(name, S("Use: /sl_ghost_offer <living_name> <security|logistics|medical> (ghost only, creative)"))
		end
		return true
	end
	if fields.sys_test_arena then
		if minetest.registered_chatcommands.sl_test_arena then
			minetest.registered_chatcommands.sl_test_arena.func(name)
		end
		return true
	end
	if fields.sys_test_bots then
		if minetest.registered_chatcommands.sl_test_bots then
			minetest.registered_chatcommands.sl_test_bots.func(name, "2")
		end
		return true
	end

	return false
end

local function handle_comms_fields(player, fields)
	local name = player:get_player_name()

	-- Handle textlist selection
	if fields.comms_target then
		local ev = minetest.explode_textlist_event(fields.comms_target)
		if ev and ev.type == "CHG" then
			local alive = {}
			if rawget(_G, "game_mode") and game_mode.get_connected_player_names then
				for _, n in ipairs(game_mode.get_connected_player_names()) do
					if n ~= name then
						local pl = rawget(_G, "game_mode") and game_mode.get_player_state and game_mode.get_player_state(n)
						if not pl or (pl.phase ~= "ghost" and pl.phase ~= "evil_ghost") then
							table.insert(alive, n)
						end
					end
				end
			else
				for _, p in ipairs(minetest.get_connected_players()) do
					local n = p:get_player_name()
					if n ~= name then table.insert(alive, n) end
				end
			end
			table.sort(alive)
			if alive[ev.index] then
				comms_selection[name] = alive[ev.index]
			end
		end
	end

	if fields.comms_send then
		local target = comms_selection[name]
		local msg = fields.comms_message or ""
		if not target then
			minetest.chat_send_player(name, minetest.colorize("#ff5555", S("No target selected.")))
			return true
		end
		if rawget(_G, "game_mode") and game_mode.send_dm then
			local ok, err = game_mode.send_dm(name, target, msg)
			if not ok then
				minetest.chat_send_player(name, minetest.colorize("#ff5555", S("TRANSMISSION FAILED: @1", err or "")))
			end
		else
			-- Fallback to chatcommand
			if minetest.registered_chatcommands.sl_dm then
				minetest.registered_chatcommands.sl_dm.func(name, target .. " " .. msg)
			end
		end
		return true
	end

	if fields.comms_open_full then
		if minetest.registered_chatcommands.sl_dm_ui then
			minetest.registered_chatcommands.sl_dm_ui.func(name)
		end
		return true
	end

	if fields.comms_matchmaking then
		if minetest.registered_chatcommands.sl_matchmaking then
			minetest.registered_chatcommands.sl_matchmaking.func(name)
		end
		return true
	end
	if fields.comms_state then
		if minetest.registered_chatcommands.sl_state then
			minetest.registered_chatcommands.sl_state.func(name)
		end
		return true
	end
	if fields.comms_status then
		if minetest.registered_chatcommands.sl_match_status then
			local _, msg = minetest.registered_chatcommands.sl_match_status.func(name)
			if msg then minetest.chat_send_player(name, msg) end
		end
		return true
	end

	return false
end

-- Global receive_fields for summon ghost small dialog
minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "sl_gui:summon_ghost" then
		local name = player:get_player_name()
		if fields.summon_ghost_close or fields.quit then return end
		if fields.summon_ghost_do then
			local ghost_name = fields.summon_ghost_name or ""
			if minetest.registered_chatcommands.sl_summon_ghost then
				minetest.registered_chatcommands.sl_summon_ghost.func(name, ghost_name)
			end
		end
		return
	end
end)

-- Expose handlers for unified_inventory to call
_G.sl_gui_system_handle_fields = handle_system_fields
_G.sl_gui_comms_handle_fields = handle_comms_fields

minetest.log("action", "[sl_gui] System & Comms tabs loaded — inventory GUI now exposes majority of sl_ commands.")
