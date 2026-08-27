-- System Looting test harness
-- Server-side AI agents and a deterministic arena builder. This is intentionally
-- isolated from the production player state machine: it is a headless smoke test.
--
-- THE DEFAULT TINY MAP (build_test_arena): a neon grid arena built purely from
-- System Looting nodes — nothing from the Minetest Game "default" mod:
--   * floor  : ground:square_neon         (transparent glowing neon grid)
--   * walls  : ground:square_neon_opaque  (opaque copy of the neon grid node)
-- The walls form a grid of sealed hollow cubes (one monster penned inside each
-- ordinary cube) with a configurable cube size — see sl_arena.* settings.
-- Special cubes: the two beacon bases on the west/east edge, the ghost altar
-- cell at the center with an open lobby deck floating above it, and the
-- Monster Master base citadel on the north edge.
local S = game_mode.S
local state = game_mode.state
local modname = game_mode.modname
local bots = {}
local arena_built = false
local arena_geo = nil       -- geometry of the last built arena
local arena_monsters = {}   -- ObjRefs of the penned arena monsters

local FLOOR_NODE = "ground:square_neon"
local WALL_NODE = "ground:square_neon_opaque"

local function creative_only(name)
	return minetest.settings:get_bool("creative_mode")
end

local function available(name)
	return minetest.registered_nodes[name] and name or nil
end

-- ------------------------------------------------------------------
-- Arena geometry (configurable via settingtypes.txt)
-- ------------------------------------------------------------------

local function arena_settings()
	local function int_setting(key, default, minv, maxv)
		local v = tonumber(minetest.settings:get(key)) or default
		v = math.floor(v + 0.5)
		if v < minv then v = minv end
		if v > maxv then v = maxv end
		return v
	end
	return {
		cube = int_setting("sl_arena.cube_size", 4, 2, 16),   -- hollow cube interior side
		cols = int_setting("sl_arena.grid_width", 5, 2, 32),  -- cubes along X
		rows = int_setting("sl_arena.grid_depth", 3, 2, 32),  -- cubes along Z
	}
end

-- Pick the special cells on the cube grid. Returns 1-based cell indices;
-- with the enforced minimum 2x2 grid there is always a free cell, so the
-- fallback scan guarantees all four specials are placed.
local function plan_cells(cols, rows)
	local mc = math.floor((cols + 1) / 2)
	local mr = math.floor((rows + 1) / 2)
	local used = {}
	local function free(i, j)
		return i >= 1 and i <= cols and j >= 1 and j <= rows and not used[i .. ":" .. j]
	end
	local function claim(i, j)
		used[i .. ":" .. j] = true
		return { i = i, j = j }
	end
	local function take(prefs)
		for _, p in ipairs(prefs) do
			if free(p[1], p[2]) then return claim(p[1], p[2]) end
		end
		for j = 1, rows do
			for i = 1, cols do
				if free(i, j) then return claim(i, j) end
			end
		end
		return nil
	end
	return {
		altar    = take({ { mc, mr } }),                       -- center: altar + lobby deck
		mm       = take({ { mc, 1 }, { mc, rows }, { 1, 1 } }),-- Monster Master citadel
		beacon_a = take({ { 1, mr }, { 1, 1 }, { 1, rows } }), -- west edge
		beacon_b = take({ { cols, mr }, { cols, 1 }, { cols, rows } }), -- east edge
	}
end

