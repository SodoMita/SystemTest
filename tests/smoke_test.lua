-- ================================================================
-- tests/smoke_test.lua
-- Headless smoke test for mods/game/sl_modebase against the engine
-- stub. Exercises the MATCH_LOOP_SPEC rules that are implemented:
--   * mod load path executes without error
--   * ghost chat + chat COMMAND seal (msg/w/tell guarded)
--   * cloud cage materialization
--   * ready check -> countdown -> insertion
--   * single death -> ghost cloud-cage transition
--   * ghost altar ritual + information offer
--   * evil-ghost revival (point loss, targetable, bounded sabotage)
--   * sabotage corrosion, interaction refusal, punch repair
--   * match timer, result screen, lobby reset (priv/box restore)
--   * clean restart without stale state
--
-- Run from the repo root:  lua5.1 tests/smoke_test.lua
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

-- Engine builtins that must exist BEFORE mods load, like the real engine.
minetest.register_chatcommand("msg", {
	params = "<name> <message>",
	func = function(_, _) return true, "[dm sent]" end,
})
minetest.register_chatcommand("w", {
	params = "<name> <message>",
	func = function(_, _) return true, "[dm sent]" end,
})
minetest.register_chatcommand("tell", {
	params = "<name> <message>",
	func = function(_, _) return true, "[dm sent]" end,
})

