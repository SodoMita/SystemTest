-- ================================================================
-- sl_chatplay — play System Looting entirely through text commands.
--
-- Why: the game's interactions (weapons, pads, spawner GUI, altar
-- rituals, possession, sabotage, matchmaking formspec) are
-- mouse/formspec-driven. This mod adds a `/cp` command language that
-- exposes EVERY role tool as text, plus:
--   * a text "vision" layer (sense / look / roster) — identity-neutral
--     exactly like the in-engine boxman view,
--   * a text HUD/pulse (auto status reports to the event feed),
--   * a headless CONSOLE PLAYER (a botmatch fake-player driven by
--     commands) so an agent can join real matches with no client,
--   * an agent transport: world file inbox (agent_inbox/) and an
--     optional HTTP endpoint.
--
-- Fairness contract (same as engine):
--   * You never see hidden info: other players' teams/phases are not
--     exposed by cp sense/look (only your own). The cp roster mirrors
--     the game's own matchmaking formspec (public info).
--   * Ghost comms stay sealed; cp enforces the ghost allowlist.
--   * Weapon damage, timers, ammo, gates all run through the real
--     sl_weapons / sl_modebase code paths (like botmatch does).
-- ================================================================

local modname = minetest.get_current_modname()

sl_chatplay = rawget(_G, "sl_chatplay") or {}
_G.sl_chatplay = sl_chatplay

sl_chatplay.modname = modname
sl_chatplay.S = (game_mode and game_mode.S) or function(s) return s end
sl_chatplay.match_gen = 0

-- ----------------------------------------------------------------
-- Settings
-- ----------------------------------------------------------------
local function setting_bool(key, default)
	local raw = minetest.settings:get(key)
	if raw == nil then return default end
	return raw == "true" or raw == "1"
end
local function setting_num(key, default)
	return tonumber(minetest.settings:get(key)) or default
end

sl_chatplay.cfg = {
	console = setting_bool("sl_chatplay.console", true),
	console_name = minetest.settings:get("sl_chatplay.console_name") or "cmd_agent",
	move_speed = setting_num("sl_chatplay.move_speed", 4.0), -- botmatch default speed
	pulse_default = setting_num("sl_chatplay.pulse", 0),     -- 0 = off
	mailbox = setting_bool("sl_chatplay.mailbox", true),
	http = setting_bool("sl_chatplay.http", false),
	-- Headless debugging verbs (/cp trace, /cp probe). On by default
	-- because they are the only way to diagnose a missed shot without
	-- a client; set sl_chatplay.debug_verbs = false to hide them.
	debug_verbs = setting_bool("sl_chatplay.debug_verbs", true),
}

-- ----------------------------------------------------------------
-- Event feed (the "chat log" an agent tail as output)
-- ----------------------------------------------------------------
-- Lines: { t = unix epoch, seq = monotonic, who = "ALL"|player name, text = ... }
sl_chatplay.feed = {}
sl_chatplay.feed_max = 400
sl_chatplay.feed_seq = 0

-- Strip Luanti colorize escapes (\027(c@#rrggbb) / \027(T@tag) / resets).
local function plain_text(s)
	s = tostring(s)
	s = s:gsub("\027%(%a@[^)]*%)", "")
	s = s:gsub("\027[A-Za-z]", "")
	return s
end
sl_chatplay.plain_text = plain_text

function sl_chatplay.feed_add(who, text)
	if text == nil or text == "" then return end
	local clean = plain_text(text)
	local last = sl_chatplay.feed[#sl_chatplay.feed]
	if last and last.text == clean and os.time() - last.t < 3 then
		return -- dedupe: chat_send_all and per-player sends both land here
	end
	sl_chatplay.feed_seq = sl_chatplay.feed_seq + 1
	table.insert(sl_chatplay.feed, {
		t = os.time(),
		seq = sl_chatplay.feed_seq,
		who = who,
		text = clean,
	})
	while #sl_chatplay.feed > sl_chatplay.feed_max do
		table.remove(sl_chatplay.feed, 1)
	end
end

-- Capture every chat line the server emits (global + targeted).
-- Wrapping the C bindings from Lua is allowed (minetest is a Lua table).
local orig_chat_send_all = minetest.chat_send_all
minetest.chat_send_all = function(msg, ...)
	local r = orig_chat_send_all(msg, ...)
	sl_chatplay.feed_add("ALL", msg)
	return r
end
local orig_chat_send_player = minetest.chat_send_player
minetest.chat_send_player = function(name, msg, ...)
	local r = orig_chat_send_player(name, msg, ...)
	if name == sl_chatplay.cfg.console_name or name == "" then
		sl_chatplay.feed_add(name == "" and "ALL" or name, msg)
	end
	return r
end

-- Broadcasts from the game go through game_mode.broadcast -> chat_send_all,
-- so the wrapping above captures them.

-- ----------------------------------------------------------------
-- Re-export helper: resolve a player ObjectRef (real or fake).
-- ----------------------------------------------------------------
function sl_chatplay.get_ref(name)
	local p = minetest.get_player_by_name(name)
	return p
end

-- ----------------------------------------------------------------
-- Pulse: periodic auto status reports when enabled (/cp hud on)
-- ----------------------------------------------------------------
sl_chatplay.pulse = { on = sl_chatplay.cfg.pulse_default > 0, every = math.max(3, sl_chatplay.cfg.pulse_default) }
local pulse_accum = 0

minetest.register_globalstep(function(dtime)
	pulse_accum = pulse_accum + dtime
	if pulse_accum < 1 then return end
	pulse_accum = 0
	if not sl_chatplay.pulse.on then return end
	sl_chatplay.pulse.t = (sl_chatplay.pulse.t or 0) + 1
	if sl_chatplay.pulse.t % math.floor(sl_chatplay.pulse.every) ~= 0 then return end
	local p = sl_chatplay.get_ref(sl_chatplay.cfg.console_name)
	if p then
		local ok, err = pcall(function()
			local status = sl_chatplay.cmd_status(p)
			if status then sl_chatplay.feed_add(sl_chatplay.cfg.console_name, "[pulse] " .. status) end
		end)
		if not ok then
			minetest.log("warning", "[sl_chatplay] pulse error: " .. tostring(err))
		end
	end
end)

-- ----------------------------------------------------------------
-- Wire in the console player + docs + commands
-- ----------------------------------------------------------------
dofile(minetest.get_modpath(modname) .. "/console.lua")
dofile(minetest.get_modpath(modname) .. "/sense.lua")
dofile(minetest.get_modpath(modname) .. "/combat.lua")
dofile(minetest.get_modpath(modname) .. "/commands.lua")
dofile(minetest.get_modpath(modname) .. "/mailbox.lua")

-- Join the console player before botmatch's start_run (1 s after mods
-- load) so it is on the roster for ready checks and match insertion.
minetest.register_on_mods_loaded(function()
	-- Re-register "cp" AFTER sl_modebase's ghost-guard wrap so the
	-- designed ghost channels survive (our own phase policy replaces it).
	sl_chatplay.install_cp()
	sl_chatplay.hook_botmatch()
	if sl_chatplay.cfg.console then
		-- auth initializes after mods load; join just after boot but
		-- before botmatch opens its first ready check (+2.5 s).
		minetest.after(1.2, sl_chatplay.console_join_scheduled)
	end
end)

minetest.log("action", "[sl_chatplay] loaded (console=" .. tostring(sl_chatplay.cfg.console)
	.. ", mailbox=" .. tostring(sl_chatplay.cfg.mailbox)
	.. ", http=" .. tostring(sl_chatplay.cfg.http) .. ")")