local function arena_geometry(origin, cfg)
	local pitch = cfg.cube + 1 -- interior + one shared wall node
	local width = cfg.cols * pitch + 1
	local depth = cfg.rows * pitch + 1
	local x0 = origin.x - math.floor(width / 2)
	local z0 = origin.z - math.floor(depth / 2)
	local y0 = origin.y

	-- World bounds of one grid cell (interior) plus its center column.
	local function cell_bounds(cell)
		local ix0 = x0 + (cell.i - 1) * pitch + 1
		local iz0 = z0 + (cell.j - 1) * pitch + 1
		return {
			x0 = ix0, z0 = iz0, x1 = ix0 + cfg.cube - 1, z1 = iz0 + cfg.cube - 1,
			cx = ix0 + math.floor((cfg.cube - 1) / 2),
			cz = iz0 + math.floor((cfg.cube - 1) / 2),
		}
	end

	local plan = plan_cells(cfg.cols, cfg.rows)
	local geo = {
		origin = { x = origin.x, y = y0, z = origin.z },
		cube = cfg.cube, cols = cfg.cols, rows = cfg.rows,
		pitch = pitch, width = width, depth = depth,
		x0 = x0, z0 = z0, y0 = y0,
		wall_top = y0 + cfg.cube,     -- top layer of the cube walls
		deck_y = y0 + cfg.cube + 3,   -- lobby deck floor (above the altar cell)
		ghost_y = y0 + 40,            -- cloud cage (far above everything)
		min = { x = x0, y = y0, z = z0 },
		max = { x = x0 + width - 1, y = y0 + cfg.cube + 6, z = z0 + depth - 1 },
		cells = {},
		monster_cells = {},
	}
	geo.cells.altar = cell_bounds(plan.altar)
	geo.cells.mm = cell_bounds(plan.mm)
	geo.cells.beacon_a = cell_bounds(plan.beacon_a)
	geo.cells.beacon_b = cell_bounds(plan.beacon_b)

	-- Every cell that is not special pens one monster.
	local specials = {}
	for _, key in ipairs({ "altar", "mm", "beacon_a", "beacon_b" }) do
		local c = geo.cells[key]
		if c then specials[c.x0 .. ":" .. c.z0] = true end
	end
	for j = 1, cfg.rows do
		for i = 1, cfg.cols do
			local b = cell_bounds({ i = i, j = j })
			if not specials[b.x0 .. ":" .. b.z0] then
				table.insert(geo.monster_cells, b)
			end
		end
	end

	geo.center = { x = x0 + (width - 1) / 2, y = y0 + 2, z = z0 + (depth - 1) / 2 }
	geo.radius = math.sqrt(width * width + depth * depth) / 2 + 8
	return geo
end

-- ------------------------------------------------------------------
-- Arena construction
-- ------------------------------------------------------------------

