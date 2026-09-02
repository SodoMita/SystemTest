-- ================================================================
-- sl_texgen/gen/forest.lua — construction "forest" biome blocks
--
-- Compiles the four 32x32 forest-biome block textures (magenta
-- cross-bloom decoration, green platform edge, cyan portal pad,
-- green pane grid wall) to client-side [combine programs.
-- ================================================================
local stx = sl_texgen.stx
local S = 32

local function draw_decoration(p, R)
	local M = "#C81EC8"
	local HOT = "#EE5AEE"
	stx.glow(p, 16, 16, 26, 110, M)
	stx.solid(p, 14, 4, 4, 24, M, 190)
	stx.solid(p, 4, 14, 24, 4, M, 190)
	stx.solid(p, 15, 5, 2, 22, HOT, 220)
	stx.solid(p, 5, 15, 22, 2, HOT, 220)
	stx.ring(p, 16, 16, 8, 230, HOT)
	stx.glow(p, 16, 16, 8, 230, HOT)
end

local function draw_platform(p, R)
	stx.solid(p, 0, 0, S, 14, "#041006", 255)
	stx.solid(p, 0, 0, S, 7, "#061808", 255)
	-- deck rails with lit tops
	stx.solid(p, 0, 16, S, 4, "#14AA19", 255)
	stx.solid(p, 0, 22, S, 4, "#19BE1E", 255)
	stx.solid(p, 0, 16, S, 1, "#78FF78", 255)
	stx.solid(p, 0, 22, S, 1, "#82FF82", 255)
	-- struts
	stx.solid(p, 4, 20, 2, 2, "#28DC2D", 255)
	stx.solid(p, 15, 20, 2, 2, "#28DC2D", 255)
	stx.solid(p, 26, 20, 2, 2, "#28DC2D", 255)
	-- under-dark
	stx.solid(p, 0, 26, S, 6, "#020603", 255)
end

local function draw_special(p, R)
	local C = "#00E0E8"
	stx.solid(p, 0, 0, S, S, "#060A0E", 255)
	stx.glow(p, 16, 16, 28, 90, "#00646E")
	for _, r in ipairs({ 4, 9, 13 }) do
		stx.frame(p, 16 - r, 16 - r, r * 2, r * 2, C, 210)
	end
	stx.solid(p, 11, 11, 10, 10, "#0A5A64", 255)
	for _, pt in ipairs({ { 2, 2 }, { 26, 2 }, { 2, 26 }, { 26, 26 } }) do
		stx.solid(p, pt[1], pt[2], 4, 2, C, 200)
		stx.solid(p, pt[1] + 1, pt[2] + 2, 2, 2, "#00BEC8", 160)
	end
end

local function draw_wall(p, R)
	stx.solid(p, 0, 0, S, S, "#06180C", 255)
	stx.noise(p, 0, 0, S, S, 40)
	local L = "#007838"
	local HOT = "#00C864"
	stx.solid(p, 10, 0, 2, 18, L, 255)
	stx.solid(p, 22, 8, 2, 24, L, 255)
	stx.solid(p, 0, 0, 2, 32, L, 255)
	stx.solid(p, 30, 0, 2, 32, L, 255)
	stx.solid(p, 0, 17, 12, 2, L, 255)
	stx.solid(p, 10, 8, 14, 2, L, 255)
	stx.solid(p, 22, 0, 10, 2, L, 255)
	stx.solid(p, 0, 30, S, 2, L, 255)
	stx.solid(p, 10, 0, 1, 18, HOT, 255)
	stx.solid(p, 0, 17, 12, 1, HOT, 255)
	stx.solid(p, 22, 8, 1, 24, HOT, 255)
end

return {
	{ name = "forest_decoration_1.png", w = S, h = S, seed = 901, draw = draw_decoration },
	{ name = "forest_platform_0.png", w = S, h = S, seed = 902, draw = draw_platform },
	{ name = "forest_special_0.png", w = S, h = S, seed = 903, draw = draw_special },
	{ name = "forest_wall_0.png", w = S, h = S, seed = 904, draw = draw_wall },
}
