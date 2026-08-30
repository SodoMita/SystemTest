-- ================================================================
-- sl_solo — SINGLEPLAYER: "SOLO PROTOCOL"
-- ================================================================
-- One human operator + a crew of identical-looking AI salvage units,
-- inserted through the REAL match pipeline (ready check -> countdown
-- -> insertion -> rules). The Simulation itself plays the Monster
-- Master: scripted horde waves of mode monsters and sl_scary entities
-- escalate against both beacon teams. Hidden among the operator's own
-- crew is THE ECHO — a corrupted unit that sabotages CORE A from
-- inside, loiters, refuses to fight the rival crew, and (late match)
-- starts hunting. Purge the Echo before the clock runs out.
--
-- WHY THE HARNESS DEPENDENCY: identity-ambiguous deception needs
-- players that LOOK like players but are AI. `aaa_botmatch` in mob
-- mode already provides exactly that (boxman bodies, A* pathfinding,
-- damage routed through the real on_punchplayer pipeline, full rule
-- parity). sl_solo is an orchestration layer on top of it, not a
-- second bot system.
--
-- REQUIRED SERVER SETTINGS (see SINGLEPLAYER.md):
--   sl_botmatch.enabled = true
--   sl_botmatch.mob_mode = true
--   sl_botmatch.auto_start = false
--   sl_botmatch.disconnect_test = false
--   sl_botmatch.bots = 6
--
-- FILES:
--   init.lua     — state, commands, HUD, harness hooks, win/loss
--   director.lua — the Simulation: wave composition + spawning
--   traitor.lua  — the Echo: behavior, tells, sabotage, hunt, reveal
--   crew.lua     — roster/designations, chatter, combat reflexes,
--                  monster<->bot damage bridge, badge scan
-- ================================================================

local modname = minetest.get_current_modname()
local S = minetest.get_translator(modname)
local modpath = minetest.get_modpath(modname)

sl_solo = rawget(_G, "sl_solo") or {}
_G.sl_solo = sl_solo

sl_solo.modname = modname
sl_solo.S = S
sl_solo.modpath = modpath

-- ---------------------------------------------------------------
-- Config (server settings; see settingtypes.txt)
-- ---------------------------------------------------------------
sl_solo.cfg = {
	difficulty = minetest.settings:get("sl_solo.difficulty") or "standard",
	badge_scan = minetest.settings:get_bool("sl_solo.badge_scan") ~= false,
	chatter = minetest.settings:get_bool("sl_solo.chatter") ~= false,
	-- 0 = pick the Echo at random; 1..N forces a deterministic pick
	-- (dev/testing hook so runs are reproducible).
	traitor_index = tonumber(minetest.settings:get("sl_solo.traitor_index") or "0") or 0,
}

-- Difficulty presets. times are seconds; sabotage windows bound the
-- Echo's corruption cadence; hunt_after is the fraction of the match
-- clock after which a living Echo starts hunting the crew.
sl_solo.difficulties = {
	recruit = {
		label = "RECRUIT",
		match_duration = 420,
		first_wave = 40,
		wave_interval = 70,
		total_waves = 4,
		sabotage_min = 55,
		sabotage_max = 95,
		hunt_after = 1.1, -- > 1: never hunts
		waves = {
			stalker_base = 1, stalker_growth = 0.5,
			scout_growth = 0.3, scout_from = 3,
			brute_from = 0,
			dredger_from = 0, wraith_from = 0, containment_from = 0,
			cap = 6,
		},
	},
	standard = {
		label = "STANDARD",
		match_duration = 540,
		first_wave = 35,
		wave_interval = 60,
		total_waves = 6,
		sabotage_min = 45,
		sabotage_max = 80,
		hunt_after = 0.7,
		waves = {
			stalker_base = 1, stalker_growth = 0.7,
			scout_growth = 0.4, scout_from = 2,
			brute_from = 3, brute_growth = 0.34,
			dredger_from = 2, wraith_from = 3, containment_from = 5,
			cap = 9,
		},
	},
	nightmare = {
		label = "NIGHTMARE",
		match_duration = 660,
		first_wave = 30,
		wave_interval = 50,
		total_waves = 9,
		sabotage_min = 35,
		sabotage_max = 60,
		hunt_after = 0.45,
		waves = {
			stalker_base = 2, stalker_growth = 0.8,
			scout_growth = 0.5, scout_from = 2,
			brute_from = 2, brute_growth = 0.5,
			dredger_from = 2, wraith_from = 2, containment_from = 4,
			cap = 12,
		},
	},
}

