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

-- Machine crafting is a map anchor now (the Objective Forge is placed
-- by the map system), so the map suites need it loaded.
H.current_modname = "sl_machine_crafting"
local okm, errm = pcall(dofile, "mods/game/sl_machine_crafting/init.lua")
check(okm, "sl_machine_crafting loads" .. (okm and "" or (" -> " .. tostring(errm))))
H.current_modname = "sl_modebase"

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
	-- After PR #14 (centralised find_spawn_pos) the spawn is no
	-- longer at the exact team-spawn coordinate: that point is
	-- inside the bastion pad, so the air-pocket search lands
	-- the player just outside the pad (typically ring 3-4 from
	-- the beacon). The relevant invariant is "near the team's
	-- bastion", not "on top of the beacon node".
	local function near_beacon(x, z, beacon_x, beacon_z, radius)
		return math.abs(x - beacon_x) <= radius
			and math.abs(z - beacon_z) <= radius
	end
	check(near_beacon(alpha:get_pos().x, alpha:get_pos().z,
		state.teams.beacon_a.spawn.x, state.teams.beacon_a.spawn.z, 20),
		"alpha inserted near beacon A (got "
			.. tostring(alpha:get_pos().x) .. "," .. tostring(alpha:get_pos().z) .. ")")
	check(near_beacon(beta:get_pos().x, beta:get_pos().z,
		state.teams.beacon_b.spawn.x, state.teams.beacon_b.spawn.z, 20),
		"beta inserted near beacon B (got "
			.. tostring(beta:get_pos().x) .. "," .. tostring(beta:get_pos().z) .. ")")
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
-- After PR #14 alpha is inserted at the air-pocket the
-- game_mode.find_spawn_pos search landed, which is just
-- outside the bastion pad — NOT at the team-spawn's
-- beacon-top y. Verify the spawn is "near" the team's beacon
-- rather than exactly at the team-spawn coordinate.
local function near_beacon(x, z, beacon_x, beacon_z, radius)
	return math.abs(x - beacon_x) <= radius
		and math.abs(z - beacon_z) <= radius
end
check(near_beacon(alpha:get_pos().x, alpha:get_pos().z,
	state.teams.beacon_a.spawn.x, state.teams.beacon_a.spawn.z, 20),
	"respawned near beacon A (got "
		.. tostring(alpha:get_pos().x) .. "," .. tostring(alpha:get_pos().z) .. ")")
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

-- (a) Damage pipeline guard: punches to players are cancelled in the lobby
alpha._hp = 20
alpha.dead = false
local canceled_lobby = H.fire_punchplayer(alpha, beta, 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 5 } }, nil, 5)
check(canceled_lobby == true, "punch damage cancelled in lobby (pipeline guard)")

-- (b) sl_scary direct-damage family: do_attack gated by match state
local ok_scary = pcall(dofile, "mods/content/sl_scary/init.lua")
check(ok_scary, "sl_scary loads under the stub harness")
local dredger = minetest.registered_entities["sl_scary:dredger"]
local fake_self = {
	attack_timer = 0, attack_range = 3, attack_damage = 4, attack_cooldown = 0,
	-- Live position: the player may have been inserted at a beacon
	-- since this stub was built (map spawns move between matches).
	object = { get_pos = function()
		local p = alpha:get_pos()
		return { x = p.x, y = p.y, z = p.z }
	end },
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

-- (d) Pipeline guard re-arms after the match ends
gm.end_match(nil, "phase 16 cleanup")
H.advance(1, 0.5)
local canceled_after = H.fire_punchplayer(alpha, beta, 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 5 } }, nil, 5)
check(canceled_after == true, "punch damage cancelled again after match end")

section("PHASE 17 — procedural map: prepare, journal, initial-state reset")
local function is_air(pos)
	local v = H.voxels[H.vhash(pos)]
	return v == nil or v == "air"
end
local mmap = gm.map
check(mmap ~= nil, "map system loaded")
check(mmap.current ~= nil and mmap.current.type == "procedural",
	"default match maps are procedural")
local seed_a = mmap.current.seed
mmap.prepare({ type = "procedural", seed = 4242 })
local d1 = mmap.current
check(d1.type == "procedural" and d1.seed == 4242, "explicit prepare pins type and seed")
check(mmap.journal_active == true, "node journal armed at map prepare")
check(H.voxels[H.vhash(d1.anchor.beacon_a)] == "sl_modebase:beacon_a"
	and H.voxels[H.vhash(d1.anchor.beacon_b)] == "sl_modebase:beacon_b",
	"beacon nodes materialized at their anchors")
check(H.voxels[H.vhash({ x = d1.origin.x, y = d1.origin.y, z = d1.origin.z })] == "ground:square_neon",
	"arena floor generated at the map origin")
check(state.teams.beacon_a.spawn.x == d1.anchor.beacon_a.x
	and state.teams.beacon_a.spawn.y == d1.anchor.beacon_a.y + 1,
	"team spawns derive from map anchors")
