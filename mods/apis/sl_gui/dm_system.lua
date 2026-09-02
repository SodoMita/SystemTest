-- ================================================================
-- WP5 — Direct Message System + Secure Link UI
-- Identity-neutral, social-deduction compliant.
-- Living players can establish private neural links (DMs) to
-- coordinate, deceive, or share intel. Ghosts are sealed and cannot
-- send or receive DMs (per MATCH_LOOP_SPEC "Ghost cloud cage").
--
-- Ownership: WP5 HUD & UI (mods/apis/sl_gui/**)
-- Interface: /sl_dm <player> <message>, /sl_dm_ui, /sl_whisper
--
-- Secure Link terminal UI: built with the vendored minetest-flow
-- layout library (mods/external/flow) whenever it is loaded. Flow
-- version:
--   * no hand-placed coordinates or string concatenation — a widget
--     tree (VBox/Label/Textlist/Field/Button) auto-lays out
--   * no manual state bookkeeping — selections and typed text live in
--     the flow context and survive redraws; no re-show code paths
--   * input arrives as typed callbacks, not raw field parsing
-- When flow is absent (headless stubs that dofile sl_gui directly)
-- the terminal falls back to the classic string formspec so the
-- command surface and tests keep working.
-- ================================================================

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Use game_mode translator if available, fallback to minetest translator
local S
if rawget(_G, "game_mode") and game_mode.S then
	S = game_mode.S
else
	S = minetest.get_translator("sl_gui") or function(s) return s end
end

local flow = rawget(_G, "flow") -- nil when the library is not loaded

local dm_cooldown = {} -- [sender_name] = next_allowed_time
local DM_COOLDOWN = 0.8 -- seconds, anti-spam
local DM_MAX_LEN = 300

-- Helper: is this player allowed to use DM? (living only, match or lobby)
local function can_use_dm(name)
	if not rawget(_G, "game_mode") then return true end
	local pl = game_mode.get_player_state(name)
	if not pl then return true end
	-- Ghost phases are sealed per spec
	if pl.phase == "ghost" or pl.phase == "evil_ghost" then
		return false, S("Ghost communications are sealed.")
	end
	return true
end

local function can_receive_dm(name)
	if not rawget(_G, "game_mode") then return true end
	local pl = game_mode.get_player_state(name)
	if not pl then return true end
	if pl.phase == "ghost" or pl.phase == "evil_ghost" then
		return false
	end
	return true
end

local function get_alive_player_names(exclude_name)
	local names = {}
	if rawget(_G, "game_mode") and game_mode.get_connected_player_names then
		for _, n in ipairs(game_mode.get_connected_player_names()) do
			if n ~= exclude_name and can_receive_dm(n) then
				table.insert(names, n)
			end
		end
	else
		for _, p in ipairs(minetest.get_connected_players()) do
			local n = p:get_player_name()
			if n ~= exclude_name then
				table.insert(names, n)
			end
		end
	end
	table.sort(names)
	return names
end

-- Core DM dispatch: identity-neutral, private, cybernetic styling
local function send_dm(sender, target, message)
	if not sender or not target or not message then
		return false, S("Invalid transmission parameters.")
	end

	-- Luanti provides string:trim(); stub fallback
	if message.trim then
		message = message:trim()
	else
		message = message:match("^%s*(.-)%s*$") or ""
	end
	if message == "" then
		return false, S("Cannot transmit empty signal.")
	end
	if #message > DM_MAX_LEN then
		return false, S("Signal too long (@1 chars max).", tostring(DM_MAX_LEN))
	end

	local ok, err = can_use_dm(sender)
	if not ok then return false, err end

	if not minetest.get_player_by_name(target) then
		-- Check botmatch bots too
		if rawget(_G, "botmatch") and botmatch.bots and botmatch.bots[target] then
			-- allow bot as target for soak tests
		else
			return false, S("Target bio-signature not found: @1", target)
		end
	end

	if not can_receive_dm(target) then
		return false, S("Target is sealed in containment and cannot receive transmissions.")
	end

	if sender == target then
		return false, S("Cannot establish link to self.")
	end

	-- Cooldown
	local now = (rawget(_G, "game_mode") and game_mode.now and game_mode.now()) or (minetest.get_us_time() / 1000000)
	if (dm_cooldown[sender] or 0) > now then
		return false, S("Link recharging. Try again in @1s.", tostring(math.ceil(dm_cooldown[sender] - now)))
	end
	dm_cooldown[sender] = now + DM_COOLDOWN

	-- Cybernetic styling: private to both parties
	local sender_color = "#00ffff"
	local target_color = "#ffaa00"
	local msg_color = "#ffffff"

	-- To sender: confirmation
	minetest.chat_send_player(sender, minetest.colorize(sender_color,
		S("[SECURE LINK] You -> @1: ", target)) .. minetest.colorize(msg_color, message))

	-- To target: incoming
	minetest.chat_send_player(target, minetest.colorize(target_color,
		S("[SECURE LINK] @1 -> You: ", sender)) .. minetest.colorize(msg_color, message))

	-- Subtle audio cue for target
	minetest.sound_play("click", { to_player = target, gain = 0.6 }, true)

	-- Log for moderation (server log only, not broadcast)
	minetest.log("action", string.format("[sl_gui][DM] %s -> %s: %s", sender, target, message))

	return true
end

-- ================================================================
-- Secure Link terminal — minetest-flow widget tree (primary)
--
-- The classic formspec was a hand-placed pile of strings plus an
-- on_player_receive_fields block that parsed raw textlist events and
-- manually re-showed the form after every action. Flow replaces the
-- whole pipeline:
--   * layout: rows of widgets inside one VBox; the window sizes
--     itself to its content, so nothing can drift out of frame
--   * state: ctx.form.dm_target / dm_message survive every redraw
--     (including the one that clears the message box after a send)
--   * input: per-widget on_event / on_key_enter callbacks; flow
--     sanitises and type-checks every field before callbacks run
--   * redraw: a callback returning true re-renders the open form
-- ================================================================
local DM_CYAN = "#00ffff" -- terminal header / link accent
local DM_RED = "#ff5555" -- transmission failure
local DM_GREEN = "#55ffaa" -- protocol hint
-- Content area width in formspec units. Flow adds its default 0.3-unit
-- window padding around the content, so the window lands ~9 units wide.
local DM_UI_INNER_W = 8.4
local DM_UI_LIST_H = 2.2 -- same visible rows as the classic terminal

local dm_flow_gui

if flow then
	local gui = flow.widgets

	-- Attempt to transmit whatever is typed, from either the button or the
	-- Enter key. Both callbacks return true to keep the terminal open and
	-- re-render it (the successful path clears the message box by wiping
	-- the flow context value the field re-seeds itself from).
	local function flow_try_send(player, ctx)
		local name = player:get_player_name()
		local targets = get_alive_player_names(name)
		local target = targets[ctx.form.dm_target]
		if not target then
			ctx.form.dm_error = S("No target selected. Select a bio-signature from the list.")
			return true
		end
		local msg = ctx.form.dm_message or ""
		local ok, err = send_dm(name, target, msg)
		if not ok then
			ctx.form.dm_error = S("TRANSMISSION FAILED: @1", err or "")
		else
			ctx.form.dm_error = nil
			ctx.form.dm_message = "" -- cleared for rapid follow-up
		end
		return true
	end

	dm_flow_gui = flow.make_gui(function(player, ctx)
		local pname = player:get_player_name()
		local targets = get_alive_player_names(pname)
		local has_targets = #targets > 0

		-- The roster can change while the terminal is open (players leave,
		-- die, un-ghost between redraws): re-validate the remembered row.
		local sel = ctx.form.dm_target
		if has_targets and (type(sel) ~= "number" or not targets[sel]) then
			sel = 1
			ctx.form.dm_target = sel
		end

		local rows = {
			gui.Label {
				label = minetest.colorize(DM_CYAN,
					S("SECURE NEURAL LINK // DM TERMINAL")),
			},
			gui.Label {
				label = S("Private, identity-neutral, ghost-proof."),
			},
		}

		if has_targets then
			rows[#rows + 1] = gui.Label {
				label = S("Select target bio-signature:"),
			}
			rows[#rows + 1] = gui.Textlist {
				name = "dm_target",
				w = DM_UI_INNER_W,
				h = DM_UI_LIST_H,
				listelems = targets,
			}
		else
			rows[#rows + 1] = gui.Label {
				label = minetest.colorize(DM_RED,
					S("NO TARGETS AVAILABLE - ALL SIGNALS SEALED")),
			}
		end

		rows[#rows + 1] = gui.Label {
			label = S("Message (max @1 chars):", tostring(DM_MAX_LEN)),
		}
		rows[#rows + 1] = gui.Field {
			name = "dm_message",
			w = DM_UI_INNER_W,
			close_on_enter = false,
			on_key_enter = flow_try_send,
		}
		rows[#rows + 1] = gui.HBox {
			gui.Spacer {},
			gui.Button {
				name = "dm_send",
				label = S("TRANSMIT"),
				on_event = flow_try_send,
			},
			gui.Button {
				name = "dm_close",
				label = S("CLOSE LINK"),
				on_event = function(p)
					dm_flow_gui:close(p)
				end,
			},
		}
		rows[#rows + 1] = gui.Label {
			label = minetest.colorize(DM_GREEN,
				S("Ghosts cannot intercept private links.")),
		}

		if ctx.form.dm_error then
			rows[#rows + 1] = gui.Label {
				label = minetest.colorize(DM_RED, ctx.form.dm_error),
			}
		end

		-- Root VBox carries the terminal chrome; the content rows were
		-- collected above so the no-targets branch can swap them out.
		local root = gui.VBox {
			bgcolor = "#0a0a12ee",
			bg_fullscreen = true,
		}
		for _, row in ipairs(rows) do
			root[#root + 1] = row
		end
		return root
	end)
end

-- ================================================================
-- Secure Link terminal — classic string formspec (fallback)
-- Only used when flow is not loaded (headless stubs that dofile
-- sl_gui directly). Mirrors the pre-flow behaviour exactly.
-- ================================================================
local function get_dm_formspec_legacy(sender)
	local alive = get_alive_player_names(sender)
	local player_list = table.concat(alive, ",")

	local fs = {
		"formspec_version[4]",
		"size[8,7]",
		"bgcolor[#0a0a12ee;true]",
		"label[0.5,0.4;" .. minetest.colorize("#00ffff", S("SECURE NEURAL LINK // DIRECT MESSAGE")) .. "]",
		"label[0.5,0.9;" .. S("Select target bio-signature:") .. "]",
		"textlist[0.5,1.3;7,2.2;dm_target;" .. minetest.formspec_escape(player_list) .. ";1;false]",
		"label[0.5,3.8;" .. S("Message (max @1 chars):", tostring(DM_MAX_LEN)) .. "]",
		"field[0.5,4.3;7,0.8;dm_message;;]",
		"field_close_on_enter[dm_message;false]",
		"button[0.5,5.4;3,0.8;dm_send;TRANSMIT]",
		"button[4.5,5.4;3,0.8;dm_close;CLOSE LINK]",
		"label[0.5,6.3;" .. minetest.colorize("#55ffaa", S("LOBBY COMMS: Use for trust, deception, coordination. Ghosts cannot intercept.")) .. "]",
	}
	return table.concat(fs, "")
end

-- Render the terminal as one standalone formspec string. With flow the
-- call needs a live player object (the renderer asks the engine which
-- formspec version that client supports); without flow a name suffices.
local function get_dm_formspec(player_or_name, ctx)
	if dm_flow_gui then
		local player = player_or_name
		if type(player) == "string" then
			player = minetest.get_player_by_name(player)
		end
		if player then
			return dm_flow_gui:render_to_formspec_string(
				player, ctx or { dm_target = 1 }, true)
		end
		return "" -- no live player to render for; callers show via dm_flow_gui
	end
	local sender = player_or_name
	if type(sender) ~= "string" and sender then
		sender = sender:get_player_name()
	end
	return get_dm_formspec_legacy(sender or "")
end

-- State for UI selection: [sender] = selected_target_name (legacy UI only)
local dm_ui_selection = {}

if not dm_flow_gui then
	minetest.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= "sl_gui:dm" then return end
		local sender = player:get_player_name()

		if fields.dm_close or fields.quit then
			return
		end

		-- Handle textlist selection
		if fields.dm_target then
			local expl = minetest.explode_textlist_event(fields.dm_target)
			if expl and expl.type == "CHG" then
				local alive = get_alive_player_names(sender)
				local idx = expl.index
				if alive[idx] then
					dm_ui_selection[sender] = alive[idx]
				end
			end
		end

		if fields.dm_send then
			local target = dm_ui_selection[sender]
			-- If no selection via list, try parsing field directly (fallback)
			if not target then
				local alive = get_alive_player_names(sender)
				if #alive > 0 then
					target = alive[1]
				end
			end

			local msg = fields.dm_message or ""
			if not target then
				minetest.chat_send_player(sender, minetest.colorize("#ff5555", S("No target selected. Select a bio-signature from the list.")))
				minetest.show_formspec(sender, "sl_gui:dm", get_dm_formspec_legacy(sender))
				return
			end

			local ok, err = send_dm(sender, target, msg)
			if not ok then
				minetest.chat_send_player(sender, minetest.colorize("#ff5555", S("TRANSMISSION FAILED: @1", err or "")))
			end

			if ok then
				-- Keep UI open for rapid follow-up, clear message field
				minetest.show_formspec(sender, "sl_gui:dm", get_dm_formspec_legacy(sender))
			else
				minetest.show_formspec(sender, "sl_gui:dm", get_dm_formspec_legacy(sender))
			end
		end
	end)
end

-- Open the secure link terminal for a player (both UI backends).
local function open_dm_terminal(name)
	local ok, err = can_use_dm(name)
	if not ok then
		return false, err
	end
	local alive = get_alive_player_names(name)
	if #alive == 0 then
		return false, S("No available bio-signatures for secure link.")
	end
	if dm_flow_gui then
		local player = minetest.get_player_by_name(name)
		if not player then return false end
		dm_flow_gui:show(player)
		return true
	end
	dm_ui_selection[name] = alive[1]
	minetest.show_formspec(name, "sl_gui:dm", get_dm_formspec_legacy(name))
	return true
end

-- Chat commands

minetest.register_chatcommand("sl_dm", {
	params = "<player> <message>",
	description = S("Send a private secure link message to a player"),
	func = function(name, param)
		local target, msg = param:match("^(%S+)%s+(.+)$")
		if not target or not msg then
			return false, S("Usage: /sl_dm <player> <message>")
		end
		local ok, err = send_dm(name, target, msg)
		if not ok then
			return false, err
		end
		return true
	end,
})

minetest.register_chatcommand("sl_whisper", {
	params = "<player> <message>",
	description = S("Alias for /sl_dm — private whisper link"),
	func = function(name, param)
		local target, msg = param:match("^(%S+)%s+(.+)$")
		if not target or not msg then
			return false, S("Usage: /sl_whisper <player> <message>")
		end
		local ok, err = send_dm(name, target, msg)
		if not ok then
			return false, err
		end
		return true
	end,
})

minetest.register_chatcommand("sl_w", {
	params = "<player> <message>",
	description = S("Short alias for /sl_dm"),
	func = function(name, param)
		local target, msg = param:match("^(%S+)%s+(.+)$")
		if not target or not msg then
			return false, S("Usage: /sl_w <player> <message>")
		end
		local ok, err = send_dm(name, target, msg)
		if not ok then
			return false, err
		end
		return true
	end,
})

minetest.register_chatcommand("sl_dm_ui", {
	description = S("Open secure link terminal for direct messaging"),
	func = function(name)
		return open_dm_terminal(name)
	end,
})

-- Alias: /sl_comms
minetest.register_chatcommand("sl_comms", {
	description = S("Open secure comms terminal (DM UI)"),
	func = function(name)
		return open_dm_terminal(name)
	end,
})

-- Clean up on leave
minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	dm_ui_selection[name] = nil
	dm_cooldown[name] = nil
end)

minetest.log("action", "[sl_gui] DM System loaded — secure neural link active."
	.. (dm_flow_gui and " (flow terminal)" or " (classic terminal)"))

-- Expose for smoke test stub
if rawget(_G, "game_mode") then
	game_mode.send_dm = send_dm
	game_mode.get_dm_formspec = get_dm_formspec
	game_mode.dm_flow_gui = dm_flow_gui
end
