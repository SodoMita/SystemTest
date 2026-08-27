local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Persistent match HUD (Phase A.3 + Phase 4 Lobby Upgrade)
-- Identity-neutral by design: it displays match phase, clock, the
-- player's own lives/phase, and public beacon integrity only.
-- It never renders team names, team colors, or other players'
-- private state, so it cannot leak hidden identity.
--
-- WP5 UPGRADE — Waiting for Players HUD:
-- When no match is active and no ready check is running, the HUD
-- shows a cybernetic standby readout with connected bio-signatures,
-- minimum threshold, and initiation hint. This satisfies
-- ROADMAP Phase 4 "Waiting for Players HUD" without leaking team.
-- ================================================================

local hud = {} -- [player_name] = { status=id, vitals=id, beacons=id, lobby=id, ready=id }
local hud_accum = 0

local function fmt_clock(secs)
	secs = math.max(0, math.floor(secs))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function build_hud(player)
	local name = player:get_player_name()
	hud[name] = {
		status = player:hud_add({
			hud_elem_type = "text",
			position = { x = 0.5, y = 0.02 },
			alignment = { x = 0, y = 1 },
			scale = { x = 400, y = 24 },
			text = "",
			number = 0x00ffff,
		}),
		vitals = player:hud_add({
			hud_elem_type = "text",
			position = { x = 0.5, y = 0.07 },
			alignment = { x = 0, y = 1 },
			scale = { x = 400, y = 20 },
			text = "",
			number = 0xffaa00,
		}),
		beacons = player:hud_add({
			hud_elem_type = "text",
			position = { x = 1.0, y = 0.02 },
			alignment = { x = -1, y = 1 },
			scale = { x = 300, y = 20 },
			text = "",
			number = 0xffffff,
		}),
		-- Phase 4: Waiting for Players readout (center-bottom, cybernetic)
		lobby = player:hud_add({
			hud_elem_type = "text",
			position = { x = 0.5, y = 0.90 },
			alignment = { x = 0, y = 0 },
			scale = { x = 400, y = 18 },
			text = "",
			number = 0x55ffaa,
		}),
		-- Phase 4: Ready-check detail readout (below vitals)
		ready = player:hud_add({
			hud_elem_type = "text",
			position = { x = 0.5, y = 0.12 },
			alignment = { x = 0, y = 1 },
			scale = { x = 350, y = 16 },
			text = "",
			number = 0xaaaaff,
		}),
	}
	return hud[name]
end

local function clear_hud(player)
	local name = player:get_player_name()
	local h = hud[name]
	if not h then return end
	for _, id in pairs(h) do
		player:hud_remove(id)
	end
	hud[name] = nil
end