check(minetest.get_meta(d1.anchor.beacon_a):get_int("hp") == 100, "beacon meta starts at full HP")
-- Determinism: same seed rebuilds the same arena.
local d1_mobs = {}
for _, m in ipairs(d1.mobs) do table.insert(d1_mobs, m.pos.x .. ":" .. m.pos.z) end
mmap.prepare({ type = "procedural", seed = 4242 })
check(mmap.current.anchor.beacon_a.x == d1.anchor.beacon_a.x,
	"same seed -> identical arena layout")
local same = true
for i, m in ipairs(mmap.current.mobs) do
	if m.pos.x .. ":" .. m.pos.z ~= d1_mobs[i] then same = false end
end
check(same, "same seed -> identical mob layout")
mmap.prepare({ type = "procedural", seed = 777 })
local diff = false
for i, m in ipairs(mmap.current.mobs) do
	if m.pos.x .. ":" .. m.pos.z ~= d1_mobs[i] then diff = true end
end
check(diff, "different seed -> different arena layout")

local cur = mmap.current
-- Match-time edits: inside the volume (rebuild covers) and outside
-- (journal covers), plus node metadata on an outside edit.
H.fire_placenode({ x = cur.origin.x + 1, y = cur.origin.y + 1, z = cur.origin.z },
	{ name = "default:stone" })
