-- ================================================================
-- sl_texgen/gen/dignodes.lua — dig-test overlay textures
--
-- Tool glyphs (pick/hammer/axe), red X and "!" markers, white rating
-- digits — all at stock alpha 192.  Overlay tiles are combined by
-- code as  sl_texgen.texture("dignodes_<group>") .. "^" ..
-- sl_texgen.texture("dignodes_rating<r>"), so the look is preserved:
-- dusty-rose framed square, gray tool head, brown handle.
-- ================================================================
local stx = sl_texgen.stx

local FRAME  = "#D0B0B0"
local FRAME2 = "#A07070"
local STEEL  = "#696969"
local WOOD   = "#46280C"
local RED    = "#B24246"
local WHITE  = "#F0F0F0"

local function framed_square(p)
	stx.solid(p, 0, 0, 16, 16, FRAME, 192)
	stx.frame(p, 0, 0, 16, 16, FRAME2, 192)
end

local function handle(p, x0, y0, len)
	for i = 0, len - 1 do
		stx.solid(p, x0 + i, y0 - i, 2, 1, WOOD, 192)
	end
end

local function draw_pick(p)
	framed_square(p)
	handle(p, 2, 13, 9)
	-- curved-ish gray head
	stx.solid(p, 3, 5, 4, 2, STEEL, 192)
	stx.solid(p, 6, 3, 4, 2, STEEL, 192)
	stx.solid(p, 9, 3, 3, 3, "#919191", 192)
end

local function draw_crumbly(p)
	framed_square(p)
	handle(p, 3, 13, 8)
	stx.solid(p, 8, 2, 6, 5, STEEL, 192)
	stx.frame(p, 8, 2, 6, 5, "#919191", 192)
end

local function draw_choppy(p)
	framed_square(p)
	handle(p, 3, 13, 8)
	stx.solid(p, 8, 2, 3, 6, STEEL, 192)
	stx.solid(p, 11, 3, 3, 4, "#919191", 192)
	stx.solid(p, 10, 2, 1, 1, "#919191", 192)
end

local function draw_x(p)
	framed_square(p)
	stx.label(p, 5, 3, "x", RED, 192, 1)
	-- thicken: the 4x6 cell stretched once more
	stx.solid(p, 4, 5, 2, 2, RED, 192)
	stx.solid(p, 10, 5, 2, 2, RED, 192)
	stx.solid(p, 4, 9, 2, 2, RED, 192)
	stx.solid(p, 10, 9, 2, 2, RED, 192)
end

local function draw_bang(p)
	framed_square(p)
	stx.label(p, 7, 2, "!", RED, 192, 1)
end

local function draw_digit(n)
	return function(p)
		stx.solid(p, 0, 0, 16, 16, WHITE, 192)
		stx.label(p, 5, 4, tostring(n), "#FFFFFF", 255, 1)
	end
end

return {
	{ name = "dignodes_cracky.png", w = 16, h = 16, seed = 0, draw = draw_pick },
	{ name = "dignodes_crumbly.png", w = 16, h = 16, seed = 0, draw = draw_crumbly },
	{ name = "dignodes_choppy.png", w = 16, h = 16, seed = 0, draw = draw_choppy },
	{ name = "dignodes_none.png", w = 16, h = 16, seed = 0, draw = draw_x },
	{ name = "dignodes_dig_immediate.png", w = 16, h = 16, seed = 0, draw = draw_bang },
	{ name = "dignodes_rating1.png", w = 16, h = 16, seed = 0, draw = draw_digit(1) },
	{ name = "dignodes_rating2.png", w = 16, h = 16, seed = 0, draw = draw_digit(2) },
	{ name = "dignodes_rating3.png", w = 16, h = 16, seed = 0, draw = draw_digit(3) },
}