-- Every hostile entity flavor the Simulation can field. Used by the
-- crew's combat reflex, the threat scans, and end-of-match cleanup.
sl_solo.monster_names = {
	["sl_scary:mob"] = true,
	["sl_scary:nerobot"] = true,
	["sl_scary:dredger"] = true,
	["sl_scary:signal_wraith"] = true,
	["sl_scary:containment"] = true,
}

-- ---------------------------------------------------------------
-- Solo state. Active between insertion and the solo report.
-- Everything in here is PRIVATE until a reveal event publishes it.
-- ---------------------------------------------------------------
sl_solo.state = {
	active = false,
	human = nil,
	human_team = nil,
	difficulty = "standard",
	preset = nil,
	-- roster (filled at insertion)
	crew = {},        -- [botname] = true  (operator's loyal-looking units)
	rivals = {},      -- [botname] = true  (beacon_b units)
	designations = {},-- [botname] = "UNIT-A" ...
	-- the Echo (hidden)
	traitor = nil,
	traitor_purged = false,
	traitor_sabotages = 0,
	-- deduction bookkeeping
	innocent_kills = 0,   -- operator kills of loyal crew
	killer_of = {},       -- [victim] = killer name (PvP attribution)
	death_note = {},      -- [victim] = free text for the report
	-- run progress
	wave = 0,
	next_wave_at = 0,
	wave_mobs = {},       -- live ObjectRefs spawned by the director
	flavor_i = 0,
	-- internal
	behaviors = {},       -- [botname] = fn(name, dt) custom behavior
	chatter_at = 0,
	hud_ids = nil,
	last_report = nil,
}

local state = sl_solo.state

function sl_solo.log(msg)
	minetest.log("action", "[sl_solo] " .. msg)
end

function sl_solo.announce(msg)
	game_mode.broadcast(minetest.colorize("#ff66cc", msg))
end

-- Include sub-files (they attach to sl_solo)
dofile(modpath .. "/director.lua")
dofile(modpath .. "/traitor.lua")
dofile(modpath .. "/crew.lua")

-- ---------------------------------------------------------------
-- Harness plumbing. botmatch defines behave / on_match_inserted /
-- attribute_kill at RUNTIME (behavior.lua is dofile'd by start_run
-- about 1 s after load), so the wrappers are installed lazily, once,
-- the first tick after each function exists.
-- ---------------------------------------------------------------
sl_solo.hooks = { behave = false, insert = false, kill = false }

function sl_solo.ensure_hooks()
	local b = rawget(_G, "botmatch")
	if not b or not b.enabled then return end

	if not sl_solo.hooks.behave and type(b.behave) == "function" then
		local orig_behave = b.behave
		b.behave = function(name, dt)
			local st = sl_solo.state
			if st.active and st.behaviors[name] and game_mode.state.match_active then
				local handled = false
				if b.safe then
					-- botmatch.safe returns ok; we need the behavior result,
					-- so invoke directly and keep the pcall semantics.
					local results = { pcall(st.behaviors[name], name, dt) }
					if not results[1] then
						minetest.log("error", "[sl_solo] behavior " .. name .. ": " .. tostring(results[2]))
					else
						handled = results[2] == true
					end
				else
					handled = st.behaviors[name](name, dt) == true
				end
				if handled then return end
			end
			local r = orig_behave(name, dt)
			-- After regular behavior: crew combat reflex vs wave mobs.
			if sl_solo.state.active then
				sl_solo.combat_reflex(name)
			end
			return r
		end
		sl_solo.hooks.behave = true
		sl_solo.log("behavior wrapper installed")
	end

	if not sl_solo.hooks.insert and type(b.on_match_inserted) == "function" then
		local orig_insert = b.on_match_inserted
		b.on_match_inserted = function()
			orig_insert()
			sl_solo.on_inserted()
		end
		sl_solo.hooks.insert = true
	end

	if not sl_solo.hooks.kill and type(b.attribute_kill) == "function" then
		local orig_kill = b.attribute_kill
		b.attribute_kill = function(attacker, victim)
			orig_kill(attacker, victim)
			sl_solo.note_kill(attacker, victim)
		end
		sl_solo.hooks.kill = true
	end
end

-- ---------------------------------------------------------------
-- Insertion: the solo protocol arms itself right after the harness
-- issues kits and roles, inside the REAL start_new_match flow.
-- ---------------------------------------------------------------
function sl_solo.on_inserted()
	local st = sl_solo.state
	local gm = game_mode
	if not gm.state.match_active then return end

	st.active = true
	st.traitor_purged = false
	st.traitor_sabotages = 0
	st.innocent_kills = 0
	st.killer_of = {}
	st.death_note = {}
	st.wave = 0
	st.wave_mobs = {}
	st.flavor_i = 0
	st.behaviors = {}
	st.hud_ids = nil
	st.last_report = nil

	local preset = sl_solo.difficulties[st.difficulty] or sl_solo.difficulties.standard
	st.preset = preset

	-- Roster: every connected bot on the operator's team is crew, the
	-- rest are the rival salvage crew.
	st.crew, st.rivals, st.designations = sl_solo.build_roster(st.human)
	st.human_team = gm.get_player_state(st.human).team or "beacon_a"

	-- Solo doctrine: the dead stay dead. Suppress AI evil-ghost revival
	-- so corruption on CORE A is ALWAYS the Echo's work (a crisp
	-- deduction signal beats ambient chaos). The human operator may
	-- still revive as an evil ghost — that choice remains theirs.
	local b = rawget(_G, "botmatch")
	if b then
		for _, botname in ipairs(b.bot_order) do
			local bot = b.bots[botname]
			if bot and bot.bm then bot.bm.revived_at = -1 end
		end
	end

	-- Pick the Echo and install its custom behavior.
	st.traitor = sl_solo.select_traitor()
	if st.traitor then
		st.behaviors[st.traitor] = sl_solo.traitor_tick
		st.traitor_next_sabotage = game_mode.now() + preset.sabotage_min
			+ math.random(0, math.max(0, preset.sabotage_max - preset.sabotage_min))
		st.hunt_at = preset.hunt_after <= 1
			and (gm.state.match_started_at + preset.match_duration * preset.hunt_after) or nil
		sl_solo.log("echo assigned to " .. tostring(st.traitor) .. " (hidden; difficulty " .. st.difficulty .. ")")
	end

	-- Arm the Simulation's wave director.
	st.next_wave_at = gm.state.match_started_at + preset.first_wave

	-- Operator kit: scanner (detect the corruption) + expulsion baton
	-- (punching a suspect routes through the real combat pipeline).
	local hp = minetest.get_player_by_name(st.human)
	if hp then
		local inv = hp:get_inventory()
		inv:add_item("main", ItemStack("sl_modebase:scanner"))
		inv:add_item("main", ItemStack("sl_solo:expulsion_baton"))
	end

	sl_solo.announce("SOLO PROTOCOL ENGAGED — difficulty " .. preset.label)
	sl_solo.announce("Your salvage unit holds CORE A. One of your own crew is compromised.")
	sl_solo.announce("Purge the Echo before the clock runs out. Trust behavior, not faces.")

	if sl_solo.cfg.chatter then
		st.chatter_at = game_mode.now() + 12 + math.random(0, 15)
	end
