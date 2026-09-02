-- ================================================================
-- tests/essence_test.lua
-- Headless stub suite for the MM essence engine (ruling §13.3):
--   * provenance: crew-placed nodes -> price (groups.sl_essence_value)
--   * dig credits the pool at price; un-priced nodes pay nothing
--   * map-placed / MM-placed / monster-placed / pre-match ignored
--   * named crafts pay directly (objective core craft -> +3)
--   * pool is per-match: reset at match start and match end
--   * ambient hazard: no-MM match spawns security units at thresholds
--   * essence is NOT score: the points path is untouched
--   * readouts: /sl_state line + spawner GUI + spawner draws pool-first
--
-- Run: lua5.1 tests/essence_test.lua (or luajit)
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

section("PHASE E1 — mod load path")
H.current_modname = "sl_modebase"
local ok, err = pcall(dofile, "mods/game/sl_modebase/init.lua")
check(ok, "init.lua loads without error" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then
	print("FATAL: mod failed to load; aborting.")
	os.exit(1)
end

local gm = game_mode
local state = game_mode.state
local mm = state.monster_master

check(game_mode.essence_price ~= nil, "essence_price API registered")
check(game_mode.add_mm_essence ~= nil, "add_mm_essence API registered")
check(game_mode.essence_reset ~= nil, "essence_reset API registered")
check(game_mode.essence_pool() == 0, "pool starts at zero")
check(game_mode.ESSENCE_CRAFT_CREDITS["sl_modebase:objective_core"] == 3,
	"objective core is the named +3 craft")

H.run_mods_loaded()
H.advance(3, 0.5)

section("PHASE E2 — players join, no match yet")
local alpha = H.new_player("alpha")
local beta = H.new_player("beta")
local gamma = H.new_player("gamma")
H.fire_joinplayer(alpha)
H.fire_joinplayer(beta)
H.fire_joinplayer(gamma)
H.advance(1, 0.5)

section("PHASE E3 — before-match placement is ignored")
H.fire_placenode({ x = 5, y = 1, z = 5 }, { name = "sl_modebase:loot_crate" }, alpha)
check(mm.essence_provenance[H.vhash({ x = 5, y = 1, z = 5 })] == nil,
	"placement outside a match records no provenance")

section("PHASE E4 — match start resets the pool (per-match state)")
-- Deterministic roster: no random Monster Master; the map stays the
-- deterministic test arena with no initial mob population (so entity
-- counts below are unambiguous).
state.settings.mm_auto_assign = false
state.settings.match_duration = 0
minetest.settings:set("sl_map.type", "test")
minetest.settings:set("sl_map.mobs", "0")
minetest.settings:set("sl_map.seed", "1")

-- Stale state must not leak: inject a pool and provenance, then start.
mm.essence_pool = 7
mm.essence_provenance[H.vhash({ x = 5, y = 1, z = 5 })] = 99
local started, start_msg = gm.start_new_match("essence suite")
check(started == true, "match starts" .. (started and "" or (" -> " .. tostring(start_msg))))
check(state.match_active == true, "match active")
check(mm.essence_pool == 0, "pool reset at match start")
check(next(mm.essence_provenance) == nil, "provenance cleared at match start")
check(state.players.alpha.team ~= nil and state.players.beta.team ~= nil,
	"players assigned to beacon teams")

section("PHASE E5 — provenance: priced placement recorded")
local priced_pos = { x = 5, y = 1, z = 5 }
H.fire_placenode(priced_pos, { name = "sl_modebase:loot_crate" }, alpha)
check(mm.essence_provenance[H.vhash(priced_pos)] == 1,
	"loot crate placement recorded at its price (1)")
check(gm.essence_pool() == 0, "placing does not credit the pool")

section("PHASE E6 — un-priced nodes pay nothing")
local free_pos = { x = 6, y = 1, z = 5 }
H.fire_placenode(free_pos, { name = "default:stone" }, alpha)
check(mm.essence_provenance[H.vhash(free_pos)] == nil,
	"rubble/scaffolding (price 0) is not tracked")

section("PHASE E7 — dig credits the pool at price")
local pool_before = mm.essence_pool
H.fire_dignode(priced_pos, { name = "sl_modebase:loot_crate" }, beta) -- any digger
check(mm.essence_pool == pool_before + 1, "dig credits the pool at the node's price")
check(mm.essence_provenance[H.vhash(priced_pos)] == nil, "provenance dropped after the dig")

-- Digging an un-tracked node pays nothing.
H.fire_dignode({ x = 7, y = 1, z = 5 }, { name = "default:stone" }, beta)
check(mm.essence_pool == pool_before + 1, "digging an un-priced node pays nothing")

section("PHASE E8 — map-placed nodes never pay (map.building)")
gm.map.building = true
H.fire_placenode({ x = 8, y = 1, z = 5 }, { name = "sl_modebase:loot_crate" }, alpha)
gm.map.building = false
check(mm.essence_provenance[H.vhash({ x = 8, y = 1, z = 5 })] == nil,
	"map materialization placement ignored")

section("PHASE E9 — MM-placed and monster-placed nodes never pay")
gm.set_monster_master("beta") -- beta leaves the beacon teams
H.fire_placenode({ x = 9, y = 1, z = 5 }, { name = "sl_modebase:loot_crate" }, beta)
check(mm.essence_provenance[H.vhash({ x = 9, y = 1, z = 5 })] == nil,
	"Monster Master placement ignored")
H.fire_placenode({ x = 10, y = 1, z = 5 }, { name = "sl_modebase:loot_crate" }, nil)
check(mm.essence_provenance[H.vhash({ x = 10, y = 1, z = 5 })] == nil,
	"placerless residue/scorch placement ignored")
gm.set_monster_master(nil)
check(state.monster_master.player == nil, "MM cleared for the rest of the suite")

local core_entry

section("PHASE E10 — the machine gate and the named +3 craft")
H.current_modname = "sl_gui"
local okc, errc = pcall(dofile, "mods/apis/sl_gui/crafting_system.lua")
check(okc, "crafting system loads" .. (okc and "" or (" -> " .. tostring(errc))))

-- Registering machine crafting gives the inventory gate its other
-- half: the Objective Forge runs exactly the recipes the inventory
-- refuses (output is a registered node).
H.current_modname = "sl_machine_crafting"
local okf, errf = pcall(dofile, "mods/game/sl_machine_crafting/init.lua")
check(okf, "machine crafting loads" .. (okf and "" or (" -> " .. tostring(errf))))
check(sl_machine ~= nil and sl_machine.start_job ~= nil, "forge API exposed")

-- Placeables are machine-only (§6.5 rule): both of these are
-- registered nodes, so the inventory UI refuses BOTH. (The objective
-- core carried a temporary sl_craft_in_inventory opt-in for the
-- essence turn; the objective-loop turn removed it — the Forge is the
-- route now.)
local ainv = alpha:get_inventory()
ainv:add_item("main", ItemStack("sl_modebase:loot_crate 2"))
ainv:add_item("main", ItemStack("construction:plasma 5"))
ainv:add_item("main", ItemStack("construction:fire 5"))
ainv:add_item("main", ItemStack("construction:sparks 5"))

H.fire_receive_fields("alpha", "crafting_system", { craft_13 = "", qty_13 = "1" })
check(not ainv:contains_item("main", ItemStack("sl_modebase:monster_spawner")),
	"machine-gated node output still refused in inventory crafting")

local pool_before_craft = mm.essence_pool
H.fire_receive_fields("alpha", "crafting_system", { craft_16 = "", qty_16 = "1" })
check(not ainv:contains_item("main", ItemStack("sl_modebase:objective_core")),
	"objective core is machine-gated too (no inventory opt-in any more)")
check(mm.essence_pool == pool_before_craft, "a refused inventory craft credits no essence")
check(ainv:contains_item("main", ItemStack("sl_modebase:loot_crate 2")),
	"a refused craft consumes nothing")

-- The machine route: feed the Forge and let it run.
minetest.settings:set("sl_machine.forge_time", "2")
local forge_pos = { x = 40, y = 5, z = 40 }
minetest.set_node(forge_pos, { name = sl_machine.FORGE_NAME })
minetest.registered_nodes[sl_machine.FORGE_NAME].on_construct(forge_pos)
local finv = minetest.get_meta(forge_pos):get_inventory()
for _, entry in ipairs(sl_machine.get_recipes()) do
	if entry.recipe.output == "sl_modebase:objective_core" then core_entry = entry end
end
check(core_entry ~= nil, "the Objective Core is a machine recipe")
ainv:remove_item("main", ItemStack("sl_modebase:loot_crate 2"))
ainv:remove_item("main", ItemStack("construction:plasma 5"))
ainv:remove_item("main", ItemStack("construction:fire 5"))
ainv:remove_item("main", ItemStack("construction:sparks 5"))
finv:add_item("src", ItemStack("sl_modebase:loot_crate 2"))
finv:add_item("src", ItemStack("construction:plasma 5"))
finv:add_item("src", ItemStack("construction:fire 5"))
finv:add_item("src", ItemStack("construction:sparks 5"))

local started_job = sl_machine.start_job(forge_pos, core_entry, "alpha")
check(started_job == true, "forge accepts the core charge")
check(mm.essence_pool == pool_before_craft, "starting a job credits nothing yet")
H.advance(sl_machine.forge_time() + 1, 0.5)
check(finv:contains_item("dst", ItemStack("sl_modebase:objective_core 1")),
	"objective core produced by the Objective Forge")
check(mm.essence_pool == pool_before_craft + 3,
	"objective-core forge run credits the pool +3 (ruling §13.3 rule 2)")
check(not finv:contains_item("src", ItemStack("sl_modebase:loot_crate 2")),
	"the forge consumed the charge up front")

-- A non-named craft credits nothing (equipment is not a named craft).
ainv:add_item("main", ItemStack("sl_modebase:loot_crate 1"))
ainv:add_item("main", ItemStack("construction:fire 2"))
pool_before_craft = mm.essence_pool
H.fire_receive_fields("alpha", "crafting_system", { craft_8 = "", qty_8 = "1" })
check(ainv:contains_item("main", ItemStack("sl_clothing:backpack_small 1")),
	"equipment craft still works")
check(mm.essence_pool == pool_before_craft, "non-named craft credits no essence")

section("PHASE E11 — essence is fuel, not score")
state.players.alpha.points = 42
state.players.beta.points = 7
local pool_before_pts = mm.essence_pool
H.fire_placenode({ x = 11, y = 1, z = 5 }, { name = "sl_modebase:loot_crate" }, gamma)
H.fire_dignode({ x = 11, y = 1, z = 5 }, { name = "sl_modebase:loot_crate" }, gamma)
check(mm.essence_pool == pool_before_pts + 1, "essence activity credits the pool")
check(state.players.alpha.points == 42 and state.players.beta.points == 7,
	"scoreboard values untouched by essence activity")

section("PHASE E12 — /sl_state readout")
minetest.registered_chatcommands.sl_state.func("alpha", "")
local state_line = false
for _, line in ipairs(H.chat_player.alpha or {}) do
	if line:find("Essence pool: " .. tostring(mm.essence_pool)) then state_line = true end
end
check(state_line, "/sl_state shows the match essence pool")

section("PHASE E13 — spawner: GUI readout + pool-first spend")
gm.set_monster_master("beta")
local sp_pos = { x = 25, y = 12, z = 25 }
minetest.set_node(sp_pos, { name = "sl_modebase:monster_spawner" })
local sp_def = minetest.registered_nodes["sl_modebase:monster_spawner"]
check(sp_def ~= nil, "monster_spawner node registered")
sp_def.on_construct(sp_pos)
local sp_meta = minetest.get_meta(sp_pos)

gm.add_mm_essence(5, "test credit")
local pool_for_gui = mm.essence_pool
sp_def.on_rightclick(sp_pos, minetest.get_node(sp_pos), beta, ItemStack(""), nil)
local pool_label = false
for _, fs in ipairs(H.formspecs.beta or {}) do
	if fs.formname:find("^sl_modebase:monster_spawner:")
		and fs.form:find("Match pool: " .. tostring(pool_for_gui)) then
		pool_label = true
	end
end
check(pool_label, "spawner GUI shows the match pool")

-- The unit's feed is empty; the pool covers the spawn.
sp_meta:set_int("spawner_cd", 0)
local spawns_before = #H.entity_spawns
local spawned_ok = gm.spawner_activate("beta", sp_pos, "stalker")
check(spawned_ok == true, "spawner runs on match-pool fuel with an empty feed")
check(mm.essence_pool == pool_for_gui - 1, "spawn burned the match pool first")
check(gm.count_feed_essence(sp_meta:get_inventory()) == 0, "unit feed untouched while pool had fuel")
check(#H.entity_spawns == spawns_before + 1, "stalker produced from pool fuel")
gm.set_monster_master(nil)

section("PHASE E14 — match end resets the pool")
local mm_end = state.monster_master
gm.end_match("beacon_a", "essence suite sweep")
H.advance(1, 0.5)
check(not state.match_active, "match ended")
check(mm_end.essence_pool == 0, "pool reset at match end")
check(next(mm_end.essence_provenance) == nil, "provenance cleared at match end")
check(mm_end.essence_hazard_level == 0, "hazard counter reset at match end")

section("PHASE E15 — ambient hazard: no-MM match, threshold security units")
local started2 = gm.start_new_match("essence suite")
check(started2 == true, "second match starts")
check(state.monster_master.player == nil, "no Monster Master in this match")
check(mm.essence_pool == 0, "fresh pool for the second match")

local spawns_before = #H.entity_spawns
gm.add_mm_essence(10, "test credit")
check(mm.essence_pool == 10, "pool accrued to the first threshold")
check(#H.entity_spawns == spawns_before + 1, "first automated security unit spawned")
local unit = H.entity_spawns[#H.entity_spawns]
check(unit.name == "sl_modebase:monster", "hazard unit is the shared monster entity")
local pad = gm.map.current.anchor.mm_pad
check(unit.pos.x == pad.x and unit.pos.y == pad.y + 1 and unit.pos.z == pad.z,
	"hazard unit spawned from the Node (MM pad anchor)")
local custodian_found = false
for _, e in pairs(H.luaentities) do
	if e.monster_variant == "custodian" then custodian_found = true end
end
check(custodian_found, "hazard unit is the custodian variant")
local hazard_broadcast = false
for _, line in ipairs(H.chat_all) do
	if line:find("security unit") then hazard_broadcast = true end
end
check(hazard_broadcast, "hazard spawn announced")

gm.add_mm_essence(15, "test credit") -- pool 25 -> second threshold
check(#H.entity_spawns == spawns_before + 2, "second security unit at the second threshold")
gm.add_mm_essence(5, "test credit") -- pool 30, below 50
check(#H.entity_spawns == spawns_before + 2, "no unit below the next threshold")

-- A live Monster Master means no automation: the pool is theirs.
gm.set_monster_master("beta")
local with_mm = #H.entity_spawns
gm.add_mm_essence(30, "test credit") -- pool 60 >= 50, but the MM is live
check(#H.entity_spawns == with_mm, "no ambient hazard while a Monster Master is live")
check(mm.essence_pool == 60, "pool still accrues for the MM to spend")
gm.set_monster_master(nil)

section("PHASE E16 — threshold knobs from settings")
gm.end_match("beacon_a", "essence suite sweep")
H.advance(1, 0.5)
minetest.settings:set("sl_essence.thresholds", "20,40")
gm.start_new_match("essence suite")
check(mm.essence_pool == 0, "fresh pool after knob change")
local spawns0 = #H.entity_spawns
gm.add_mm_essence(15, "test credit") -- below the first custom threshold
check(#H.entity_spawns == spawns0, "no unit below the custom first threshold (20)")
gm.add_mm_essence(5, "test credit") -- pool 20
check(#H.entity_spawns == spawns0 + 1, "unit spawned at the custom first threshold")
gm.end_match("beacon_a", "essence suite sweep")
H.advance(1, 0.5)
check(mm.essence_pool == 0, "pool reset after the final match")

section("PHASE E17 — pricing mechanism reads def groups")
minetest.register_node("essence_test:gadget", {
	description = "test gadget",
	groups = { cracky = 1, sl_essence_value = 2 },
})
check(game_mode.essence_price("essence_test:gadget") == 2,
	"price read from groups.sl_essence_value on a node def")
check(game_mode.essence_price("essence_test:missing") == 0,
	"unknown node def prices at zero")

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
