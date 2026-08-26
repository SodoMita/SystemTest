-- ================================================================
-- aaa_botmatch — headless soak-test harness for System Looting.
--
-- WHY THE aaa_ PREFIX: Luanti sorts mods alphabetically. This mod
-- must load BEFORE every other mod so it can wrap the callback
-- registration functions (register_on_dieplayer, ...) and collect
-- every handler any mod registers. When a simulated player dies,
-- punches, chats, or respawns, the harness replays the collected
-- handlers exactly like the engine would — so sl_modebase's real
-- match logic runs unmodified.
--
-- INERT UNLESS ENABLED: everything is gated behind the setting
--   sl_botmatch.enabled = true
-- so normal servers never load any of this behavior.
--
-- TELEMETRY: writes <world>/botmatch_stats.json after every match
-- and at run end. Lua errors triggered by simulated play are
-- captured (pcall) into stats.bugs and logged as
-- "[botmatch][BUG] ..." lines, which the soak driver harvests.
-- ================================================================

local modname = minetest.get_current_modname()

botmatch = rawget(_G, "botmatch") or {}
_G.botmatch = botmatch

botmatch.modpath = minetest.get_modpath(modname)
botmatch.enabled = minetest.settings:get_bool("sl_botmatch.enabled")

if not botmatch.enabled then
	minetest.log("action", "[botmatch] disabled (set sl_botmatch.enabled = true to run soak tests)")
	return
end

botmatch.config = {
	bots = tonumber(minetest.settings:get("sl_botmatch.bots") or "4") or 4,
	matches = tonumber(minetest.settings:get("sl_botmatch.matches") or "3") or 3,
	seed = tonumber(minetest.settings:get("sl_botmatch.seed") or "20260827") or 20260827,
	match_duration = tonumber(minetest.settings:get("sl_botmatch.match_duration") or "120") or 120,
	lives = tonumber(minetest.settings:get("sl_botmatch.lives") or "3") or 3,
	bot_speed = tonumber(minetest.settings:get("sl_botmatch.bot_speed") or "4") or 4,
	attack_interval = tonumber(minetest.settings:get("sl_botmatch.attack_interval") or "2.5") or 2.5,
	inter_match_delay = tonumber(minetest.settings:get("sl_botmatch.inter_match_delay") or "4") or 4,
	combat_damage = tonumber(minetest.settings:get("sl_botmatch.combat_damage") or "5") or 5,
	disconnect_test = minetest.settings:get_bool("sl_botmatch.disconnect_test")
		or minetest.settings:get("sl_botmatch.disconnect_test") == nil,
}

math.randomseed(botmatch.config.seed)

botmatch.bots = {}
botmatch.bot_order = {}
botmatch.connected = {}
botmatch.callbacks = {
	dieplayer = {}, respawnplayer = {}, punchplayer = {},
	chat_message = {}, punchnode = {}, joinplayer = {}, leaveplayer = {},
}
botmatch.bugs = {}
botmatch.match_index = 0
botmatch.current = nil
botmatch.summon_in_progress = false
botmatch.finished = false

botmatch.stats = {
	seed = botmatch.config.seed,
	matches_requested = botmatch.config.matches,
	matches_completed = 0,
	engine = minetest.get_version().string,
	started_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	matches = {},
}

-- ================================================================
-- Callback interception (must run before other mods register)
-- ================================================================
local intercepted = {
	dieplayer = "register_on_dieplayer",
	respawnplayer = "register_on_respawnplayer",
	punchplayer = "register_on_punchplayer",
	chat_message = "register_on_chat_message",
	punchnode = "register_on_punchnode",
	joinplayer = "register_on_joinplayer",
	leaveplayer = "register_on_leaveplayer",
}
for kind, register_name in pairs(intercepted) do
	local original = minetest[register_name]
	if original then
		minetest[register_name] = function(fn, ...)
			table.insert(botmatch.callbacks[kind], fn)
			return original(fn, ...)
		end
	end
end