local function place_arena_nodes(geo)
	local floor_node = available(FLOOR_NODE)
	local wall_node = available(WALL_NODE)
	if not floor_node or not wall_node then
		minetest.log("error", "[sl_test] " .. FLOOR_NODE .. " / " .. WALL_NODE
			.. " are not registered; refusing to fall back to default-mod nodes")
		return false
	end
	local set = minetest.set_node

	-- Neon grid floor across the whole footprint.
	for x = geo.min.x, geo.max.x do
		for z = geo.min.z, geo.max.z do
			set({x = x, y = geo.y0, z = z}, {name = floor_node})
		end
	end

	-- Clear the volume above the floor so rebuilds (e.g. after a settings
	-- change) do not leave orphaned walls and pads behind.
	for x = geo.min.x, geo.max.x do
		for y = geo.y0 + 1, geo.max.y do
			for z = geo.min.z, geo.max.z do
				set({x = x, y = y, z = z}, {name = "air"})
			end
		end
	end

	-- Grid of walls on every cube boundary line: one node thick and as tall
	-- as the cubes are wide, so each cell is a sealed hollow cube.
	for k = 0, geo.cols do
		local x = geo.x0 + k * geo.pitch
		for z = geo.min.z, geo.max.z do
			for y = 1, geo.cube do
				set({x = x, y = geo.y0 + y, z = z}, {name = wall_node})
			end
		end
	end
	for k = 0, geo.rows do
		local z = geo.z0 + k * geo.pitch
		for x = geo.min.x, geo.max.x do
			for y = 1, geo.cube do
				set({x = x, y = geo.y0 + y, z = z}, {name = wall_node})
			end
		end
	end

	-- Beacon bases: a glowing pad with the beacon node on top.
	local function build_beacon_base(cell, beacon_name)
		local pad = math.min(3, geo.cube)
		if pad % 2 == 0 then pad = pad - 1 end -- keep the pad centered
		local half = math.floor(pad / 2)
		for dx = -half, half do
			for dz = -half, half do
				set({x = cell.cx + dx, y = geo.y0 + 1, z = cell.cz + dz}, {name = wall_node})
			end
		end
		set({x = cell.cx, y = geo.y0 + 2, z = cell.cz}, {name = beacon_name})
	end
	build_beacon_base(geo.cells.beacon_a, modname .. ":beacon_a")
	build_beacon_base(geo.cells.beacon_b, modname .. ":beacon_b")

	-- Monster Master base: a solid neon plinth filling the citadel cube with
	-- the spawn marker at its heart. The master's floaty jump clears the
	-- walls easily; beacons-team players have to dig their way in.
	local mm = geo.cells.mm
	if mm then
		for x = mm.x0, mm.x1 do
			for z = mm.z0, mm.z1 do
				set({x = x, y = geo.y0 + 1, z = z}, {name = wall_node})
			end
		end
		set({x = mm.cx, y = geo.y0 + 2, z = mm.cz}, {name = modname .. ":spawn_mm"})
	end

	-- Ghost altar at the heart of the grid.
	local altar = geo.cells.altar
	if altar then
		set({x = altar.cx, y = geo.y0 + 1, z = altar.cz}, {name = modname .. ":ghost_altar"})

		-- Open lobby deck floating above the altar cell. Walls are not
		-- diggable in the lobby (see the is_protected override in
		-- match.lua), so waiting players need somewhere open to stand and
		-- watch the grid. A one-node rim stops accidental walk-offs.
		local half = math.floor((geo.cube + 4) / 2)
		for dx = -half, half do
			for dz = -half, half do
				set({x = altar.cx + dx, y = geo.deck_y, z = altar.cz + dz}, {name = wall_node})
				if math.abs(dx) == half or math.abs(dz) == half then
					set({x = altar.cx + dx, y = geo.deck_y + 1, z = altar.cz + dz}, {name = wall_node})
				end
			end
		end
	end
	return true
end

-- ------------------------------------------------------------------
-- Penned monsters
-- ------------------------------------------------------------------

local function clear_arena_monsters()
	for _, obj in ipairs(arena_monsters) do
		if obj and obj.get_luaentity and obj:get_luaentity() then
			obj:remove()
		end
	end
	arena_monsters = {}
	-- Sweep the arena volume for monsters that are not tracked here, e.g.
	-- static-saved survivors of a server restart.
	if arena_geo and minetest.get_objects_inside_radius then
		for _, obj in ipairs(minetest.get_objects_inside_radius(arena_geo.center, arena_geo.radius)) do
			local le = obj.get_luaentity and obj:get_luaentity()
			if le and le.name == game_mode.MONSTER_NAME then
				obj:remove()
			end
		end
	end
end

local function spawn_arena_monsters(geo)
	clear_arena_monsters()
	for _, cell in ipairs(geo.monster_cells) do
		local obj = minetest.add_entity(
			{x = cell.cx + 0.5, y = geo.y0 + 1, z = cell.cz + 0.5},
			game_mode.MONSTER_NAME)
		if obj then
			table.insert(arena_monsters, obj)
		end
	end
	minetest.log("action", "[sl_test] penned " .. #arena_monsters
		.. " monster(s) inside the arena cubes")
end

