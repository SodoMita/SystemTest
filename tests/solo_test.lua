-- ================================================================
-- tests/solo_test.lua
-- Headless end-to-end test for the SINGLEPLAYER Solo Protocol.
-- Loads the REAL aaa_botmatch harness, sl_modebase and sl_solo on the
-- engine stub, then drives a full solo run through the real pipeline:
--
--   harness boot (arena + 6 embodied AI units)
--   /solo_start -> ready check -> countdown -> insertion
--   roster: operator + 3 crew bots (beacon_a) vs 3 rivals (beacon_b)
--   hidden Echo selected from the crew (deterministic via
--   sl_solo.traitor_index)
--   the Simulation's wave director deploys waves
--   the Echo corrupts CORE A (the deduction tell)
--   operator kills a loyal unit -> guilt is logged
--   operator purges the Echo -> solo victory + report + clean reset
--   /solo_start again -> clean second run, /solo_stop aborts
--
-- Run from the repo root:  lua5.1 tests/solo_test.lua
-- (also runs under the lupa Lua runtime: see docs in SINGLEPLAYER.md)
-- ================================================================

local H = dofile("tests/minetest_stub.lua")

local pass_count, fail_count = 0, 0
local function check(cond, label)
	if cond then
		pass_count = pass_count + 1
		print("  [PASS] " .. label)
	else
		fail_count = fail_count + 1
		print("  [FAIL] " .. label)
	end
end

local function section(title)
	print("== " .. title)
end

local function chat_all_contains(part)
	for _, line in ipairs(H.chat_all) do
		if tostring(line):find(part, 1, true) then return true end
	end
	return false
end

local function player_chat_contains(name, part)
	for _, line in ipairs(H.chat_player[name] or {}) do
		if tostring(line):find(part, 1, true) then return true end
	end
	return false
end

-- Register every mod path BEFORE loading, since get_modpath resolves
-- dofile() includes at load time.
H.modpaths["aaa_botmatch"] = "mods/game/aaa_botmatch"
H.modpaths["sl_modebase"] = "mods/game/sl_modebase"
H.modpaths["sl_solo"] = "mods/game/sl_solo"

-- Solo requires the embodied-AI harness config.
H.settings["sl_botmatch.enabled"] = true
H.settings["sl_botmatch.mob_mode"] = true
H.settings["sl_botmatch.auto_start"] = false
H.settings["sl_botmatch.disconnect_test"] = false
H.settings["sl_botmatch.bots"] = "6"
H.settings["sl_botmatch.matches"] = "1"

section("PHASE 1 — boot: harness -> modebase -> solo")
H.current_modname = "aaa_botmatch"
local ok, err = pcall(dofile, "mods/game/aaa_botmatch/init.lua")
check(ok, "aaa_botmatch loads" .. (ok and "" or (" -> " .. tostring(err))))
check(botmatch and botmatch.enabled == true, "harness enabled under stub settings")

H.current_modname = "sl_modebase"
ok, err = pcall(dofile, "mods/game/sl_modebase/init.lua")
check(ok, "sl_modebase loads" .. (ok and "" or (" -> " .. tostring(err))))

H.current_modname = "sl_solo"
ok, err = pcall(dofile, "mods/game/sl_solo/init.lua")
check(ok, "sl_solo loads" .. (ok and "" or (" -> " .. tostring(err))))
check(sl_solo and sl_solo.difficulties and sl_solo.difficulties.standard, "difficulty presets registered")
check(minetest.registered_chatcommands["solo_start"], "/solo_start registered")
check(minetest.registered_chatcommands["solo_stop"], "/solo_stop registered")
check(minetest.registered_tools["sl_solo:expulsion_baton"], "expulsion baton registered")
check(minetest.registered_entities["aaa_botmatch:player_mob"], "mob-mode bodies registered by harness")
check(botmatch.config.disconnect_test == false, "disconnect scenario disabled for solo")

section("PHASE 2 — harness boots the arena and the crew lobby")
H.run_mods_loaded()
check(minetest.registered_entities["aaa_botmatch:player_mob"].sl_solo_badge == true,
	"badge scan installed on mob bodies at mods_loaded")