end

-- ---------------------------------------------------------------
-- Kill attribution (PvP only; simulation kills have no attacker and
-- are reported as MIA).
-- ---------------------------------------------------------------
function sl_solo.note_kill(attacker, victim)
	local st = sl_solo.state
	if not st.active or not attacker or not victim then return end
	st.killer_of[victim] = attacker
	if attacker == st.human and st.crew[victim] and victim ~= st.traitor then
		st.innocent_kills = st.innocent_kills + 1
		minetest.chat_send_player(st.human, minetest.colorize("#ff5555",
			"OPERATOR NOTE: that unit was LOYAL. The simulation logs your doubt."))
	end
end

-- ---------------------------------------------------------------
-- Death reveals (registered AFTER sl_modebase's handler, so phase
-- transitions have already happened when this runs).
-- ---------------------------------------------------------------
minetest.register_on_dieplayer(function(player)
	local st = sl_solo.state
	if not st.active then return end
	local name = player:get_player_name()

	if name == st.traitor and not st.traitor_purged then
		sl_solo.reveal_traitor_death(name)
	elseif st.crew[name] then
		local desig = st.designations[name] or name
		local killer = st.killer_of[name]
		if killer == st.human then
			-- guilt note already sent via note_kill
		elseif killer then
			game_mode.broadcast(desig .. " signal lost — terminated by another salvager.")
		else
			game_mode.broadcast(desig .. " signal lost — simulation interference.")
		end
	end
end)

