local S = game_mode.S
local state = game_mode.state

-- Format a pool entry for the Bots listbox (Name, Team, status).
local function format_bot_pool_line(entry)
	if not entry then return "" end
	local status = (rawget(_G, "botmatch") and botmatch.bots and botmatch.bots[entry.name]) and "in" or "out"
	return string.format("%s | %s | %s", entry.name, entry.team, status)
end

-- Read the bot pool from the aaa_botmatch mod. Returns a list, or an
-- empty list if the harness is not loaded (the formspec still renders
-- normally in non-botmatch sessions).
local function get_bot_pool()
	if not rawget(_G, "botmatch") or not botmatch.pool then return {} end
	return botmatch.pool
end

-- Get the matchmaking formspec
local function get_matchmaking_formspec(player_name)
	local player = minetest.get_player_by_name(player_name)
	if not player then return "" end

	local pl = game_mode.get_player_state(player_name)
	local privs = minetest.get_player_privs(player_name)
	local is_admin = privs.sl_admin or privs.server
	-- The Bots panel only appears in mob mode (the only mode where bots
	-- can be added/removed at runtime). The session must also be in
	-- lobby, because mid-match pool edits are rejected anyway.
	local show_bots_panel = is_admin
		and rawget(_G, "botmatch")
		and botmatch.config
		and botmatch.config.mob_mode

	-- Two layouts: 10 units tall for the basic matchmaking screen,
	-- 14 units tall when the Bots admin panel is shown.
	local fs = {
		"formspec_version[4]",
		"size[10," .. (show_bots_panel and "14" or "10") .. "]",
		"bgcolor[#101010ff;true]",
		"label[0.5,0.5;" .. minetest.colorize("#00ffff", "SYSTEM MATCHMAKING") .. "]",
	}

	-- Match Status
	local status_text = state.match_active and minetest.colorize("#ff5555", "MATCH IN PROGRESS") or minetest.colorize("#55ff55", "LOBBY - READY TO START")
	table.insert(fs, "label[0.5,1.0;Status: " .. status_text .. "]")

	-- Win Conditions
	table.insert(fs, "box[0.5,1.5;4,3.4;#1a1a1aff]")
	table.insert(fs, "label[0.7,1.8;Win Conditions:]")

	local win_conds = state.win_conditions or { elimination = true, objective = false }

	table.insert(fs, string.format("checkbox[0.7,2.2;cond_elimination;Last Team Standing;%s]",
		tostring(win_conds.elimination)))
	table.insert(fs, string.format("checkbox[0.7,2.8;cond_objective;Item Delivery;%s]",
		tostring(win_conds.objective)))

	local desc = ""
	if win_conds.elimination and win_conds.objective then
		desc = "Hybrid: First team to eliminate others OR deliver the Core wins."
	elseif win_conds.elimination then
		desc = "Elimination: Last team standing wins."
	elseif win_conds.objective then
		desc = "Objective: First team to deliver the Core wins."
	else
		desc = minetest.colorize("#ff5555", "WARNING: No win conditions set!")
	end
	table.insert(fs, "textarea[0.7,3.5;3.6,1.2;;;" .. minetest.formspec_escape(desc) .. "]")

	-- Role Selection
	table.insert(fs, "box[5.0,1.5;4.5,3.4;#1a1a1aff]")
	table.insert(fs, "label[5.2,1.8;Match Settings:]")

	local sett = state.settings or { beacon_hp = 100, mm_auto_assign = true }

	table.insert(fs, "label[5.2,2.3;Beacon HP:]")
	table.insert(fs, string.format("field[7.5,2.1;1.5,0.6;sett_beacon_hp;;%d]", sett.beacon_hp))

	table.insert(fs, string.format("checkbox[5.2,3.3;sett_mm_auto;MM Auto-Assign;%s]", tostring(sett.mm_auto_assign)))
	table.insert(fs, string.format("checkbox[5.2,3.7;sett_auto_start;Auto-Start Matches;%s]", tostring(sett.auto_start)))

	table.insert(fs, "button[5.2,4.3;4,0.6;save_settings;Apply Settings]")

	-- Role Section
	table.insert(fs, "box[0.5,5.1;9,1.5;#1a1a1aff]")
	local mm_name = state.monster_master.player or "None"
	table.insert(fs, "label[0.7,5.4;Monster Master: " .. minetest.colorize("#ffaa00", mm_name) .. "]")

	if not state.match_active then
		if mm_name == player_name then
			table.insert(fs, "button[5.2,5.6;4,0.8;leave_mm;Resign Role]")
		elseif mm_name == "None" then
			table.insert(fs, "button[5.2,5.6;4,0.8;take_mm;Become MM]")
		end
	end

	-- Player List
	table.insert(fs, "box[0.5,6.8;9,1.9;#1a1a1aff]")
	table.insert(fs, "label[0.7,7.05;Connected Players:]")

	local connected = minetest.get_connected_players()
	local names = {}
	for _, p in ipairs(connected) do
		local n = p:get_player_name()
		local pstate = game_mode.get_player_state(n)
		local role_str = ""
		if n == state.monster_master.player then
			role_str = " [MM]"
		elseif pstate.team then
			role_str = " [" .. game_mode.get_team_label(pstate.team) .. "]"
		end
		table.insert(names, n .. role_str)
	end
	table.insert(fs, "textlist[0.7,7.45;8.6,1.05;player_list;" .. table.concat(names, ",") .. "]")

	-- Bots admin panel (mob mode only; admin only).
	-- Layout: listbox of current pool on the left, add form on the right,
	-- remove / clear buttons below the listbox.
	if show_bots_panel then
		local pool = get_bot_pool()
		local pool_lines = {}
		for _, entry in ipairs(pool) do
			table.insert(pool_lines, format_bot_pool_line(entry))
		end
		table.insert(fs, "box[0.5,8.9;9,3.7;#1a1a1aff]")
		table.insert(fs, "label[0.7,9.1;" .. minetest.colorize("#00ffff", "Bot Roster (mob mode)") .. "]")
		table.insert(fs, "label[0.7,9.45;Name | Team | Spawn]")
		if #pool_lines > 0 then
			table.insert(fs, "textlist[0.7,9.85;4.6,2.5;bot_pool;" .. table.concat(pool_lines, ",") .. "]")
		else
			table.insert(fs, "textlist[0.7,9.85;4.6,2.5;bot_pool;]")
		end
		table.insert(fs, "label[5.6,9.85;Add bot:]")
		table.insert(fs, "field[5.6,10.35;1.8,0.6;bot_add_name;;]")
		table.insert(fs, "dropdown[7.6,10.35;1.9,0.6;bot_add_team;beacon_a,beacon_b;beacon_a]")
		table.insert(fs, "button[5.6,11.05;1.8,0.6;bot_add;ADD]")
		table.insert(fs, "label[5.6,11.8;Select a bot above and:]")
		table.insert(fs, "button[5.6,12.3;1.8,0.6;bot_remove;REMOVE]")
		table.insert(fs, "button[7.6,12.3;1.9,0.6;bot_clear;CLEAR ALL]")
	end

	-- Control Buttons — last row in the window, so it has to stay inside
	-- the frame. Without the bots panel the button is at y=8.9; with
	-- the panel, it shifts down to y=12.7 so it doesn't crowd the
	-- Clear button.
	local btn_y = show_bots_panel and 12.7 or 8.9
	if not state.match_active then
		if is_admin then
			table.insert(fs, "image_button[3," .. btn_y .. ";4,0.85;gui_button_next.png;start_match;START MATCH]")
		else
			table.insert(fs, "label[3," .. (btn_y + 0.2) .. ";Waiting for admin to start...]")
		end
	else
		if is_admin then
			table.insert(fs, "button[3," .. btn_y .. ";4,0.85;stop_match;FORCE STOP MATCH]")
		end
	end

	return table.concat(fs, "")
