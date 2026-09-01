-- ================================================================
-- System Looting — map system
-- ================================================================
-- Three map types feed the match loop:
--   procedural : generated from a seed every match (deterministic
--                rebuild: same seed -> same arena)
--   test       : the deterministic headless test arena built by
--                test_harness.lua (registered as a builder below)
--   schematic  : handmade arenas saved as .mts schematics (the
--                WorldEdit //schem save workflow used by MTCTF) or
--                plain-Lua schematic tables, plus a map.conf
--                describing anchors and mob spawns
--
-- RESET CONTRACT (all types): when a match ends the map returns to
-- its initial state —
--   * the arena volume is re-materialized (re-run generator or
--     re-place the schematic), so every node created, dug or
--     mutated during the match is replaced with the initial node,
--     whether the map was loaded (schematic) or generated;
--   * node edits OUTSIDE the arena volume are journaled during the
--     match and restored one by one at reset;
--   * every mob is removed at match end and the map's initial mob
--     population is (re)spawned at match start;
--   * beacons are restored at full integrity with fresh metadata.
--
-- External arena owners (aaa_botmatch) can adopt() a descriptor to
-- get journal reset + mob purge without the system rebuilding their
-- arena.
-- ================================================================

local S = game_mode.S
local state = game_mode.state
local modpath = game_mode.modpath

local map = {
	current = nil,        -- active/prepared map descriptor
	journal = {},          -- [n] = { pos, node = {name, param1, param2}, meta }
	journal_index = {},    -- [pos_hash] = n (first change wins)
	journal_active = false,
	spawned_mobs = {},     -- entity refs of the current match population
	runtime = {            -- /sl_map set overrides (persisted)
		type = nil, schematic = nil, seed = nil,
	},
	building = false,      -- true while (re)materializing a map
}

game_mode.map = map

local MAX_JOURNAL = 65536

-- ================================================================
-- Settings / configuration
-- ================================================================

local function sget(key)
	return minetest.settings:get(key)
end

local function sget_int(key, default)
	local n = tonumber(sget(key))
	if not n then return default end
	return math.floor(n)
end

local MAP_TYPES = { procedural = true, test = true, schematic = true }

local function configured_type()
	local t = map.runtime.type or sget("sl_map.type") or "procedural"
	if not MAP_TYPES[t] then
		minetest.log("warning", "[game_mode] unknown sl_map.type '" .. tostring(t)
			.. "', falling back to procedural")
		t = "procedural"
	end
	return t
end

local function configured_origin(default)
	local raw = sget("sl_map.origin") or ""
	local x, y, z = raw:match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
	if x then
		return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
	end
	return default
end

-- Deterministic PRNG (Lua 5.1 compatible; same numbers on engine and stub).
local function make_rng(seed)
	local s = (tonumber(seed) or 0) % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end
map.make_rng = make_rng

local function rng_int(rng, lo, hi)
	return lo + math.floor(rng() * (hi - lo + 1))
end

-- ================================================================
-- Small helpers
-- ================================================================

local function parse_triplet(str)
	if not str then return nil end
	local x, y, z = tostring(str):match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
	if not x then return nil end
	return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end
map.parse_triplet = parse_triplet

-- Two-coordinate "X,Z" setting value (layout overrides sit on the
-- arena floor plane; the Y comes from the generator).
local function parse_pair(str)
	if not str then return nil end
	local x, z = tostring(str):match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
	if not x then return nil end
	return { x = tonumber(x), z = tonumber(z) }
end
map.parse_pair = parse_pair

local function write_node(pos, name, param2)
	if param2 then
		minetest.set_node(pos, { name = name, param2 = param2 })
	else
		minetest.set_node(pos, { name = name })
	end
end

-- Fill a box (inclusive corners) with one node. The default is air so
-- a rebuild erases anything a match left behind.
local function fill_box(minp, maxp, name)
	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				minetest.set_node({ x = x, y = y, z = z }, { name = name or "air" })
			end
		end
	end
end

local function node_or(name, fallback)
	-- The game always ships the ground mod; keep the canonical name so
	-- generated/schematic layouts match across engine and stub tests.
	if minetest.registered_nodes[name] then return name end
	if fallback and minetest.registered_nodes[fallback] then return fallback end
	return name
end

local FLOOR_NODE = node_or("ground:square_neon", "default:glass")
local WALL_NODE = node_or("ground:square_neon_opaque", "default:obsidianbrick")

local function emerge_volume(minp, maxp)
	if not minetest.load_area then return end
	-- load_area(pos1, pos2) synchronously emerges every block in the
	-- range; without this, set_node silently no-ops on ungenerated
	-- blocks (headless servers have no players to trigger mapgen).
	pcall(minetest.load_area, vector.round(minp), vector.round(maxp))
end

local function pos_in_volume(pos, minp, maxp)
	return pos.x >= minp.x and pos.x <= maxp.x
		and pos.y >= minp.y and pos.y <= maxp.y
		and pos.z >= minp.z and pos.z <= maxp.z
end

-- ================================================================
-- map.conf parsing (same role as MTCTF's map.conf, plain parser so
-- it also runs under the headless stub)
-- ================================================================
-- Keys:
--   name / author              -- display metadata
--   rotation = 0|90|180|270    -- schematic placement rotation
--   size = X,Y,Z               -- optional, else read from schematic
--   beacon_a.pos / beacon_b.pos = X,Y,Z   (schematic-relative)
--   altar.pos, mm.pos, lobby.pos, ghost.pos = X,Y,Z
--   mobs.<n> = X,Y,Z[,variant]
local function parse_conf_file(path)
	local conf = {}
	local fh = io.open(path, "r")
	if not fh then return conf end
	for line in fh:lines() do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and line:sub(1, 1) ~= "#" then
			local key, value = line:match("^([^=]-)%s*=%s*(.-)$")
			if key and value then
				conf[key:gsub("%s+$", "")] = value
			end
		end
	end
	fh:close()
	return conf
end

local function conf_mobs(conf)
	local mobs = {}
	local i = 1
	while conf["mobs." .. i] do
		local parts = {}
		for v in (conf["mobs." .. i] .. ","):gmatch("(.-),") do
			table.insert(parts, (v:gsub("^%s+", ""):gsub("%s+$", "")))
		end
		local pos = parse_triplet(table.concat({ parts[1], parts[2], parts[3] }, ","))
		if pos then
			table.insert(mobs, { pos = pos, variant = parts[4] or "stalker" })
		end
		i = i + 1
	end
	return mobs
end

-- ================================================================
-- Schematic map discovery
-- ================================================================
-- Handmade maps live in
--   <modpath>/maps/<name>/map.mts (+ optional map.conf)
--   <modpath>/maps/<name>/map.lua (plain-Lua schematic table)
--   <world>/maps/<name>/...       (same layout, server-local)
--   <world>/schems/<name>.mts     (WorldEdit //schem save output)
-- and are used directly from there.

local function dir_list(path, is_dir)
	if minetest.get_dir_list then
		local ok, res = pcall(minetest.get_dir_list, path, is_dir)
		if ok then return res or {} end
	end
	return {}
end

local function file_exists(path)
	local fh = io.open(path, "rb")
	if fh then fh:close() return true end
	return false
end

local function world_dir()
	if minetest.get_worldpath then
		local ok, res = pcall(minetest.get_worldpath)
		if ok and res and res ~= "" then return res end
	end
	return nil
end

function map.list_schematic_maps()
	local found = {}

	local function scan_root(root)
		for _, dname in ipairs(dir_list(root, true)) do
			local dir = root .. "/" .. dname
			local mts = dir .. "/map.mts"
			local lua = dir .. "/map.lua"
			if file_exists(mts) or file_exists(lua) then
				found[dname] = dir
			end
		end
	end

	scan_root(modpath .. "/maps")

	local w = world_dir()
	if w then
		scan_root(w .. "/maps")
		-- WorldEdit drops schematics into <world>/schems/<name>.mts
		for _, fname in ipairs(dir_list(w .. "/schems", false)) do
			local name = fname:match("^(.*)%.mts$")
			if name and name ~= "" then
				found[name] = w .. "/schems/" .. name
			end
		end
	end

	return found
end

local function load_map_conf(dir_or_none, name)
	if dir_or_none and file_exists(dir_or_none .. "/map.conf") then
		return parse_conf_file(dir_or_none .. "/map.conf")
	end
	return { name = name, author = "" }
end

-- Resolve the schematic source for a handmade map directory.
-- Returns { kind = "mts"|"lua", path = ... , size = {x,y,z} } or nil + error.
local function resolve_schematic(dir, conf)
	local mts = dir .. "/map.mts"
	local lua = dir .. "/map.lua"

	local function size_from_conf()
		local raw = conf.size and parse_triplet(conf.size)
		if raw and raw.x > 0 and raw.y > 0 and raw.z > 0 then
			return raw
		end
		return nil
	end

	if file_exists(mts) then
		local size = size_from_conf()
		if not size and minetest.read_schematic then
			local ok, schem = pcall(minetest.read_schematic, mts, { write_lua = true })
			if ok and schem and schem.size then
				size = { x = schem.size.x, y = schem.size.y, z = schem.size.z }
			end
		end
		if not size then
			return nil, S("map.mts found but its size is unknown (add 'size = X,Y,Z' to map.conf)")
		end
		return { kind = "mts", path = mts, size = size }
	end

	if file_exists(lua) then
		local chunk, err = loadfile(lua)
		if not chunk then
			return nil, S("map.lua failed to load: @1", tostring(err))
		end
		local ok, schem = pcall(chunk)
		if not ok or type(schem) ~= "table" or not schem.size or not schem.data then
			return nil, S("map.lua must return a schematic table {{size=...,data=...}}")
		end
		return {
			kind = "lua",
			path = lua,
			size = { x = schem.size.x, y = schem.size.y, z = schem.size.z },
			schematic = schem,
		}
	end

	return nil, S("no map.mts or map.lua in @1", tostring(dir))
end

-- Place the schematic with its min corner at minp.
local function place_schematic_at(source, minp, rotation)
	if not minetest.place_schematic then
		return false, S("engine lacks place_schematic")
	end
	local what = source.kind == "lua" and source.schematic or source.path
	local ok, err = pcall(minetest.place_schematic, minp, what, rotation, nil, true)
	if not ok then
		return false, tostring(err)
	end
	return true
end

-- ================================================================
-- Shared finalization: anchors -> spawns, state registration,
-- cloud cage, descriptor bookkeeping
-- ================================================================

-- Anchor conventions (all absolute node positions unless noted):
--   beacon_a / beacon_b : the beacon node; player spawn = anchor + 1 up
--   altar               : the ghost altar node
--   mm_pad              : spawn_mm node; MM player spawn = anchor + 1 up
--   lobby               : player STAND position (not a node anchor)
local function apply_spawns(anchor)
	local function spawn_of(pos)
		return { x = pos.x, y = pos.y + 1, z = pos.z }
	end

	state.teams.beacon_a.spawn = spawn_of(anchor.beacon_a)
	state.teams.beacon_b.spawn = spawn_of(anchor.beacon_b)
	state.monster_master.base_spawn = spawn_of(anchor.mm_pad)
	state.ghost_spawn = table.copy(anchor.ghost)
	state.lobby_spawn = table.copy(anchor.lobby)
	game_mode.save_spawns()
end

local function ensure_platform(pos, node_name)
	-- Solid 3x3 pad one node below an anchor so beacons never float.
	local y = pos.y - 1
	for dx = -1, 1 do
		for dz = -1, 1 do
			local p = { x = pos.x + dx, y = y, z = pos.z + dz }
			local n = minetest.get_node_or_nil(p)
			if not n or n.name == "air" or n.name == "ignore" then
				write_node(p, node_name)
			end
		end
	end
end

local function fresh_beacon_meta(pos, label)
	local meta = minetest.get_meta(pos)
	meta:set_int("hp", state.settings.beacon_hp or 100)
	meta:set_string("infotext", S("@1 (HP: @2)", label, tostring(state.settings.beacon_hp or 100)))
end

-- Place / refresh the gameplay anchor nodes and their metadata.
local function place_anchor_nodes(anchor)
	write_node(anchor.beacon_a, game_mode.modname .. ":beacon_a")
	write_node(anchor.beacon_b, game_mode.modname .. ":beacon_b")
	fresh_beacon_meta(anchor.beacon_a, state.teams.beacon_a.label)
	fresh_beacon_meta(anchor.beacon_b, state.teams.beacon_b.label)
	if minetest.registered_nodes[game_mode.modname .. ":ghost_altar"] then
		write_node(anchor.altar, game_mode.modname .. ":ghost_altar")
	end
	if minetest.registered_nodes[game_mode.modname .. ":spawn_mm"] then
		write_node(anchor.mm_pad, game_mode.modname .. ":spawn_mm")
	end
	if minetest.registered_nodes[game_mode.modname .. ":monster_spawner"] then
		local sp = { x = anchor.mm_pad.x, y = anchor.mm_pad.y, z = anchor.mm_pad.z + 1 }
		write_node(sp, game_mode.modname .. ":monster_spawner")
	end
end

-- Wipe the containment column and re-materialize the cage, so cages
-- left at a previous map's ghost height never survive a map change.
local function build_cage()
	if not state.ghost_spawn then return end
	if minetest.load_area then
		pcall(minetest.load_area, vector.round(state.ghost_spawn))
	end
	local g = vector.round(state.ghost_spawn)
	map.building = true
	fill_box(
		{ x = g.x - 6, y = g.y - 2, z = g.z - 6 },
		{ x = g.x + 6, y = g.y + 5, z = g.z + 6 }, "air")
	map.building = false
	if game_mode.build_cloud_cage then
		game_mode.build_cloud_cage()
	end
end

-- Extend descriptor volume so the reset box always contains the
-- ghost cage and the lobby platform.
local function extend_volume_for_shared(desc)
	local gs = desc.anchor.ghost
	local cmin = { x = gs.x - 6, y = gs.y - 2, z = gs.z - 6 }
	local cmax = { x = gs.x + 6, y = gs.y + 5, z = gs.z + 6 }
	desc.minp = vector.round({ x = math.min(desc.minp.x, cmin.x), y = math.min(desc.minp.y, cmin.y), z = math.min(desc.minp.z, cmin.z) })
	desc.maxp = vector.round({ x = math.max(desc.maxp.x, cmax.x), y = math.max(desc.maxp.y, cmax.y), z = math.max(desc.maxp.z, cmax.z) })
end

-- ================================================================
-- Procedural map builder
-- ================================================================
-- A seeded, symmetrical neon arena floating above the worldgen plane:
-- glasslike floor, opaque perimeter, two beacon bastions, a midfield
-- altar, a Monster Master redoubt, a lobby platform out front and a
-- seeded scatter of cover blocks and mob spawn points.

local function build_procedural(opts)
	local seed = opts.seed
	local origin = table.copy(opts.origin)
	local rng = make_rng(seed)

	local W = math.max(16, math.min(64, sget_int("sl_map.arena_size", 48) / 2))
	local fy = origin.y

	map.building = true

	-- Emerge before building: set_node no-ops on ungenerated blocks.
	emerge_volume(
		{ x = origin.x - W - 2, y = fy - 2, z = origin.z - W - 14 },
		{ x = origin.x + W + 2, y = fy + 46, z = origin.z + W + 8 })

	-- Clear the volume, then lay the floor: the arena floats clean.
	fill_box(
		{ x = origin.x - W - 1, y = fy - 2, z = origin.z - W - 1 },
		{ x = origin.x + W + 1, y = fy + 5, z = origin.z + W + 1 }, "air")
	fill_box(
		{ x = origin.x - W, y = fy, z = origin.z - W },
		{ x = origin.x + W, y = fy, z = origin.z + W }, FLOOR_NODE)

	-- Perimeter walls.
	for x = origin.x - W, origin.x + W do
		for y = 1, 5 do
			write_node({ x = x, y = fy + y, z = origin.z - W }, WALL_NODE)
			write_node({ x = x, y = fy + y, z = origin.z + W }, WALL_NODE)
		end
	end
	for z = origin.z - W, origin.z + W do
		for y = 1, 5 do
			write_node({ x = origin.x - W, y = fy + y, z = z }, WALL_NODE)
			write_node({ x = origin.x + W, y = fy + y, z = z }, WALL_NODE)
		end
	end

	-- Layout overrides: X,Z anchors for the cloud cage, the two beacon
	-- bastions and the MM redoubt. A descriptor's resolved layout wins
	-- (a same-match reset must not drift if settings changed in between);
	-- otherwise the sl_map.*_pos settings are read, and unset entries
	-- fall back to the stock centre-line arrangement.
	local function layout_or(key, fallback)
		if opts.layout and opts.layout[key] then
			return { x = opts.layout[key].x, z = opts.layout[key].z }
		end
		return parse_pair(sget("sl_map." .. key .. "_pos")) or fallback
	end

	-- Beacon bastions: raised 5x5 pads, by default at the midfield line.
	local bx = W - 8
	local anchor = {}
	local beacon_a2 = layout_or("beacon_a", { x = origin.x - bx, z = origin.z })
	local beacon_b2 = layout_or("beacon_b", { x = origin.x + bx, z = origin.z })
	if beacon_a2.x == beacon_b2.x and beacon_a2.z == beacon_b2.z then
		minetest.log("warning",
			"[game_mode] sl_map.beacon_a_pos and sl_map.beacon_b_pos are the same position; beacon B reverts to the default")
		beacon_b2 = { x = origin.x + bx, z = origin.z }
	end
	for _, bp in ipairs({ beacon_a2, beacon_b2 }) do
		for dx = -2, 2 do
			for dz = -2, 2 do
				write_node({ x = bp.x + dx, y = fy + 1, z = bp.z + dz }, WALL_NODE)
			end
		end
		for _, corner in ipairs({ { -2, -2 }, { -2, 2 }, { 2, -2 }, { 2, 2 } }) do
			for y = 2, 3 do
				write_node({ x = bp.x + corner[1], y = fy + y, z = bp.z + corner[2] }, WALL_NODE)
			end
		end
	end
	anchor.beacon_a = { x = beacon_a2.x, y = fy + 2, z = beacon_a2.z }
	anchor.beacon_b = { x = beacon_b2.x, y = fy + 2, z = beacon_b2.z }

	-- Midfield altar platform.
	ensure_platform({ x = origin.x, y = fy + 1, z = origin.z }, WALL_NODE)
	anchor.altar = { x = origin.x, y = fy + 1, z = origin.z }

	-- Monster Master redoubt, by default at +Z; overridable X,Z.
	local mm2 = layout_or("mm_base", { x = origin.x, z = origin.z + W - 6 })
	for dx = -3, 3 do
		for dz = -3, 3 do
			write_node({ x = mm2.x + dx, y = fy + 1, z = mm2.z + dz }, WALL_NODE)
			local edge = (dx == -3 or dx == 3 or dz == -3 or dz == 3)
			if edge then
				for y = 2, 4 do
					write_node({ x = mm2.x + dx, y = fy + y, z = mm2.z + dz }, WALL_NODE)
				end
			end
		end
	end
	-- Doorway on the side facing the arena centre.
	local door_dir = (mm2.z >= origin.z) and -1 or 1
	write_node({ x = mm2.x, y = fy + 2, z = mm2.z + door_dir * 3 }, "air")
	write_node({ x = mm2.x, y = fy + 3, z = mm2.z + door_dir * 3 }, "air")
	anchor.mm_pad = { x = mm2.x, y = fy + 1, z = mm2.z }

	-- Seeded cover blocks, mirrored for fairness.
	local clusters = {}
	local wanted = math.floor(W / 3)
	local guard = 0
	while #clusters < wanted and guard < wanted * 40 do
		guard = guard + 1
		local cx = rng_int(rng, -(W - 6), W - 6)
		local cz = rng_int(rng, -(W - 6), W - 6)
		if math.abs(cx) > 5 and math.abs(cz) > 5
			and math.abs(math.abs(cx) - bx) > 4
			and math.abs(cz - (W - 6)) > 5
			and math.abs(cz + (W - 6)) > 5 then
			table.insert(clusters, { cx, cz })
		end
	end
	for _, c in ipairs(clusters) do
		for _, m in ipairs({ { 1, 1 }, { -1, -1 } }) do
			local px, pz = origin.x + c[1] * m[1], origin.z + c[2] * m[2]
			local h = rng_int(rng, 1, 3)
			for dx = 0, 1 do
				for dz = 0, 1 do
					for y = 1, h do
						write_node({ x = px + dx, y = fy + y, z = pz + dz }, WALL_NODE)
					end
				end
			end
		end
	end

	-- Lobby platform out front (-Z), outside the arena walls.
	local lz = origin.z - W - 10
	for dx = -5, 5 do
		for dz = -5, 5 do
			write_node({ x = origin.x + dx, y = fy, z = lz + dz }, FLOOR_NODE)
			local edge = (dx == -5 or dx == 5 or dz == -5 or dz == 5)
			if edge then
				write_node({ x = origin.x + dx, y = fy + 1, z = lz + dz }, WALL_NODE)
			end
		end
	end
	anchor.lobby = { x = origin.x, y = fy + 1, z = lz }
	local cage2 = layout_or("cage", { x = origin.x, z = origin.z })
	anchor.ghost = { x = cage2.x, y = fy + 40, z = cage2.z }

	-- Initial mob population: seeded scatter inside the arena.
	local mobs = {}
	local budget = math.max(0, sget_int("sl_map.mobs", 6))
	local variants = game_mode.MONSTER_TYPE_ORDER or { "stalker" }
	local i = 0
	while i < budget do
		local px = origin.x + rng_int(rng, -(W - 5), W - 5)
		local pz = origin.z + rng_int(rng, -(W - 5), W - 5)
		table.insert(mobs, {
			pos = { x = px, y = fy + 2, z = pz },
			variant = variants[(i % #variants) + 1],
		})
		i = i + 1
	end

	map.building = false

	-- Reset box must contain every layout anchor, even when overrides
	-- sit far outside the stock volume: the re-materialization replaces
	-- nodes inside it, and outside it the journal restores edits.
	local minp = { x = origin.x - W - 1, y = fy - 2, z = lz - 7 }
	local maxp = { x = origin.x + W + 1, y = fy + 6, z = origin.z + W + 2 }
	for _, a in ipairs({ anchor.beacon_a, anchor.beacon_b, anchor.mm_pad }) do
		minp.x = math.min(minp.x, a.x - 4)
		minp.z = math.min(minp.z, a.z - 4)
		maxp.x = math.max(maxp.x, a.x + 4)
		maxp.z = math.max(maxp.z, a.z + 4)
	end

	return {
		type = "procedural",
		name = S("Procedural arena @1", tostring(seed)),
		seed = seed,
		origin = origin,
		anchor = anchor,
		mobs = mobs,
		minp = minp,
		maxp = maxp,
		-- Resolved layout: carried on the descriptor so a same-match
		-- rebuild (reset) reproduces the exact anchors even if the
		-- sl_map.*_pos settings were edited mid-match.
		layout = {
			cage = { x = anchor.ghost.x, z = anchor.ghost.z },
			beacon_a = { x = anchor.beacon_a.x, z = anchor.beacon_a.z },
			beacon_b = { x = anchor.beacon_b.x, z = anchor.beacon_b.z },
			mm_base = { x = anchor.mm_pad.x, z = anchor.mm_pad.z },
		},
	}
end

-- ================================================================
-- Schematic (handmade) map builder
-- ================================================================

-- Rotate a schematic-relative position into placement-relative space
-- (mirrors the engine's schematic rotation in blitToVManip).
local function rotate_rel(rel, rot, sx, sz)
	local x, z = rel.x, rel.z
	if rot == "90" then
		return { x = z, y = rel.y, z = sx - 1 - x }
	elseif rot == "180" then
		return { x = sx - 1 - x, y = rel.y, z = sz - 1 - z }
	elseif rot == "270" then
		return { x = sz - 1 - z, y = rel.y, z = x }
	end
	return { x = x, y = rel.y, z = z }
end

local function build_schematic(opts)
	local available = map.list_schematic_maps()
	local pick
	if opts.name and opts.name ~= "random" and opts.name ~= "" then
		if not available[opts.name] then
			return nil, S("handmade map '@1' not found (check /sl_map list)", opts.name)
		end
		pick = opts.name
	else
		-- Seeded choice so a pinned seed also pins the handmade map.
		local names = {}
		for n in pairs(available) do table.insert(names, n) end
		if #names == 0 then
			return nil, S("no handmade maps installed (mods/game/sl_modebase/maps/)")
		end
		table.sort(names)
		local rng = make_rng(opts.seed)
		pick = names[1 + math.floor(rng() * #names)]
	end

	local dir = available[pick]
	local conf = load_map_conf(dir, pick)
	local source, err = resolve_schematic(dir, conf)
	if not source then
		return nil, err
	end

	local rot = tostring(conf.rotation or "0"):match("^(%d+)$") or "0"
	if not ({ ["0"] = true, ["90"] = true, ["180"] = true, ["270"] = true })[rot] then
		rot = "0"
	end

	local sx, sz = source.size.x, source.size.z
	if rot == "90" or rot == "270" then
		sx, sz = sz, sx
	end

	local origin = table.copy(opts.origin)
	local minp = {
		x = origin.x - math.floor(sx / 2),
		y = origin.y,
		z = origin.z - math.floor(sz / 2),
	}
	local maxp = { x = minp.x + sx - 1, y = minp.y + source.size.y - 1, z = minp.z + sz - 1 }

	map.building = true
	emerge_volume(
		{ x = minp.x - 2, y = minp.y - 2, z = minp.z - 14 },
		{ x = maxp.x + 2, y = minp.y + 48, z = maxp.z + 4 })

	local ok, perr = place_schematic_at(source, minp, rot)
	if not ok then
		map.building = false
		return nil, perr
	end

	-- Resolve anchors. map.conf coordinates are schematic-relative
	-- (as authored in WorldEdit); defaults sit on top of the placed
	-- structure with auto-pads so a bare schematic still works.
	local anchor = {}
	local function rel_world(key, default_rel)
		local rel = parse_triplet(conf[key]) or default_rel
		rel = rotate_rel(rel, rot, source.size.x, source.size.z)
		return { x = minp.x + rel.x, y = minp.y + rel.y, z = minp.z + rel.z }
	end

	anchor.beacon_a = rel_world("beacon_a.pos",
		{ x = math.floor(source.size.x * 0.2), y = source.size.y, z = math.floor(source.size.z / 2) })
	anchor.beacon_b = rel_world("beacon_b.pos",
		{ x = math.floor(source.size.x * 0.8) - 1, y = source.size.y, z = math.floor(source.size.z / 2) })
	anchor.altar = rel_world("altar.pos",
		{ x = math.floor(source.size.x / 2), y = source.size.y, z = math.floor(source.size.z / 2) })
	anchor.mm_pad = rel_world("mm.pos",
		{ x = math.floor(source.size.x / 2), y = source.size.y, z = math.floor(source.size.z * 0.8) - 1 })
	anchor.lobby = rel_world("lobby.pos",
		{ x = math.floor(source.size.x / 2), y = 1, z = 2 })
	anchor.ghost = rel_world("ghost.pos",
		{ x = math.floor(source.size.x / 2), y = source.size.y + 12, z = math.floor(source.size.z / 2) })

	-- Solid ground under every anchor that sits in the air.
	for _, key in ipairs({ "beacon_a", "beacon_b", "altar", "mm_pad", "lobby" }) do
		ensure_platform(anchor[key], WALL_NODE)
	end
	place_anchor_nodes(anchor)

	-- Mobs: explicit map.conf list, or a seeded scatter over the map.
	local mobs = {}
	for _, m in ipairs(conf_mobs(conf)) do
		local rel = rotate_rel(m.pos, rot, source.size.x, source.size.z)
		table.insert(mobs, {
			pos = { x = minp.x + rel.x, y = minp.y + rel.y, z = minp.z + rel.z },
			variant = m.variant,
		})
	end
	if #mobs == 0 then
		local budget = math.max(0, sget_int("sl_map.mobs", 6))
		local variants = game_mode.MONSTER_TYPE_ORDER or { "stalker" }
		local rng = make_rng(opts.seed)
		for i = 1, budget do
			table.insert(mobs, {
				pos = {
					x = minp.x + rng_int(rng, 2, sx - 3),
					y = maxp.y + 1,
					z = minp.z + rng_int(rng, 2, sz - 3),
				},
				variant = variants[((i - 1) % #variants) + 1],
			})
		end
	end

	map.building = false

	return {
		type = "schematic",
		name = conf.name or pick,
		author = conf.author,
		seed = opts.seed,
		origin = origin,
		dir = dir,
		rotation = rot,
		size = { x = source.size.x, y = source.size.y, z = source.size.z },
		anchor = anchor,
		mobs = mobs,
		minp = { x = minp.x - 1, y = minp.y - 2, z = minp.z - 1 },
		maxp = { x = maxp.x + 1, y = maxp.y + 3, z = maxp.z + 1 },
	}
end

-- ================================================================
-- Builder registry (test_harness registers the "test" type)
-- ================================================================

local builders = {}
builders.procedural = build_procedural
builders.schematic = build_schematic

function map.register_builder(map_type, fn)
	builders[map_type] = fn
end

-- ================================================================
-- Prepare / materialize / reset
-- ================================================================

local function serialize_descriptor(desc)
	local function clean_pos(p) return p and { x = p.x, y = p.y, z = p.z } or nil end
	local function clean_pair(p) return p and { x = p.x, z = p.z } or nil end
	local mobs = {}
	for _, m in ipairs(desc.mobs or {}) do
		table.insert(mobs, { pos = clean_pos(m.pos), variant = m.variant })
	end
	return {
		type = desc.type, name = desc.name, author = desc.author,
		seed = desc.seed, origin = clean_pos(desc.origin),
		dir = desc.dir, rotation = desc.rotation, size = desc.size,
		anchor = {
			beacon_a = clean_pos(desc.anchor.beacon_a),
			beacon_b = clean_pos(desc.anchor.beacon_b),
			altar = clean_pos(desc.anchor.altar),
			mm_pad = clean_pos(desc.anchor.mm_pad),
			lobby = clean_pos(desc.anchor.lobby),
			ghost = clean_pos(desc.anchor.ghost),
		},
		layout = desc.layout and {
			cage = clean_pair(desc.layout.cage),
			beacon_a = clean_pair(desc.layout.beacon_a),
			beacon_b = clean_pair(desc.layout.beacon_b),
			mm_base = clean_pair(desc.layout.mm_base),
		} or nil,
		mobs = mobs,
		minp = clean_pos(desc.minp), maxp = clean_pos(desc.maxp),
	}
end

local function persist_current()
	local st = game_mode.storage
	if not st or not map.current then return end
	st:set_string("map.current", minetest.serialize(serialize_descriptor(map.current)))
	st:set_string("map.runtime", minetest.serialize(map.runtime))
end

function map.persist() persist_current() end

local function unpersist_current()
	local st = game_mode.storage
	if not st then return nil end
	local rt = st:get_string("map.runtime")
	if rt ~= "" then
		local data = minetest.deserialize(rt)
		if data then map.runtime = data end
	end
	local raw = st:get_string("map.current")
	if raw == "" then return nil end
	local desc = minetest.deserialize(raw)
	if desc and desc.type and desc.anchor and desc.minp then
		return desc
	end
	return nil
end

-- (Re)build a descriptor into the world. Procedural/test maps are
-- deterministic functions of their seed, so re-running the builder
-- reproduces the initial arena exactly; handmade maps are re-placed
-- from their schematic. Everything inside minp..maxp is overwritten
-- (including air), erasing any match residue.
-- Returns true when the arena volume was actually rebuilt (external
-- owners return false: their arena is journal-restored instead).
-- A rebuilt descriptor is fully finalized: spawns applied, anchor
-- nodes placed, volume extended for the cage/lobby.
local function materialize(desc)
	if desc.type == "external" then
		return false
	end
	local builder = builders[desc.type]
	if builder then
		local rebuilt, err = builder({
			seed = desc.seed,
			origin = desc.origin,
			name = desc.dir and desc.dir:match("([^/]+)$") or nil,
			layout = desc.layout, -- resolved layout overrides (procedural)
		})
		if not rebuilt then
			minetest.log("error", "[game_mode] map rebuild failed: " .. tostring(err))
			return false
		end
		apply_spawns(rebuilt.anchor)
		place_anchor_nodes(rebuilt.anchor)
		extend_volume_for_shared(rebuilt)
		map.current = rebuilt
		return true
	end
	minetest.log("error", "[game_mode] no builder for map type " .. tostring(desc.type))
	return false
end

local function default_origin(map_type)
	if map_type == "test" then
		return { x = 0, y = 0, z = 0 }
	end
	return configured_origin({ x = 0, y = 30, z = 0 })
end

-- Resolve the next seed: a pinned runtime/config seed replays the
-- same arena; otherwise every match gets a fresh one.
local function next_seed()
	local pinned = map.runtime.seed or tonumber(sget("sl_map.seed")) or nil
	if pinned and pinned ~= 0 then
		return math.floor(pinned)
	end
	return math.floor(math.random() * 2000000000)
end

-- Build and register the map for the coming match.
function map.prepare(opts)
	opts = opts or {}

	-- An adopted external arena (aaa_botmatch) stays in place across
	-- matches: only re-arm the journal and the mob purge.
	if map.current and map.current.type == "external" and not opts.force then
		map.journal = {}
		map.journal_index = {}
		map.journal_active = true
		map.clear_mobs()
		persist_current()
		return true, map.current
	end

	local map_type = opts.type or configured_type()
	local name = opts.name or map.runtime.schematic or sget("sl_map.schematic") or "random"
	local seed = opts.seed or next_seed()
	local origin = table.copy(opts.origin) or default_origin(map_type)

	local desc, err
	if builders[map_type] then
		desc, err = builders[map_type]({ seed = seed, origin = origin, name = name })
	else
		err = S("no builder registered for map type '@1'", map_type)
	end

	-- Never block a match on a map problem: fall back to procedural.
	if not desc then
		minetest.log("warning", "[game_mode] map type '" .. tostring(map_type)
			.. "' failed (" .. tostring(err) .. "); falling back to procedural")
		map_type = "procedural"
		desc = build_procedural({ seed = seed, origin = origin })
	end

	map.building = true
	apply_spawns(desc.anchor)
	place_anchor_nodes(desc.anchor)
	extend_volume_for_shared(desc)
	map.building = false
	build_cage()

	desc.seed = seed
	map.current = desc
	map.journal = {}
	map.journal_index = {}
	map.journal_active = true
	map.clear_mobs()
	persist_current()

	minetest.log("action", string.format(
		"[game_mode] map prepared: type=%s name=%s seed=%s volume=%s..%s mobs=%d",
		desc.type, tostring(desc.name), tostring(desc.seed),
		minetest.pos_to_string(desc.minp), minetest.pos_to_string(desc.maxp),
		#(desc.mobs or {})))
	return true, desc
end

-- External arena owners (aaa_botmatch) register their own volume and
-- spawns; matches on it still get journal-based node reset and the
-- mob purge, but the map system never rebuilds the arena itself.
function map.adopt(desc)
	map.current = {
		type = "external",
		name = desc.name or "external",
		seed = nil,
		origin = desc.origin,
		anchor = desc.anchor,
		mobs = desc.mobs or {},
		minp = desc.minp,
		maxp = desc.maxp,
	}
	map.journal = {}
	map.journal_index = {}
	persist_current()
end

-- ================================================================
-- Mob lifecycle: purge everything at match end, spawn the map's
-- initial population at match start
-- ================================================================

local function mob_entity_names()
	local names = { [game_mode.MONSTER_NAME or (game_mode.modname .. ":monster")] = true }
	for _, def in pairs(game_mode.MONSTER_TYPES or {}) do
		if def.entity then
			names[def.entity] = true
		end
	end
	names["sl_scary:mob"] = true
	return names
end

function map.is_mob_name(name)
	return mob_entity_names()[name] == true
end

function map.clear_mobs()
	map.spawned_mobs = {}
	local mob_names = mob_entity_names()
	for _, luaent in pairs(minetest.luaentities or {}) do
		if luaent and luaent.object then
			if mob_names[luaent.name] or luaent.monster_owner or luaent.sl_map_mob then
				pcall(function() luaent.object:remove() end)
			end
		end
	end
end

function map.spawn_initial_mobs()
	local desc = map.current
	if not desc or not desc.mobs then return 0 end
	map.clear_mobs()
	local count = 0
	for _, m in ipairs(desc.mobs) do
		local obj = game_mode.spawn_monster(m.pos, m.variant, nil)
		if obj then
			count = count + 1
			table.insert(map.spawned_mobs, obj)
		end
	end
	if count > 0 then
		minetest.log("action", "[game_mode] initial map population spawned: "
			.. count .. " mob(s)")
	end
	return count
end

-- Leftover dropped items inside the arena are match residue too.
function map.clear_items_in_volume()
	local desc = map.current
	if not desc then return end
	for _, luaent in pairs(minetest.luaentities or {}) do
		if luaent and luaent.object and luaent.name == "__builtin:item" then
			local ok, pos = pcall(function() return luaent.object:get_pos() end)
			if ok and pos and pos_in_volume(vector.round(pos), desc.minp, desc.maxp) then
				pcall(function() luaent.object:remove() end)
			end
		end
	end
end

-- ================================================================
-- Node-change journal: anything a match changed OUTSIDE the map
-- volume is restored node-for-node at reset (inside the volume the
-- full re-materialization is authoritative)
-- ================================================================

local function journal_record(pos, oldnode)
	if not map.journal_active or map.building then return end
	local p = vector.round(pos)
	local hash = game_mode.pos_hash(p)
	if map.journal_index[hash] then return end
	if #map.journal >= MAX_JOURNAL then return end

	local node = oldnode or minetest.get_node(p)
	local entry = {
		pos = p,
		node = { name = node.name, param1 = node.param1 or 0, param2 = node.param2 or 0 },
	}
	local meta = minetest.get_meta(p)
	if meta and meta.to_table then
		local ok, mtable = pcall(meta.to_table, meta)
		if ok and mtable then entry.meta = mtable end
	end
	map.journal_index[hash] = #map.journal + 1
	table.insert(map.journal, entry)
end

local function restore_journal(volume_rebuild_covers)
	local entries = map.journal
	local desc = map.current
	for i = #entries, 1, -1 do
		local e = entries[i]
		if not (volume_rebuild_covers and desc and pos_in_volume(e.pos, desc.minp, desc.maxp)) then
			write_node(e.pos, e.node.name, e.node.param2)
			local meta = minetest.get_meta(e.pos)
			if e.meta and meta and meta.from_table then
				pcall(meta.from_table, meta, e.meta)
			end
		end
	end
	map.journal = {}
	map.journal_index = {}
end

minetest.register_on_placenode(function(pos, newnode, placer, oldnode)
	journal_record(pos, oldnode)
end)

minetest.register_on_dignode(function(pos, oldnode, digger)
	journal_record(pos, oldnode)
end)

-- ================================================================
-- Reset to initial state (called at match end)
-- ================================================================

function map.reset()
	local desc = map.current or unpersist_current()
	if not desc then
		return false
	end
	map.current = desc
	map.journal_active = false

	-- 1. Re-materialize the arena (or restore the journal fully when
	--    an external owner owns the build). materialize() also refreshes
	--    spawns and anchor nodes for rebuilt maps.
	map.building = true
	local volume_rebuilt = materialize(desc)
	if not volume_rebuilt then
		-- External arena: only restore the gameplay anchors themselves
		-- (a destroyed beacon is swapped via set_node, which the journal
		-- never sees); the owner's build stays untouched.
		write_node(desc.anchor.beacon_a, game_mode.modname .. ":beacon_a")
		write_node(desc.anchor.beacon_b, game_mode.modname .. ":beacon_b")
		if desc.anchor.altar then
			write_node(desc.anchor.altar, game_mode.modname .. ":ghost_altar")
		end
	end
	-- 2. Undo every journaled edit the rebuild does not already cover.
	restore_journal(volume_rebuilt)
	map.building = false
	build_cage()

	-- 3. No mobs survive the match; items left in the arena are wiped.
	map.clear_mobs()
	map.clear_items_in_volume()

	-- 4. Beacons back to full integrity.
	for _, team_id in ipairs(state.teams_order or { "beacon_a", "beacon_b" }) do
		local tdef = state.teams[team_id]
		tdef.hp = state.settings.beacon_hp or 100
		local key = team_id == "beacon_a" and "beacon_a" or "beacon_b"
		local pos = desc.anchor[key]
		if pos then
			fresh_beacon_meta(pos, tdef.label)
		end
	end

	persist_current()
	minetest.log("action", "[game_mode] map reset to initial state: "
		.. tostring(desc.name))
	return true
end

-- ================================================================
-- Save the current arena out as a handmade map (the no-WorldEdit
-- route to the same .mts workflow)
-- ================================================================

function map.save_current(name)
	name = (name or ""):match("^(%w[%w%-_]*)$")
	if not name then
		return false, S("map name must be letters/digits/dashes")
	end
	if not minetest.create_schematic then
		return false, S("engine lacks create_schematic")
	end
	local desc = map.current
	if not desc or not desc.minp then
		return false, S("no map prepared yet")
	end

	local out_dir = modpath .. "/maps/" .. name
	local conf_path = out_dir .. "/map.conf"
	local mts_path = out_dir .. "/map.mts"
	if file_exists(conf_path) or file_exists(mts_path) then
		return false, S("a map named '@1' already exists", name)
	end

	-- The engine appends ".mts" to the filename it is given.
	local ok = minetest.create_schematic(desc.minp, desc.maxp, nil, out_dir .. "/map")
	if not ok then
		return false, S("create_schematic failed")
	end

	-- Anchor/mob coordinates are stored schematic-relative (minp = 0,0,0).
	local fh = io.open(conf_path, "w")
	if fh then
		local function rel(p)
			return string.format("%d,%d,%d", p.x - desc.minp.x, p.y - desc.minp.y, p.z - desc.minp.z)
		end
		fh:write("name = " .. tostring(desc.name or name) .. "\n")
		fh:write("author = server export\n")
		fh:write("size = " .. string.format("%d,%d,%d",
			desc.maxp.x - desc.minp.x + 1,
			desc.maxp.y - desc.minp.y + 1,
			desc.maxp.z - desc.minp.z + 1) .. "\n")
		fh:write("rotation = 0\n")
		fh:write("beacon_a.pos = " .. rel(desc.anchor.beacon_a) .. "\n")
		fh:write("beacon_b.pos = " .. rel(desc.anchor.beacon_b) .. "\n")
		fh:write("altar.pos = " .. rel(desc.anchor.altar) .. "\n")
		fh:write("mm.pos = " .. rel(desc.anchor.mm_pad) .. "\n")
		fh:write("lobby.pos = " .. rel(desc.anchor.lobby) .. "\n")
		fh:write("ghost.pos = " .. rel(desc.anchor.ghost) .. "\n")
		for i, m in ipairs(desc.mobs or {}) do
			fh:write(string.format("mobs.%d = %s,%s\n", i, rel(m.pos), tostring(m.variant)))
		end
		fh:close()
	end
	return true, mts_path
end

-- Boot: restore any persisted runtime overrides.
unpersist_current()
