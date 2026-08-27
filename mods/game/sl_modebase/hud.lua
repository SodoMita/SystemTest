local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Persistent match HUD (Phase A.3)
-- Identity-neutral by design: it displays match phase, clock, the
-- the player's own phase, and public beacon integrity only.
-- It never renders team names, team colors, or other players'
-- private state, so it cannot leak hidden identity.
-- ================================================================

local hud = {} -- [player_name] = { status = id, vitals = id, beacons = id }
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

	-- Line 2: own phase (private, role-local; single-life design)
	local vitals = ""
	if state.match_active and pl.phase ~= "alive" then
		vitals = "[" .. string.upper(tostring(pl.phase):gsub("_", " ")) .. "]"
	end
	player:hud_change(h.vitals, "text", vitals)

	-- Line 3: beacon integrity. Beacon HP is already public information
	-- (every damage event is broadcast), so this leaks no hidden identity.
	local a_hp = state.teams.beacon_a.hp or 0
	local b_hp = state.teams.beacon_b.hp or 0
	player:hud_change(h.beacons, "text",
		S("CORE A @1", tostring(a_hp)) .. "   " .. S("CORE B @1", tostring(b_hp)))
end

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
	local ok, err = pcall(update_hud, player)
	if not ok then
		minetest.log("error", "[game_mode] HUD init failed: " .. tostring(err))
	end
end)

minetest.register_on_leaveplayer(function(player)
	clear_hud(player)
end)
