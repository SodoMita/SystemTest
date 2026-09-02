-- ================================================================
-- sl_texgen/gen/ground.lua — sl_blocks/ground textures
--
-- Ports:
--   * sus_nodes white/rainbow TV-static noise, 64x64 and the 4-frame
--     64x256 vertical animation strips (vertical_frames node anim).
--     Pure per-pixel noise from the seeded rng — the stock look.
--   * square_neon / square_neon_opaque — soft glowing grid squares.
--   * x_neon / x2_neon / rhombus_neon — soft glowing glyphs.
--     Drawn as alpha ramps (two-pass disc/line glow over the glyph),
--     close to the stock blurred-neon look; these are recolorable
--     base textures, node `color` does the tinting in-game.
-- ================================================================
local C = sl_texgen.canvas

local G = 64

local function alpha(col, a) return { col[1], col[2], col[3], a } end

----------------------------------------------------------------
-- noise
----------------------------------------------------------------
local function draw_noise(rainbow)
	return function(c, R)
		for y = 0, c.h - 1 do
			for x = 0, c.w - 1 do
				local v = math.floor(R() * 256)
				if rainbow then
					local r = math.floor((math.sin((x + v) * 0.12) * 0.5 + 0.5) * 255)
					local g = math.floor((math.sin((y + v) * 0.10 + 2) * 0.5 + 0.5) * 255)
					local b = math.floor((math.sin((x + y + v) * 0.08 + 4) * 0.5 + 0.5) * 255)
					C.set(c, x, y, { r, g, b, 255 })
				else
					C.set(c, x, y, { v, v, v, 255 })
				end
			end
		end
	end
end

----------------------------------------------------------------
-- neon glyphs: soft white glow via layered alpha passes
----------------------------------------------------------------
local function glow_disc(c, cx, cy, r)
	for rr = r, 1, -1 do
		local a = math.floor(46 + (1 - rr / r) * 90)
		C.disc(c, cx, cy, rr, alpha({ 255, 255, 255 }, a))
	end
end

local function glow_line(c, x0, y0, x1, y1, w)
	for i = w, 1, -1 do
		local a = math.floor(50 + (1 - i / w) * 130)
		-- draw parallel lines
		if x0 == x1 or y0 == y1 then
			local o = i - 1
			C.line(c, x0, y0 + o, x1, y1 + o, alpha({ 255, 255, 255 }, a))
			if o > 0 then
				C.line(c, x0, y0 - o, x1, y1 - o, alpha({ 255, 255, 255 }, a))
			end
		else
			C.line(c, x0, y0, x1, y1, alpha({ 255, 255, 255 }, a))
		end
	end
end

local function draw_square(c)
	C.clear(c, { 0, 0, 0, 0 })
	-- solid center so the glasslike node has body; strong rim
	C.rect(c, 2, 2, G - 4, G - 4, alpha({ 255, 255, 255 }, 26))
	for rr = 9, 1, -1 do
		local a = math.floor(30 + (1 - rr / 9) * 140)
		C.frame(c, rr, rr, G - rr * 2, G - rr * 2, alpha({ 255, 255, 255 }, a))
	end
	-- hot inner line
	C.frame(c, 2, 2, G - 4, G - 4, alpha({ 255, 255, 255 }, 235))
	C.frame(c, 3, 3, G - 6, G - 6, alpha({ 255, 255, 255 }, 120))
end

local function draw_square_opaque(c)
	draw_square(c)
	-- bake onto a dark plate (stock "opaque" variant)
	for y = 0, G - 1 do
		for x = 0, G - 1 do
			local p = C.get(c, x, y)
			local a = p[4] / 255
			C.set(c, x, y, {
				math.floor(p[1] * a + 8 * (1 - a)),
				math.floor(p[2] * a + 9 * (1 - a)),
				math.floor(p[3] * a + 12 * (1 - a)),
				255,
			})
		end
	end
end

local function draw_x(c, big)
	C.clear(c, { 0, 0, 0, 0 })
	local inset = big and 5 or 7
	glow_line(c, inset, inset, G - 1 - inset, G - 1 - inset, 5)
	glow_line(c, G - 1 - inset, inset, inset, G - 1 - inset, 5)
end

local function draw_rhombus(c)
	C.clear(c, { 0, 0, 0, 0 })
	local m = 6
	-- rotated square outline via diagonal steps
	for i = 0, G - 1 - 2 * m do
		local t = i
		-- top-left edge going down-right
		C.set(c, m + t, m + 0 + 0, { 0, 0, 0, 0 })
	end
	-- simpler: draw with lines between the 4 corners, thick glow
	local pts = {
		{ G / 2, m }, { G - m, G / 2 }, { G / 2, G - m }, { m, G / 2 },
	}
	for i = 1, 4 do
		local a, b = pts[i], pts[i % 4 + 1]
		glow_line(c, a[1], a[2], b[1], b[2], 5)
	end
end

return {
	{ name = "sus_nodes_white_noise_noanim_4n.png", w = G, h = G, seed = 11, draw = draw_noise(false) },
	{ name = "sus_nodes_rainbow_noise_noanim_4n.png", w = G, h = G, seed = 12, draw = draw_noise(true) },
	{ name = "sus_nodes_white_noise_anim_4n.png", w = G, h = G, frames = 4, vertical = true, seed = 11, draw = draw_noise(false) },
	{ name = "sus_nodes_rainbow_noise_anim_4n.png", w = G, h = G, frames = 4, vertical = true, seed = 12, draw = draw_noise(true) },
	{ name = "square_neon.png", w = G, h = G, seed = 0, draw = draw_square },
	{ name = "square_neon_opaque.png", w = G, h = G, seed = 0, draw = draw_square_opaque },
	{ name = "x_neon.png", w = G, h = G, seed = 0, draw = function(c) draw_x(c, true) end },
	{ name = "x2_neon.png", w = G, h = G, seed = 0, draw = function(c) draw_x(c, false) end },
	{ name = "rhombus_neon.png", w = G, h = G, seed = 0, draw = draw_rhombus },
}
