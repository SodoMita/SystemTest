-- ================================================================
-- tests/objective_loop_test.lua
-- Headless stub suite for the CRAFTING-TO-OBJECTIVE LOOP
-- (docs/NEXT_AGENT_PLAN.md, Turn 2 — INTEGRATION §5.4):
--
--   scavenge -> refine at the Objective Forge -> forge the Objective
--   Core -> carry it to the beacon -> deliver -> match ends
--
-- The chain had never run end-to-end: the inventory UI refuses every
-- recipe whose output is a registered node (§6.5 "placeables come
-- only from machines"), which left the whole salvage branch dead, the
-- exotic neon types were unobtainable on any map, and the only
-- "objective test" in the tree narrated the steps without performing
-- them. This suite performs them.
--
-- Covered:
--   * the map carries a forge anchor and materializes the forge node
--   * salvage veins exist and can be scavenged
--   * refining + core assembly run at the forge, never in inventory
--   * the forge is LOUD, single-job, time-gated and match-bound
--   * the core craft credits the MM pool +3 (ruling §13.3 rule 2)
--   * delivery: beacon proximity, and every refusal path
--   * match end, reset and the forge returning idle for the next match
--
-- Run: luajit tests/objective_loop_test.lua (or lua5.1)
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
for _, cmd in ipairs({ "msg", "w", "tell" }) do
	minetest.register_chatcommand(cmd, {
		params = "<name> <message>",
		func = function(_, _) return true, "[dm sent]" end,
	})
end

-- The neon block set registers through the `core` alias the engine
-- provides alongside `minetest`.
core = core or minetest

-- The neon block set (ground / construction) is real game content and
-- sl_modebase depends on it, but loading MTG `default` in a stub suite
-- is not worth it — only its sound tables are referenced.
default = default or {}
for _, fn in ipairs({ "node_sound_glass_defaults", "node_sound_stone_defaults",
	"node_sound_wood_defaults", "node_sound_metal_defaults", "node_sound_defaults" }) do
	default[fn] = default[fn] or function() return {} end
end
H.modpaths.ground = "mods/sl_blocks/ground"
H.modpaths.construction = "mods/sl_blocks/construction"
H.current_modname = "ground"
local okg, errg = pcall(dofile, "mods/sl_blocks/ground/init.lua")
if not okg then print("FATAL: ground failed: " .. tostring(errg)) os.exit(1) end
H.current_modname = "construction"
local okb, errb = pcall(dofile, "mods/sl_blocks/construction/init.lua")
if not okb then print("FATAL: construction failed: " .. tostring(errb)) os.exit(1) end

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------
-- The stub has no drop physics, so "dig a node and pick it up" is
-- modelled explicitly: fire the engine's dignode handlers (the essence
-- engine listens there), then hand the dropped node to the digger —
-- which is what the engine does when a player walks over the drop or
-- mines with an empty hand.
local function dig_into_inventory(player, pos)
	local node = minetest.get_node(pos)
	if not node or node.name == "air" then return nil end
	H.fire_dignode(pos, node, player)
	player:get_inventory():add_item("main", ItemStack(node.name .. " 1"))
	minetest.remove_node(pos)
	return node.name
end

-- Count one named node inside an inclusive box (the stub has no area
-- iterator; maps are small).
local function count_in_box(name, minp, maxp)
	local n = 0
	for x = minp.x, maxp.x do
		for y = minp.y, maxp.y do
			for z = minp.z, maxp.z do
				if H.voxels[H.vhash({ x = x, y = y, z = z })] == name then n = n + 1 end
			end
		end
	end
	return n
end

