-- ================================================================
-- tests/smoke_test.lua
-- Headless smoke test for mods/game/sl_modebase against the engine
-- stub. Exercises the MATCH_LOOP_SPEC rules that are implemented:
--   * mod load path executes without error
--   * ghost chat + chat COMMAND seal (msg/w/tell guarded)
--   * cloud cage materialization
--   * ready check -> countdown -> insertion
--   * lives -> ghost cloud-cage transition
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

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