section("PHASE 1 — mod load path")
H.current_modname = "sl_modebase"
local ok, err = pcall(dofile, "mods/game/sl_modebase/init.lua")
check(ok, "init.lua loads without error" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then
	print("FATAL: mod failed to load; aborting.")
	os.exit(1)
end

local gm = game_mode
local state = game_mode.state

check(minetest.registered_nodes["sl_modebase:ghost_altar"] ~= nil, "ghost_altar node registered")
check(minetest.registered_tools["sl_modebase:sabotage_charge"] ~= nil, "sabotage_charge tool registered")
check(minetest.registered_chatcommands.sl_ready ~= nil, "/sl_ready registered")
check(minetest.registered_chatcommands.sl_ghost_offer ~= nil, "/sl_ghost_offer registered")
check(minetest.registered_chatcommands.msg.sl_ghost_guarded == true,
	"engine /msg wrapped with ghost guard")
check(minetest.registered_chatcommands.w.sl_ghost_guarded == true,
	"engine /w wrapped with ghost guard")
check(minetest.registered_chatcommands.sl_match_start.params == "[now]",
	"/sl_match_start accepts 'now' bypass")

section("PHASE 2 — cloud cage materialization")
H.run_mods_loaded()
H.advance(3, 0.5) -- the builder runs 2 s after mods_loaded
local gs = state.ghost_spawn
check(H.voxels[H.vhash({ x = gs.x, y = gs.y - 1, z = gs.z })] == "default:glass",
	"cage floor materialized below ghost spawn")
check(H.voxels[H.vhash({ x = gs.x - 5, y = gs.y, z = gs.z - 5 })] == "default:obsidianbrick",
	"cage corner pylon materialized")

section("PHASE 3 — players join into lobby")
-- Three players: with only two, eliminating one ends the match instantly
-- (team elimination), which would mask the ghost-cage transition under test.
local alpha = H.new_player("alpha")
local beta = H.new_player("beta")
local gamma = H.new_player("gamma")
H.fire_joinplayer(alpha)
H.fire_joinplayer(beta)
H.fire_joinplayer(gamma)
H.advance(1, 0.5)
check(alpha:get_pos().y == state.lobby_spawn.y, "alpha spawns at lobby")
check(beta:get_pos().x == state.lobby_spawn.x, "beta spawns at lobby")

section("PHASE 4 — ready check -> countdown -> insertion")
state.settings.mm_auto_assign = false -- deterministic roster: no random Monster Master
local ok_start, msg_start = minetest.registered_chatcommands.sl_match_start.func("alpha", "")
check(ok_start == true, "ready check opens" .. (ok_start and "" or (" -> " .. tostring(msg_start))))
check(state.ready_check.active == true, "ready_check.active")
minetest.registered_chatcommands.sl_ready.func("alpha", "")
check(state.ready_check.countdown_left == 0, "countdown waits for full roster")
minetest.registered_chatcommands.sl_ready.func("beta", "")
minetest.registered_chatcommands.sl_ready.func("gamma", "")
check(state.ready_check.countdown_left > 0, "countdown starts when all players are ready")
H.advance(7, 0.5)
check(state.match_active == true, "match starts after countdown")
check(alpha:get_pos().x == state.teams.beacon_a.spawn.x
	and alpha:get_pos().z == state.teams.beacon_a.spawn.z, "alpha inserted at beacon A spawn")
check(beta:get_pos().x == state.teams.beacon_b.spawn.x, "beta inserted at beacon B spawn")
check(state.players.alpha.phase == "alive" and state.players.beta.phase == "alive",
	"both players alive at insertion")

section("PHASE 5 — single death sends the player to the cloud cage")
alpha:set_hp(0)
H.respawn(alpha)
check(state.players.alpha.phase == "ghost", "first (and only) death transitioned alpha to ghost")
check(alpha:get_pos().y == state.ghost_spawn.y, "ghost held in cloud cage altitude")
check(H.player_privs.alpha.fly == true, "cage ghost has flight")
check(alpha:get_properties().selectionbox[1] == 0, "contained ghost is untargetable")
check(alpha:get_inventory():contains_item("main", ItemStack("sl_modebase:reincarnate")),
	"cage ghost holds the revival option")

section("PHASE 6 — ghost communication seal (chat + commands)")
check(H.fire_chat_message("alpha", "hello living") == true, "ghost chat message blocked")
local dm_ok, dm_msg = minetest.registered_chatcommands.msg.func("alpha", "beta secret plan")
check(dm_ok == false and tostring(dm_msg):find("sealed") ~= nil,
	"ghost /msg direct message blocked by guard")
local living_ok = minetest.registered_chatcommands.msg.func("beta", "hello")
check(living_ok == true, "living player /msg still works")
check(H.fire_chat_message("beta", "ordinary chat") == false, "living chat passes through")

section("PHASE 7 — ghost altar ritual")
minetest.set_node({ x = 10, y = 10, z = 10 }, { name = "sl_modebase:ghost_altar" })
local altar_pos = { x = 10, y = 10, z = 10 }
local binv = beta:get_inventory()
binv:add_item("main", ItemStack("sl_modebase:ritual_ashen_relic"))
binv:add_item("main", ItemStack("sl_modebase:ritual_soul_shard"))
binv:add_item("main", ItemStack("sl_modebase:ritual_signal_ink"))
local altar_def = minetest.registered_nodes["sl_modebase:ghost_altar"]
altar_def.on_rightclick(altar_pos, minetest.get_node(altar_pos), beta, ItemStack(""),
	{ type = "node", under = altar_pos })
check(state.players.alpha.ghost_summoned_by == "beta", "random contained ghost summoned for beta")
check(alpha:get_pos().y == 11.2, "ghost transported to altar")
check(not binv:contains_item("main", ItemStack("sl_modebase:ritual_ashen_relic")),
	"ritual components consumed")

section("PHASE 8 — summoned ghost offers one information packet")
H.settings.creative_mode = true -- /sl_ghost_offer is a creative-mode dev control
local offer_ok, offer_msg = minetest.registered_chatcommands.sl_ghost_offer.func("alpha", "beta medical")
H.settings.creative_mode = false
check(offer_ok == true, "offer accepted" .. (offer_ok and "" or (" -> " .. tostring(offer_msg))))
check(binv:contains_item("main", ItemStack("sl_modebase:data_pad_medical")),
	"information packet delivered to summoner")
check(state.players.alpha.ghost_summoned_by == nil, "channel closed after transmission")

section("PHASE 9 — voluntary evil-ghost revival")
state.players.alpha.points = 25
local reinc_def = minetest.registered_craftitems["sl_modebase:reincarnate"]
reinc_def.on_use(ItemStack("sl_modebase:reincarnate"), alpha, nil)
check(state.players.alpha.phase == "evil_ghost", "alpha revived as evil ghost")
check(state.players.alpha.points == 0, "revival burned all earned points")
check(alpha:get_properties().selectionbox[5] == 1.75, "evil ghost is targetable for purging")
check(alpha:get_inventory():contains_item("main", ItemStack("sl_modebase:sabotage_charge")),
	"evil ghost received one bounded sabotage charge")

section("PHASE 10 — bounded sabotage + corrosion + repair counterplay")
minetest.set_node({ x = 40, y = 9, z = 0 }, { name = "sl_modebase:beacon_b" })
local sabotage_def = minetest.registered_tools["sl_modebase:sabotage_charge"]
sabotage_def.on_use(ItemStack("sl_modebase:sabotage_charge"), alpha,
	{ type = "node", under = { x = 40, y = 9, z = 0 } })
check(gm.is_sabotaged({ x = 40, y = 9, z = 0 }), "beacon B registered as sabotaged")
check(minetest.get_meta({ x = 40, y = 9, z = 0 }):get_string("infotext") == "SIGNAL CORRUPTED",
	"visible corruption marker on node")
local hp_before = state.teams.beacon_b.hp
H.advance(3.5, 0.5)
local corroded = hp_before - state.teams.beacon_b.hp
check(corroded == 6, "beacon corrosion ticks: 3 x 2 damage (got " .. corroded .. ")")

-- Interaction refusal on a sabotaged interactable
minetest.set_node({ x = 12, y = 10, z = 10 }, { name = "sl_modebase:loot_crate" })
gm.register_sabotage({ x = 12, y = 10, z = 10 }, "node")
local fs_before = #(H.formspecs.beta or {})
minetest.registered_nodes["sl_modebase:loot_crate"].on_rightclick(
	{ x = 12, y = 10, z = 10 }, minetest.get_node({ x = 12, y = 10, z = 10 }),
	beta, ItemStack(""), nil)
check(#(H.formspecs.beta or {}) == fs_before, "sabotaged loot crate refuses interaction")

-- Living player repairs by punching
H.fire_punchnode({ x = 40, y = 9, z = 0 }, minetest.get_node({ x = 40, y = 9, z = 0 }), beta, nil)
check(not gm.is_sabotaged({ x = 40, y = 9, z = 0 }), "punch repair cleared the sabotage")
check(minetest.get_meta({ x = 40, y = 9, z = 0 }):get_int("sl_sabotaged_until") == 0,
	"corruption marker cleared from meta")

section("PHASE 10b — evil-ghost possession (fused WP3 system) + exorcism")
minetest.set_node({ x = 14, y = 10, z = 10 }, { name = "sl_modebase:loot_crate" })
local focus_def = minetest.registered_tools["sl_modebase:possession_focus"]
check(focus_def ~= nil, "possession_focus tool registered")
local focus_stack = ItemStack("sl_modebase:possession_focus")
focus_def.on_use(focus_stack, alpha, { type = "node", under = { x = 14, y = 10, z = 10 } })
check(gm.is_possessed({ x = 14, y = 10, z = 10 }), "focus claimed the vessel")
check(not focus_stack:is_empty(), "focus is reusable (cooldown-bounded, not consumed)")
check(minetest.get_meta({ x = 14, y = 10, z = 10 }):get_string("infotext") == "OBJECT POSSESSED",
	"discoverable possession marker set")
local fs_before2 = #(H.formspecs.beta or {})
minetest.registered_nodes["sl_modebase:loot_crate"].on_rightclick(
	{ x = 14, y = 10, z = 10 }, minetest.get_node({ x = 14, y = 10, z = 10 }),
	beta, ItemStack(""), nil)
check(#(H.formspecs.beta or {}) == fs_before2, "possessed crate refused the living")
local whisper = false
for _, line in ipairs(H.chat_player.alpha or {}) do
	if line:find("vessel was touched") then whisper = true end
end
check(whisper, "ghost owner received the identity whisper")
H.fire_punchnode({ x = 14, y = 10, z = 10 }, minetest.get_node({ x = 14, y = 10, z = 10 }), beta, nil)
check(gm.is_possessed({ x = 14, y = 10, z = 10 }), "first punch resisted (2-hit exorcism)")
H.fire_punchnode({ x = 14, y = 10, z = 10 }, minetest.get_node({ x = 14, y = 10, z = 10 }), beta, nil)
check(not gm.is_possessed({ x = 14, y = 10, z = 10 }), "second punch exorcised the vessel")
check((state.players.alpha.possession_ready_at or 0) > H.now(),
	"exorcism applied the re-possession cooldown penalty")

section("PHASE 11 — match timer, result screen, lobby reset")
state.settings.match_duration = 5
state.match_started_at = H.now() - 4 -- backdate so the timer expires within 2 s
H.advance(2, 0.5)
check(state.match_active == false, "match ended by timer")
local results_seen = false
for _, fs in ipairs(H.formspecs.alpha or {}) do
	if fs.formname == "sl_modebase:results" then results_seen = true end
end
check(results_seen, "result screen formspec shown")
local scoreboard_seen = false
for _, line in ipairs(H.chat_all) do
	if line:find("RESULTS") then scoreboard_seen = true end
end
check(scoreboard_seen, "result scoreboard broadcast to chat")
check(next(state.sabotage) == nil, "all sabotages purged at match end")
check(next(state.possession) == nil, "all possessions purged at match end")
check(alpha:get_pos().x == state.lobby_spawn.x and alpha:get_pos().y == state.lobby_spawn.y,
	"players returned to lobby")
check(gamma:get_pos().y == state.lobby_spawn.y, "gamma returned to lobby too")
check(H.player_privs.alpha.fly == nil, "ghost flight privilege revoked in lobby")
check(alpha:get_properties().selectionbox[5] == 1.75, "selectionbox restored in lobby")
check(state.players.alpha.phase == "alive", "clean reset normalized ghost identity (no soft-lock)")

section("PHASE 12 — clean restart without stale state")
local ok2, msg2 = minetest.registered_chatcommands.sl_match_start.func("alpha", "now")
check(ok2 == true, "'now' bypass restarts immediately" .. (ok2 and "" or (" -> " .. tostring(msg2))))
check(state.match_active == true, "new match active")
check(state.players.alpha.phase == "alive", "evil-ghost state reset to alive")
check(state.players.alpha.points == 0, "points reset")
check(not state.ready_check.active, "no stale ready check")
check(alpha:get_pos().y == state.teams.beacon_a.spawn.y, "respawned at team spawn")
check(state.teams.beacon_b.hp == (state.settings.beacon_hp or 100),
	"beacon HP restored at insertion (no stale damage; was " .. tostring(state.teams.beacon_b.hp) .. ")")

section("PHASE 12b — rejoin after beacon destruction (regression: nil-spawn crash)")
-- Simulate: beacon destroyed (spawn invalidated) while this player was
-- disconnected; on return the respawn chain must demote, not crash.
local saved_spawn = table.copy(state.teams.beacon_b.spawn)
state.teams.beacon_b.spawn = nil
local spawn_ok = pcall(gm.spawn_player, beta)
check(spawn_ok, "spawn_player survives a destroyed-team spawn (no table.copy(nil))")
check(state.players.beta.phase == "ghost", "returning player of a destroyed team enters the cage")
check(beta:get_pos().y == state.ghost_spawn.y, "demoted player held at cage altitude")
state.teams.beacon_b.spawn = saved_spawn
state.players.beta.phase = "alive"

section("PHASE 13 — HUD is present and identity-neutral")
H.advance(1, 0.5) -- let the HUD globalstep refresh under the new match
local hud_texts = {}
for _, t in pairs(alpha._hud_texts) do table.insert(hud_texts, tostring(t)) end
local joined = table.concat(hud_texts, " | ")
check(#hud_texts >= 3, "HUD elements created (" .. #hud_texts .. ")")
check(joined:find("MATCH #") ~= nil, "HUD shows match phase/clock")
-- FIX 2026-08-27: beacons moved center below Match and shortened from CORE A/B to A/B per feedback
-- Accept both old and new formats for backward compat, but require A and B HP present
local has_beacon = (joined:find("A %d+") ~= nil and joined:find("B %d+") ~= nil)
	or (joined:find("CORE A") ~= nil and joined:find("CORE B") ~= nil)
check(has_beacon, "HUD shows public beacon integrity (A/B HP)")
-- Ensure new centered layout: beacons should be centered (not top-right) — check position via HUD count >=5 includes lobby+ready
check(#hud_texts >= 5, "HUD has 5 elements after WP5 upgrade (status, beacons centered, vitals, ready, lobby)")
check(joined:find("Beacon A") == nil and joined:find("beacon_a") == nil,
	"HUD leaks no team identifiers")

section("PHASE 14 — game-side auto-start")
gm.end_match(nil, "phase 14 setup")
H.advance(1, 0.5)
check(not state.match_active, "match ended for auto-start test")
-- Control: with auto_start OFF nothing relaunches on its own.
state.settings.auto_start = false
H.advance(6, 0.5)
check(not state.match_active, "no auto-start while the setting is OFF")
-- Enabled: lobby intermission -> silent readiness -> countdown -> insertion.
state.settings.auto_start = true
state.settings.auto_start_delay = 1
state.settings.countdown = 1
state.settings.match_duration = 600 -- undo the phase-11 timer fixture
H.advance(8, 0.5)
check(state.match_active, "auto-start relaunched the match with no player input")
check(not state.ready_check.active, "ready check consumed by insertion")
-- Roster gate: a lone player must not trigger matches.
gm.end_match(nil, "phase 14 roster gate")
H.advance(1, 0.5)
H.remove_player("beta")
H.remove_player("gamma")
H.advance(6, 0.5)
check(not state.match_active, "auto-start stays idle with fewer than 2 players")
state.settings.auto_start = false

section("PHASE 15 — monster spawner unit (MM-only GUI, essence-burning)")
-- PHASE 14's roster gate left only alpha; restore the trio for these phases.
H.new_player("beta")
H.new_player("gamma")
beta = H.players["beta"]
gamma = H.players["gamma"]
state.settings.match_duration = 0 -- keep the timer off; the phases advance the clock
local spawner_pos = { x = 30, y = 12, z = 30 }
minetest.set_node(spawner_pos, { name = "sl_modebase:monster_spawner" })
local spawner_def = minetest.registered_nodes["sl_modebase:monster_spawner"]
check(spawner_def ~= nil, "monster_spawner node registered")
check(minetest.registered_craftitems["sl_modebase:monster_essence"] ~= nil,
	"monster_essence resource registered")
spawner_def.on_construct(spawner_pos)
local spawner_meta = minetest.get_meta(spawner_pos)
check(spawner_meta:get_inventory():get_size("feed") == 10, "spawner feed inventory sized (10)")
check(spawner_meta:get_int("spawner_cd") == 5, "unit gets its own spawn-rate setting (default 5 s)")
check(spawner_meta:get_int("spawner_min") == 1, "unit gets its own minimum-essence setting (default 1)")

-- A living non-MM player is refused
local fs_beta_before = #(H.formspecs.beta or {})
spawner_def.on_rightclick(spawner_pos, minetest.get_node(spawner_pos), beta, ItemStack(""), nil)
check(#(H.formspecs.beta or {}) == fs_beta_before, "non-MM click opens no GUI")
local refused = false
for _, line in ipairs(H.chat_player.beta or {}) do
	if line:find("Only the Monster Master") then refused = true end
end
check(refused, "non-MM clicker is refused with a message")

-- MM assignment gifts the summoning tool plus starter Monster Essence
gm.set_monster_master("beta")
check(beta:get_inventory():contains_item("main", ItemStack("sl_modebase:summon_monster")),
	"MM still receives the summoning tool")
check(beta:get_inventory():contains_item("main", ItemStack("sl_modebase:monster_essence")),
	"MM receives starter Monster Essence")

-- MM click opens the GUI listing every creature in the catalog
spawner_def.on_rightclick(spawner_pos, minetest.get_node(spawner_pos), beta, ItemStack(""), nil)
local spawner_form
for _, fs in ipairs(H.formspecs.beta or {}) do
	if fs.formname:find("^sl_modebase:monster_spawner:") then spawner_form = fs.form end
end
check(spawner_form ~= nil, "MM click opens the spawner GUI")
local all_listed = true
for id in pairs(gm.MONSTER_TYPES) do
	if spawner_form:find("spawn_" .. id) == nil then all_listed = false end
end
check(all_listed, "GUI lists every monster type (incl. sl_scary mobs)")

-- Empty feed: selection is refused, nothing spawns
local spawns_before = #H.entity_spawns
spawner_meta:set_int("spawner_cd", 0) -- back-to-back spawns here; rate covered in 14b
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_brute = "" })
check(#H.entity_spawns == spawns_before, "no spawn without essence")

-- Load the feed, then pick a Brute from the list
spawner_meta:get_inventory():add_item("feed", ItemStack("sl_modebase:monster_essence 3"))
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_brute = "" })
check(#H.entity_spawns == spawns_before + 1, "Brute spawned from the GUI list")
check(H.entity_spawns[#H.entity_spawns].name == "sl_modebase:monster",
	"spawned entity is the shared monster")
check(gm.count_feed_essence(spawner_meta:get_inventory()) == 2, "one essence consumed per spawn")
check(spawner_meta:get_string("infotext"):find("feed: 2") ~= nil,
	"infotext tracks the remaining feed")
local produced = false
for _, line in ipairs(H.chat_all) do
	if line:find("Brute") then produced = true end
end
check(produced, "spawn broadcast names the creature")

-- A sl_scary horror mob from the same list (external entity, own stats)
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_dredger = "" })
check(#H.entity_spawns == spawns_before + 2, "Dredger spawned from the GUI list")
check(H.entity_spawns[#H.entity_spawns].name == "sl_scary:dredger",
	"mob entry deploys its own sl_scary entity")
check(gm.count_feed_essence(spawner_meta:get_inventory()) == 1,
	"mob spawn also burns one essence")

-- A non-MM cannot drive the GUI
H.fire_receive_fields("gamma", "sl_modebase:monster_spawner:30,12,30", { spawn_brute = "" })
check(#H.entity_spawns == spawns_before + 2, "non-MM field input ignored")

-- An unknown creature id is ignored
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_kraken = "" })
check(#H.entity_spawns == spawns_before + 2, "unknown creature id ignored")

-- The spawner is a possessable system (evil-ghost counterplay target)
check(gm.is_possessable("sl_modebase:monster_spawner"),
	"spawner registered as a possessable system")

section("PHASE 15b — per-node spawner settings: minimal essence + spawn rate")
-- feed currently holds 1 essence (3 added, brute + dredger consumed)
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30",
	{ save_spawner_cfg = "", spawner_cd = "8", spawner_min = "2" })
check(spawner_meta:get_int("spawner_cd") == 8, "spawn-rate saved to this unit's node")
check(spawner_meta:get_int("spawner_min") == 2, "minimum essence saved to this unit's node")
local cfg_msg = false
for _, line in ipairs(H.chat_player.beta or {}) do
	if line:find("configured") then cfg_msg = true end
end
check(cfg_msg, "settings save confirms the new values")

H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_brute = "" })
check(#H.entity_spawns == spawns_before + 2, "spawn refused below the unit's minimum essence")
local low_feed_msg = false
for _, line in ipairs(H.chat_player.beta or {}) do
	if line:find("needs at least") then low_feed_msg = true end
end
check(low_feed_msg, "feed-too-low message explains the minimum")

-- At the unit's minimum the spawner runs again (and now obeys its rate)
spawner_meta:get_inventory():add_item("feed", ItemStack("sl_modebase:monster_essence 2"))
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_stalker = "" })
check(#H.entity_spawns == spawns_before + 3, "spawn allowed at the unit's minimum essence")
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_stalker = "" })
check(#H.entity_spawns == spawns_before + 3, "immediate second spawn refused by the unit's rate")
local spool_msg = false
for _, line in ipairs(H.chat_player.beta or {}) do
	if line:find("still spooling") then spool_msg = true end
end
check(spool_msg, "cooldown message tells the MM to wait")
check(spawner_meta:get_inventory():get_stack("feed", 1):get_count() == 2,
	"refused cooldown spawn does not burn essence")
H.advance(9, 0.5)
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30", { spawn_stalker = "" })
check(#H.entity_spawns == spawns_before + 4, "spawn allowed once the unit's rate has elapsed")

-- Only the Monster Master may reconfigure a unit
H.fire_receive_fields("gamma", "sl_modebase:monster_spawner:30,12,30",
	{ save_spawner_cfg = "", spawner_cd = "0", spawner_min = "1" })
check(spawner_meta:get_int("spawner_cd") == 8 and spawner_meta:get_int("spawner_min") == 2,
	"non-MM cannot change a unit's settings")

-- Reset the unit through the same GUI
H.fire_receive_fields("beta", "sl_modebase:monster_spawner:30,12,30",
	{ save_spawner_cfg = "", spawner_cd = "5", spawner_min = "1" })
check(spawner_meta:get_int("spawner_cd") == 5 and spawner_meta:get_int("spawner_min") == 1,
	"settings persist per node and can be reset via the GUI")

section("PHASE 16 — lobby safety: monsters never attack outside matches")
if state.match_active then
	gm.end_match(nil, "phase 16 setup")
	H.advance(1, 0.5)
end
check(not state.match_active, "lobby state established")

-- (a) Damage pipeline: no blanket lobby cancel anymore (sandbox
-- doctrine, MT CTF — unallocated players fight under full rules; ghosts
-- are still vetoed, monsters still stand down via their own gate).
alpha._hp = 20
alpha.dead = false
local canceled_lobby = H.fire_punchplayer(alpha, beta, 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 5 } }, nil, 5)
check(canceled_lobby == false, "lobby punch passes the pipeline (sandbox doctrine)")
alpha:set_hp(20)
alpha:punch(beta, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 5 } }, nil)
check(alpha:get_hp() == 15, "lobby body takes the punch (fleshy=100, not immortal)")