end

-- Handle formspec fields
minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "sl_modebase:matchmaking" then return end
	local name = player:get_player_name()

	if fields.take_mm then
		game_mode.set_monster_master(name)
		game_mode.broadcast(S("@1 is now the Monster Master!", name))
		if achievement_progress then
			achievement_progress(player, "play_monster_master", 1)
		end
	elseif fields.leave_mm then
		game_mode.set_monster_master(nil)
		game_mode.broadcast(S("Monster Master has resigned."))
	elseif fields.cond_elimination then
		state.win_conditions.elimination = (fields.cond_elimination == "true")
	elseif fields.cond_objective then
		state.win_conditions.objective = (fields.cond_objective == "true")
	elseif fields.save_settings then
		state.settings.beacon_hp = tonumber(fields.sett_beacon_hp) or 100
		state.settings.mm_auto_assign = (fields.sett_mm_auto == "true")
		state.settings.auto_start = (fields.sett_auto_start == "true")
		minetest.chat_send_player(name, S("Match settings updated."))
	elseif fields.bot_add then
		-- The formspec only emits the bots panel in mob mode for admins,
		-- so the botmatch mod is guaranteed loaded here.
		if not rawget(_G, "botmatch") or not botmatch.config.mob_mode then
			minetest.chat_send_player(name, "[System Looting] bot match harness not in mob mode")
		else
			local bot_name = (fields.bot_add_name or ""):match("^%s*(.-)%s*$") or ""
			local team = fields.bot_add_team or "beacon_a"
			if bot_name == "" then
				minetest.chat_send_player(name, "[System Looting] bot name is empty")
			else
				local ok, err = botmatch.add_bot(bot_name, team, true)
				if not ok then
					minetest.chat_send_player(name, "[System Looting] " .. tostring(err))
				else
					minetest.chat_send_player(name, "[System Looting] added bot " .. bot_name
						.. " on " .. team)
				end
			end
		end
	elseif fields.bot_remove then
		if not rawget(_G, "botmatch") or not botmatch.config.mob_mode then
			minetest.chat_send_player(name, "[System Looting] bot match harness not in mob mode")
		else
			-- textlist returns the entry's display name, not its index,
			-- because we passed an unkeyed list. Split on " | " to get
			-- the original name.
			local selected = fields.bot_pool or ""
			local bot_name = selected:match("^([^|]+)") or ""
			bot_name = bot_name:match("^%s*(.-)%s*$") or ""
			if bot_name == "" then
				minetest.chat_send_player(name, "[System Looting] select a bot first")
			else
				local ok, err = botmatch.remove_bot(bot_name)
				if not ok then
					minetest.chat_send_player(name, "[System Looting] " .. tostring(err))
				else
					minetest.chat_send_player(name, "[System Looting] removed bot " .. bot_name)
				end
			end
		end
	elseif fields.bot_clear then
		if not rawget(_G, "botmatch") or not botmatch.config.mob_mode then
			minetest.chat_send_player(name, "[System Looting] bot match harness not in mob mode")
		else
			local ok, err = botmatch.clear_bots()
			if not ok then
				minetest.chat_send_player(name, "[System Looting] " .. tostring(err))
			else
				minetest.chat_send_player(name, "[System Looting] cleared the bot pool")
			end
		end
	elseif fields.start_match then
		-- Terminal launch goes through the ready check; creative-mode admins
		-- (test harness) can bypass it for fast iteration.
		local ok, msg
		if minetest.settings:get_bool("creative_mode") then
			ok, msg = game_mode.start_new_match(name)
		else
			ok, msg = game_mode.begin_ready_check(name)
		end
		if not ok and msg then
			minetest.chat_send_player(name, "[System Looting] " .. msg)
		end
	elseif fields.stop_match then
		if state.match_active then
			game_mode.end_match(nil, S("Stopped by @1", name))
		end
	end

	-- Refresh for everyone near terminals or who has it open?
	-- For now just refresh for the user
	if not fields.quit then
		minetest.show_formspec(name, "sl_modebase:matchmaking", get_matchmaking_formspec(name))
	end
end)

-- Register the Lobby Terminal node
minetest.register_node(game_mode.modname .. ":lobby_terminal", {
	description = S("Lobby Matchmaking Terminal"),
	drawtype = "mesh",
	mesh = "terminal.obj",
	tiles = { "terminal_texture.png^[colorize:#00ffff:50" },
	paramtype = "light",
	light_source = 10,
	groups = { cracky = 1, oddly_breakable_by_hand = 1 },
	selection_box = { type = "fixed", fixed = { -0.4, -0.5, -0.3, 0.4, 0.6, 0.3 } },
	collision_box = { type = "fixed", fixed = { -0.4, -0.5, -0.3, 0.4, 0.6, 0.3 } },

	on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
		if not clicker or not clicker:is_player() then return itemstack end
		local name = clicker:get_player_name()
		minetest.show_formspec(name, "sl_modebase:matchmaking", get_matchmaking_formspec(name))
		return itemstack
	end,
})

-- Command to open the menu
minetest.register_chatcommand("sl_matchmaking", {
	description = S("Open matchmaking menu"),
	func = function(name)
		minetest.show_formspec(name, "sl_modebase:matchmaking", get_matchmaking_formspec(name))
		return true
	end,
})