local function update_hud(player)
	local name = player:get_player_name()
	local h = hud[name] or build_hud(player)
	local pl = game_mode.get_player_state(name)

	-- Line 1: match phase + remaining time
	local status
	if state.match_active then
		status = S("MATCH #@1", tostring(state.match_count or 0))
		local duration = state.settings.match_duration or 0
		if duration > 0 then
			local left = duration - (game_mode.now() - state.match_started_at)
			status = status .. "  " .. fmt_clock(left)
		end
	elseif state.ready_check.active then
		if state.ready_check.countdown_left > 0 then
			status = S("INSERTION IN @1...", tostring(math.ceil(state.ready_check.countdown_left)))
		else
			status = S("READY CHECK - type /sl_ready")
		end
	else
		status = S("LOBBY")
	end
	player:hud_change(h.status, "text", status)

	-- Line 2: own lives + own phase (private, role-local)
	local vitals = ""
	if state.match_active then
		vitals = S("LIVES @1", string.rep("|", math.max(0, pl.lives or 0)))
		if pl.phase ~= "alive" then
			vitals = vitals .. "  [" .. string.upper(tostring(pl.phase):gsub("_", " ")) .. "]"
		end
	end
	player:hud_change(h.vitals, "text", vitals)

	-- Line 3: beacon integrity. Beacon HP is already public information
	-- (every damage event is broadcast), so this leaks no hidden identity.
	local a_hp = state.teams.beacon_a.hp or 0
	local b_hp = state.teams.beacon_b.hp or 0
	player:hud_change(h.beacons, "text",
		S("CORE A @1", tostring(a_hp)) .. "   " .. S("CORE B @1", tostring(b_hp)))

	-- Phase 4: Waiting for Players HUD (only when lobby idle)
	local lobby_text = ""
	local ready_text = ""

	if not state.match_active then
		if state.ready_check.active then
			-- Ready check detail: X/Y confirmed, countdown hint
			local connected = game_mode.get_connected_player_names()
			local ready_count = 0
			for _, pname in ipairs(connected) do
				if state.ready_check.ready[pname] then
					ready_count = ready_count + 1
				end
			end
			if state.ready_check.countdown_left > 0 then
				ready_text = S("NEURAL LINK: @1/@2 CONFIRMED // INSERTION T-@3s // PREPARE FOR DEPLOYMENT",
					tostring(ready_count), tostring(#connected),
					tostring(math.ceil(state.ready_check.countdown_left)))
			else
				ready_text = S("READY CHECK: @1/@2 BIO-SIGS CONFIRMED // AWAITING NEURAL LINK // TYPE /sl_ready",
					tostring(ready_count), tostring(#connected))
			end
		else
			-- Pure lobby: Waiting for Players + Auto-start readout
			local connected = game_mode.get_connected_player_names()
			local count = #connected
			local min_required = 2
			local auto_on = state.settings.auto_start
			local auto_delay = state.settings.auto_start_delay or 8

			if count < min_required then
				lobby_text = S("WAITING FOR PLAYERS: @1/@2 // INSUFFICIENT BIO-SIGNATURES // BEACON LINK: STANDBY",
					tostring(count), tostring(min_required))
				if auto_on then
					lobby_text = lobby_text .. S(" // AUTO-START: ON (@1s)", tostring(auto_delay))
				end
			else
				if auto_on then
					lobby_text = S("WAITING FOR PLAYERS: @1 READY // AUTO-START: ON // INTERMISSION @2s // BEACON LINK: STANDBY",
						tostring(count), tostring(auto_delay))
				else
					lobby_text = S("WAITING FOR PLAYERS: @1 READY // BEACON LINK: STANDBY // USE TERMINAL OR /sl_match_start TO INITIATE SEQUENCE",
						tostring(count))
				end
			end
			-- Add hint about DM system and inventory GUI (identity-neutral, social layer)
			if count >= 2 then
				lobby_text = lobby_text .. "  //  " .. S("COMMS: /sl_dm_ui // INV: SYSTEM TAB FOR ALL COMMANDS")
			end
		end
	end

	player:hud_change(h.lobby, "text", lobby_text)
	player:hud_change(h.ready, "text", ready_text)
end

-- Expose for smoke test and for external HUD refresh (e.g., after reconnect)
game_mode.update_hud = update_hud
game_mode.build_hud = build_hud

minetest.register_globalstep(function(dtime)
	hud_accum = hud_accum + dtime
	if hud_accum < 0.5 then return end
	hud_accum = 0
	for _, player in ipairs(minetest.get_connected_players()) do
		local ok, err = pcall(update_hud, player)
		if not ok then
			minetest.log("error", "[game_mode] HUD update failed: " .. tostring(err))
		end
	end
end)

minetest.register_on_joinplayer(function(player)
	-- Build eagerly so the lobby line is visible immediately.
	-- Reconnect hardening: force a full HUD rebuild on rejoin, clear stale IDs.
	local name = player:get_player_name()
	if hud[name] then
		clear_hud(player)
	end
	local ok, err = pcall(update_hud, player)
	if not ok then
		minetest.log("error", "[game_mode] HUD init failed: " .. tostring(err))
	else
		-- Reconnect notice (identity-neutral, only to self)
		if state.match_active then
			minetest.after(0.6, function()
				local p = minetest.get_player_by_name(name)
				if p then
					minetest.chat_send_player(name,
						S("RECONNECT: Neural link re-established. Match #@1 active. HUD synchronized.",
						tostring(state.match_count or 0)))
				end
			end)
		else
			minetest.after(0.6, function()
				local p = minetest.get_player_by_name(name)
				if p then
					minetest.chat_send_player(name,
						S("RECONNECT: Lobby link synchronized. Awaiting initiation sequence."))
				end
			end)
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	clear_hud(player)
end)
