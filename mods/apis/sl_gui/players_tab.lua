-- ================================================================
-- WP5 — Players (Roster) Tab for the Unified Inventory
-- Lists every connected operator: team, phase/alive status, HP,
-- points, ready-check state and the current Monster Master.
-- Read-only roster; quick links jump to Comms / chat state.
-- ================================================================

local S
if rawget(_G, "game_mode") and game_mode.S then
	S = game_mode.S
else
	S = minetest.get_translator("sl_gui") or function(s) return s end
end

-- Mirror the system tab's safe state accessors so this tab still builds
-- when sl_modebase is absent (headless stubs, main-menu probes).
local function get_state()
	if rawget(_G, "game_mode") and game_mode.state then
		return game_mode.state
	end
	return {
		match_active = false,
		match_count = 0,
		players = {},
		monster_master = { player = nil },
		ready_check = { active = false, ready = {} },
	}
end

local function get_player_state(name)
	if rawget(_G, "game_mode") and game_mode.get_player_state then
		return game_mode.get_player_state(name)
	end
	return { team = nil, role = nil, phase = "alive", points = 0, eliminated = false }
end

-- Swatch colour + short tag for a roster row.
-- Phases: alive | ghost | evil_ghost ; role: monster_master.
local function status_of(pname, pl, state)
	if pname == state.monster_master.player
		or (pl and pl.role == "monster_master") then
		return "#e8c33a", S("MM")
	end
	local phase = pl and pl.phase or "alive"
	if phase == "evil_ghost" or phase == "master_monster" then
		return "#c0566a", S("EVIL")
	end
	if phase == "ghost" or phase == "monster" then
		return "#9aa7c7", S("GHOST")
	end
	if pl and pl.eliminated then
		return "#888888", S("ELIM")
	end
	if state.ready_check and state.ready_check.active and state.ready_check.ready[pname] then
		return "#7aca7a", S("READY")
	end
	return "#55ff77", S("ALIVE")
end

-- Gather one roster record per connected player, sorted:
-- Monster Master first, then Beacon A, Beacon B, unassigned; name within a group.
local function gather_roster(viewer)
	local state = get_state()
	local gm = rawget(_G, "game_mode")

	local group_rank = { monster_master = 0, beacon_a = 1, beacon_b = 2 }
	local records = {}
	for _, p in ipairs(minetest.get_connected_players()) do
		local pname = p:get_player_name()
		local pl = get_player_state(pname)

		local is_mm = pname == state.monster_master.player
			or pl.role == "monster_master"
		local group = is_mm and "monster_master" or pl.team or "none"

		local team_label = "-"
		if is_mm then
			team_label = S("Monster Master")
		elseif pl.team then
			team_label = (gm and gm.get_team_label and gm.get_team_label(pl.team))
				or pl.team
		end

		local color, status = status_of(pname, pl, state)

		local hp = 0
		if p.get_hp then hp = p:get_hp() or 0 end
		local hp_max = 20
		local props = p.get_properties and p:get_properties()
		if props and props.hp_max then hp_max = props.hp_max end

		local display_name = pname
		if viewer and pname == viewer then
			display_name = pname .. " " .. S("(you)")
		end

		records[#records + 1] = {
			name = display_name,
			sort_name = pname,
			team = team_label,
			status = status,
			color = color,
			hp = string.format("%d/%d", hp, hp_max),
			points = tostring(pl.points or 0),
			group = group,
			rank = group_rank[group] or 3,
			alive = (status == "ALIVE" or status == "READY"),
			ghost = (status == "GHOST" or status == "EVIL"),
		}
	end

	table.sort(records, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.sort_name < b.sort_name
	end)
	return records, state
end

