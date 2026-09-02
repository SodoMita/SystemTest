-- ================================================================
-- sl_texgen/canvas.lua
-- Tiny deterministic software rasterizer shared by every generator.
--
-- A canvas is { w, h, px = table of w*h*4 ints } (RGBA, row-major,
-- origin top-left).  Everything here is pure Lua 5.1, has no engine
-- dependency and is fully deterministic: generators must only draw
-- through these primitives and seed via rng() so the runtime output
-- is byte-stable and verifiable in headless tests.
-- ================================================================

local C = {}

----------------------------------------------------------------
-- colors
----------------------------------------------------------------

local function clamp8(v)
	if v < 0 then return 0 elseif v > 255 then return 255 end
	return math.floor(v)
end
C.clamp8 = clamp8

function C.rgba(r, g, b, a)
	return { clamp8(r), clamp8(g), clamp8(b), clamp8(a or 255) }
end

-- shade(color, factor[, alpha]) — multiply rgb by factor
function C.shade(col, f, a)
	return { clamp8(col[1] * f), clamp8(col[2] * f), clamp8(col[3] * f), clamp8(a or col[4] or 255) }
end

----------------------------------------------------------------
-- rng — small LCG kept inside double-precision exact range
----------------------------------------------------------------

local function mul32(a, b)
	-- (a * b) % 2^32 using 16-bit splits, exact in doubles
	local ah, al = math.floor(a / 65536) % 65536, a % 65536
	local bh, bl = math.floor(b / 65536) % 65536, b % 65536
	return (al * bl + ((ah * bl + al * bh) % 65536) * 65536) % 4294967296
end

--- deterministic [0,1) stream; seed is any integer
function C.rng(seed)
	local s = (math.floor(seed or 1)) % 4294967296
	if s == 0 then s = 2463534242 end
	return function()
		s = (mul32(s, 1103515245) + 12345) % 4294967296
		return s / 4294967296
	end
end

