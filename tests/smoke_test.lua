-- ================================================================
-- tests/smoke_test.lua
-- Headless smoke test for mods/game/sl_modebase against the engine
-- stub. Exercises the MATCH_LOOP_SPEC rules that are implemented:
--   * mod load path executes without error
--   * neon ground nodes register (arena building blocks)
--   * cloud cage materialization
--   * ghost chat + chat COMMAND seal (msg/w/tell guarded)
--   * ready check -> countdown -> insertion
--   * lives -> ghost cloud-cage transition
--   * ghost altar ritual + information offer
--   * evil-ghost revival (point loss, targetable, bounded sabotage)
--   * sabotage corrosion, interaction refusal, punch repair
--   * match timer, result screen, lobby reset (priv/box restore)
--   * clean restart without stale state
--   * neon grid arena: geometry, penned monsters, zero default-mod nodes
--   * infinite flat neon grid floor under every generated chunk
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
-- Load the real ground mod first so the neon arena nodes exist. The stub
-- has no engine `core` alias and no `default` mod, so shim both.
core = minetest
default = {
	node_sound_glass_defaults = function() return {} end,
	node_sound_stone_defaults = function() return {} end,
}
H.current_modname = "ground"
local ok_ground, err_ground = pcall(dofile, "mods/sl_blocks/ground/init.lua")
check(ok_ground, "ground mod loads" .. (ok_ground and "" or (" -> " .. tostring(err_ground))))
check(minetest.registered_nodes["ground:square_neon"] ~= nil, "neon grid floor node registered")
local opaque_def = minetest.registered_nodes["ground:square_neon_opaque"]
check(opaque_def ~= nil, "opaque neon grid node registered")
check(opaque_def and opaque_def.drawtype == "normal" and opaque_def.use_texture_alpha == nil,
	"opaque neon grid node is not alpha-blended (true copy, but opaque)")

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
check(H.voxels[H.vhash({ x = gs.x, y = gs.y - 1, z = gs.z })] == "ground:square_neon",
	"cage floor materialized below ghost spawn (neon grid)")
check(H.voxels[H.vhash({ x = gs.x - 5, y = gs.y, z = gs.z - 5 })] == "ground:square_neon_opaque",
	"cage corner pylon materialized (opaque neon)")

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

section("PHASE 5 — lives drain into cloud-cage ghost state")
for i = 1, 5 do
	alpha:set_hp(0)
	H.respawn(alpha)
end
check(state.players.alpha.lives == 0, "alpha lives drained to 0")
check(state.players.alpha.phase == "ghost", "alpha transitioned to ghost")
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
check(state.players.alpha.lives == (state.settings.lives or 5), "lives refilled")
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
check(joined:find("CORE A") ~= nil and joined:find("CORE B") ~= nil,
	"HUD shows public beacon integrity")
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

section("PHASE 15 — neon grid arena (default tiny map)")
-- Default settings: cube 4, grid 5x3 -> pitch 5, footprint 26x16,
-- x0=-13, z0=-8. Four special cubes, the rest pen one monster each.
local function vox(x, y, z)
	return H.voxels[H.vhash({ x = x, y = y, z = z })]
end
local function count_monsters()
	local n = 0
	for _, obj in ipairs(H.luaentities) do
		local le = obj.get_luaentity and obj:get_luaentity()
		if le and le.name == "sl_modebase:monster" then n = n + 1 end
	end
	return n
end

check(gm.build_test_arena({ x = 0, y = 0, z = 0 }) == true, "arena build accepted")
check(vox(-13, 0, -8) == "ground:square_neon", "floor is the transparent neon grid")
check(vox(12, 0, 7) == "ground:square_neon", "neon grid floor covers the far corner")
check(vox(-13, 1, 0) == "ground:square_neon_opaque", "cube walls are the opaque neon grid")
check(vox(-8, 4, 0) == "ground:square_neon_opaque", "interior wall line present")
check(vox(-8, 4, 0) ~= nil and vox(-8, 5, 0) == "air", "walls exactly as tall as the cubes")
check(vox(-4, 1, -1) == "air", "cube interiors stay hollow")
check(vox(-1, 1, -1) == "sl_modebase:ghost_altar", "ghost altar at the center cube")
check(vox(-11, 1, -1) == "ground:square_neon_opaque" and vox(-11, 2, -1) == "sl_modebase:beacon_a",
	"beacon A base: opaque neon pad + beacon")
check(vox(9, 2, -1) == "sl_modebase:beacon_b", "beacon B base on the east edge")
check(state.teams.beacon_a.spawn.x == -11 and state.teams.beacon_a.spawn.y == 3,
	"beacon A team spawn follows the arena")