-- Operator link lost mid-protocol: settle the match instead of
-- leaving the AI crew playing with itself.
minetest.register_on_leaveplayer(function(player)
	local st = sl_solo.state
	if not st.active then return end
	local name = player:get_player_name()
	if name ~= st.human then return end
	minetest.after(5, function()
		if st.active and game_mode.state.match_active
				and not minetest.get_player_by_name(st.human) then
			game_mode.end_match(nil, "Operator link lost — protocol suspended")
		end
	end)
end)

-- ---------------------------------------------------------------
-- End-of-match: classify the run, clean the Simulation's leftovers,
-- and publish the solo report. sl_solo wraps game_mode.end_match at
-- LOAD time (sl_solo loads after sl_modebase); botmatch's telemetry
-- hook then wraps THIS wrapper, preserving the chain.
-- ---------------------------------------------------------------
local orig_end_match = game_mode.end_match
game_mode.end_match = function(winner, reason)
	local st = sl_solo.state
	local classification = nil
	if st.active then
		classification = sl_solo.classify_end(winner, reason)
	end

	-- The Simulation withdraws its horde (sl_modebase only removes the
	-- shared monster entity; sl_scary mobs are ours to sweep).
	sl_solo.clear_monsters()

	orig_end_match(winner, reason)

	if classification then
		sl_solo.publish_report(classification)
		sl_solo.clear_hud()
		st.active = false
		st.behaviors = {}
		st.traitor = st.traitor_purged and st.traitor or nil
	end
end

function sl_solo.classify_end(winner, reason)
	local st = sl_solo.state
	local preset = st.preset or sl_solo.difficulties.standard
	local echo_desig = st.designations[st.traitor] or "UNKNOWN"
	if st.traitor_purged then
		return {
			verdict = "COMPLETE",
			title = "SOLO PROTOCOL COMPLETE",
			detail = "The Echo (" .. echo_desig .. ") was purged from the crew.",
			won = true,
		}
	end
	local detail
	if reason and (reason:find("abort") or reason:find("Operator link lost")) then
		detail = "Protocol aborted — the Echo (" .. echo_desig .. ") was never named."
	elseif winner and winner ~= st.human_team and state.teams[winner] then
		detail = "CORE A fell with the Echo (" .. echo_desig .. ") still hidden."
	elseif winner == st.human_team then
		detail = "The rival crew is gone — and the Echo (" .. echo_desig ..
			") walked out amid the carnage."
	else
		detail = "Time expired with the Echo (" .. echo_desig .. ") at large."
	end
	return { verdict = "FAILED", title = "SOLO PROTOCOL FAILED", detail = detail, won = false }
end

function sl_solo.publish_report(c)
	local st = sl_solo.state
	local preset = st.preset or sl_solo.difficulties.standard
	sl_solo.announce("== " .. c.title .. " ==")
	sl_solo.announce(c.detail)
	sl_solo.announce(string.format(
		"Waves survived: %d/%d | Echo sabotages: %d | Loyal units lost to your hand: %d",
		st.wave, preset.total_waves, st.traitor_sabotages, st.innocent_kills))
	if c.won then
		sl_solo.announce("Run again with /solo_start " .. sl_solo.next_difficulty_hint(st.difficulty))
	end
	st.last_report = {
		verdict = c.verdict, won = c.won, detail = c.detail,
		waves = st.wave, difficulty = st.difficulty,
		sabotages = st.traitor_sabotages, innocent_kills = st.innocent_kills,
	}
end

function sl_solo.next_difficulty_hint(current)
	if current == "recruit" then return "standard" end
	if current == "standard" then return "nightmare" end
	return "nightmare"
end

-- ---------------------------------------------------------------
-- Operator HUD: solo progress line (top center, below the match HUD)
-- ---------------------------------------------------------------
function sl_solo.build_hud(player)
	local st = sl_solo.state
	if not st.hud_ids then st.hud_ids = {} end
	st.hud_ids.solo = player:hud_add({
		hud_elem_type = "text",
		position = { x = 0.5, y = 0.145 },
		offset = { x = 0, y = 0 },
		alignment = { x = 0, y = 1 },
		scale = { x = 400, y = 18 },
		text = "",
		number = 0xff66cc,
	})
end

function sl_solo.clear_hud()
	local st = sl_solo.state
	local player = st.human and minetest.get_player_by_name(st.human) or nil
	if player and st.hud_ids and st.hud_ids.solo then
		player:hud_remove(st.hud_ids.solo)
	end
	st.hud_ids = nil