function C.rint(R, n) return math.floor(R() * n) end
function C.pick(R, t) return t[math.floor(R() * #t) + 1] end
function C.lerp(a, b, t) return a + (b - a) * t end

----------------------------------------------------------------
-- pixel primitives
----------------------------------------------------------------

function C.new(w, h)
	return { w = w, h = h, px = {} }
end

local function inb(c, x, y)
	return x >= 0 and y >= 0 and x < c.w and y < c.h
end

--- replace pixel
function C.set(c, x, y, col)
	x, y = math.floor(x), math.floor(y)
	if not inb(c, x, y) then return end
	local i = (y * c.w + x) * 4
	c.px[i + 1], c.px[i + 2], c.px[i + 3], c.px[i + 4] = col[1], col[2], col[3], col[4]
end

--- fetch a copy of a pixel (or nil outside)
function C.get(c, x, y)
	x, y = math.floor(x), math.floor(y)
	if not inb(c, x, y) then return nil end
	local i = (y * c.w + x) * 4
	return { c.px[i + 1], c.px[i + 2], c.px[i + 3], c.px[i + 4] }
end

--- src-over blend a pixel
function C.over(c, x, y, col)
	x, y = math.floor(x), math.floor(y)
	if not inb(c, x, y) then return end
	local sa = col[4] / 255
	if sa <= 0 then return end
	local i = (y * c.w + x) * 4
	local dr, dg, db, da = c.px[i + 1] or 0, c.px[i + 2] or 0, c.px[i + 3] or 0, c.px[i + 4] or 0
	if sa >= 1 or da == 0 then
		c.px[i + 1], c.px[i + 2], c.px[i + 3], c.px[i + 4] = col[1], col[2], col[3], col[4]
		return
	end
	da = da / 255
	local oa = sa + da * (1 - sa)
	local k0, k1 = sa / oa, (da * (1 - sa)) / oa
	c.px[i + 1] = clamp8(col[1] * k0 + dr * k1)
	c.px[i + 2] = clamp8(col[2] * k0 + dg * k1)
	c.px[i + 3] = clamp8(col[3] * k0 + db * k1)
	c.px[i + 4] = clamp8(oa * 255)
end

local function maybe_over(c, x, y, col, blend)
	if blend == "over" then C.over(c, x, y, col) else C.set(c, x, y, col) end
end

--- filled rectangle
function C.rect(c, x, y, w, h, col, blend)
	for yy = y, y + h - 1 do
		for xx = x, x + w - 1 do
			maybe_over(c, xx, yy, col, blend)
		end
	end
end

--- 1px outline rectangle
function C.frame(c, x, y, w, h, col, blend)
	for xx = x, x + w - 1 do
		maybe_over(c, xx, y, col, blend)
		maybe_over(c, xx, y + h - 1, col, blend)
	end
	for yy = y + 1, y + h - 2 do
		maybe_over(c, x, yy, col, blend)
		maybe_over(c, x + w - 1, yy, col, blend)
	end
end

--- Bresenham line
function C.line(c, x0, y0, x1, y1, col, blend)
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx - dy
	while true do
		maybe_over(c, x0, y0, col, blend)
		if x0 == x1 and y0 == y1 then break end
		local e2 = err * 2
		if e2 > -dy then err = err - dy; x0 = x0 + sx end
		if e2 < dx then err = err + dx; y0 = y0 + sy end
	end
end

--- filled circle
function C.disc(c, cx, cy, r, col, blend)
	cx, cy, r = math.floor(cx), math.floor(cy), math.ceil(r)
	for yy = cy - r, cy + r do
		for xx = cx - r, cx + r do
			local dx, dy = xx - cx, yy - cy
			if dx * dx + dy * dy <= r * r then
				maybe_over(c, xx, yy, col, blend)
			end
		end
	end
end

--- 1px circle (midpoint algorithm)
function C.ring(c, cx, cy, r, col, blend)
	if r < 1 then C.set(c, cx, cy, col); return end
	cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
	local x, y, err = r, 0, 1 - r
	while x >= y do
		maybe_over(c, cx + x, cy + y, col, blend)
		maybe_over(c, cx + y, cy + x, col, blend)
		maybe_over(c, cx - y, cy + x, col, blend)
		maybe_over(c, cx - x, cy + y, col, blend)
		maybe_over(c, cx - x, cy - y, col, blend)
		maybe_over(c, cx - y, cy - x, col, blend)
		maybe_over(c, cx + y, cy - x, col, blend)
		maybe_over(c, cx + x, cy - y, col, blend)
		y = y + 1
		if err < 0 then
			err = err + 2 * y + 1
		else
			x = x - 1
			err = err + 2 * (y - x) + 1
		end
	end
end

--- ring with thickness t (draws t concentric rings)
function C.thick_ring(c, cx, cy, r, t, col, blend)
	for i = 0, t - 1 do
		C.ring(c, cx, cy, r - i, col, blend)
	end
end

--- radial gradient blob: color lerps col_in -> col_out (incl. alpha)
--- from center to radius; drawn with src-over. Great for glows/puffs.
function C.radial(c, cx, cy, rad, col_in, col_out)
	local r = math.ceil(rad)
	for yy = cy - r, cy + r do
		for xx = cx - r, cx + r do
			local d = math.sqrt((xx - cx) * (xx - cx) + (yy - cy) * (yy - cy))
			if d <= rad then
				local t = d / rad
				C.over(c, xx, yy, {
					C.lerp(col_in[1], col_out[1], t),
					C.lerp(col_in[2], col_out[2], t),
					C.lerp(col_in[3], col_out[3], t),
					C.lerp(col_in[4], col_out[4], t),
				})
			end
		end
	end
end

--- paste src canvas at (dx, dy) with src-over
function C.paste(c, src, dx, dy)
	for y = 0, src.h - 1 do
		for x = 0, src.w - 1 do
			local i = (y * src.w + x) * 4
			local a = src.px[i + 4]
			if a and a > 0 then
				C.over(c, x + dx, y + dy, { src.px[i + 1], src.px[i + 2], src.px[i + 3], a })
			end
		end
	end
end

--- fill whole canvas
function C.clear(c, col)
	C.rect(c, 0, 0, c.w, c.h, col)
end

----------------------------------------------------------------
-- pattern helpers (facade styles shared by workshop/modebox faces)
----------------------------------------------------------------

--- random pixel speckle (multiplicative brightness jitter)
function C.speckle(c, R, col, amt, alpha)
	amt = amt or 0.12
	for y = 0, c.h - 1 do
		for x = 0, c.w - 1 do
			local f = 1 - amt / 2 + R() * amt
			C.set(c, x, y, C.shade(col, f, alpha or col[4]))
		end
	end
end

--- horizontal 1px alternating two-color stripes (the "fabricator cloth" look)
function C.stripes_h(c, ca, cb)
	for y = 0, c.h - 1 do
		C.rect(c, 0, y, c.w, 1, (y % 2 == 0) and ca or cb)
	end
end

--- 45° diagonal stripes (caution tape)
function C.stripes_diag(c, w, ca, cb, period)
	for y = 0, c.h - 1 do
		for x = 0, c.w - 1 do
			C.set(c, x, y, ((math.floor((x + y) / period)) % w < 1) and ca or cb)
		end
	end
end

--- rounded-corner filled rect (radius r in px)
function C.round_rect(c, x, y, w, h, r, col, blend)
	C.rect(c, x + r, y, w - 2 * r, h, col, blend)
	C.rect(c, x, y + r, w, h - 2 * r, col, blend)
	C.disc(c, x + r, y + r, r, col, blend)
	C.disc(c, x + w - 1 - r, y + r, r, col, blend)
	C.disc(c, x + r, y + h - 1 - r, r, col, blend)
	C.disc(c, x + w - 1 - r, y + h - 1 - r, r, col, blend)
end

----------------------------------------------------------------
-- 3x5 micro font (matches tools/sheet.py glyphs used during dev)
----------------------------------------------------------------

local GLYPHS = {
	["0"]="111101101101111",["1"]="010110010010111",["2"]="111001111100111",["3"]="111001111001111",
	["4"]="101101111001001",["5"]="111100111001111",["6"]="111100111101111",["7"]="111001010010010",
	["8"]="111101111101111",["9"]="111101111001111",
	a="010101111101101",b="110101110101110",c="011100100100011",d="110101101101110",
	e="111100110100111",f="011100110100100",g="011100101101011",h="100100111101101",
	i="010000010010010",j="001001001101010",k="101110100110101",l="100100100100011",
	m="101111111101101",n="110101101101101",o="010101101101010",p="110101110100100",
	q="010101101110011",r="110101100100100",s="011100010001110",t="111010010010010",
	u="101101101101011",v="101101101010010",w="101101111111101",x="101101010101101",
	y="101101011001110",z="111001010100111",
	[" "]="000000000000000",["_"]="000000000000111",["-"]="000000111000000",
	["."]="000000000000010",[","]="000000000101000",["/"]="001001010100100",
	["("]="001010010010010",[")"]="100010010100100",[":"]="000010000010000",
	["="]="000111000111000",["+"]="000010111010000",["!"]="010010010000010",
	["'"]="010010000000000",["%"]="101001010100101",["?"]="111001011000010",
}

--- text metrics: width in px for scale s
function C.text_width(str, s)
	s = s or 1
	return (#str * 4 - 1) * s
end

--- draw text; blend "over" default; returns right edge x
function C.text(c, x, y, str, col, s, blend)
	s = s or 1
	str = tostring(str):lower()
	local cx = x
	for i = 1, #str do
		local g = GLYPHS[string.sub(str, i, i)]
		if g then
			for r = 0, 4 do
				for cc = 0, 2 do
					if string.sub(g, r * 3 + cc + 1, r * 3 + cc + 1) == "1" then
						if s == 1 then
							maybe_over(c, cx + cc, y + r, col, blend or "over")
						else
							C.rect(c, cx + cc * s, y + r * s, s, s, col, blend or "over")
						end
					end
				end
			end
		end
		cx = cx + 4 * s
	end
	return cx
end

function C.text_center(c, cx, y, str, col, s, blend)
	C.text(c, cx - math.floor(C.text_width(str, s) / 2), y, str, col, s, blend)
end

----------------------------------------------------------------
-- sheet composition
----------------------------------------------------------------

--- compose 1..n frame canvases (all same size) into a horizontal
--- sprite strip (or vertical when vertical=true)
function C.compose(canvases, vertical)
	local n = #canvases
	local w, h = canvases[1].w, canvases[1].h
	local sheet = C.new(vertical and w or w * n, vertical and h * n or h)
	for i = 1, n do
		local src = canvases[i]
		local ox = vertical and 0 or (i - 1) * w
		local oy = vertical and (i - 1) * h or 0
		for y = 0, h - 1 do
			local so = (y * w) * 4
			local di = ((oy + y) * sheet.w + ox) * 4
			for k = 0, w * 4 - 1 do
				sheet.px[di + k + 1] = src.px[so + k + 1]
			end
		end
	end
	return sheet
end

return C