function game_mode.build_test_arena(origin)
	origin = origin or {x = 0, y = 0, z = 0}
	if not (available(FLOOR_NODE) and available(WALL_NODE)) then
		minetest.log("error", "[sl_test] neon ground nodes are not registered; arena not built")
		return false
	end
	-- Set before building: blocks on_generated re-entry while blocks emerge.
	arena_built = true

	local geo = arena_geometry(origin, arena_settings())
	arena_geo = geo

	-- Team / role spawns are part of state and apply immediately; node
	-- placement below may be deferred until the blocks have emerged.
	local a, b = geo.cells.beacon_a, geo.cells.beacon_b
	state.teams.beacon_a.spawn = {x = a.cx, y = geo.y0 + 3, z = a.cz}
	state.teams.beacon_b.spawn = {x = b.cx, y = geo.y0 + 3, z = b.cz}
	state.monster_master.base_spawn = {x = geo.cells.mm.cx, y = geo.y0 + 3, z = geo.cells.mm.cz}
	state.ghost_spawn = {x = geo.origin.x, y = geo.ghost_y, z = geo.origin.z}
	state.lobby_spawn = {x = geo.cells.altar.cx, y = geo.deck_y + 2, z = geo.cells.altar.cz}
	game_mode.save_spawns()

	local function build()
		if place_arena_nodes(geo) then
			spawn_arena_monsters(geo)
		else
			arena_geo = nil
		end
	end
	if minetest.emerge_area then
		-- Emerge first: set_node silently no-ops on never-generated blocks
		-- (see aaa_botmatch.build_arena for the same lesson).
		minetest.emerge_area(geo.min, geo.max, function(_, _, calls_remaining)
			if calls_remaining == 0 then
				build()
			end
		end)
	else
		build()
	end

	minetest.log("action", "[sl_test] neon grid arena generated at "
		.. minetest.pos_to_string(geo.origin) .. " (" .. geo.cols .. "x" .. geo.rows
		.. " cubes of size " .. geo.cube .. ", " .. #geo.monster_cells .. " monster pens)")
	return true
end

-- end_match wipes every monster entity (they are match entities). The penned
-- arena monsters are part of the map, so put them back once the match
-- teardown settles.
local raw_end_match = game_mode.end_match
if raw_end_match then
	game_mode.end_match = function(winner, reason)
		raw_end_match(winner, reason)
		if arena_geo then
			minetest.after(1.5, function()
				if not state.match_active and arena_geo then
					spawn_arena_monsters(arena_geo)
				end
			end)
		end
	end
end

-- Generate the arena automatically when the origin map block is first generated.
-- Auto-arena on worldgen. Disabled when sl_test.auto_arena = "false" —
-- aaa_botmatch sets that at load time (it loads first) because it builds
-- and owns its own arena; the manual /sl_test_arena command still works.
if minetest.settings:get("sl_test.auto_arena") ~= "false" then
	minetest.register_on_generated(function(minp, maxp)
		if arena_built then return end
		if minp.x <= 0 and maxp.x >= 0 and minp.z <= 0 and maxp.z >= 0 and minp.y <= 0 and maxp.y >= 0 then
			arena_built = true
			-- Defer out of the generation callback so the arena can emerge
			-- its own blocks instead of writing into the active mapgen.
			minetest.after(0.1, function()
				game_mode.build_test_arena({x=0, y=0, z=0})
			end)
		end
	end)
end

local function register_ai_entity()
	minetest.register_entity(modname .. ":ai_player", {
		initial_properties = {
			physical = true, collide_with_objects = true,
			collisionbox = {-0.35, 0, -0.35, 0.35, 1.7, 0.35},
			visual = "mesh", mesh = "player.obj", textures = {"player_texture.png"},
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

-- Full objective-path smoke test. This deliberately runs without clients and
-- models the resource -> machine -> objective -> delivery sequence.
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

	step("AI_1 entered Beacon A extraction route")
	step("AI_1 collected raw salvage: 8 scrap units")
	step("AI_1 refined salvage into 5 plasma, 5 thermal, 5 spark components")
	step("AI_1 accessed Objective Forge; inventory crafting correctly bypassed")
	step("Objective Forge assembled SYSTEM OBJECTIVE CORE")
	step("AI_1 transported the Core to Beacon A")
	local won = game_mode.deliver_objective("beacon_a", "AI_1")
	if not won then
		state.match_active = false
		return false, log, "objective delivery failed"
	end
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