check(vox(-1, 1, -6) == "ground:square_neon_opaque" and vox(-1, 2, -6) == "sl_modebase:spawn_mm",
	"monster master base: neon plinth + spawn marker")
check(state.monster_master.base_spawn.x == -1 and state.monster_master.base_spawn.y == 3,
	"monster master spawn set on the base")
check(vox(-1, 7, -1) == "ground:square_neon_opaque", "lobby deck floor above the altar cube")
check(vox(-5, 8, -5) == "ground:square_neon_opaque", "lobby deck has a rim")
check(state.lobby_spawn.x == -1 and state.lobby_spawn.y == 9,
	"lobby spawn sits on the open deck")
check(count_monsters() == 11, "one monster penned in every ordinary cube (got "
	.. count_monsters() .. ")")
do
	local placed_ok = true
	for _, obj in ipairs(H.luaentities) do
		local le = obj.get_luaentity and obj:get_luaentity()
		if le and le.name == "sl_modebase:monster" then
			local p = obj:get_pos()
			-- centered on a cube's floor node, never inside a wall line
			if p.y ~= 1 or (p.x % 1) ~= 0.5 or (p.z % 1) ~= 0.5 then
				placed_ok = false
			end
			local fx, fz = math.floor(p.x), math.floor(p.z)
			if (fx - (-13)) % 5 == 0 or (fz - (-8)) % 5 == 0 then
				placed_ok = false -- on a wall grid line
			end
		end
	end
	check(placed_ok, "monsters spawn centered inside their cubes, not in walls")
end

-- Rebuilds must not duplicate the penned monsters.
gm.build_test_arena({ x = 0, y = 0, z = 0 })
check(count_monsters() == 11, "arena rebuild does not duplicate monsters (got "
	.. count_monsters() .. ")")

-- The cube size is configurable from game settings.
H.settings["sl_arena.cube_size"] = 2
H.settings["sl_arena.grid_width"] = 3
H.settings["sl_arena.grid_depth"] = 2
gm.build_test_arena({ x = 0, y = 0, z = 0 })
check(vox(-2, 1, 0) == "ground:square_neon_opaque" and vox(-2, 2, 0) == "ground:square_neon_opaque",
	"cube size 2 -> wall pitch 3, walls two high")
check(vox(-2, 3, 0) == "air", "smaller cubes leave no tall walls behind")
check(state.lobby_spawn.y == 7, "lobby deck follows the configured cube size")
check(count_monsters() == 2, "2x2-grid monster count follows the settings (got "
	.. count_monsters() .. ")")
H.settings["sl_arena.cube_size"] = nil
H.settings["sl_arena.grid_width"] = nil
H.settings["sl_arena.grid_depth"] = nil

-- The whole generated map must be free of Minetest Game default nodes.
local leaked = {}
for key, name in pairs(H.voxels) do
	if tostring(name):sub(1, 8) == "default:" then
		table.insert(leaked, key .. "=" .. tostring(name))
	end
end
check(#leaked == 0, "generated map contains no default-mod nodes ("
	.. table.concat(leaked, ", ") .. ")")

section("PHASE 16 — infinite flat neon grid floor")
-- Every chunk that crosses ground level gets a flat neon grid floor, so
-- players can walk off the arena forever and never fall into the void.
H.fire_on_generated({ x = 800, y = 0, z = -300 }, { x = 815, y = 15, z = -285 })
check(vox(800, 0, -300) == "ground:square_neon", "far chunk floored (near corner)")
check(vox(815, 0, -285) == "ground:square_neon", "far chunk floored (far corner)")
check(vox(807, 0, -292) == "ground:square_neon", "far chunk floored (middle)")
check(vox(807, 1, -292) == nil, "floor generation adds nothing above the surface")

-- Negative coordinates are floored too: the plane is infinite both ways.
H.fire_on_generated({ x = -5000, y = -32, z = 5000 }, { x = -4985, y = 47, z = 5015 })
check(vox(-4992, 0, 5007) == "ground:square_neon", "negative-coordinate chunk floored")

-- Chunks that do not cross ground level stay untouched.
H.fire_on_generated({ x = 800, y = 32, z = 300 }, { x = 815, y = 47, z = 315 })
H.fire_on_generated({ x = 900, y = -16, z = 300 }, { x = 915, y = -1, z = 315 })
check(vox(807, 40, 307) == nil, "no floor in chunks above ground level")
check(vox(907, -8, 307) == nil, "no floor in chunks below ground level")

-- The arena floor and the infinite floor are one flat plane.
check(vox(0, 0, 0) == "ground:square_neon", "arena sits on the same flat plane")
check(gm.generate_floor({ x = 2000, y = 0, z = 0 }, { x = 2000, y = 0, z = 0 }) == 1,
	"generate_floor reports the number of columns floored")

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
