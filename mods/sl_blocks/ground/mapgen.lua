-- System Looting worldgen: no Minetest Game nodes.
-- y = 0  -> glasslike neon plane
-- y < 0  -> hollow cubes of opaque neon (walls + floors)
-- cube interiors spawn monsters; origin surface is the monster-master base.

local PLANE = "ground:square_neon"
local SOLID = "ground:square_neon_opaque"

local function cube_size()
	local n = tonumber(minetest.settings:get("sl_cube_size") or "") or 8
	return math.max(4, math.min(32, math.floor(n)))
end

local function monsters_per_cube()
	local n = tonumber(minetest.settings:get("sl_cube_monsters") or "") or 1
	return math.max(0, math.min(8, math.floor(n)))
end

-- True when this node is a wall or floor of the cube lattice.
local function is_cube_shell(x, y, z, size)
	if y >= 0 then
		return false
	end
	return (x % size == 0) or (z % size == 0) or (y % size == 0)
end

-- Deterministic per-cube seed so monsters spawn once per cube, not per chunk.
local function cube_seed(ix, iy, iz)
	return ix * 73856093 + iy * 19349663 + iz * 83492791
end

local mm_base_done = false

local function place_mm_base()
	if mm_base_done then
		return
	end
	mm_base_done = true

	-- Raised neon pad + walls for the monster master, sitting on the y=0 plane.
	local origin = { x = 0, y = 0, z = 0 }
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
	-- Roof
	for x = -4, 4 do
		for z = -4, 4 do
			minetest.set_node({ x = x, y = 5, z = z }, { name = SOLID })
		end
	end
	-- Door on +Z face
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

local function spawn_cube_monsters(minp, maxp, size)
	local count = monsters_per_cube()
	if count <= 0 then
		return
	end
	if not (game_mode and game_mode.spawn_monster) then
		return
	end

	local ix0 = math.floor(minp.x / size)
	local ix1 = math.floor(maxp.x / size)
	local iy0 = math.floor(minp.y / size)
	local iy1 = math.floor(maxp.y / size)
	local iz0 = math.floor(minp.z / size)
	local iz1 = math.floor(maxp.z / size)

	local variants = (game_mode.MONSTER_TYPE_ORDER) or { "stalker" }

	for ix = ix0, ix1 do
		for iy = iy0, iy1 do
			for iz = iz0, iz1 do
				-- Cubes live strictly below the surface plane.
				if iy < 0 then
					local cx = ix * size + math.floor(size / 2)
					local cy = iy * size + math.floor(size / 2)
					local cz = iz * size + math.floor(size / 2)
					if cx >= minp.x and cx <= maxp.x
							and cy >= minp.y and cy <= maxp.y
							and cz >= minp.z and cz <= maxp.z then
						local rng = PseudoRandom(cube_seed(ix, iy, iz))
						for n = 1, count do
							local ox = rng:next(-math.floor(size / 4), math.floor(size / 4))
							local oz = rng:next(-math.floor(size / 4), math.floor(size / 4))
							local pos = { x = cx + ox, y = cy, z = cz + oz }
							local variant = variants[(rng:next(1, #variants))]
							game_mode.spawn_monster(pos, variant)
						end
					end
				end
			end
		end
	end
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
					-- Keep generated chunks empty of default stone / water.
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
			and minp.y <= 0 and maxp.y >= 5 then
		minetest.after(0, place_mm_base)
	end

	minetest.after(0, function()
		spawn_cube_monsters(minp, maxp, size)
	end)
end)
