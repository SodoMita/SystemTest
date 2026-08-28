-- Handmade map in plain-Lua schematic form.
-- Same role as a WorldEdit-saved map.mts, but author-readable: the
-- loader (sl_modebase/map.lua) accepts either. The returned table is
-- the engine's schematic format:
--   size = {x, y, z}
--   data = flat node array ordered z, then y, then x (x fastest)
-- Anchor/mob positions live in map.conf next to this file.

local SX, SY, SZ = 21, 5, 21
local FLOOR = "ground:square_neon"
local WALL = "ground:square_neon_opaque"

local data = {}
for i = 1, SX * SY * SZ do
	data[i] = { name = "air" }
end

local function set(x, y, z, name)
	-- index = z*(SY*SX) + y*SX + x, 1-based for Lua
	data[z * SY * SX + y * SX + x + 1] = { name = name }
end

-- Floor.
for x = 0, SX - 1 do
	for z = 0, SZ - 1 do
		set(x, 0, z, FLOOR)
	end
end

-- Perimeter walls, two high.
for x = 0, SX - 1 do
	for y = 1, 2 do
		set(x, y, 0, WALL)
		set(x, y, SZ - 1, WALL)
	end
end
for z = 0, SZ - 1 do
	for y = 1, 2 do
		set(0, y, z, WALL)
		set(SX - 1, y, z, WALL)
	end
end

-- Beacon daises at the midfield line (beacon nodes placed by the game).
for _, cx in ipairs({ 5, 15 }) do
	for dx = -1, 1 do
		for dz = -1, 1 do
			set(cx + dx, 1, 10 + dz, WALL)
		end
	end
end

-- Midfield altar dais.
for dx = -1, 1 do
	for dz = -1, 1 do
		set(10 + dx, 1, 10 + dz, WALL)
	end
end

-- Monster Master pad at the far end, with flanking pillars.
for dx = -1, 1 do
	for dz = -1, 1 do
		set(10 + dx, 1, 17 + dz, WALL)
	end
end
set(9, 2, 18, WALL)
set(11, 2, 18, WALL)

-- Symmetric cover blocks.
for _, c in ipairs({ { 4, 5 }, { 16, 5 }, { 4, 14 }, { 16, 14 } }) do
	set(c[1], 1, c[2], WALL)
	set(c[1] + 1, 1, c[2], WALL)
	set(c[1], 1, c[2] + 1, WALL)
end

return {
	size = { x = SX, y = SY, z = SZ },
	data = data,
}
