-- System Looting test harness
-- Server-side AI agents and a deterministic arena builder. This is intentionally
-- isolated from the production player state machine: it is a headless smoke test.
local S = game_mode.S
local state = game_mode.state
local modname = game_mode.modname
local bots = {}
local arena_built = false

local function creative_only(name)
	return minetest.settings:get_bool("creative_mode")
end

local function node(name)
	if minetest.registered_nodes[name] then
		return name
	end
	if minetest.registered_nodes["ground:square_neon"] then
		return "ground:square_neon"
	end
	return name
end

-- ================================================================
-- Deterministic test arena — the "test procedural" map type.
-- Registered with the map system as a builder so matches on it get
-- the same initial-state reset contract as every other map.
-- ================================================================
local function build_test_map(opts)
	local origin = table.copy(opts.origin) or { x = 0, y = 0, z = 0 }
	local floor = node("ground:square_neon")
	local wall = node("ground:square_neon_opaque")

	-- Compact 41 x 21 neon arena: glasslike floor, opaque perimeter, MM pad.
	for x = -20, 20 do
		for z = -10, 10 do
			minetest.set_node({x=origin.x+x, y=origin.y, z=origin.z+z}, {name=floor})
			if x == -20 or x == 20 or z == -10 or z == 10 then
				for y = 1, 3 do
					minetest.set_node({x=origin.x+x, y=origin.y+y, z=origin.z+z}, {name=wall})
				end
			end
		end
	end
	for _, x in ipairs({-12, 12}) do
		for dx = -3, 3 do
			for dz = -3, 3 do
				minetest.set_node({x=origin.x+x+dx, y=origin.y+1, z=origin.z+dz}, {name=wall})
			end
		end
	end
	-- Monster master base at +Z of the arena.
	for x = -3, 3 do
		for z = 12, 18 do
			minetest.set_node({x=origin.x+x, y=origin.y, z=origin.z+z}, {name=floor})
			if x == -3 or x == 3 or z == 12 or z == 18 then
				for y = 1, 4 do
					minetest.set_node({x=origin.x+x, y=origin.y+y, z=origin.z+z}, {name=wall})
				end
			end
		end
	end

	-- SALVAGE VEINS — the raw material of the machine chain, in fixed
	-- mirrored pairs (the test arena must stay byte-for-byte
	-- reproducible for CI). They sit ON the floor, never in it, so
	-- scavenging cannot punch a hole in the arena.
	for _, v in ipairs({
		{ -8, -4, "ground:square_neon" }, { 8, 4, "ground:square_neon" },
		{ -8, 4, "ground:rhombus_neon" }, { 8, -4, "ground:rhombus_neon" },
		{ -4, -6, "ground:x_neon" },      { 4, 6, "ground:x_neon" },
		{ -4, 6, "ground:x2_neon" },      { 4, -6, "ground:x2_neon" },
	}) do
		for dx = 0, 1 do
			for dz = 0, 1 do
				minetest.set_node(
					{ x = origin.x + v[1] + dx, y = origin.y + 1, z = origin.z + v[2] + dz },
					{ name = node(v[3]) })
			end
		end
	end

	-- Deterministic initial mob population (fixed seed: same arena,
	-- same mobs, every time).
	local mobs = {}
	local budget = tonumber(minetest.settings:get("sl_map.mobs")) or 6
	local variants = game_mode.MONSTER_TYPE_ORDER or { "stalker" }
	local rng = game_mode.map.make_rng(1)
	local spots = {
		{ -6, 5 }, { 6, 5 }, { -6, -5 }, { 6, -5 }, { 0, 6 }, { 0, -6 },
		{ -16, 0 }, { 16, 0 }, { -9, 7 }, { 9, 7 }, { -9, -7 }, { 9, -7 },
	}
	for i = 1, math.min(budget, #spots) do
		table.insert(mobs, {
			pos = { x = origin.x + spots[i][1], y = origin.y + 1, z = origin.z + spots[i][2] },
			variant = variants[((i - 1) % #variants) + 1],
		})
	end

	return {
		type = "test",
		name = "Deterministic test arena",
		seed = opts.seed,
		origin = origin,
		anchor = {
			beacon_a = { x = origin.x - 12, y = origin.y + 2, z = origin.z },
			beacon_b = { x = origin.x + 12, y = origin.y + 2, z = origin.z },
			altar = { x = origin.x, y = origin.y + 1, z = origin.z },
			-- The Objective Forge: one per arena, on neutral ground a
			-- few nodes off the midfield altar.
			forge = { x = origin.x, y = origin.y + 1, z = origin.z + 4 },
			mm_pad = { x = origin.x, y = origin.y + 1, z = origin.z + 15 },
			lobby = { x = origin.x, y = origin.y + 5, z = origin.z },
			ghost = { x = origin.x, y = origin.y + 40, z = origin.z },
		},
		mobs = mobs,
		minp = { x = origin.x - 21, y = origin.y - 2, z = origin.z - 11 },
		maxp = { x = origin.x + 21, y = origin.y + 6, z = origin.z + 19 },
	}
end

if game_mode.map and game_mode.map.register_builder then
	game_mode.map.register_builder("test", build_test_map)
end

function game_mode.build_test_arena(origin)
	origin = origin or {x = 0, y = 0, z = 0}
	if game_mode.map and game_mode.map.prepare then
		local ok, err = game_mode.map.prepare({ type = "test", origin = origin })
		if not ok then
			minetest.log("error", "[sl_test] arena build failed: " .. tostring(err))
			return false
		end
	else
		minetest.log("error", "[sl_test] map system unavailable")
		return false
	end
	arena_built = true
	minetest.log("action", "[sl_test] deterministic arena generated at " .. minetest.pos_to_string(origin))
	return true
end

-- Generate the arena automatically when the origin map block is first generated.
-- Auto-arena on worldgen. Disabled when sl_test.auto_arena = "false" —
-- aaa_botmatch sets that at load time (it loads first) because it builds
-- and owns its own arena; the manual /sl_test_arena command still works.
if minetest.settings:get("sl_test.auto_arena") ~= "false" then
	minetest.register_on_generated(function(minp, maxp)
		if arena_built then return end
		if minp.x <= 0 and maxp.x >= 0 and minp.z <= 0 and maxp.z >= 0 and minp.y <= 0 and maxp.y >= 0 then
			game_mode.build_test_arena({x=0, y=0, z=0})
		end
	end)
end

local function register_ai_entity()
	minetest.register_entity(modname .. ":ai_player", {
		initial_properties = {
			physical = true, collide_with_objects = true,
			collisionbox = {-0.35, 0, -0.35, 0.35, 1.7, 0.35},
			visual = "mesh", mesh = "player.obj", textures = {sl_texgen.texture("player_texture.png")},
			visual_size = {x=1, y=1}, static_save = false,
		},
		team = "beacon_a", target = nil, action_timer = 0,
		on_step = function(self, dtime)
			if not state.match_active then return end
			self.action_timer = self.action_timer + dtime
			local team = state.teams[self.team]
			if not team or not team.spawn then return end
			local pos = self.object:get_pos()
			local target = self.target or ((self.team == "beacon_a") and state.teams.beacon_b.spawn or state.teams.beacon_a.spawn)
			if not pos or not target then return end
			local delta = vector.subtract(target, pos)
			local distance = vector.length(delta)
			if distance > 2 then
				local dir = vector.normalize(delta)
				self.object:set_velocity({x=dir.x * 1.5, y=0, z=dir.z * 1.5})
			else
				self.object:set_velocity({x=0, y=0, z=0})
			end
			if distance < 3 and self.action_timer >= 2 then
				self.action_timer = 0
				local victim = (self.team == "beacon_a") and "beacon_b" or "beacon_a"
				game_mode.damage_beacon(victim, 5, self.bot_name or "AI")
			end
		end,
	})
end
register_ai_entity()

function game_mode.spawn_test_bots(count)
	count = math.max(2, math.min(tonumber(count) or 2, 8))
	game_mode.build_test_arena({x=0, y=0, z=0})
	for _, obj in ipairs(bots) do if obj and obj:get_luaentity() then obj:remove() end end
	bots = {}
	state.match_active = true
	for i = 1, count do
		local team = (i % 2 == 1) and "beacon_a" or "beacon_b"
		local spawn = state.teams[team].spawn
		local obj = minetest.add_entity({x=spawn.x, y=spawn.y, z=spawn.z + (i-1) * 0.5}, modname .. ":ai_player")
		if obj then
			local lua = obj:get_luaentity(); lua.team = team; lua.bot_name = "AI_" .. i
			table.insert(bots, obj)
		end
	end
	game_mode.broadcast(S("Headless AI test started with @1 agents.", tostring(#bots)))
	return #bots
end

minetest.register_chatcommand("sl_test_arena", {
	description = S("Generate the deterministic headless test arena (creative only)"),
	func = function(name)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		game_mode.build_test_arena({x=0, y=0, z=0})
		return true, S("Test arena generated at the origin.")
	end,
})

minetest.register_chatcommand("sl_test_bots", {
	params = "[count]",
	description = S("Spawn deterministic AI players (creative only)"),
	func = function(name, param)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		return true, S("Spawned @1 AI players.", tostring(game_mode.spawn_test_bots(param)))
	end,
})

-- Full objective-path smoke test. This deliberately runs without
-- clients and PERFORMS the resource -> machine -> objective ->
-- delivery sequence against the real systems: it scavenges the map's
-- salvage veins, refines them at the Objective Forge, forges the
-- Objective Core and delivers it. (The previous version narrated the
-- same steps without performing them, which is exactly the gap that
-- let a dead crafting tree ship.)
function game_mode.run_headless_objective_test()
	game_mode.build_test_arena({x=0, y=0, z=0})
	state.match_active = true
	state.win_conditions.objective = true
	state.win_conditions.elimination = false
	state.teams.beacon_a.hp = state.settings.beacon_hp or 100
	state.teams.beacon_b.hp = state.settings.beacon_hp or 100

	local log = {}
	local function step(message)
		table.insert(log, message)
		minetest.log("action", "[sl_test][objective] " .. message)
	end
	local function fail(message)
		state.match_active = false
		return false, log, message
	end

	-- 1. The machine must exist on the map (it is a map anchor now).
	if not sl_machine then return fail("sl_machine_crafting is not loaded") end
	local anchor = game_mode.map and game_mode.map.current and game_mode.map.current.anchor
	if not anchor or not anchor.forge then return fail("the map resolved no forge anchor") end
	local fpos = anchor.forge
	if minetest.get_node(fpos).name ~= sl_machine.FORGE_NAME then
		return fail("no Objective Forge at the map anchor")
	end
	local inv = minetest.get_meta(fpos):get_inventory()
	step("forge online at " .. minetest.pos_to_string(fpos))

	-- 2. Scavenge the raw charge from the arena's salvage veins.
	local need = {
		["ground:square_neon"] = 8, ["ground:rhombus_neon"] = 4,
		["ground:x_neon"] = 4, ["ground:x2_neon"] = 4,
	}
	local got = {}
	for x = -20, 20 do
		for z = -10, 10 do
			for y = 1, 2 do
				local p = { x = x, y = y, z = z }
				local name = minetest.get_node(p).name
				if need[name] and (got[name] or 0) < need[name] then
					got[name] = (got[name] or 0) + 1
					minetest.remove_node(p)
				end
			end
		end
	end
	for name, count in pairs(need) do
		if (got[name] or 0) < count then
			return fail("only " .. tostring(got[name] or 0) .. "/" .. count .. " " .. name .. " on the map")
		end
	end
	step("scavenged raw salvage: 8 square, 4 rhombus, 4 x, 4 x2 neon")

	-- 3. Run the chain through the forge. This is a diagnostic, so the
	--    run clock is fired straight past instead of waited out.
	local function run_forge(output, ingredients, take_from_output)
		local entry
		for _, e in ipairs(sl_machine.get_recipes()) do
			if e.recipe.output == output then entry = e break end
		end
		if not entry then return false, "no machine recipe for " .. output end
		for item, count in pairs(ingredients or entry.recipe.ingredients) do
			local stack = ItemStack(item .. " " .. count)
			if take_from_output then
				inv:add_item("src", inv:remove_item("dst", stack))
			else
				inv:add_item("src", stack)
			end
		end
		local ok, err = sl_machine.start_job(fpos, entry, "AI_1")
		if not ok then return false, tostring(err) end
		local def = minetest.registered_nodes[sl_machine.FORGE_NAME]
		if def and def.on_timer then def.on_timer(fpos, sl_machine.forge_time() + 1) end
		return true
	end

	local chain = {
		{ "construction:plasma",   { ["ground:x_neon"] = 4 },        false },
		{ "construction:fire",     { ["ground:x2_neon"] = 4 },       false },
		{ "construction:sparks",   { ["ground:rhombus_neon"] = 4 },  false },
		{ "sl_modebase:loot_crate",{ ["ground:square_neon"] = 8 },   false },
		{ "sl_modebase:objective_core", {
			["sl_modebase:loot_crate"] = 2, ["construction:plasma"] = 5,
			["construction:fire"] = 5,      ["construction:sparks"] = 5,
		}, true },
	}
	for _, run in ipairs(chain) do
		local ok, err = run_forge(run[1], run[2], run[3])
		if not ok then return fail(run[1] .. ": " .. tostring(err)) end
		step("forged " .. run[1])
	end

	local core = inv:remove_item("dst", ItemStack("sl_modebase:objective_core 1"))
	if core:get_count() ~= 1 then return fail("the forge produced no Objective Core") end
	step("SYSTEM OBJECTIVE CORE assembled (" .. tostring(game_mode.essence_pool and game_mode.essence_pool() or 0) .. " essence in the MM pool)")

	-- 4. Deliver it at the beacon.
	local carrier = state.teams.beacon_a.spawn and "beacon_a" or nil
	if not carrier then return fail("beacon A has no spawn on this map") end
	local won, why = game_mode.deliver_objective("beacon_a", "AI_1")
	if not won then return fail("delivery refused: " .. tostring(why)) end
	step("Beacon A wins by objective delivery")
	return true, log
end

minetest.register_chatcommand("sl_test_objective", {
	description = S("Run headless resource-to-objective win test (creative only)"),
	func = function(name)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		local ok, log, err = game_mode.run_headless_objective_test()
		if not ok then return false, S("Objective test failed: @1", err or "unknown") end
		return true, S("Objective test passed: @1", table.concat(log, " | "))
	end,
})

minetest.register_chatcommand("sl_test_stop", {
	description = S("Stop deterministic AI players (creative only)"),
	func = function(name)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		for _, obj in ipairs(bots) do if obj and obj:get_luaentity() then obj:remove() end end
		bots = {}; state.match_active = false
		return true, S("Headless AI test stopped.")
	end,
})
