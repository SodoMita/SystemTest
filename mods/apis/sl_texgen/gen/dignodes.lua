-- ================================================================
-- sl_texgen/gen/dignodes.lua — dig-test overlay textures
--
-- Ports mods/apis/dignodes/textures: tool glyphs (pick/hammer/axe),
-- red X and "!" markers and white rating digits, all at stock alpha
-- 192.  Overlay tiles are combined by code as
--   "dignodes_<group>.png^dignodes_rating<r>.png"
-- so exact geometry is not critical, but the look is preserved:
-- dusty-rose framed square, gray tool head, brown handle.
-- ================================================================
local C = sl_texgen.canvas

local FRAME  = { 208, 176, 176, 192 }  -- dusty rose fill
local FRAME2 = { 160, 112, 112, 192 }  -- dusty rose border
local STEEL  = { 105, 105, 105, 192 }  -- tool head
local STEEL2 = { 145, 145, 145, 192 }  -- tool head light
local WOOD   = { 70, 40, 12, 192 }     -- handle
local RED    = { 178, 66, 70, 192 }    -- X / !
local WHITE  = { 240, 240, 240, 192 }  -- rating digits

local function framed_square(c)
	C.clear(c, FRAME)
	C.frame(c, 0, 0, 16, 16, FRAME2)
end

-- diagonal handle from bottom-left to top-right, tool head at top
local function handle(c, x0, y0, len)
	for i = 0, len - 1 do
		local x, y = x0 + i, y0 - i
		C.set(c, x, y, WOOD)
		C.set(c, x + 1, y, WOOD)
	end
end

-- pick: curved-ish gray head crossing the handle top
local function draw_pick(c)
	framed_square(c)
	handle(c, 2, 13, 9)
	for i = 0, 7 do
		local y = 3 + math.floor((4 - math.abs(i - 3.5)) * 0.6)
		C.set(c, 3 + i, y, STEEL)
		C.set(c, 3 + i, y + 1, STEEL2)
	end
end

-- crumbly: hammer head at handle top
local function draw_crumbly(c)
	framed_square(c)
	handle(c, 3, 13, 8)
	C.rect(c, 8, 2, 6, 5, STEEL)
	C.frame(c, 8, 2, 6, 5, STEEL2)
end

-- choppy: axe head
local function draw_choppy(c)
	framed_square(c)
	handle(c, 3, 13, 8)
	C.rect(c, 8, 2, 3, 6, STEEL)
	C.rect(c, 11, 3, 3, 4, STEEL2)
	C.set(c, 10, 2, STEEL)
end

local function draw_x(c)
	framed_square(c)
	for i = 0, 9 do
		C.set(c, 3 + i, 3 + i, RED)
		C.set(c, 4 + i, 3 + i, RED)
		C.set(c, 3 + i, 12 - i, RED)
		C.set(c, 4 + i, 12 - i, RED)
	end
end

local function draw_bang(c)
	framed_square(c)
	C.rect(c, 7, 3, 2, 7, RED)
	C.rect(c, 7, 11, 2, 2, RED)
end

local function draw_digit(c, n)
	C.clear(c, WHITE)
	if n == 1 then
		C.rect(c, 7, 3, 2, 10, WHITE)
		C.set(c, 6, 4, WHITE)
	elseif n == 2 then
		C.line(c, 5, 3, 10, 3, WHITE)
		C.line(c, 10, 4, 6, 8, WHITE)
		C.line(c, 6, 8, 10, 8, WHITE)
		C.line(c, 10, 9, 5, 12, WHITE)
		C.rect(c, 5, 12, 6, 1, WHITE)
	else
		C.line(c, 5, 3, 10, 3, WHITE)
		C.set(c, 10, 4, WHITE)
		C.rect(c, 9, 5, 2, 2, WHITE)
		C.rect(c, 6, 7, 3, 2, WHITE)
		C.set(c, 5, 9, WHITE)
		C.line(c, 5, 10, 10, 10, WHITE)
		C.line(c, 10, 11, 5, 12, WHITE)
		C.line(c, 5, 12, 5, 11, WHITE)
		for x = 5, 10 do C.set(c, x, 13, WHITE) end
	end
end

return {
	{ name = "dignodes_cracky.png", w = 16, h = 16, seed = 0, draw = draw_pick },
	{ name = "dignodes_crumbly.png", w = 16, h = 16, seed = 0, draw = draw_crumbly },
	{ name = "dignodes_choppy.png", w = 16, h = 16, seed = 0, draw = draw_choppy },
	{ name = "dignodes_none.png", w = 16, h = 16, seed = 0, draw = draw_x },
	{ name = "dignodes_dig_immediate.png", w = 16, h = 16, seed = 0, draw = draw_bang },
	{ name = "dignodes_rating1.png", w = 16, h = 16, seed = 0, draw = function(c) draw_digit(c, 1) end },
	{ name = "dignodes_rating2.png", w = 16, h = 16, seed = 0, draw = function(c) draw_digit(c, 2) end },
	{ name = "dignodes_rating3.png", w = 16, h = 16, seed = 0, draw = function(c) draw_digit(c, 3) end },
}