end

function sl_solo.hud_step()
	local st = sl_solo.state
	if not st.human then return end
	-- Bots carry fake HUDs; never spend effort on them.
	if rawget(_G, "botmatch") and botmatch.bots[st.human] then return end
	local player = minetest.get_player_by_name(st.human)
	if not player then return end
	if not st.hud_ids then sl_solo.build_hud(player) end

	local preset = st.preset or sl_solo.difficulties.standard
	local left = math.max(0, math.floor(st.next_wave_at - game_mode.now()))
	local hostiles = sl_solo.count_monsters()
	local crew_alive, crew_total = 0, 1
	for botname in pairs(st.crew) do
		crew_total = crew_total + 1
		local pl = game_mode.get_player_state(botname)
		if pl.phase == "alive" and not pl.eliminated then
			crew_alive = crew_alive + 1
		end
	end
	local human_pl = game_mode.get_player_state(st.human)
	if human_pl.phase == "alive" and not human_pl.eliminated then
		crew_alive = crew_alive + 1
	end
	local waves_left = preset.total_waves > 0 and (st.wave .. "/" .. preset.total_waves) or tostring(st.wave)
	local echo_status = st.traitor_purged and "PURGED" or "UNKNOWN"
	player:hud_change(st.hud_ids.solo, "text", string.format(
		"SOLO %s | WAVE %s | NEXT WAVE %ds | HOSTILES %d | CREW %d/%d | ECHO: %s",
		(preset.label or "STANDARD"), waves_left, left, hostiles, crew_alive, crew_total, echo_status))
end

-- ---------------------------------------------------------------
-- Main tick
-- ---------------------------------------------------------------
local accum = 0
minetest.register_globalstep(function(dtime)
	accum = accum + dtime
	if accum < 0.5 then return end
	local dt = accum
	accum = 0

	sl_solo.ensure_hooks()
	sl_solo.install_punch_bridges()

	local st = sl_solo.state
	if not st.active or not game_mode.state.match_active then return end

	sl_solo.director_step(dt)
	if sl_solo.cfg.chatter then
		sl_solo.chatter_step(dt)
	end
	sl_solo.hud_step()

	-- CORE A destroyed ends the run as a loss via the normal beacon
	-- destruction flow; nothing solo-specific to poll here.
end)

-- ---------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------
local function harness_status()
	local b = rawget(_G, "botmatch")
	if not b or not b.enabled then
		return nil, "the AI harness is disabled. Add to server settings:\n" ..
			"  sl_botmatch.enabled = true\n" ..
			"  sl_botmatch.mob_mode = true\n" ..
			"  sl_botmatch.auto_start = false\n" ..
			"  sl_botmatch.disconnect_test = false\n" ..
			"  sl_botmatch.bots = 6\nthen restart the world. See SINGLEPLAYER.md."
	end
	if not b.config.mob_mode then
		return nil, "the AI harness needs sl_botmatch.mob_mode = true (embodied crew)."
	end
	if type(b.behave) ~= "function" or #b.bot_order < 1 then
		return nil, "the harness is still materializing the arena; try again in a few seconds."
	end
	if #b.bot_order < 4 then
		return nil, "solo protocol needs at least 4 AI units (sl_botmatch.bots = 6 recommended); found "
			.. #b.bot_order .. "."
	end
	return b
end

minetest.register_chatcommand("solo_start", {
	description = "Start a singleplayer Solo Protocol run (params: recruit|standard|nightmare)",
	params = "[recruit|standard|nightmare]",
	func = function(name, param)
		local st = sl_solo.state
		if st.active then
			return false, "A Solo Protocol run is already active (/solo_stop to abort)."
		end
		if game_mode.state.match_active then
			return false, "A regular match is already running."
		end
		if not minetest.get_player_by_name(name) then
			return false, "Operator must be connected."
		end
		local b, err = harness_status()
		if not b then
			return false, "Solo Protocol unavailable: " .. err
		end

		-- (portable trim: Luanti ships string.trim but the headless stub
		-- and plain Lua do not)
		local diff = (param ~= "" and param ~= nil) and param:gsub("^%s*(.-)%s*$", "%1") or sl_solo.cfg.difficulty
		if not sl_solo.difficulties[diff] then
			return false, "Unknown difficulty '" .. tostring(diff) ..
				"'. Valid: recruit, standard, nightmare."
		end

		local preset = sl_solo.difficulties[diff]
		st.difficulty = diff
		st.human = name

		-- The operator always anchors CORE A so the deduction cast is stable.
		game_mode.get_player_state(name).team = "beacon_a"

		-- Solo owns the match configuration for this run.
		game_mode.state.settings.auto_start = false
		game_mode.state.settings.match_duration = preset.match_duration
		game_mode.state.win_conditions.elimination = true
		game_mode.state.win_conditions.objective = false

		local ok, msg = game_mode.begin_ready_check(name)
		if not ok then
			return false, msg or "ready check failed"
		end
		-- The operator authored the launch: auto-confirm their own slot.
		game_mode.mark_ready(name, true)
		sl_solo.announce("SOLO PROTOCOL: insertion sequence armed (" .. preset.label .. ").")
		sl_solo.log("operator " .. name .. " launched a " .. diff .. " solo protocol")
		return true
	end,
})

