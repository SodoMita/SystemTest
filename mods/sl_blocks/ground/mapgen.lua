-- System Looting worldgen: no Minetest Game nodes.
-- y = 0  -> glasslike neon plane (infinite)
-- y < 0  -> hollow cubes of opaque neon (walls + floors)
-- origin surface is the monster-master base
-- A FIXED number of monsters is spawned once when the origin is generated.

local PLANE = "ground:square_neon"
local SOLID = "ground:square_neon_opaque"

local function cube_size()
	local n = tonumber(minetest.settings:get("sl_cube_size")
		or minetest.settings:get("sl_arena.cube_size") or "") or 8
	return math.max(4, math.min(32, math.floor(n)))
end

-- Total monsters for the whole world, spawned exactly once at mapgen.
-- DISABLED BY DEFAULT since the match map system landed: mobs are match
-- entities now — purged when a match ends, (re)spawned from the map's
-- initial population when the next match starts. Set sl_map.mapgen_mobs
-- = true to restore the old ambient-worldgen monsters.
local function mapgen_mobs_enabled()
	return minetest.settings:get_bool("sl_map.mapgen_mobs", false)
end

local function monster_budget()
	local n = tonumber(minetest.settings:get("sl_cube_monsters") or "") or 12
	return math.max(0, math.min(64, math.floor(n)))
end

local function is_cube_shell(x, y, z, size)
	if y >= 0 then
		return false
	end
	return (x % size == 0) or (z % size == 0) or (y % size == 0)
end

local mm_base_done = false
local monsters_done = false

local function storage()
	return minetest.get_mod_storage and minetest.get_mod_storage() or nil
end

local function already_spawned()
	if monsters_done then
		return true
	end
	local st = storage()
	if st and st:get_string("sl_mapgen_mobs") == "1" then
		monsters_done = true
		return true
	end
	return false
end

local function mark_spawned()
	monsters_done = true
	local st = storage()
	if st then
		st:set_string("sl_mapgen_mobs", "1")
	end
end

local function place_mm_base()
	if mm_base_done then
		return
	end
	mm_base_done = true

	for x = -4, 4 do
		for z = -4, 4 do
			minetest.set_node({ x = x, y = 0, z = z }, { name = PLANE })
			local edge = (x == -4 or x == 4 or z == -4 or z == 4)
			if edge then
				for y = 1, 4 do
					minetest.set_node({ x = x, y = y, z = z }, { name = SOLID })
				end
			end
		end
	end
	for x = -4, 4 do
		for z = -4, 4 do
			minetest.set_node({ x = x, y = 5, z = z }, { name = SOLID })
		end
	end
	for y = 1, 2 do
		minetest.set_node({ x = 0, y = y, z = 4 }, { name = "air" })
	end

	if minetest.registered_nodes["sl_modebase:spawn_mm"] then
		minetest.set_node({ x = 0, y = 1, z = 0 }, { name = "sl_modebase:spawn_mm" })
	end
	if minetest.registered_nodes["sl_modebase:monster_spawner"] then
		minetest.set_node({ x = 2, y = 1, z = 0 }, { name = "sl_modebase:monster_spawner" })
	end

	if game_mode and game_mode.state then
		game_mode.state.monster_master.base_spawn = { x = 0, y = 2, z = 0 }
		game_mode.state.lobby_spawn = { x = 0, y = 2, z = 8 }
		if game_mode.save_spawns then
			game_mode.save_spawns()
		end
	end

	minetest.log("action", "[ground] monster master base placed at origin")
end

-- Place a fixed budget of monsters, one per underground cube around origin,
-- never again for this world.
local function spawn_fixed_monsters()
	if already_spawned() then
		return
	end
	if not (game_mode and game_mode.spawn_monster) then
		return
	end

	local budget = monster_budget()
	if budget <= 0 then
		mark_spawned()
		return
	end

	local size = cube_size()
	local variants = (game_mode.MONSTER_TYPE_ORDER) or { "stalker" }
	local spawned = 0
	-- First underground layer of cubes: iy = -1. Walk a square spiral in XZ.
	local ix, iz = 0, 0
	local dx, dz = 1, 0
	local segment_len, walked, turns = 1, 0, 0

	while spawned < budget do
		local cx = ix * size + math.floor(size / 2)
		local cy = -size + math.floor(size / 2)
		local cz = iz * size + math.floor(size / 2)
		-- Skip the cube directly under the MM pad so the base is not infested.
		if not (ix == 0 and iz == 0) then
			local variant = variants[(spawned % #variants) + 1]
			game_mode.spawn_monster({ x = cx, y = cy, z = cz }, variant)
			spawned = spawned + 1
		end
		ix = ix + dx
		iz = iz + dz
		walked = walked + 1
		if walked == segment_len then
			walked = 0
			local ndx, ndz = -dz, dx
			dx, dz = ndx, ndz
			turns = turns + 1
			if turns % 2 == 0 then
				segment_len = segment_len + 1
			end
		end
		-- Safety: never walk forever if budget is huge.
		if segment_len > 32 then
			break
		end
	end

	mark_spawned()
	minetest.log("action", "[ground] spawned " .. spawned
		.. " mapgen monsters (fixed budget, once)")
end

minetest.register_on_generated(function(minp, maxp, blockseed)
	local size = cube_size()
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	if not vm then
		return
	end
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data = vm:get_data()
	local c_air = minetest.get_content_id("air")
	local c_ignore = minetest.get_content_id("ignore")
	local c_plane = minetest.get_content_id(PLANE)
	local c_solid = minetest.get_content_id(SOLID)

	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				local vi = area:index(x, y, z)
				if y == 0 then
					data[vi] = c_plane
				elseif y < 0 and is_cube_shell(x, y, z, size) then
					data[vi] = c_solid
				else
					if data[vi] == c_ignore then
						data[vi] = c_air
					end
				end
			end
		end
	end

	vm:set_data(data)
	vm:calc_lighting()
	vm:write_to_map()
	vm:update_map()

	if minp.x <= 0 and maxp.x >= 0 and minp.z <= 0 and maxp.z >= 0
			and minp.y <= 0 and maxp.y >= 0 then
		minetest.after(0, place_mm_base)
		if mapgen_mobs_enabled() then
			minetest.after(0, spawn_fixed_monsters)
		end
	end
end)