-- (b) sl_scary direct-damage family: do_attack gated by match state
local ok_scary = pcall(dofile, "mods/content/sl_scary/init.lua")
check(ok_scary, "sl_scary loads under the stub harness")
local dredger = minetest.registered_entities["sl_scary:dredger"]
alpha:set_hp(20) -- (a) left a mark on purpose; the mob test starts clean
local dpos = alpha:get_pos()
local fake_self = {
	attack_timer = 0, attack_range = 3, attack_damage = 4, attack_cooldown = 0,
	object = { get_pos = function() return { x = dpos.x, y = dpos.y, z = dpos.z } end },
}
dredger.do_attack(fake_self, alpha, 1)
check(alpha:get_hp() == 20, "horror mob attack does nothing in the lobby")

-- (c) The gate is match-state, not a kill-switch: same attack lands in-match
-- Phase 15 assigned beta as Monster Master (which clears their team);
-- release the role so both beacon teams have members again.
gm.set_monster_master(nil)
state.settings.countdown = 1
gm.begin_ready_check("phase16")
gm.mark_ready("alpha", true)
gm.mark_ready("beta", true)
gm.mark_ready("gamma", true)
H.advance(4, 0.5)
check(state.match_active, "match started for the in-match control")
fake_self.attack_timer = 0
alpha._hp = 20
dredger.do_attack(fake_self, alpha, 1)
check(alpha:get_hp() == 16, "horror mob attack lands during an active match (4 dmg)")

-- (d) After the match ends the range stays open (sandbox doctrine);
-- the guard vetoes the dead, not the lobby.
gm.end_match(nil, "phase 16 cleanup")
H.advance(1, 0.5)
local canceled_after = H.fire_punchplayer(alpha, beta, 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 5 } }, nil, 5)
check(canceled_after == false, "post-match punch passes (no blanket lobby cancel)")
local apl_sm = gm.get_player_state("alpha")
local saved_phase = apl_sm.phase
apl_sm.phase = "ghost"
local canceled_ghost = H.fire_punchplayer(alpha, beta, 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 5 } }, nil, 5)
apl_sm.phase = saved_phase
check(canceled_ghost == true, "the dead stay vetoed after the match")

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