H.fire_dignode({ x = cur.origin.x, y = cur.origin.y, z = cur.origin.z + 1 })
local outside = { x = 300, y = 8, z = 300 }
local outside2 = { x = 310, y = 8, z = 300 }
minetest.get_meta(outside2):set_string("owner", "tester")
H.fire_dignode(outside2)
H.fire_placenode(outside, { name = "default:cobble" })
check(#mmap.journal == 4, "journal recorded the four match edits (got " .. #mmap.journal .. ")")
gm.damage_beacon("beacon_a", 30, "phase17", true)
check(state.teams.beacon_a.hp == 70, "beacon damaged during the match")

mmap.reset()
check(is_air({ x = cur.origin.x + 1, y = cur.origin.y + 1, z = cur.origin.z }),
	"node placed inside the arena during the match was removed (rebuild)")
check(H.voxels[H.vhash({ x = cur.origin.x, y = cur.origin.y, z = cur.origin.z + 1 })] == "ground:square_neon",
	"dug floor node restored to the generated initial state")
check(is_air(outside), "out-of-arena placed node journaled and restored")
check(is_air(outside2), "out-of-arena dug node journaled and restored")
check(minetest.get_meta(outside2):get_string("owner") == "tester",
	"node metadata restored with the journaled node")
check(#mmap.journal == 0 and mmap.journal_active == false, "journal closed and cleared at reset")
check(state.teams.beacon_a.hp == (state.settings.beacon_hp or 100),
	"beacon HP restored at reset")
check(minetest.get_meta(mmap.current.anchor.beacon_a):get_int("hp") == 100,
	"beacon meta refreshed at reset")

section("PHASE 18 — mob lifecycle: purge at match end, respawn at game start")
mmap.prepare({ type = "procedural", seed = 4242 })
local spawned = mmap.spawn_initial_mobs()
check(spawned == #mmap.current.mobs and spawned > 0,
	"initial mob population spawned at game start (" .. spawned .. ")")
local function mob_count()
	local n = 0
	for _, e in pairs(H.luaentities) do
		if mmap.is_mob_name(e.name) then
			n = n + 1
		end
	end
	return n
end
check(mob_count() == spawned, "map mobs registered as live entities")
-- The Monster Master deploys extra monsters during the match...
gm.spawn_monster({ x = 0, y = 40, z = 0 }, "brute", "beta")
local dredger_obj = minetest.add_entity({ x = 0, y = 40, z = 0 }, "sl_scary:dredger")
check(mob_count() == spawned + 2, "MM-spawned and sl_scary mobs also live entities")
-- ...and dropped items pile up inside the arena.
local item_inside = minetest.add_item({ x = 0, y = 40, z = 0 }, ItemStack("default:cobble"))
local item_outside = minetest.add_item({ x = 500, y = 8, z = 500 }, ItemStack("default:cobble"))
mmap.reset()
check(mob_count() == 0, "every mob is gone once the match ends (incl. MM + horror mobs)")
check(item_inside._removed == true, "dropped items inside the arena purged at reset")
check(item_outside._removed ~= true, "items outside the arena volume survive")
mmap.spawn_initial_mobs()
check(mob_count() == spawned, "mobs respawn fresh at the next game start")

section("PHASE 19 — handmade map from schematic (.lua variant, map.conf anchors)")
H.dir_tree["mods/game/sl_modebase/maps"] =
	{ dirs = { "neon_crossfire", "mini_test" }, files = {} }
local list_ok, list_msg = minetest.registered_chatcommands.sl_map.func("alpha", "list")
check(list_ok == true and tostring(list_msg):find("mini_test") ~= nil
	and tostring(list_msg):find("neon_crossfire") ~= nil,
	"/sl_map lists installed handmade maps")
H.player_privs.alpha = { server = true } -- stub treats server as admin
H.schematic_placements = {}
mmap.prepare({ type = "schematic", name = "mini_test", seed = 5 })
local sd = mmap.current
check(sd.type == "schematic" and sd.name == "Mini Test",
	"handmade map loaded from its directory")
local place_min = { x = -10, y = 30, z = -10 } -- origin {0,30,0} centered on 21x21
check(sd.minp.x == place_min.x - 1 and sd.minp.y == place_min.y - 2 and sd.minp.z == place_min.z - 1,
	"map volume pads the schematic box (reset volume)")
check(#H.schematic_placements == 1 and H.schematic_placements[1].pos.x == place_min.x
	and H.schematic_placements[1].pos.y == place_min.y
	and H.schematic_placements[1].force == true,
	"schematic force-placed at the computed min corner")
check(sd.anchor.beacon_a.x == place_min.x + 5 and sd.anchor.beacon_a.y == place_min.y + 2
	and sd.anchor.beacon_a.z == place_min.z + 10,
	"beacon anchors come from map.conf (schematic-relative)")
check(H.voxels[H.vhash(sd.anchor.beacon_a)] == "sl_modebase:beacon_a",
	"beacon node placed on the handmade map's dais")
check(H.voxels[H.vhash({ x = place_min.x, y = place_min.y, z = place_min.z })] == "ground:square_neon",
	"schematic floor materialized")
check(#sd.mobs == 3 and sd.mobs[1].variant == "stalker" and sd.mobs[3].variant == "brute",
	"map.conf defines the initial mob population")
-- Machine crafting is a map anchor like any other: a handmade map
-- declares it in map.conf (forge.pos) and the placement follows.
check(sd.anchor.forge ~= nil and sd.anchor.forge.x == place_min.x + 10
	and sd.anchor.forge.z == place_min.z + 14,
	"the Objective Forge anchor comes from map.conf (schematic-relative)")
check(H.voxels[H.vhash(sd.anchor.forge)] == "sl_machine_crafting:objective_forge",
	"the Objective Forge is placed on the handmade map")
-- Reset contract on the handmade map: re-place + journal restore.
local hm_outside = { x = 400, y = 8, z = 400 }
H.fire_placenode(hm_outside, { name = "default:stone" })
H.fire_placenode({ x = place_min.x + 10, y = place_min.y + 4, z = place_min.z + 10 },
	{ name = "default:cobble" }) -- inside the schematic volume
mmap.reset()
check(#H.schematic_placements == 2, "reset re-places the handmade schematic")
check(is_air(hm_outside), "out-of-map edit restored")
check(is_air({ x = place_min.x + 10, y = place_min.y + 4, z = place_min.z + 10 }),
	"node placed inside the handmade map was wiped by the re-placement")
check(H.voxels[H.vhash({ x = place_min.x, y = place_min.y, z = place_min.z })] == "ground:square_neon",
	"handmade floor back to its initial state")

-- .mts variant (binary schematic, WorldEdit-style): conf parsing and
-- anchor math (the stub records placements without decoding the file).
mmap.prepare({ type = "schematic", name = "neon_crossfire", seed = 5 })
local nd = mmap.current
check(nd.type == "schematic" and nd.name == "Neon Crossfire", ".mts handmade map discovered")
check(nd.minp.x == -25 and nd.minp.z == -25 and nd.minp.y == 28,
	".mts centered on origin (padded volume)")
check(nd.anchor.beacon_a.x == -24 + 6 and nd.anchor.beacon_a.y == 30 + 2
	and nd.anchor.beacon_a.z == -24 + 24,
	".mts beacon anchors read from map.conf")
check(#nd.mobs == 5, ".mts map.conf mob list parsed")

section("PHASE 20 — /sl_map commands and the test-procedural map type")
H.player_privs.beta = {} -- not an admin
local denied = minetest.registered_chatcommands.sl_map.func("beta", "procedural")
check(denied == false, "non-admin cannot change the map type")
local set_ok = minetest.registered_chatcommands.sl_map.func("alpha", "test")
check(set_ok == true, "/sl_map test accepted")
mmap.prepare()
check(mmap.current.type == "test", "test-procedural map built on next prepare")
check(mmap.current.anchor.beacon_a.x == -12 and mmap.current.anchor.beacon_a.y == 2,
	"deterministic test arena layout (beacon A at -12)")
check(state.lobby_spawn.y == 5 and state.ghost_spawn.y == 40,
	"test arena registers lobby and cage spawns")
local status_ok, status_msg = minetest.registered_chatcommands.sl_map.func("alpha", "")
check(status_ok == true and tostring(status_msg):find("test") ~= nil,
	"/sl_map status reports the active map")
-- Map export (create_schematic route); io is stubbed out so nothing
-- is written to the real repository during tests.
local real_io_open = io.open
io.open = function() return nil end
local save_ok, save_msg = mmap.save_current("exporttest")
io.open = real_io_open
check(save_ok == true, "current map exports to a handmade map (/sl_map save)")
check(H.created_schematics["mods/game/sl_modebase/maps/exporttest/map.mts"] ~= nil,
	"export writes <maps>/<name>/map.mts")

section("PHASE 21a — mob_player.lua: animation payload is in seconds, not frame indices")
-- The mob wears the SimpleOutlinedBoxman.glb mesh (the same one real
-- players wear). Its animation payload to obj:set_animation must use
-- the SAME keyframe coordinates the model defines in
-- mods/content/sl_characters/model_boxman.lua, otherwise the engine
-- will play back the wrong range. That table expresses ranges as
-- frame_index / 60 (seconds). A previous version of this file used
-- raw integer frame indices like {x=0,y=79}, which don't exist on the
-- boxman; the engine silently clamped to the last frame and the
-- boolean blend (also tried in a prior version) raised a type error
-- on the next phase transition. Lock the payload in here.
--
-- Stash the live game_mode/botmatch globals, install lightweight
-- stubs, load the module, then restore the live globals. This
-- keeps later phases unaffected.
local saved_gm, saved_bm = game_mode, botmatch
local stub_bm = { mobs = {}, config = { bot_speed = 1.0 }, bots = {}, modpath = "mods/game/aaa_botmatch" }
local stub_gm = { get_player_state = function(n) return { phase = "alive", eliminated = false } end }
_G.game_mode = stub_gm
_G.botmatch = stub_bm
local ok_mob, err_mob = pcall(dofile, "mods/game/aaa_botmatch/mob_player.lua")
_G.game_mode = saved_gm
_G.botmatch = saved_bm
check(ok_mob, "mob_player.lua loads with stubbed globals"
	.. (ok_mob and "" or (" -> " .. tostring(err_mob))))
local mob_def = minetest.registered_entities["aaa_botmatch:player_mob"]
check(mob_def ~= nil, "mob entity registered")
check(mob_def.initial_properties.mesh == "SimpleOutlinedBoxman.glb",
	"mob wears the canonical boxman mesh (matches real players)")
check(mob_def.initial_properties.visual_size.x == 10
	and mob_def.initial_properties.visual_size.y == 10,
	"mob visual_size matches real players (10x10; was 1x before)")
-- The animation payload lives inside mob_player.lua as locals, so
-- we can't observe them at runtime. Instead, lock the SOURCE down
-- to the canonical payload from model_boxman.lua.
local mob_src
do
	local f = io.open("mods/game/aaa_botmatch/mob_player.lua", "r")
	mob_src = f:read("*a"); f:close()
end
local function has_decl(pat)
	return mob_src:find(pat, 1, false) ~= nil
end
-- Canonical stand: {x = 0, y = 0}, NOT {x = 0, y = 79}.
check(has_decl("ANIM_STAND%s*=%s*{%s*x%s*=%s*0"),
	"mob declares ANIM_STAND starting at x=0 (in seconds, matches boxman)")
-- The walk range must be the 1/60 -> 40/60 form, not raw integer frames.
check(mob_src:find("1/60") ~= nil and mob_src:find("40/60") ~= nil,
	"mob declares the walk range as 1/60 .. 40/60 (seconds, not frame integers)")
-- animation_speed must equal 2 (the boxman model speed), not 30.
check(has_decl("ANIM_SPEED_STAND%s*=%s*2") and has_decl("ANIM_SPEED_WALK%s*=%s*2"),
	"mob uses the boxman's animation_speed = 2 (not 30)")
-- Third arg of set_animation must be a number; the constant
-- ANIM_NO_LOOP_BLEND = 0 exists and is a number, not a boolean.
check(has_decl("ANIM_NO_LOOP_BLEND%s*=%s*0"),
	"mob defines ANIM_NO_LOOP_BLEND = 0 (number, not a boolean)")
-- Make sure no third arg is the literal `true`.
local _, true_call_count = mob_src:gsub("set_animation%([^)]*true", "")
check(true_call_count == 0,
	"no set_animation call site still passes a boolean blend (got "
	.. true_call_count .. ")")
-- Evil ghosts are fully invisible: visual_size = 0 is set in
-- apply_phase_props. Read the source and confirm.
check(mob_src:find("evil_ghost") ~= nil
	and mob_src:find("visual_size%s*=%s*{%s*x%s*=%s*0") ~= nil,
	"mob source sets visual_size = {0,0} for the ghost phase(s)")

section("PHASE 21 — procedural layout overrides (cloud cage / beacons / MM base)")
minetest.settings:set("sl_map.cage_pos", "5,5")
minetest.settings:set("sl_map.beacon_a_pos", "-30,2")
minetest.settings:set("sl_map.beacon_b_pos", "30,2")
minetest.settings:set("sl_map.mm_base_pos", "0,40")
mmap.prepare({ type = "procedural", seed = 4242 })
local dl = mmap.current
check(dl.anchor.ghost.x == 5 and dl.anchor.ghost.z == 5,
	"cloud cage anchored at the configured X,Z")
check(dl.anchor.beacon_a.x == -30 and dl.anchor.beacon_a.z == 2,
	"beacon A bastion at the configured position")
check(dl.anchor.beacon_b.x == 30 and dl.anchor.beacon_b.z == 2,
	"beacon B bastion at the configured position")
check(dl.anchor.mm_pad.x == 0 and dl.anchor.mm_pad.z == 40,
	"MM redoubt at the configured position")
check(state.ghost_spawn.x == 5 and state.ghost_spawn.z == 5,
	"ghost cage spawn follows the override")
check(state.monster_master.base_spawn.x == 0 and state.monster_master.base_spawn.z == 40,
	"MM base spawn follows the override")
check(state.teams.beacon_a.spawn.x == -30 and state.teams.beacon_a.spawn.y == dl.anchor.beacon_a.y + 1,
	"team A spawn follows the override")
check(H.voxels[H.vhash({ x = -30, y = dl.origin.y + 2, z = 2 })] == "sl_modebase:beacon_a",
	"beacon node materialized on the override bastion")
check(H.voxels[H.vhash({ x = 0, y = dl.origin.y + 1, z = 40 })] == "sl_modebase:spawn_mm",
	"MM pad node materialized at the override redoubt")
check(dl.minp.x <= -34 and dl.maxp.x >= 34 and dl.minp.z <= -4 and dl.maxp.z >= 44,
	"reset volume expanded to contain the overridden anchors")
-- Same-match reset rebuilds the same overridden layout.
mmap.reset()
local dr = mmap.current
check(dr.anchor.beacon_a.x == -30 and dr.anchor.beacon_a.z == 2,
	"reset rebuild keeps the overridden beacon A")
check(dr.anchor.mm_pad.x == 0 and dr.anchor.mm_pad.z == 40,
	"reset rebuild keeps the overridden MM redoubt")
check(H.voxels[H.vhash({ x = -30, y = dr.origin.y + 2, z = 2 })] == "sl_modebase:beacon_a",
	"override rebuild materializes beacon A again")
-- Collision guard: identical positions for both beacons fall back.
minetest.settings:set("sl_map.beacon_a_pos", "0,40")
minetest.settings:set("sl_map.beacon_b_pos", "0,40")
mmap.prepare({ type = "procedural", seed = 4242 })
local dg = mmap.current
check(dg.anchor.beacon_a.x == 0 and dg.anchor.beacon_a.z == 40,
	"beacon A honours the shared override position")
check(dg.anchor.beacon_b.x ~= 0 or dg.anchor.beacon_b.z ~= 40,
	"beacon B falls back when both positions collide")
-- Reset the overrides so the default arrangement holds again.
minetest.settings:set("sl_map.cage_pos", nil)
minetest.settings:set("sl_map.beacon_a_pos", nil)
minetest.settings:set("sl_map.beacon_b_pos", nil)
minetest.settings:set("sl_map.mm_base_pos", nil)
mmap.prepare({ type = "procedural", seed = seed_a })

-- Restore the default configuration for any later phases.
mmap.runtime.type = nil
mmap.runtime.schematic = nil
mmap.runtime.seed = nil
mmap.prepare({ type = "procedural", seed = seed_a })

section("PHASE 21b — air-pocket spawn search: 2 unclaimed air nodes, no anchor overlap")
-- Regression for the "spawning in a node below beacon" report.
-- Originally, game_mode.spawn_player (real players) AND the mob
-- body spawner (bot bodies) used the static beacon-top
-- coordinate as the spawn, which collided with the 5x5 bastion
-- pad and the altar pad. The fix in PR #14 was to centralise
-- the air-pocket search in sl_modebase/spawn.lua as
-- game_mode.find_spawn_pos, then have both real players and
-- bot bodies go through it. This phase exercises the search
-- directly against a hand-built arena in a clean area, so a
-- regression to the static spawn fails the suite.
local saved_gm, saved_bm = game_mode, botmatch
-- The spawn search needs the stub harness's get_node / set_node
-- to behave, and it needs a real-ish game_mode with a map and
-- teams. Build a minimal one in a clean arena area so the
-- bastion pads, altar pad, and floor are present.
local function build_test_arena(centre)
	-- Clear a 24x24 region.
	for x = centre.x - 12, centre.x + 12 do
		for z = centre.z - 12, centre.z + 12 do
			H.voxels[H.vhash({ x = x, y = 0, z = z })] = nil
			H.voxels[H.vhash({ x = x, y = 1, z = z })] = nil
		end
	end
	-- Floor at y=0.
	for x = centre.x - 12, centre.x + 12 do
		for z = centre.z - 12, centre.z + 12 do
			minetest.set_node({ x = x, y = 0, z = z }, { name = "ground:square_neon" })
		end
	end
	-- 5x5 bastion pads at y=1 around each beacon, beacons at y=2.
	for _, bp in ipairs({ { x = centre.x - 6, z = centre.z }, { x = centre.x + 6, z = centre.z } }) do
		for dx = -2, 2 do for dz = -2, 2 do
			minetest.set_node({ x = bp.x + dx, y = 1, z = bp.z + dz },
				{ name = "ground:square_neon_opaque" })
		end end
		minetest.set_node({ x = bp.x, y = 2, z = bp.z }, { name = "sl_modebase:beacon_a" })
	end
	-- 3x3 altar pad in the middle.
	for dx = -1, 1 do for dz = -1, 1 do
		minetest.set_node({ x = centre.x + dx, y = 1, z = centre.z + dz },
			{ name = "ground:square_neon_opaque" })
	end end
	minetest.set_node({ x = centre.x, y = 1, z = centre.z }, { name = "sl_modebase:ghost_altar" })
end

local centre = { x = 200, z = 200 }
build_test_arena(centre)
local _stub_gm = {
	state = {
		teams = {
			beacon_a = { spawn = { x = centre.x - 6, y = 3, z = centre.z } },
			beacon_b = { spawn = { x = centre.x + 6, y = 3, z = centre.z } },
		},
		lobby_spawn = { x = centre.x, y = 5, z = centre.z },
	},
	mmap = {
		current = {
			origin = { x = centre.x, y = 0, z = centre.z },
			anchor = {
				beacon_a = { x = centre.x - 6, y = 2, z = centre.z },
				beacon_b = { x = centre.x + 6, y = 2, z = centre.z },
				altar    = { x = centre.x,     y = 1, z = centre.z },
				mm_pad   = { x = centre.x,     y = 1, z = centre.z + 8 },
			},
		},
	},
}
_G.game_mode = _stub_gm
-- game_mode.find_spawn_pos is a closure that captures its
-- module-level helpers (is_passable, is_ground, candidate_ok,
-- etc.) and its own claim table. We have to load the real
-- spawn.lua to get them — but spawn.lua also writes the live
-- spawn_player, which we don't want to overwrite. Save and
-- restore the live game_mode around the load, so the search
-- becomes available on _stub_gm without breaking anything.
local saved_spawn_player = game_mode.spawn_player
local ok_spawn, err_spawn = pcall(dofile, "mods/game/sl_modebase/spawn.lua")
check(ok_spawn, "spawn.lua loads under the test arena stub"
	.. (ok_spawn and "" or (" -> " .. tostring(err_spawn))))
-- Restore the live spawn_player that the load just clobbered.
game_mode.spawn_player = saved_spawn_player
-- The search now lives on _stub_gm.find_spawn_pos.
check(type(_stub_gm.find_spawn_pos) == "function",
	"game_mode.find_spawn_pos is exposed by spawn.lua")
-- Spawn one position per team.
local p_a = _stub_gm.find_spawn_pos("beacon_a", "alpha")
local p_b = _stub_gm.find_spawn_pos("beacon_b", "beta")
-- The two positions must be distinct (the claim table ensures
-- they don't share the same air pocket).
check(not (p_a.x == p_b.x and p_a.z == p_b.z),
	"two team spawns do not collide on the same air pocket (a="
		.. p_a.x .. "," .. p_a.z .. " b=" .. p_b.x .. "," .. p_b.z .. ")")
for i, p in ipairs({ { "beacon_a", p_a }, { "beacon_b", p_b } }) do
	local tag, pos = p[1], p[2]
	local foot  = minetest.get_node({ x = pos.x, y = pos.y,     z = pos.z }).name
	local head  = minetest.get_node({ x = pos.x, y = pos.y + 1, z = pos.z }).name
	local floor = minetest.get_node({ x = pos.x, y = pos.y - 1, z = pos.z }).name
	check(foot == "air" or foot == "ignore",
		tag .. " spawn foot is air/ignore (got " .. foot .. ")")
	check(head == "air" or head == "ignore",
		tag .. " spawn head is air/ignore (got " .. head .. ")")
	check(floor ~= "air" and floor ~= "ignore" and floor ~= nil,
		tag .. " spawn floor is solid (got " .. tostring(floor) .. ")")
	-- The spawn must clear every structural anchor by the
	-- documented footprint. The bastions are at x = ±6 from
	-- centre, z = centre.z. The altar is at (centre, centre).
	-- The MM pad is at (centre, centre+8). Half-extents are
	-- 3, 2, 4 respectively, so spawn x must not be within 3
	-- of (centre.x±6), spawn z must not be within 2 of
	-- centre.z, and (z - centre.z) must not be within 4 of 8.
	local off_x = math.abs(pos.x - centre.x)
	local off_z = math.abs(pos.z - centre.z)
	local near_beacon_a = (math.abs(pos.x - (centre.x - 6)) <= 3) and (off_z <= 3)
	local near_beacon_b = (math.abs(pos.x - (centre.x + 6)) <= 3) and (off_z <= 3)
	local near_altar    = (off_x <= 2) and (off_z <= 2)
	local near_mm_pad   = (off_x <= 4) and (math.abs(pos.z - (centre.z + 8)) <= 4)
	check(not (near_beacon_a or near_beacon_b or near_altar or near_mm_pad),
		tag .. " spawn clears every structural anchor footprint (got x="
			.. pos.x .. " z=" .. pos.z .. ")")
end
-- claim release: clear_spawn_claims lets a subsequent call
-- reuse a previously claimed pocket.
check(type(_stub_gm.clear_spawn_claims) == "function",
	"game_mode.clear_spawn_claims is exposed by spawn.lua")
_stub_gm.clear_spawn_claims()
local p_a2 = _stub_gm.find_spawn_pos("beacon_a", "alpha")
check(p_a2 and p_a2.x and p_a2.z,
	"find_spawn_pos returns a valid position after claim release")
-- Lock the source: the centralised search lives in
-- sl_modebase/spawn.lua, and aaa_botmatch/mob_player.lua is a
-- thin wrapper that delegates to game_mode.find_spawn_pos.
local spawn_src
do
	local f = io.open("mods/game/sl_modebase/spawn.lua", "r")
	spawn_src = f:read("*a"); f:close()
end
check(spawn_src:find("function game_mode.find_spawn_pos") ~= nil,
	"sl_modebase/spawn.lua defines game_mode.find_spawn_pos")
check(spawn_src:find("game_mode.spawn_claims") ~= nil
	and spawn_src:find("function game_mode.clear_spawn_claims") ~= nil,
	"sl_modebase/spawn.lua owns the shared claim table and clear hook")
check(spawn_src:find("is_passable") ~= nil
	and spawn_src:find("is_ground") ~= nil
	and spawn_src:find("candidate_ok") ~= nil,
	"sl_modebase/spawn.lua has the air/floor/candidate validators")
local mob_src
do
	local f = io.open("mods/game/aaa_botmatch/mob_player.lua", "r")
	mob_src = f:read("*a"); f:close()
end
check(mob_src:find("local SPAWN_SLOTS%s*=") == nil,
	"static SPAWN_SLOTS table removed from mob_player.lua")
check(mob_src:find("function%s+next_spawn_pos") == nil,
	"old next_spawn_pos round-robin function removed from mob_player.lua")
check(mob_src:find("game_mode.find_spawn_pos") ~= nil,
	"mob_player.lua delegates to the centralised search")
check(mob_src:find("local function find_spawn_pos") == nil
	or mob_src:find("local function find_spawn_pos%(team, name%)") ~= nil,
	[[mob_player.lua no longer carries the local search (the
	wrapper is allowed but the heavy logic must be in sl_modebase)]])
-- Restore the live globals so the harness is unchanged for any
-- later phases (this test runs near the end of the suite).
_G.game_mode = saved_gm
_G.botmatch = saved_bm

section("PHASE 21c — MM's monster kills / destroys beacon: credit goes to the MM")
-- A Monster Master's monster (luaentity with `monster_owner = MM_name`)
-- killing a player must credit the MM with the kill, not the player
-- who happens to be standing nearest. Same mechanic for the beacon
-- destruction path: the MM's monster hitting the enemy beacon must
-- give the +1000 objective credit and the +1 essence to the MM.
--
-- The match_active gate is on (PHASE 12's match is still live) and
-- state.monster_master is unset at this point, so we set it to alpha
-- (an existing real player) and use a fake hitter object whose
-- get_luaentity returns { monster_owner = "alpha" }.
state.settings.match_duration = 0 -- keep this match alive through the phase
state.match_active = true -- force on for this phase
-- Disable team-elimination so killing beta doesn't immediately
-- end the match (which would zero kills and credit end-match
-- points, masking the kill-credit under test).
local saved_elimination = state.win_conditions.elimination
state.win_conditions.elimination = false
gm.set_monster_master("alpha")
-- Reset alpha's score fields so we can observe the MM credit cleanly.
local alpha_pl = gm.get_player_state("alpha")
alpha_pl.points = 0
alpha_pl.earned_points = 0
alpha_pl.kills = 0
alpha_pl.deaths = 0
alpha_pl.last_puncher = nil

-- (1) MM's monster kills beta: last_puncher on beta must be "alpha".
local beta_pl = gm.get_player_state("beta")
beta_pl.last_puncher = nil
local fake_monster_hitter = {
	is_player = function() return false end,
	get_luaentity = function() return { monster_owner = "alpha" } end,
	get_player_name = function() return nil end,
}
local cancel1 = H.fire_punchplayer(beta, fake_monster_hitter, 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 4 } }, nil, 4)
check(cancel1 == false,
	"MM's monster hitting a player is not blocked by the punch handler")
check(beta_pl.last_puncher == "alpha",
	"MM's monster killing a player sets victim's last_puncher to the MM (got "
		.. tostring(beta_pl.last_puncher) .. ")")

-- (2) Confirm the punch pipeline credits the MM on death. Drop
-- beta's HP to 0 with the MM's monster as the last puncher;
-- on_dieplayer reads last_puncher and calls award_kill_points.
-- Capture alpha's state BEFORE set_hp so we can measure the delta
-- (the end_match path inside check_team_elimination may zero kills
-- after the kill credit, so we compare deltas not absolutes).
local alpha_pl_before = gm.get_player_state("alpha")
local kills_before = alpha_pl_before.kills
local earned_before = alpha_pl_before.earned_points
gm.get_player_state("beta").last_puncher = "alpha"
beta:set_hp(0)
H.respawn(beta)
-- award_kill_points(alpha, beta) gives alpha 7 points (K/D = 1.0
-- first kill) and bumps alpha.kills by 1, beta.deaths by 1.
local alpha_after = gm.get_player_state("alpha")
check(alpha_after.kills == kills_before + 1,
	"MM gets the kill credit (alpha.kills delta = 1, got delta = "
		.. tostring(alpha_after.kills - kills_before) .. ")")
check(alpha_after.earned_points == earned_before + 7,
	"MM gets the K/D-weighted kill points (alpha.earned_points delta = 7, got delta = "
		.. tostring(alpha_after.earned_points - earned_before) .. ")")
check(alpha_after.points == 7,
	"MM's pl.points = +7 too (no end-match bonus during a live match, got "
		.. tostring(alpha_after.points) .. ")")

-- (3) MM's monster destroying the enemy beacon must credit the MM
-- with the +1000 objective and the +1 essence. Simulate by calling
-- game_mode.damage_beacon with the MM as the attacker (the
-- engine's punch pipeline forwards the monster's owner as
-- attacker_name through damage_beacon → handle_beacon_destruction).
gm.state.monster_master.essence_pool = 0
local mm_pool_before = gm.state.monster_master.essence_pool
local alpha_earned_before = gm.get_player_state("alpha").earned_points
-- Clear all last_puncher fields so the kill-loop fired by
-- handle_beacon_destruction (which calls set_hp(0) on every
-- surviving beacon_b player) does not double-count beta's death
-- (beta's last_puncher was "alpha" from the punch above).
for name, pl in pairs(state.players) do
	pl.last_puncher = nil
end
gm.damage_beacon("beacon_b", 100, "alpha", true)
-- end_match zeros kills and deaths but leaves pl.earned_points
-- alone (match.lua's clean-reset comment confirms this), so we
-- can read the +1000 objective credit here.
local alpha_earned_after = gm.get_player_state("alpha").earned_points
check(alpha_earned_after == alpha_earned_before + 1000,
	"MM's monster destroying the enemy beacon credits +1000 to the MM's earned_points (got "
		.. tostring(alpha_earned_after - alpha_earned_before) .. ")")
check(gm.state.monster_master.essence_pool == mm_pool_before + 1,
	"MM's monster destroying the enemy beacon credits +1 essence to the MM's pool (got "
		.. tostring(gm.state.monster_master.essence_pool) .. ")")
-- The MM's team (beacon_a) should have won, so the match is now
-- over — end_match already ran. Restore for the next phase.
state.match_active = false
gm.set_monster_master(nil)
state.players.alpha.phase = "alive"
state.players.alpha.eliminated = false
state.players.beta.phase = "alive"
state.players.beta.eliminated = false
state.players.beta.last_puncher = nil

-- (4) Negative control: a monster WITHOUT a monster_owner (e.g. a
-- spawner-hazard, or the soak-loop's test_harness) must NOT credit
-- the MM, and the victim's last_puncher must stay nil (so the
-- upcoming on_dieplayer no-ops, no phantom credit).
gm.state.monster_master.essence_pool = 0
local mm_pool_before2 = gm.state.monster_master.essence_pool
gm.set_monster_master("alpha")
state.match_active = true
state.settings.match_duration = 0
local gamma_pl = gm.get_player_state("gamma")
gamma_pl.last_puncher = nil
local orphan_monster = {
	is_player = function() return false end,
	get_luaentity = function() return { -- no monster_owner
		monster_variant = "stalker",
	} end,
	get_player_name = function() return nil end,
}
H.fire_punchplayer(gamma, orphan_monster, 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 4 } }, nil, 4)
check(gamma_pl.last_puncher == nil,
	"ownerless monster does NOT set victim's last_puncher (got "
		.. tostring(gamma_pl.last_puncher) .. ")")
-- And: the damage_beacon path with a literal "A Monster" attacker
-- must not credit anyone, and must not credit the MM's essence.
gm.damage_beacon("beacon_a", 50, "A Monster", true)
check(gm.state.monster_master.essence_pool == mm_pool_before2,
	"anonymous monster beacon hit does NOT credit the MM's essence pool")
state.match_active = false
gm.set_monster_master(nil)
state.win_conditions.elimination = saved_elimination -- restore
state.players.alpha.phase = "alive"
state.players.alpha.eliminated = false

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