-- ----------------------------------------------------------------
section("PHASE O1 — mod load: the machine side of the crafting rule")
H.current_modname = "sl_modebase"
local ok, err = pcall(dofile, "mods/game/sl_modebase/init.lua")
check(ok, "sl_modebase loads" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then print("FATAL: aborting.") os.exit(1) end

local gm = game_mode
local state = gm.state

H.current_modname = "sl_gui"
local okc, errc = pcall(dofile, "mods/apis/sl_gui/crafting_system.lua")
check(okc, "crafting system loads" .. (okc and "" or (" -> " .. tostring(errc))))

H.current_modname = "sl_machine_crafting"
local okf, errf = pcall(dofile, "mods/game/sl_machine_crafting/init.lua")
check(okf, "sl_machine_crafting loads" .. (okf and "" or (" -> " .. tostring(errf))))
if not okf then print("FATAL: aborting.") os.exit(1) end

local FORGE = sl_machine.FORGE_NAME
check(sl_machine.get_recipes ~= nil, "machine recipe resolver registered")
check(minetest.registered_nodes[FORGE] ~= nil, "the Objective Forge node is registered")
check(sl_machine.forge_time() > 0, "forge run time is positive")

local core_def = minetest.registered_nodes["sl_modebase:objective_core"]
check(core_def ~= nil, "the Objective Core node is registered")
check(core_def.groups and core_def.groups.sl_craft_in_inventory == nil,
	"the core no longer opts into inventory crafting (machine-only)")
check(core_def.groups and (core_def.groups.objective or 0) >= 1,
	"the core is tagged objective (§6.10 A: no recipe may consume it)")
check(core_def.stack_max == 1, "the core does not stack (§6.10 A: cannot be hoarded)")

-- The gate and the machine are the same predicate, so they cannot drift.
local machine_outputs, node_recipes, non_node_recipes = {}, 0, 0
for _, entry in ipairs(sl_machine.get_recipes()) do
	machine_outputs[entry.recipe.output] = true
	node_recipes = node_recipes + 1
end
for _, recipe in ipairs(get_crafting_recipes()) do
	if minetest.registered_nodes[recipe.output] then
		check(machine_outputs[recipe.output] == true,
			"every node-output recipe is reachable at the forge: " .. tostring(recipe.output))
	else
		non_node_recipes = non_node_recipes + 1
	end
end
check(node_recipes >= 8, "the machine branch carries the salvage tree (" .. node_recipes .. " recipes)")
check(non_node_recipes >= 3, "the inventory branch still carries the personal recipes (" .. non_node_recipes .. ")")
check(not machine_outputs["sl_clothing:backpack_small"],
	"personal (non-placeable) outputs are NOT machine recipes")

H.run_mods_loaded()
H.advance(2, 0.5)

-- ----------------------------------------------------------------
section("PHASE O2 — map + match: the forge is a real map anchor")
local alpha = H.new_player("alpha")
local beta = H.new_player("beta")
local gamma = H.new_player("gamma")
H.fire_joinplayer(alpha)
H.fire_joinplayer(beta)
H.fire_joinplayer(gamma)
H.advance(1, 0.5)

state.settings.mm_auto_assign = false
state.settings.match_duration = 0
minetest.settings:set("sl_map.type", "test")
minetest.settings:set("sl_map.mobs", "0")
minetest.settings:set("sl_map.seed", "1")
minetest.settings:set("sl_machine.forge_time", "6")

-- Objective mode through the real matchmaking control, not a poke at
-- internal state: the lobby terminal's win-condition checkbox. The terminal's
-- mutating fields are admin-gated (a forged packet from any client used to be
-- able to flip win conditions), so the operator here holds sl_admin -- and the
-- two checks below that a priv-less client is refused are what keeps that gate
-- honest.
H.player_privs.alpha = { sl_admin = true }
local elim_before = state.win_conditions.elimination
local obj_before = state.win_conditions.objective
H.fire_receive_fields("beta", "sl_modebase:matchmaking",
	{ cond_objective = "true", cond_elimination = "false" })
check(state.win_conditions.objective == obj_before
	and state.win_conditions.elimination == elim_before,
	"a priv-less client cannot flip win conditions through the terminal")
H.fire_receive_fields("alpha", "sl_modebase:matchmaking", { cond_objective = "true" })
H.fire_receive_fields("alpha", "sl_modebase:matchmaking", { cond_elimination = "false" })
check(state.win_conditions.objective == true, "objective win condition enabled from the terminal")
check(state.win_conditions.elimination == false, "elimination disabled for this match")

local started, start_msg = gm.start_new_match("objective loop suite")
check(started == true, "match starts" .. (started and "" or (" -> " .. tostring(start_msg))))
check(state.match_active == true, "match active")

local desc = gm.map.current
check(desc ~= nil and desc.anchor ~= nil, "match map descriptor present")
check(desc.anchor.forge ~= nil, "the map resolves a forge anchor")
local fpos = desc.anchor.forge
check(H.voxels[H.vhash(fpos)] == FORGE, "the Objective Forge is materialized at its anchor")
check(minetest.get_meta(fpos):get_string("job_output") == "", "the forge starts idle")
check(sl_machine.status() ~= nil and sl_machine.status().present == true,
	"sl_machine.status() sees the map's forge")

-- ----------------------------------------------------------------
section("PHASE O3 — salvage: the raw neon is actually obtainable")
-- Before this turn the arena floor was square_neon and nothing else,
-- so rhombus/x/x2 — the ingredients of every component — existed
-- nowhere on any map and the chain was unwinnable.
local raw = {
	["ground:square_neon"] = count_in_box("ground:square_neon", { x = -21, y = 1, z = -11 }, { x = 21, y = 1, z = 11 }),
	["ground:rhombus_neon"] = count_in_box("ground:rhombus_neon", { x = -21, y = 1, z = -11 }, { x = 21, y = 1, z = 11 }),
	["ground:x_neon"] = count_in_box("ground:x_neon", { x = -21, y = 1, z = -11 }, { x = 21, y = 1, z = 11 }),
	["ground:x2_neon"] = count_in_box("ground:x2_neon", { x = -21, y = 1, z = -11 }, { x = 21, y = 1, z = 11 }),
}
check(raw["ground:square_neon"] >= 8, "square neon veins seeded (" .. raw["ground:square_neon"] .. " nodes)")
check(raw["ground:rhombus_neon"] >= 4, "rhombus neon veins seeded (" .. raw["ground:rhombus_neon"] .. " nodes)")
check(raw["ground:x_neon"] >= 4, "x neon veins seeded (" .. raw["ground:x_neon"] .. " nodes)")
check(raw["ground:x2_neon"] >= 4, "x2 neon veins seeded (" .. raw["ground:x2_neon"] .. " nodes)")

-- Veins sit ON the floor, never in it: scavenging may not punch a hole
-- through the arena (the floor is one node below them).
local vein_y = nil
for x = -21, 21 do
	for z = -11, 11 do
		if H.voxels[H.vhash({ x = x, y = 1, z = z })] == "ground:x_neon" then vein_y = 1 break end
	end
	if vein_y then break end
end
check(vein_y == 1, "veins sit on top of the floor plane")
check(H.voxels[H.vhash({ x = 0, y = 0, z = 0 })] ~= "air", "the floor itself is intact")

-- Scavenge the exact charge the core recipe needs.
local need = {
	["ground:square_neon"] = 8,
	["ground:rhombus_neon"] = 4,
	["ground:x_neon"] = 4,
	["ground:x2_neon"] = 4,
}
local gathered = { ["ground:square_neon"] = 0, ["ground:rhombus_neon"] = 0,
	["ground:x_neon"] = 0, ["ground:x2_neon"] = 0 }
for x = -21, 21 do
	for z = -11, 11 do
		for _, wants in ipairs({ "ground:square_neon", "ground:rhombus_neon", "ground:x_neon", "ground:x2_neon" }) do
			if gathered[wants] < need[wants] then
				local p = { x = x, y = 1, z = z }
				if H.voxels[H.vhash(p)] == wants then
					if dig_into_inventory(alpha, p) == wants then
						gathered[wants] = gathered[wants] + 1
					end
				end
			end
		end
	end
end
local ainv = alpha:get_inventory()
check(ainv:contains_item("main", ItemStack("ground:square_neon 8")), "scavenged 8 square neon")
check(ainv:contains_item("main", ItemStack("ground:rhombus_neon 4")), "scavenged 4 rhombus neon")
check(ainv:contains_item("main", ItemStack("ground:x_neon 4")), "scavenged 4 x neon")
check(ainv:contains_item("main", ItemStack("ground:x2_neon 4")), "scavenged 4 x2 neon")

-- ----------------------------------------------------------------
section("PHASE O4 — the inventory refuses every placeable")
local inv_recipe_ids = {}
for i, r in ipairs(get_crafting_recipes()) do
	if minetest.registered_nodes[r.output] then inv_recipe_ids[r.output] = i end
end
local before_counts = {}
for name, _ in pairs(inv_recipe_ids) do
	before_counts[name] = 0
	for _, stack in ipairs(ainv:get_list("main")) do
		if stack:get_name() == name then before_counts[name] = before_counts[name] + stack:get_count() end
	end
end
H.fire_receive_fields("alpha", "crafting_system",
	{ [("craft_%d"):format(inv_recipe_ids["construction:plasma"])] = "", qty_1 = "1" })
H.fire_receive_fields("alpha", "crafting_system",
	{ [("craft_%d"):format(inv_recipe_ids["sl_modebase:objective_core"])] = "", qty_1 = "1" })
check(not ainv:contains_item("main", ItemStack("construction:plasma")),
	"inventory crafting still refuses components (machine-only)")
check(not ainv:contains_item("main", ItemStack("sl_modebase:objective_core")),
	"inventory crafting refuses the Objective Core (machine-only)")

-- ----------------------------------------------------------------
section("PHASE O5 — the forge: single job, time-gated, LOUD")
local FORGE_TIME = sl_machine.forge_time()
local function recipe_for(output)
	for _, entry in ipairs(sl_machine.get_recipes()) do
		if entry.recipe.output == output then return entry end
	end
	return nil
end
local function forge_run(output, ingredients, player)
	player = player or alpha
	local entry = recipe_for(output)
	if not entry then return false, "no such machine recipe" end
	local meta = minetest.get_meta(fpos)
	local inv = meta:get_inventory()
	for item, count in pairs(ingredients) do
		inv:add_item("src", ItemStack(item .. " " .. count))
	end
	local ok_start, start_err = sl_machine.start_job(fpos, entry, player:get_player_name())
	if not ok_start then return false, start_err end
	H.advance(FORGE_TIME + 1, 0.5)
	return true
end

local forge_def = minetest.registered_nodes[FORGE]
check(forge_def.can_dig and forge_def.can_dig(fpos, alpha) == false,
	"the forge cannot be mined away mid-match (no griefing the economy)")

-- Not enough charge -> refused, nothing consumed.
local meta = minetest.get_meta(fpos)
local finv = meta:get_inventory()
finv:add_item("src", ItemStack("ground:x_neon 1"))
local ok_short, err_short = sl_machine.start_job(fpos, recipe_for("construction:plasma"), "alpha")
check(ok_short == false, "the forge refuses a short charge")
check(err_short ~= nil, "the refusal explains why: " .. tostring(err_short))
check(finv:contains_item("src", ItemStack("ground:x_neon 1")), "a refused run consumes nothing")

finv:add_item("src", ItemStack("ground:x_neon 3"))
ok_short = sl_machine.start_job(fpos, recipe_for("construction:plasma"), "alpha")
check(ok_short == true, "the forge accepts the full charge")

-- LOUD: the whole arena is told what is being made and where.
local loud = false
for _, line in ipairs(H.chat_all) do
	if line:find("Objective Forge") and line:find(minetest.pos_to_string(fpos), 1, true) then loud = true end
end
check(loud, "starting a run broadcasts the job and the forge position")

-- One job at a time.
local ok_second = sl_machine.start_job(fpos, recipe_for("construction:fire"), "alpha")
check(ok_second == false, "the forge runs one job at a time")

-- Inputs are locked while a job runs.
check(forge_def.allow_metadata_inventory_put(fpos, "src", 1, ItemStack("ground:x_neon 1"), alpha) == 0,
	"the input slots lock while a job runs")

-- Time-gated: not done before the clock runs out.
H.advance(FORGE_TIME - 2, 0.5)
check(not finv:contains_item("dst", ItemStack("construction:plasma")),
	"the output is not produced before the run finishes")
check(minetest.get_meta(fpos):get_string("job_output") == "construction:plasma",
	"the job is still running mid-way")
check(sl_machine.status().running == true, "status() reports the running job")

-- /sl_state readout: the run is public knowledge (§6.10 B "loud").
H.chat_player.alpha = {}
minetest.registered_chatcommands.sl_state.func("alpha", "")
local state_line = false
for _, line in ipairs(H.chat_player.alpha or {}) do
	if line:find("Forge: ", 1, true) and line:find("left)", 1, true) then state_line = true end
end
check(state_line, "/sl_state shows the running forge job")

H.advance(3, 0.5)
check(finv:contains_item("dst", ItemStack("construction:plasma 8")),
	"the forge produced the batch when the run finished")
check(not finv:contains_item("src", ItemStack("ground:x_neon 4")),
	"the charge was consumed up front")
check(sl_machine.status().running == false, "the forge is idle again after the run")

-- ----------------------------------------------------------------
section("PHASE O6 — refine the rest, then forge the Core")
local ok_plasma = finv:contains_item("dst", ItemStack("construction:plasma 8"))
local plasma_taken = finv:remove_item("dst", ItemStack("construction:plasma 8"))
ainv:add_item("main", plasma_taken)
check(ok_plasma and ainv:contains_item("main", ItemStack("construction:plasma 8")),
	"the plasma batch is collectable from the output slot")

local ok_sparks, e1 = forge_run("construction:sparks", { ["ground:rhombus_neon"] = 4 })
local ok_fire, e2 = forge_run("construction:fire", { ["ground:x2_neon"] = 4 })
local ok_crate, e3 = forge_run("sl_modebase:loot_crate", { ["ground:square_neon"] = 8 })
check(ok_sparks == true, "sparks refined at the forge" .. (ok_sparks and "" or (" -> " .. tostring(e1))))
check(ok_fire == true, "thermal units refined at the forge" .. (ok_fire and "" or (" -> " .. tostring(e2))))
check(ok_crate == true, "loot crates assembled at the forge" .. (ok_crate and "" or (" -> " .. tostring(e3))))

meta = minetest.get_meta(fpos)
finv = meta:get_inventory()
ainv:add_item("main", finv:remove_item("dst", ItemStack("construction:sparks 8")))
ainv:add_item("main", finv:remove_item("dst", ItemStack("construction:fire 8")))
ainv:add_item("main", finv:remove_item("dst", ItemStack("sl_modebase:loot_crate 2")))
check(ainv:contains_item("main", ItemStack("construction:sparks 8")), "sparks collected")
check(ainv:contains_item("main", ItemStack("construction:fire 8")), "thermal units collected")
check(ainv:contains_item("main", ItemStack("sl_modebase:loot_crate 2")), "loot crates collected")

-- The named craft: +3 essence (ruling §13.3 rule 2).
local pool_before_core = gm.essence_pool()
local ok_core, e4 = forge_run("sl_modebase:objective_core", {
	["sl_modebase:loot_crate"] = 2,
	["construction:plasma"] = 5,
	["construction:fire"] = 5,
	["construction:sparks"] = 5,
})
check(ok_core == true, "the Objective Core is forged" .. (ok_core and "" or (" -> " .. tostring(e4))))
check(gm.essence_pool() == pool_before_core + 3,
	"the core run credits the MM pool +3 (ruling §13.3 rule 2)")

meta = minetest.get_meta(fpos)
finv = meta:get_inventory()
local core_stack = finv:remove_item("dst", ItemStack("sl_modebase:objective_core 1"))
check(core_stack:get_count() == 1, "exactly one Core comes out of the forge")
ainv:add_item("main", core_stack)
check(ainv:contains_item("main", ItemStack("sl_modebase:objective_core 1")),
	"the Core is in the carrier's inventory")

-- ----------------------------------------------------------------
section("PHASE O7 — delivery refusals (before the winning delivery)")
local core_def_node = minetest.registered_nodes["sl_modebase:objective_core"]
local beacon_a_spawn = state.teams.beacon_a.spawn
print("  [note] carrier team: " .. tostring(state.players.alpha.team))

-- >8 blocks from the beacon: refused, and the core is not consumed.
local far_pos = { x = beacon_a_spawn.x + 20, y = beacon_a_spawn.y, z = beacon_a_spawn.z }
local before_match = state.match_active
core_def_node.after_place_node(far_pos, alpha)
check(state.match_active == before_match, "a core placed >8 blocks from the beacon does not end the match")

-- A non-beacon-team player cannot deliver.
gm.set_monster_master("beta")
local near_pos = { x = beacon_a_spawn.x + 2, y = beacon_a_spawn.y, z = beacon_a_spawn.z }
core_def_node.after_place_node(near_pos, beta)
check(state.match_active == true, "the Monster Master cannot deliver a Core")
gm.set_monster_master(nil)

-- Objective mode off: refused even at the right distance.
state.win_conditions.objective = false
core_def_node.after_place_node(near_pos, alpha)
check(state.match_active == true, "delivery refused while objective mode is off")
state.win_conditions.objective = true

-- ----------------------------------------------------------------
section("PHASE O8 — the winning delivery ends the match")
local won_team = nil
local orig_end = gm.end_match
gm.end_match = function(winner, reason)
	won_team = winner
	won_reason = reason
	return orig_end(winner, reason)
end

local deliver_pos = { x = beacon_a_spawn.x + 2, y = beacon_a_spawn.y, z = beacon_a_spawn.z }
core_def_node.after_place_node(deliver_pos, alpha)
gm.end_match = orig_end

check(won_team == "beacon_a", "delivering the Core wins for the delivering team (got " .. tostring(won_team) .. ")")
check(won_reason ~= nil and tostring(won_reason):find("Objective Core") ~= nil,
	"the win reason names the delivery: " .. tostring(won_reason))
check(not state.match_active, "the match ended")
check(gm.essence_pool() == 0, "the essence pool reset with the match")
check(sl_machine.status() == nil or sl_machine.status().running == false,
	"no forge job survives the match end")

-- No active match: the direct API refuses as well.
local ok_direct, why_direct = gm.deliver_objective("beacon_b", "beta")
check(ok_direct == false, "deliver_objective refuses with no active match")
check(why_direct == "no active match", "refusal reason: " .. tostring(why_direct))

-- ----------------------------------------------------------------
section("PHASE O9 — reset: the forge comes back, idle and empty")
local re_desc = gm.map.current
check(re_desc.anchor.forge ~= nil, "the reset descriptor still carries the forge anchor")
check(H.voxels[H.vhash(re_desc.anchor.forge)] == FORGE, "the forge is re-materialized after the reset")
check(minetest.get_meta(re_desc.anchor.forge):get_string("job_output") == "",
	"the re-placed forge is idle")
local re_inv = minetest.get_meta(re_desc.anchor.forge):get_inventory()
check(re_inv:is_empty("src") and re_inv:is_empty("dst"), "the re-placed forge holds no charge")

-- ----------------------------------------------------------------
section("PHASE O10 — a job abandoned by the match end is forfeit")
local started2 = gm.start_new_match("objective loop suite")
check(started2 == true, "second match starts" .. (started2 and "" or (" -> " .. tostring(started2))))
state.win_conditions.objective = true
state.win_conditions.elimination = false
fpos = gm.map.current.anchor.forge
meta = minetest.get_meta(fpos)
finv = meta:get_inventory()
finv:add_item("src", ItemStack("ground:x_neon 4"))
local abandoned_ok = sl_machine.start_job(fpos, recipe_for("construction:plasma"), "alpha")
check(abandoned_ok == true, "a run starts in the second match")
gm.end_match("beacon_a", "objective loop suite sweep")
H.advance(1, 0.5)
check(minetest.get_meta(fpos):get_string("job_output") == "",
	"the match end abandons the running job")
check(not finv:contains_item("dst", ItemStack("construction:plasma")),
	"an abandoned charge pays out nothing")
local forfeit_line = false
for _, line in ipairs(H.chat_all) do
	if line:find("charge is lost") then forfeit_line = true end
end
check(forfeit_line, "the forfeit is announced")

-- ----------------------------------------------------------------
section("PHASE O11 — access control: who may run the forge")
local started3 = gm.start_new_match("objective loop suite")
check(started3 == true, "third match starts")
fpos = gm.map.current.anchor.forge
forge_def.on_construct(fpos)
H.chat_player.alpha = {}
forge_def.on_rightclick(fpos, minetest.get_node(fpos), alpha, ItemStack(""))
local opened = false
for _, fs in ipairs(H.formspecs.alpha or {}) do
	if fs.formname:find("^sl_machine_crafting:forge:") then opened = true end
end
check(opened, "a beacon-team crew member can open the forge")

gm.set_monster_master("beta")
H.chat_player.beta = {}
H.formspecs.beta = {}
forge_def.on_rightclick(fpos, minetest.get_node(fpos), beta, ItemStack(""))
local mm_opened = false
for _, fs in ipairs(H.formspecs.beta or {}) do
	if fs.formname:find("^sl_machine_crafting:forge:") then mm_opened = true end
end
check(not mm_opened, "the Monster Master cannot open the forge")
gm.set_monster_master(nil)

-- The GUI field handler enforces the same rule (not just
-- on_rightclick): every player in a 3-crew match has a beacon team,
-- so the negative needs a Monster Master.
local plasma_entry = recipe_for("construction:plasma")
finv = minetest.get_meta(fpos):get_inventory()
finv:add_item("src", ItemStack("ground:x_neon 4"))
gm.set_monster_master("gamma")
H.fire_receive_fields("gamma", "sl_machine_crafting:forge:" .. gm.pos_hash(fpos),
	{ [("forge_%d"):format(plasma_entry.id)] = "" })
check(minetest.get_meta(fpos):get_string("job_output") == "",
	"the Monster Master cannot start a run through the GUI either")
gm.set_monster_master(nil)

-- ... and a crew member can.
H.fire_receive_fields("alpha", "sl_machine_crafting:forge:" .. gm.pos_hash(fpos),
	{ [("forge_%d"):format(plasma_entry.id)] = "" })
check(minetest.get_meta(fpos):get_string("job_output") == "construction:plasma",
	"a crew member starts the run through the GUI")
H.advance(sl_machine.forge_time() + 1, 0.5)
check(finv:contains_item("dst", ItemStack("construction:plasma 8")),
	"the GUI-started run completes")

-- ----------------------------------------------------------------
section("PHASE O12 — /sl_test_objective performs the chain for real")
-- The creative-mode diagnostic used to narrate the steps without
-- performing them (INTEGRATION §5.4). It now runs the same chain this
-- suite does; assert that it reports success.
gm.end_match("beacon_a", "objective loop suite sweep")
H.advance(1, 0.5)
local ok_obj, obj_log, obj_err = gm.run_headless_objective_test()
check(ok_obj == true, "/sl_test_objective runs the chain" .. (ok_obj and "" or (" -> " .. tostring(obj_err))))
check(type(obj_log) == "table" and #obj_log >= 5,
	"the diagnostic logs every step it performed (" .. tostring(obj_log and #obj_log or 0) .. " steps)")
local logged_core = false
if obj_log then
	for _, line in ipairs(obj_log) do
		if line:find("SYSTEM OBJECTIVE CORE") then logged_core = true end
	end
end
check(logged_core, "the diagnostic reached a forged Objective Core")
check(not state.match_active, "the diagnostic's delivery ended its match")

-- ----------------------------------------------------------------
section("PHASE O13 — hardening: a refused dig must not eat the charge")
-- can_dig is a Lua-level convention: the engine calls on_dig whether
-- or not can_dig would refuse. A naive on_dig would spill the charge
-- and then have the dig refused — the crew loses the charge to a
-- punch that did nothing.
local started4 = gm.start_new_match("objective loop suite")
check(started4 == true, "fourth match starts")
fpos = gm.map.current.anchor.forge
forge_def.on_construct(fpos)
finv = minetest.get_meta(fpos):get_inventory()
finv:add_item("src", ItemStack("ground:x_neon 4"))
forge_def.on_dig(fpos, minetest.get_node(fpos), alpha)
check(finv:contains_item("src", ItemStack("ground:x_neon 4")),
	"a dig refused by can_dig leaves the charge in the slots")
check(H.voxels[H.vhash(fpos)] == FORGE, "and the forge is still standing")

-- Inputs lock in BOTH directions while a job runs.
finv:add_item("src", ItemStack("ground:x_neon 4"))
local move_entry = recipe_for("construction:plasma")
sl_machine.start_job(fpos, move_entry, "alpha")
check(forge_def.allow_metadata_inventory_move(fpos, "main", 1, "src", 1, 4, alpha) == 0,
	"nothing can be moved INTO the input slots mid-run either")
check(forge_def.allow_metadata_inventory_move(fpos, "src", 1, "main", 1, 4, alpha) == 0,
	"nothing can be moved OUT of the input slots mid-run")

gm.end_match("beacon_a", "objective loop suite sweep")
H.advance(1, 0.5)
check(not finv:contains_item("src", ItemStack("ground:x_neon")),
	"the match-end sweep leaves the forge slots empty")
check(minetest.get_meta(fpos):get_string("job_output") == "", "and idle")

-- Outside a match the forge can be mined, and the charge spills
-- rather than being deleted with the machine.
finv:add_item("src", ItemStack("ground:x_neon 4"))
local drops_before = #H.item_drops
forge_def.on_dig(fpos, minetest.get_node(fpos), alpha)
check(#H.item_drops > drops_before, "mining a cold forge spills its charge on the floor")

-- ----------------------------------------------------------------
section("PHASE O14 — the production arena feeds the same loop")
-- The test arena is deterministic; the procedural arena is what
-- players actually load. It must seed the same salvage veins — before
-- this turn the exotic neon types existed on no map at all.
gm.map.prepare({ type = "procedural", seed = 424242, origin = { x = 0, y = 30, z = 0 } })
local pd = gm.map.current
check(pd ~= nil and pd.type == "procedural", "procedural arena built")
check(pd.anchor.forge ~= nil, "the procedural arena resolves a forge anchor")
check(H.voxels[H.vhash(pd.anchor.forge)] == FORGE, "the procedural arena materializes the forge")
local pv = {}
for _, t in ipairs({ "ground:square_neon", "ground:rhombus_neon",
	"ground:x_neon", "ground:x2_neon" }) do
	pv[t] = count_in_box(t,
		{ x = pd.minp.x, y = pd.origin.y + 1, z = pd.minp.z },
		{ x = pd.maxp.x, y = pd.origin.y + 1, z = pd.maxp.z })
end
check(pv["ground:square_neon"] >= 8, "procedural square veins (" .. pv["ground:square_neon"] .. " nodes)")
check(pv["ground:rhombus_neon"] >= 4, "procedural rhombus veins (" .. pv["ground:rhombus_neon"] .. " nodes)")
check(pv["ground:x_neon"] >= 4, "procedural x veins (" .. pv["ground:x_neon"] .. " nodes)")
check(pv["ground:x2_neon"] >= 4, "procedural x2 veins (" .. pv["ground:x2_neon"] .. " nodes)")

-- Stations are placeables, so they are Forge outputs too. These were
-- dead recipes before this turn: registered nodes, already refused by
-- the inventory gate, with no machine anywhere to run them.
local machine_outputs2 = {}
for _, entry in ipairs(sl_machine.get_recipes()) do
	machine_outputs2[entry.recipe.output] = true
end
check(machine_outputs2["sl_modebase:ghost_altar"] == true,
	"the Ghost Altar is reachable at the forge (it was a dead recipe)")
check(machine_outputs2["sl_modebase:monster_spawner"] == true,
	"the Monster Spawner Unit is reachable at the forge")

-- ----------------------------------------------------------------
section("PHASE O15 — the Core is a story object, not a resource")
-- 6.10 A: nothing may consume it, and dying with it must hand it to
-- somebody else rather than deleting it.
local consumers = 0
for _, recipe in ipairs(get_crafting_recipes()) do
	for item, _ in pairs(recipe.ingredients) do
		if item == "sl_modebase:objective_core" then consumers = consumers + 1 end
	end
end
check(consumers == 0, "no recipe consumes the Objective Core (groups.objective)")

-- Dying with it: the core system is absent here, so the death fountain
-- drops it on the floor; with sl_weapons loaded it lands in the corpse
-- instead. Either way it changes hands — it is never destroyed.
local started5 = gm.start_new_match("objective loop suite")
check(started5 == true, "fifth match starts")
minetest.settings:set("creative_mode", "false")
ainv:add_item("main", ItemStack("sl_modebase:objective_core 1"))
check(ainv:contains_item("main", ItemStack("sl_modebase:objective_core 1")), "carrier holds the Core")
alpha:set_pos({ x = 0, y = 1, z = 0 })
alpha:set_hp(0)
local core_dropped = false
for _, d in ipairs(H.item_drops) do
	if d.name == "sl_modebase:objective_core" then core_dropped = true end
end
check(core_dropped, "dying with the Core drops it for someone else to take")
check(not ainv:contains_item("main", ItemStack("sl_modebase:objective_core")),
	"and it leaves the dead player's inventory")

-- ----------------------------------------------------------------
section("PHASE O16 — a full output slot spills, it does not delete")
fpos = gm.map.current.anchor.forge
forge_def.on_construct(fpos)
finv = minetest.get_meta(fpos):get_inventory()
-- Fill the output slot with something inert, then run a job into it.
local dst_size = finv:get_size("dst")
for i = 1, dst_size do
	finv:set_stack("dst", i, ItemStack("sl_modebase:loot_crate 1"))
end
local spill_before = #H.item_drops
finv:add_item("src", ItemStack("ground:x_neon 4"))
sl_machine.start_job(fpos, recipe_for("construction:plasma"), "alpha")
H.advance(sl_machine.forge_time() + 1, 0.5)
check(#H.item_drops > spill_before, "a full output slot spills the product on the floor")
local spilled_plasma = false
for _, d in ipairs(H.item_drops) do
	if d.name == "construction:plasma" then spilled_plasma = true end
end
check(spilled_plasma, "the spilled product is what the run made")

-- ----------------------------------------------------------------
section("PHASE O17 — stations are placeables, so the Forge builds them")
-- Loaded last on purpose: sl_weapons wraps the match lifecycle, and
-- nothing in this suite runs after this point.
gm.end_match("beacon_a", "objective loop suite sweep")
H.advance(1, 0.5)
H.modpaths.sl_weapons = "mods/game/sl_weapons"
H.current_modname = "sl_weapons"
local okw, errw = pcall(dofile, "mods/game/sl_weapons/init.lua")
check(okw, "sl_weapons loads for the station check" .. (okw and "" or (" -> " .. tostring(errw))))
if okw then
	H.run_mods_loaded()
	local machine_outputs3 = {}
	for _, entry in ipairs(sl_machine.get_recipes()) do
		machine_outputs3[entry.recipe.output] = true
	end
	check(minetest.registered_nodes["sl_weapons:fabricator"] ~= nil,
		"the Precision Fabricator is a registered node (a placeable)")
	check(machine_outputs3["sl_weapons:fabricator"] == true,
		"the Precision Fabricator is a forge output (its inventory recipe was dead)")
	check(machine_outputs3["sl_modebase:ghost_altar"] == true,
		"the Ghost Altar is a forge output")
	-- The Fabricator's OWN products are its private table, not the
	-- shared registry: the two machines must not fight over recipes.
	local overlap = 0
	for id, r in pairs(sl_weapons.FAB_RECIPES or {}) do
		if machine_outputs3[r.item] then overlap = overlap + 1 end
	end
	check(overlap == 0, "the Fabricator's recipe table and the Forge's do not overlap")
end

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
