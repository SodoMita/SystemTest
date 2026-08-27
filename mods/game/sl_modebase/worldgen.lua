-- ================================================================
-- System Looting — worldgen: the infinite flat neon grid floor
-- ================================================================
-- The game runs on the singlenode mapgen (see game.conf), which
-- generates nothing on its own: without help the world is pure void.
-- This file gives every generated chunk a flat floor of transparent
-- neon grid (ground:square_neon) at ground level, extending infinitely
-- in every direction, so players can never walk off the map and fall
-- into the void. The floor is a single node thick — the void still
-- shows through the glowing grid, which is the look the game wants.
-- The tiny arena (test_harness.lua) is a finite grid of monster cubes
-- sitting on top of this plane, at the same ground level.
-- ================================================================

local FLOOR_LEVEL = 0

game_mode.FLOOR_LEVEL = FLOOR_LEVEL
game_mode.FLOOR_NODE = "ground:square_neon"

-- Floor one generated chunk (minp..maxp as passed to on_generated).
-- Inside the generation callback the mapgen VoxelManip is available for
-- a fast bulk write; when it is not (headless test stub, or an engine
-- that refuses the mapgen object) this falls back to plain set_node.
-- Returns the number of floor nodes written.
function game_mode.generate_floor(minp, maxp)
	local floor_node = minetest.registered_nodes[game_mode.FLOOR_NODE]
		and game_mode.FLOOR_NODE
	if not floor_node then
		return 0
	end
	-- Only chunks that cross ground level contain floor columns.
	if minp.y > FLOOR_LEVEL or maxp.y < FLOOR_LEVEL then
		return 0
	end

	if minetest.get_mapgen_object and minetest.get_content_id and VoxelArea then
		-- Fast path: bulk-write straight into the mapgen's VoxelManip.
		-- Only valid while inside on_generated; any failure here (wrong
		-- context, missing object) falls through to the set_node path.
		local ok, placed = pcall(function()
			local vm = minetest.get_mapgen_object("voxelmanip")
			local emin, emax = vm:get_emerged_area()
			local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
			local data = vm:get_data()
			local id = minetest.get_content_id(floor_node)
			local count = 0
			for z = minp.z, maxp.z do
				for x = minp.x, maxp.x do
					local vi = area:index(x, FLOOR_LEVEL, z)
					if data[vi] ~= id then
						data[vi] = id
						count = count + 1
					end
				end
			end
			if count > 0 then
				vm:set_data(data)
				vm:write_to_map()
			end
			return count
		end)
		if ok then
			return placed
		end
		minetest.log("warning", "[game_mode] mapgen VoxelManip path failed ("
			.. tostring(placed) .. "); flooring chunk with set_node instead")
	end

	local count = 0
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			minetest.set_node({ x = x, y = FLOOR_LEVEL, z = z }, { name = floor_node })
			count = count + 1
		end
	end
	return count
end

-- The floor is on by default. Disabled with sl_arena.infinite_floor = false
-- (string comparison, matching the sl_test.auto_arena convention, so an
-- unset setting behaves like the engine's nil and keeps the floor on).
if minetest.settings:get("sl_arena.infinite_floor") ~= "false" then
	minetest.register_on_generated(function(minp, maxp, blockseed)
		game_mode.generate_floor(minp, maxp)
	end)
	minetest.log("action", "[game_mode] infinite flat neon grid floor enabled (y = "
		.. FLOOR_LEVEL .. ")")
end