-- Route player lookups through the bot registry.
local engine_get_player_by_name = minetest.get_player_by_name
minetest.get_player_by_name = function(name)
	return botmatch.bots[name] or engine_get_player_by_name(name)
end

local engine_get_connected_players = minetest.get_connected_players
minetest.get_connected_players = function()
	local list = engine_get_connected_players()
	for _, n in ipairs(botmatch.connected) do
		if botmatch.bots[n] then
			table.insert(list, botmatch.bots[n])
		end
	end
	return list
end

-- Engine player information lookup: return a synthetic modern client
-- record for bots so builtin HUD code (minimap gating etc.) works.
local engine_get_player_information = minetest.get_player_information
minetest.get_player_information = function(name)
	if botmatch.bots[name] then
		return {
			protocol_version = 44,
			formspec_version = 4,
			lang_code = "en",
			major = 5, minor = 10, patch = 0,
			version_string = "botmatch",
			address = "127.0.0.1",
			ip_version = 4,
			connection_time = 0,
		}
	end
	return engine_get_player_information(name)
end

-- ================================================================
-- Safe invocation + bug harvesting
-- ================================================================
function botmatch.safe(context, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		table.insert(botmatch.bugs, {
			context = context,
			error = tostring(err),
			match = botmatch.match_index,
			t = minetest.get_us_time() / 1000000,
		})
		minetest.log("error", "[botmatch][BUG] " .. context .. ": " .. tostring(err))
	end
	return ok
end

-- Replay collected handlers like the engine does. For punchplayer and
-- chat_message a non-nil return short-circuits (cancels), matching
-- engine semantics.
function botmatch.fire(kind, ...)
	local canceled = false
	for _, fn in ipairs(botmatch.callbacks[kind]) do
		local results = { pcall(fn, ...) }
		if not results[1] then
			table.insert(botmatch.bugs, {
				context = "on_" .. kind,
				error = tostring(results[2]),
				match = botmatch.match_index,
				t = minetest.get_us_time() / 1000000,
			})
			minetest.log("error", "[botmatch][BUG] on_" .. kind .. ": " .. tostring(results[2]))
		elseif results[2] ~= nil and (kind == "punchplayer" or kind == "chat_message") then
			canceled = true
		end
	end
	return canceled
end

function botmatch.is_connected(name)
	for _, n in ipairs(botmatch.connected) do
		if n == name then return true end
	end
	return false
end

-- ================================================================
-- Death / kill accounting
-- ================================================================
function botmatch.on_bot_lethal(bot)
	local name = bot:get_player_name()
	bot.bm.kit = false -- ritual kit drops with the body
	botmatch.record_death(name)
	botmatch.fire("dieplayer", bot, { type = "punch" })
	-- Engine would show the respawn screen; simulate the delay.
	minetest.after(2, function()
		bot.dead = false
		bot._hp = 1 -- respawn handlers (spawn_player) restore full HP
		botmatch.fire("respawnplayer", bot)
		-- Fixed starting equipment is re-issued every life, so the ritual
		-- kit returns with its designated carrier after respawn.
		if bot.bm.carrier and game_mode.state.match_active
				and game_mode.get_player_state(bot:get_player_name()).phase == "alive" then
			local inv = bot:get_inventory()
			inv:add_item("main", ItemStack("sl_modebase:ritual_ashen_relic"))
			inv:add_item("main", ItemStack("sl_modebase:ritual_soul_shard"))
			inv:add_item("main", ItemStack("sl_modebase:ritual_signal_ink"))
			bot.bm.kit = true
		end
	end)
end

function botmatch.attribute_kill(attacker, victim)
	local m = botmatch.current
	if not m then return end
	local ab = m.bots[attacker]
	if ab then
		ab.kills = ab.kills + 1
		local ateam = game_mode.get_player_state(attacker).team
		if ateam and m.teams[ateam] then m.teams[ateam].kills = m.teams[ateam].kills + 1 end
	end
	local vb = m.bots[victim]
	if vb then
		local vteam = game_mode.get_player_state(victim).team
		if vteam and m.teams[vteam] then m.teams[vteam].deaths = m.teams[vteam].deaths + 1 end
	end
end

function botmatch.record_death(name)
	local m = botmatch.current
	if not m or not m.bots[name] then return end
	m.bots[name].deaths = m.bots[name].deaths + 1
	m.bots[name].lives_used = m.bots[name].lives_used + 1
end

function botmatch.record_event(key, amount)
	local m = botmatch.current
	if m then m.events[key] = (m.events[key] or 0) + (amount or 1) end
end

function botmatch.record_bot_flag(name, flag)
	local m = botmatch.current
	if m and m.bots[name] then m.bots[name][flag] = true end
end

function botmatch.record_beacon_damage(team_id, amount, attacker)
	local m = botmatch.current
	if not m or not m.teams[team_id] then return end
	amount = amount or 0
	local tdef = game_mode.state.teams[team_id]
	local hp_before = (tdef and tdef.hp) or 0
	m.teams[team_id].damage_taken = m.teams[team_id].damage_taken + amount
	if attacker and m.bots[attacker] then
		local ateam = game_mode.get_player_state(attacker).team
		if ateam and m.teams[ateam] then
			m.teams[ateam].damage_dealt = m.teams[ateam].damage_dealt + amount
		end
	end
	if hp_before > 0 and hp_before - amount <= 0 then
		m.events.beacon_destructions = m.events.beacon_destructions + 1
	end
end

-- ================================================================
-- Hook the game_mode API (deferred: game_mode loads after this mod)
-- ================================================================
function botmatch.hook_game_mode()
	if botmatch.hooked or not rawget(_G, "game_mode") then return end
	botmatch.hooked = true
	local gm = game_mode

	local orig_end = gm.end_match
	gm.end_match = function(winner, reason)
		if gm.state.match_active then
			botmatch.finish_match(winner, reason)
		end
		orig_end(winner, reason)
		botmatch.schedule_next()
	end

	local orig_damage = gm.damage_beacon
	gm.damage_beacon = function(team_id, amount, attacker, silent)
		botmatch.record_beacon_damage(team_id, amount, attacker)
		orig_damage(team_id, amount, attacker, silent)
	end
end

-- ================================================================
-- Run lifecycle
-- ================================================================
function botmatch.start_run()
	if not rawget(_G, "game_mode") then
		minetest.log("error", "[botmatch][BUG] start_run: game_mode not loaded")
		return
	end
	botmatch.hook_game_mode()

	local state = game_mode.state
	state.settings.lives = botmatch.config.lives
	state.settings.match_duration = botmatch.config.match_duration
	state.settings.mm_auto_assign = false -- deterministic roster
	state.win_conditions.elimination = true

	dofile(botmatch.modpath .. "/behavior.lua")

	botmatch.build_arena()
	botmatch.spawn_bots()

	minetest.after(1.5, botmatch.next_match)
end

function botmatch.spawn_bots()
	local fp = dofile(botmatch.modpath .. "/fake_player.lua")
	local names = { "bot_alpha", "bot_beta", "bot_gamma", "bot_delta", "bot_epsilon", "bot_zeta" }
	for i = 1, math.min(botmatch.config.bots, #names) do
		local bot = fp.new(names[i])
		botmatch.bots[names[i]] = bot
		table.insert(botmatch.bot_order, names[i])
		table.insert(botmatch.connected, names[i])
		botmatch.fire("joinplayer", bot)
	end
	minetest.log("action", "[botmatch] " .. #botmatch.bot_order .. " simulated players connected")
end

function botmatch.next_match()
	if botmatch.finished then return end
	if botmatch.match_index >= botmatch.config.matches then
		botmatch.finish_run()
		return
	end
	botmatch.match_index = botmatch.match_index + 1

	-- Fresh per-match telemetry skeleton.
	local bots_stats = {}
	for _, name in ipairs(botmatch.bot_order) do
		local pl = game_mode.get_player_state(name)
		bots_stats[name] = {
			team = pl.team or "?", kills = 0, deaths = 0, lives_used = 0,
			revived_evil = false, final_phase = "?",
		}
	end
	botmatch.current = {
		id = botmatch.match_index,
		started = minetest.get_us_time() / 1000000,
		winner = nil, reason = nil, duration_s = nil,
		teams = {
			beacon_a = { kills = 0, deaths = 0, damage_dealt = 0, damage_taken = 0, hp_end = 0 },
			beacon_b = { kills = 0, deaths = 0, damage_dealt = 0, damage_taken = 0, hp_end = 0 },
		},
		bots = bots_stats,
		events = {
			ghost_summons = 0, offers = 0, revivals = 0,
			sabotages = 0, repairs = 0, disconnects = 0, beacon_destructions = 0,
		},
	}
	botmatch.summon_in_progress = false

	local ok, err = game_mode.begin_ready_check("botmatch")
	if not ok then
		table.insert(botmatch.bugs, { context = "ready_check", error = tostring(err) })
		minetest.log("error", "[botmatch][BUG] ready_check: " .. tostring(err))
		minetest.after(5, botmatch.next_match)
		return
	end
	for _, name in ipairs(botmatch.connected) do
		game_mode.mark_ready(name)
	end
	local countdown = game_mode.state.settings.countdown or 5
	minetest.after(countdown + 1.5, botmatch.on_match_inserted)
end

function botmatch.schedule_next()
	if botmatch.finished then return end
	if botmatch.match_index >= botmatch.config.matches then
		minetest.after(1, botmatch.finish_run)
	else
		minetest.after(botmatch.config.inter_match_delay, botmatch.next_match)
	end
end

function botmatch.finish_match(winner, reason)
	local m = botmatch.current
	if not m then return end
	local state = game_mode.state

	m.duration_s = (minetest.get_us_time() / 1000000) - m.started
	if winner == "beacons" then
		m.winner = "beacons"
	elseif winner and state.teams[winner] then
		m.winner = winner
	else
		m.winner = "draw"
	end
	m.reason = tostring(reason or "")

	-- Snapshot finals BEFORE sl_modebase's clean reset normalizes phases.
	for name, bs in pairs(m.bots) do
		local pl = game_mode.get_player_state(name)
		bs.final_phase = pl.phase
		bs.team = pl.team or bs.team
	end
	for _, team_id in ipairs({ "beacon_a", "beacon_b" }) do
		m.teams[team_id].hp_end = math.max(0, state.teams[team_id].hp or 0)
	end

	table.insert(botmatch.stats.matches, m)
	botmatch.stats.matches_completed = #botmatch.stats.matches
	botmatch.current = nil
	botmatch.write_stats()
	minetest.log("action", string.format("[botmatch] match %d complete: winner=%s duration=%.1fs events=[summons=%d revivals=%d sabotages=%d repairs=%d disconnects=%d]",
		m.id, m.winner, m.duration_s, m.events.ghost_summons, m.events.revivals,
		m.events.sabotages, m.events.repairs, m.events.disconnects))
end

local function compute_aggregate()
	local matches = botmatch.stats.matches
	local agg = {
		matches = #matches,
		win_rate = { beacon_a = 0, beacon_b = 0, draw = 0, beacons = 0 },
		avg_duration_s = 0,
		kills_total = 0, deaths_total = 0,
		lives_used_total = 0,
		avg_beacon_damage_taken = 0,
		events = { ghost_summons = 0, offers = 0, revivals = 0, sabotages = 0,
			repairs = 0, disconnects = 0, beacon_destructions = 0 },
	}
	if #matches == 0 then return agg end
	local dur_sum, dmg_sum = 0, 0
	for _, m in ipairs(matches) do
		agg.win_rate[m.winner] = (agg.win_rate[m.winner] or 0) + 1
		dur_sum = dur_sum + (m.duration_s or 0)
		for k, v in pairs(m.events) do agg.events[k] = (agg.events[k] or 0) + v end
		for _, team_id in ipairs({ "beacon_a", "beacon_b" }) do
			dmg_sum = dmg_sum + m.teams[team_id].damage_taken
		end
		for _, bs in pairs(m.bots) do
			agg.kills_total = agg.kills_total + bs.kills
			agg.deaths_total = agg.deaths_total + bs.deaths
			agg.lives_used_total = agg.lives_used_total + bs.lives_used
		end
	end
	for k in pairs(agg.win_rate) do
		agg.win_rate[k] = agg.win_rate[k] / #matches
	end
	agg.avg_duration_s = dur_sum / #matches
	agg.avg_beacon_damage_taken = dmg_sum / (#matches * 2)
	-- Side bias: positive favors beacon_a. A balanced mode trends to 0.
	agg.side_bias = (agg.win_rate.beacon_a or 0) - (agg.win_rate.beacon_b or 0)
	return agg
end

function botmatch.finish_run()
	if botmatch.finished then return end
	botmatch.finished = true
	botmatch.stats.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
	botmatch.stats.aggregate = compute_aggregate()
	botmatch.stats.bugs = botmatch.bugs
	botmatch.write_stats()
	minetest.log("action", string.format("[botmatch] RUN COMPLETE: %d/%d matches, %d bug events. Stats written to botmatch_stats.json",
		botmatch.stats.matches_completed, botmatch.config.matches, #botmatch.bugs))
end

-- ================================================================
-- Minimal JSON encoder + atomic stats writer
-- ================================================================
local function json_escape(s)
	return (tostring(s):gsub('[%c"\\]', function(c)
		local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
		return map[c] or string.format("\\u%04x", c:byte())
	end))
end

local function is_array(t)
	local n = 0
	for k in pairs(t) do
		n = n + 1
		if type(k) ~= "number" then return false end
	end
	return n == #t
end

local function json_encode(v)
	local tv = type(v)
	if tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if math.floor(v) == v and math.abs(v) < 2 ^ 52 then return string.format("%d", v) end
		return string.format("%.4f", v)
	elseif tv == "boolean" then
		return v and "true" or "false"
	elseif tv == "string" then
		return '"' .. json_escape(v) .. '"'
	elseif tv == "table" then
		if is_array(v) then
			local parts = {}
			for _, item in ipairs(v) do table.insert(parts, json_encode(item)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local parts = {}
		for _, k in ipairs(keys) do
			table.insert(parts, '"' .. json_escape(k) .. '":' .. json_encode(v[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function botmatch.write_stats()
	local path = minetest.get_worldpath() .. "/botmatch_stats.json"
	local payload = botmatch.stats
	payload.bugs = botmatch.bugs
	local f = io.open(path .. ".tmp", "w")
	if not f then
		minetest.log("error", "[botmatch][BUG] cannot write stats file: " .. path)
		return
	end
	f:write(json_encode(payload))
	f:close()
	os.rename(path .. ".tmp", path)
end

-- ================================================================
-- Behavior tick
-- ================================================================
local tick_accum = 0
minetest.register_globalstep(function(dtime)
	if botmatch.finished then return end
	botmatch.hook_game_mode()
	tick_accum = tick_accum + dtime
	if tick_accum < 0.5 then return end
	local dt = tick_accum
	tick_accum = 0

	if rawget(_G, "game_mode") and game_mode.state.match_active and botmatch.behave then
		-- Round-robin action order: a fixed iteration order would give the
		-- first bot a systematic first-strike advantage (measurable side bias).
		botmatch.tick_n = (botmatch.tick_n or 0) + 1
		local n = #botmatch.bot_order
		for i = 0, n - 1 do
			local name = botmatch.bot_order[(botmatch.tick_n + i - 1) % n + 1]
			if botmatch.is_connected(name) then
				botmatch.safe("behavior:" .. name, botmatch.behave, name, dt)
			end
		end
	end
end)

minetest.register_on_mods_loaded(function()
	minetest.log("action", string.format(
		"[botmatch] soak harness ONLINE: %d bots, %d matches, seed %d",
		botmatch.config.bots, botmatch.config.matches, botmatch.config.seed))
	minetest.after(1, botmatch.start_run)
end)