minetest.register_chatcommand("solo_stop", {
	description = "Abort the active Solo Protocol run",
	func = function(name)
		local st = sl_solo.state
		if not st.active and not game_mode.state.match_active then
			return false, "No run is active."
		end
		game_mode.end_match(nil, "Solo Protocol aborted by " .. name)
		return true
	end,
})

minetest.register_chatcommand("solo_status", {
	description = "Solo Protocol status (no hidden information is ever shown)",
	func = function(name)
		local st = sl_solo.state
		if not st.active then
			local last = st.last_report
			if last then
				return true, ("Last run: %s (%s) — waves %d, echo sabotages %d.")
					:format(last.verdict, last.difficulty, last.waves, last.sabotages)
			end
			return true, "No run active. /solo_start [recruit|standard|nightmare]"
		end
		local preset = st.preset or sl_solo.difficulties.standard
		local parts = {
			"ACTIVE (" .. preset.label .. ")",
			"wave " .. st.wave .. "/" .. preset.total_waves,
			"next in " .. math.max(0, math.floor(st.next_wave_at - game_mode.now())) .. "s",
			"hostiles " .. sl_solo.count_monsters(),
			"echo: " .. (st.traitor_purged and "PURGED" or "at large"),
		}
		return true, "Solo Protocol: " .. table.concat(parts, " | ")
	end,
})

minetest.register_chatcommand("solo_help", {
	description = "How to play the Solo Protocol",
	func = function()
		return true, table.concat({
			"SOLO PROTOCOL — one of your own crew is the Echo.",
			"1. /solo_start [recruit|standard|nightmare]",
			"2. Survive the Simulation's waves; defend CORE A (rival crew holds CORE B).",
			"3. Watch your crew: the Echo corrupts CORE A from inside, loiters,",
			"   avoids combat, flees hordes early — and hunts late.",
			"4. Right-click a unit nearby to prox-scan its designation.",
			"5. Punch a suspect four times with the expulsion baton to purge it.",
			"   Purge the Echo -> win. Kill a loyal unit -> the simulation logs your doubt.",
			"Signal Scanner sweeps corruption; the dead stay dead; faces tell you nothing.",
		}, "\n")
	end,
})

minetest.register_on_mods_loaded(function()
	local b = rawget(_G, "botmatch")
	if b and b.enabled then
		-- The soak harness must not schedule its own matches underneath
		-- the solo protocol, and a mid-run disconnect scenario would
		-- fake a "vanished crew member" tell.
		b.config.disconnect_test = false
		if b.config.mob_mode then
			sl_solo.install_badge_scan()
		end
		sl_solo.log("harness detected — solo protocol online")
	else
		sl_solo.log("harness not enabled — commands will explain setup (/solo_help)")
	end
	-- The Simulation borrows the shared monster catalog for flavor
	-- variants; register sl_scary's entities as known hostiles too.
	sl_solo.monster_names[game_mode.MONSTER_NAME] = true
end)

-- Operator tool: a plain, readable melee option so purging a suspect
-- is a decision (4 hits), not an accident (fist chip damage).
minetest.register_tool(modname .. ":expulsion_baton", {
	description = S("Expulsion Baton\n(Purge protocol: four strikes end a unit)"),
	inventory_image = "default_stick.png^[colorize:#ff66cc:120",
	tool_capabilities = {
		full_punch_interval = 0.9,
		max_drop_level = 1,
		damage_groups = { fleshy = 6 },
	},
	sound = { breaks = "default_tool_breaks" },
	groups = { disable_repair = 1 },
})
