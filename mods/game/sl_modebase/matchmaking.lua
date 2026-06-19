local S = game_mode.S
local state = game_mode.state

-- Get the matchmaking formspec
local function get_matchmaking_formspec(player_name)
	local player = minetest.get_player_by_name(player_name)
	if not player then return "" end

	local pl = game_mode.get_player_state(player_name)
	local privs = minetest.get_player_privs(player_name)
	local is_admin = privs.sl_admin or privs.server

	local fs = {
		"formspec_version[4]",
		"size[10,9]",
		"bgcolor[#101010ff;true]",
		"label[0.5,0.5;" .. minetest.colorize("#00ffff", "SYSTEM MATCHMAKING") .. "]",
	}

	-- Match Status
	local status_text = state.match_active and minetest.colorize("#ff5555", "MATCH IN PROGRESS") or minetest.colorize("#55ff55", "LOBBY - READY TO START")
	table.insert(fs, "label[0.5,1.0;Status: " .. status_text .. "]")

	-- Win Conditions
	table.insert(fs, "box[0.5,1.5;4,3;#1a1a1aff]")
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
	table.insert(fs, "textarea[0.7,3.5;3.6,1.0;;;" .. minetest.formspec_escape(desc) .. "]")

	-- Role Selection
	table.insert(fs, "box[5.0,1.5;4.5,3;#1a1a1aff]")
	table.insert(fs, "label[5.2,1.8;Monster Master:]")
	
	local mm_name = state.monster_master.player or "None"
	table.insert(fs, "label[5.2,2.3;Current: " .. minetest.colorize("#ffaa00", mm_name) .. "]")
	
	if not state.match_active then
		if mm_name == player_name then
			table.insert(fs, "button[5.2,3.5;4,0.8;leave_mm;Resign Role]")
		elseif mm_name == "None" then
			table.insert(fs, "button[5.2,3.5;4,0.8;take_mm;Become Monster Master]")
		else
			table.insert(fs, "label[5.2,3.5;Role is taken.]")
		end
	end

	-- Player List
	table.insert(fs, "box[0.5,4.8;9,3;#1a1a1aff]")
	table.insert(fs, "label[0.7,5.1;Connected Players:]")
	
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
	table.insert(fs, "textlist[0.7,5.5;8.6,2;player_list;" .. table.concat(names, ",") .. "]")

	-- Control Buttons
	if not state.match_active then
		if is_admin then
			table.insert(fs, "image_button[3,8;4,0.8;gui_button_next.png;start_match;START MATCH]")
		else
			table.insert(fs, "label[3,8;Waiting for admin to start...]")
		end
	else
		if is_admin then
			table.insert(fs, "button[3,8;4,0.8;stop_match;FORCE STOP MATCH]")
		end
	end

	return table.concat(fs, "")
end

-- Handle formspec fields
minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "sl_modebase:matchmaking" then return end
	local name = player:get_player_name()

	if fields.take_mm then
		minetest.chat_send_all("Fields take mm triggered")
		minetest.run_chatcommand("sl_be_monster_master", "")
	elseif fields.leave_mm then
		game_mode.set_monster_master(nil)
		game_mode.broadcast(S("Monster Master has resigned."))
	elseif fields.cond_elimination then
		state.win_conditions.elimination = (fields.cond_elimination == "true")
	elseif fields.cond_objective then
		state.win_conditions.objective = (fields.cond_objective == "true")
	elseif fields.start_match then
		minetest.run_chatcommand("sl_match_start", "")
	elseif fields.stop_match then
		minetest.run_chatcommand("sl_match_stop", "")
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