function get_players_formspec(player)
	local name = player:get_player_name()
	local records, state = gather_roster(name)

	local alive_c, ghost_c = 0, 0
	for _, r in ipairs(records) do
		if r.alive then alive_c = alive_c + 1 end
		if r.ghost then ghost_c = ghost_c + 1 end
	end

	local fs = {}

	-- Header: roster summary
	table.insert(fs, "box[0.2,0.3;11.6,1.0;#0a1a2aee]")
	table.insert(fs, string.format("label[0.4,0.55;%s]",
		minetest.formspec_escape(S("OPERATOR ROSTER"))))
	table.insert(fs, string.format("label[0.4,0.95;%s: %d  |  %s: %d  |  %s: %d  |  MM: %s]",
		minetest.formspec_escape(S("Connected")), #records,
		minetest.formspec_escape(S("Alive")), alive_c,
		minetest.formspec_escape(S("Ghosts")), ghost_c,
		minetest.formspec_escape(state.monster_master.player or S("none"))
	))

	-- Match / ready line
	local line2
	if state.ready_check and state.ready_check.active then
		if state.ready_check.countdown_left and state.ready_check.countdown_left > 0 then
			line2 = S("INSERTION IN @1s", tostring(math.ceil(state.ready_check.countdown_left)))
		else
			local ready_c = 0
			for _, r in ipairs(records) do
				if state.ready_check.ready[r.sort_name] then ready_c = ready_c + 1 end
			end
			line2 = S("READY CHECK: @1/@2 confirmed", tostring(ready_c), tostring(#records))
		end
	elseif state.match_active then
		line2 = S("MATCH #@1 ACTIVE", tostring(state.match_count or 0))
	else
		line2 = S("LOBBY - STANDBY")
	end
	table.insert(fs, string.format("label[7.0,0.55;%s]", minetest.formspec_escape(line2)))

	-- Column header strip
	table.insert(fs, "box[0.2,1.45;11.6,0.5;#151520ee]")
	table.insert(fs, "label[0.95,1.78;Name]")
	table.insert(fs, "label[4.6,1.78;Team]")
	table.insert(fs, "label[8.1,1.78;Status]")
	table.insert(fs, "label[9.8,1.78;HP]")
	table.insert(fs, "label[11.0,1.78;Pts]")

	-- Roster table. Column types: colour swatch, then text cells.
	-- The whole item list is one comma-joined element: rows join with
	-- commas too (never semicolons — that feeds the client parser garbage).
	table.insert(fs, "tablecolumns[color;text;text;text;text;text]")
	local items = {
		-- header row (the swatch column is empty for it)
		table.concat({ "", minetest.formspec_escape(S("Name")),
			minetest.formspec_escape(S("Team")),
			minetest.formspec_escape(S("Status")),
			minetest.formspec_escape(S("HP")),
			minetest.formspec_escape(S("Pts")) }, ","),
	}
	for _, r in ipairs(records) do
		items[#items + 1] = table.concat({
			r.color,
			minetest.formspec_escape(r.name),
			minetest.formspec_escape(r.team),
			minetest.formspec_escape(r.status),
			minetest.formspec_escape(r.hp),
			minetest.formspec_escape(r.points),
		}, ",")
	end
	table.insert(fs, string.format("table[0.2,2.0;11.6,6.7;players_roster;%s;1]",
		table.concat(items, ",")))

	-- Legend
	table.insert(fs, "box[0.2,8.9;11.6,1.2;#1a1a1aee]")
	table.insert(fs, string.format("label[0.4,9.15;%s]",
		minetest.formspec_escape(S("LEGEND"))))
	table.insert(fs, string.format("label[0.4,9.5;%s]",
		minetest.formspec_escape(S("ALIVE = in the field   READY = confirmed insertion   GHOST = cloud cage (sealed comms)"))))
	table.insert(fs, string.format("label[0.4,9.8;%s]",
		minetest.formspec_escape(S("EVIL = corrupted ghost   ELIM = eliminated   MM = Monster Master"))))

	-- Actions
	table.insert(fs, "button[0.3,10.35;2.5,0.7;players_refresh; REFRESH ]")
	table.insert(fs, "button[3.0,10.35;3.0,0.7;players_open_comms; OPEN COMMS ]")
	table.insert(fs, "button[6.2,10.35;3.0,0.7;players_state; MY STATE ]")
	table.insert(fs, "button[9.4,10.35;2.3,0.7;players_status; MATCH STATUS ]")

	return table.concat(fs, "")
end

-- ================================================================
-- Field handler — hooked in by unified_inventory
-- ================================================================

local function handle_players_fields(player, fields)
	local name = player:get_player_name()

	if fields.players_refresh then
		-- Rebuilding the inventory is enough; returning true makes
		-- unified_inventory re-render the same tab.
		return true
	end

	if fields.players_open_comms then
		-- Jump straight to the Comms tab for private messages.
		player:get_meta():set_string("current_tab", "comms")
		return true
	end

	if fields.players_state then
		if minetest.registered_chatcommands.sl_state then
			minetest.registered_chatcommands.sl_state.func(name)
		end
		return true
	end

	if fields.players_status then
		if minetest.registered_chatcommands.sl_match_status then
			local _, msg = minetest.registered_chatcommands.sl_match_status.func(name)
			if msg then minetest.chat_send_player(name, msg) end
		end
		return true
	end

	-- Row clicks on the roster carry no action yet; don't let them
	-- fall through as unhandled refreshes.
	if fields.players_roster then
		return true
	end

	return false
end

_G.sl_gui_players_handle_fields = handle_players_fields

minetest.log("action", "[sl_gui] Players roster tab loaded.")
