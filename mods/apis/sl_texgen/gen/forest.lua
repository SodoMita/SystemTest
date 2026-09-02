-- ================================================================
-- sl_texgen/gen/forest.lua — construction "forest" biome blocks
--
-- Ports the four 32x32 forest-biome block textures: the magenta
-- cross-bloom decoration, the green platform edge, the cyan portal
-- pad and the green pane grid wall.  Alpha 192 throughout (stock).
-- ================================================================
local C = sl_texgen.canvas

local S = 32

local function alpha(col, a) return { col[1], col[2], col[3], a or 192 } end

-- decoration: soft magenta glow cross with a small ring core
local function draw_decoration(c, R)
	C.clear(c, { 0, 0, 0, 0 })
	local mid = { 190, 30, 190 }
	local hot = { 230, 90, 230 }
	C.radial(c, 16, 16, 13, alpha(mid, 120), alpha(mid, 0))
	C.rect(c, 14, 4, 4, 24, alpha(mid, 190))
	C.rect(c, 4, 14, 24, 4, alpha(mid, 190))
	C.rect(c, 15, 5, 2, 22, alpha(hot, 220))
	C.rect(c, 5, 15, 22, 2, alpha(hot, 220))
	C.thick_ring(c, 16, 16, 4, 2, alpha(hot, 230))
	C.disc(c, 16, 16, 2, alpha(hot, 240))
end

-- platform: dark top, glowing green deck edge with struts
local function draw_platform(c, R)
	C.clear(c, { 3, 8, 4, 192 })
	for y = 0, 13 do
		for x = 0, 31 do
			local f = y / 13
			local g = math.floor(10 + 26 * (1 - f))
			C.set(c, x, y, { 2, g, 4, 192 })
		end
	end
	-- deck rails
	C.rect(c, 0, 16, 32, 4, { 20, 170, 25, 192 })
	C.rect(c, 0, 22, 32, 4, { 25, 190, 30, 192 })
	C.rect(c, 0, 16, 32, 1, { 120, 255, 120, 192 })
	C.rect(c, 0, 22, 32, 1, { 130, 255, 130, 192 })
	-- struts
	C.rect(c, 4, 20, 2, 2, { 40, 220, 45, 192 })
	C.rect(c, 26, 20, 2, 2, { 40, 220, 45, 192 })
	C.rect(c, 15, 20, 2, 2, { 40, 220, 45, 192 })
	-- under-dark
	C.rect(c, 0, 26, 32, 6, { 2, 6, 3, 192 })
end

-- special: cyan portal pad — concentric squares + corner dashes
local function draw_special(c, R)
	C.clear(c, { 6, 10, 14, 192 })
	C.radial(c, 16, 16, 14, { 0, 60, 70, 110 }, { 6, 10, 14, 0 })
	local rings = {
		{ 4, { 30, 200, 220 }, 1 }, { 6, { 60, 220, 235 }, 2 },
		{ 9, { 20, 160, 180 }, 1 }, { 12, { 0, 230, 240 }, 2 },
	}
	for _, r in ipairs(rings) do
		C.frame(c, 16 - r[1], 16 - r[1], r[1] * 2, r[1] * 2, alpha(r[2], 210))
		for _ = 2, r[3] do
			C.frame(c, 15 - r[1], 15 - r[1], r[1] * 2 + 2, r[1] * 2 + 2, alpha(r[2], 120))
		end
	end
	C.rect(c, 12, 12, 8, 8, { 10, 90, 100, 220 })
	-- corner dashes (NE/NW/SE/SW)
	for _, pt in ipairs({ { 2, 2 }, { 26, 2 }, { 2, 26 }, { 26, 26 } }) do
		C.rect(c, pt[1], pt[2], 4, 2, { 0, 220, 230, 200 })
		C.rect(c, pt[1] + 1, pt[2] + 2, 2, 2, { 0, 190, 200, 160 })
	end
end

-- wall: dark green field with lighter pane grid
local function draw_wall(c, R)
	C.clear(c, { 6, 26, 12, 192 })
	for y = 0, 31 do
		for x = 0, 31 do
			local f = 0.9 + R() * 0.2
			C.set(c, x, y, { math.floor(6 * f), math.floor(26 * f), math.floor(12 * f), 192 })
		end
	end
	local line = { 0, 120, 60, 192 }
	local hotline = { 0, 200, 100, 192 }
	-- verticals
	C.rect(c, 10, 0, 2, 18, line)
	C.rect(c, 22, 8, 2, 24, line)
	C.rect(c, 0, 0, 2, 32, line)
	C.rect(c, 30, 0, 2, 32, line)
	-- horizontals
	C.rect(c, 0, 17, 12, 2, line)
	C.rect(c, 10, 8, 14, 2, line)
	C.rect(c, 22, 0, 10, 2, line)
	C.rect(c, 0, 30, 32, 2, line)
	-- top-lit edges
	C.rect(c, 10, 0, 1, 18, hotline)
	C.rect(c, 0, 17, 12, 1, hotline)
	C.rect(c, 22, 8, 1, 24, hotline)
end

return {
	{ name = "forest_decoration_1.png", w = S, h = S, seed = 901, draw = draw_decoration },
	{ name = "forest_platform_0.png", w = S, h = S, seed = 902, draw = draw_platform },
	{ name = "forest_special_0.png", w = S, h = S, seed = 903, draw = draw_special },
	{ name = "forest_wall_0.png", w = S, h = S, seed = 904, draw = draw_wall },
}