H.advance(2.5) -- after(1) start_run: hooks game_mode, arena, 6 bots
check(#botmatch.bot_order == 6, "6 AI units connected (found " .. #botmatch.bot_order .. ")")
check(game_mode.state.teams.beacon_a.spawn ~= nil, "arena built: beacon A anchored")
check(game_mode.state.teams.beacon_b.spawn ~= nil, "arena built: beacon B anchored")
check(botmatch.behave ~= nil and botmatch.hooked, "harness hooked into game_mode")
H.advance(0.1) -- first sl_solo tick after behavior.lua exists
check(#H.globalsteps >= 3, "solo/modebase/harness globalsteps registered")

-- Deterministic run: fixed seed + forced Echo index.
math.randomseed(7)
sl_solo.cfg.traitor_index = 1

-- The operator joins the lobby.
local operator = H.new_player("operator")
H.fire_joinplayer(operator)
H.advance(0.5)

section("PHASE 3 — /solo_start: ready check -> insertion -> roster")
local cmd = minetest.registered_chatcommands["solo_start"]
local okmsg = cmd.func("operator", "standard")
check(okmsg, "/solo_start accepts the standard preset")
check(game_mode.state.ready_check.active or game_mode.state.ready_check.countdown_left > 0
	or game_mode.state.match_active, "launch opened the ready check")
check(game_mode.get_player_state("operator").team == "beacon_a", "operator anchored to CORE A team")
H.advance(6.5) -- countdown (5 s) -> insertion
check(game_mode.state.match_active, "match inserted through the real pipeline")
check(sl_solo.state.active, "solo protocol active")
check(game_mode.state.settings.match_duration == 540, "solo owns match duration (standard 540 s)")

local crew_list, rival_list = {}, {}
for _, n in ipairs(botmatch.bot_order) do
	if sl_solo.state.crew[n] then table.insert(crew_list, n)
	elseif sl_solo.state.rivals[n] then table.insert(rival_list, n) end
end
check(#crew_list == 3, "crew of 3 AI units on CORE A (found " .. #crew_list .. ")")
check(#rival_list == 3, "rival crew of 3 on CORE B (found " .. #rival_list .. ")")
check(game_mode.count_team_players("beacon_a") == 4, "beacon_a roster: operator + 3 crew")
check(game_mode.count_team_players("beacon_b") == 3, "beacon_b roster: 3 rivals")

local st = sl_solo.state
check(st.traitor ~= nil and st.crew[st.traitor], "Echo selected from the crew (identity hidden)")
check(st.traitor ~= "operator", "Echo is never the operator")
check(st.designations[st.traitor] ~= nil, "Echo carries a crew designation")
check(st.designations[crew_list[1]] == "UNIT-A", "crew designations assigned in roster order")
check(st.designations[rival_list[1]] == "UNIT-X", "rival designations assigned")

local op_inv = operator:get_inventory()
check(op_inv:contains_item("main", ItemStack("sl_modebase:scanner")), "operator issued the Signal Scanner")
check(op_inv:contains_item("main", ItemStack("sl_solo:expulsion_baton")), "operator issued the expulsion baton")
for _, n in ipairs(botmatch.bot_order) do
	check(game_mode.get_player_state(n).phase == "alive", n .. " inserted alive")
end
check(chat_all_contains("SOLO PROTOCOL ENGAGED"), "protocol announcement broadcast")

section("PHASE 4 — the Simulation deploys waves")
H.advance(40) -- first wave at +35 s
check(st.wave >= 1, "wave 1 fired (count " .. st.wave .. ")")
local monster_spawns = 0
for _, e in ipairs(H.entity_spawns) do
	if e.name == game_mode.MONSTER_NAME or sl_solo.monster_names[e.name] then
		monster_spawns = monster_spawns + 1
	end
end
check(monster_spawns >= 1, "director spawned hostiles via game_mode.spawn_monster (" .. monster_spawns .. ")")
check(chat_all_contains("THE SIMULATION: WAVE"), "wave announcement broadcast")
H.advance(70) -- wave 2 (and changes of the guard)
check(st.wave >= 2, "waves escalate (count " .. st.wave .. ")")

section("PHASE 5 — the Echo corrupts CORE A (the tell)")
-- Isolate the scene: send operator and loyal crew away from CORE A so
-- the Echo's stealth roll always succeeds (deterministic tell), force
-- the sabotage window open (white-box), and watch the marker land.
local traitor = st.traitor
local a_spawn = game_mode.state.teams.beacon_a.spawn
local bpos = { x = a_spawn.x, y = a_spawn.y - 1, z = a_spawn.z }
operator:set_pos({ x = 0, y = 2, z = -8 })
for _, n in ipairs(crew_list) do
	if n ~= traitor then botmatch.bots[n]:set_pos({ x = 0, y = 2, z = 8 }) end
end
botmatch.bots[traitor]:set_pos({ x = a_spawn.x, y = a_spawn.y, z = 2 }) -- within 3 m of the core
st.traitor_next_sabotage = game_mode.now() + 0.6
H.advance(2.5) -- one behavior tick lands inside the open window
check(game_mode.is_sabotaged(bpos), "CORE A corrupted by the hidden Echo")
check(st.traitor_sabotages >= 1, "sabotage booked to the Echo's hidden ledger")
check(chat_all_contains("CORE A INTEGRITY COMPROMISED"), "public corruption signal broadcast")
-- The discoverable marker is the meta field; the infotext is rewritten
-- each corrosion tick by the existing sabotage system (HP readout).
check(minetest.get_meta(bpos):get_int("sl_sabotaged_until") > 0,
	"visible corruption marker applied (repair counterplay live)")
check(not game_mode.is_possessed(bpos), "no possession: rival evil-ghost path suppressed in solo")
-- Corrosion + expiry run through the real sabotage systems.
local hp_before = game_mode.state.teams.beacon_a.hp
H.advance(3)
check(game_mode.state.teams.beacon_a.hp < hp_before, "corrosion ticks the core down")
game_mode.clear_sabotage_at(bpos)

section("PHASE 6 — operator kills a LOYAL unit; the simulation logs the doubt")
local innocent = nil
for _, n in ipairs(crew_list) do
	if n ~= traitor then innocent = n break end
end
operator:set_pos(botmatch.bots[innocent]:get_pos())
botmatch.external_punch(innocent, "operator", 100)
check(game_mode.get_player_state(innocent).phase == "ghost", "loyal unit died into the cloud cage")
check(st.innocent_kills == 1, "guilt ledger counted the loyal kill")
check(player_chat_contains("operator", "that unit was LOYAL"), "operator privately notified of the doubt")
check(st.killer_of[innocent] == "operator", "kill attributed through the real pipeline")

section("PHASE 7 — operator purges the Echo -> SOLO VICTORY")
check(game_mode.state.match_active, "match still live before the purge")
botmatch.external_punch(traitor, "operator", 100)
check(st.traitor_purged, "Echo exposed on death")
check(chat_all_contains("ECHO EXPOSED"), "reveal broadcast")
H.advance(5) -- the 4 s reveal beat -> solo end_match
check(not game_mode.state.match_active, "solo victory ended the match")
check(not st.active, "solo protocol deactivated after the report")
check(chat_all_contains("SOLO PROTOCOL COMPLETE"), "victory report broadcast")
check(st.last_report ~= nil and st.last_report.won == true, "run report stored")
check(#st.wave_mobs == 0, "wave mob registry emptied (simulation withdrew)")

section("PHASE 8 — clean reset allows an immediate second run")
check(game_mode.get_player_state("operator").phase == "alive", "operator normalized after reset")
check(game_mode.state.sabotage == nil or next(game_mode.state.sabotage) == nil, "sabotage purged at reset")
local ok2 = cmd.func("operator", "recruit")
check(ok2, "second run launched (recruit preset)")
check(game_mode.state.ready_check.active or game_mode.state.match_active, "ready check re-opened")
H.advance(7)
check(game_mode.state.match_active and sl_solo.state.active, "second run inserted")
check(sl_solo.state.difficulty == "recruit", "difficulty switch honored")
check(sl_solo.state.wave == 0, "wave director re-armed from zero")
check(game_mode.state.settings.match_duration == 420, "recruit duration applied")

section("PHASE 9 — /solo_stop aborts and reports honestly")
local traitor2 = sl_solo.state.traitor
check(traitor2 ~= nil, "Echo re-selected for the second run")
local stop_cmd = minetest.registered_chatcommands["solo_stop"]
stop_cmd.func("operator")
check(not game_mode.state.match_active, "abort ended the match")
check(not sl_solo.state.active, "abort deactivated the protocol")
check(chat_all_contains("SOLO PROTOCOL FAILED"), "abort reports a failed run (Echo was never named)")

section("PHASE 10 — guards")
local bad = cmd.func("operator", "absurd")
check(bad == false, "unknown difficulty rejected (no state change)")
check(game_mode.state.ready_check.active == false, "rejected launch opened nothing")
local default_ok = cmd.func("operator", "")
check(default_ok, "empty param defaults to the configured difficulty")
H.advance(7)
check(game_mode.state.match_active, "default-difficulty run inserted")
check(sl_solo.state.difficulty == "standard", "default difficulty applied (standard)")
local dup = cmd.func("operator", "recruit")
check(dup == false, "no second run while one is active")
minetest.registered_chatcommands["solo_stop"].func("operator")
check(not game_mode.state.match_active, "cleanup stop works")

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
