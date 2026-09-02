-- ================================================================
-- sl_texgen/stx.lua — [combine program compiler
--
-- The modifier language has no rect/gradient primitives, so the mod
-- ships a handful of tiny grayscale bases (textures/stx_*.png, tens
-- of KB, texture-packable, media-cached, sent once) and compiles
-- every generated texture into a pure "[combine:WxH:x,y=term:..."
-- program the CLIENT renders.  Nothing is rasterized server-side and
-- nothing but those base files and the program strings (which ride
-- inside the node/item defs) ever crosses the network.
--
-- Program model: blits of quantized primitives in white, colored via
-- one sheet-level "^[multiply:<family color>" finish (plus per-blit
-- colors where needed), alpha via "^[opacity:n".  Quantized radii /
-- alphas keep the client's unique-texture cache bounded.
--
-- All ops are deterministic; generators drive them with stx.rng.
-- ================================================================

local stx = {}

-- ----------------------------------------------------------------
-- rng (same LCG the bases script and old canvas used)
-- ----------------------------------------------------------------
local function mul32(a, b)
	local ah, al = math.floor(a / 65536) % 65536, a % 65536
	local bh, bl = math.floor(b / 65536) % 65536, b % 65536
	return (al * bl + ((ah * bl + al * bh) % 65536) * 65536) % 4294967296
end

function stx.rng(seed)
	local s = (math.floor(seed or 1)) % 4294967296
	if s == 0 then s = 2463534242 end
	return function()
		s = (mul32(s, 1103515245) + 12345) % 4294967296
		return s / 4294967296
	end
end

-- ----------------------------------------------------------------
-- font atlas index (must match tools/texgen_make_bases.py layout:
-- cells sorted by byte value, 8 columns x rows, cell 8x12, glyph 6x10)
-- ----------------------------------------------------------------
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
local GLYPH_CELL = {}
local GLYPH_TOTAL = 0
local GLYPH_ROWS = 0
do
	local keys = {}
	for k in pairs(GLYPHS) do keys[#keys + 1] = k end
	table.sort(keys)
	for i, k in ipairs(keys) do
		GLYPH_CELL[k] = { col = (i - 1) % 8, row = math.floor((i - 1) / 8) }
		GLYPH_TOTAL = i
	end
	GLYPH_ROWS = math.ceil(GLYPH_TOTAL / 8)
end
stx.GLYPH_COUNT = GLYPH_TOTAL

-- ----------------------------------------------------------------
-- program state
-- ----------------------------------------------------------------

--- new(w, h, opts): opts.frames (sprite strip length, default 1),
--- opts.finishing (list of raw modifiers appended to the whole sheet,
--- e.g. {"^[multiply:#E07828"}), opts.name (for error messages)
function stx.new(w, h, opts)
	opts = opts or {}
	return {
		name = opts.name or "?",
		w = w, h = h,
		frames = opts.frames or 1,
		finishing = opts.finishing or {},
		blits = {},
		_ox = 0, -- x offset of the frame being drawn
	}
end

local function multerm(color)
	if not color or color == "#FFFFFF" or color == "#ffffff" or color == "white" then
		return ""
	end
	return "^[multiply:" .. color
end

local function opterm(alpha)
	if not alpha or alpha >= 250 then return "" end
	return ("^[opacity:%d"):format(math.max(0, math.floor(alpha)))
end

local function add(p, x, y, term)
	x = math.floor(x + (p._ox or 0))
	y = math.floor(y + (p._oy or 0))
	p.blits[#p.blits + 1] = { x = x, y = y, term = term }
end

-- ----------------------------------------------------------------
-- drawing ops (called per frame; frames offset automatically)
-- ----------------------------------------------------------------

--- solid color rectangle
function stx.solid(p, x, y, w, h, color, alpha)
	add(p, x, y, ("stx_px.png^[resize:%dx%d"):format(w, h) .. multerm(color) .. opterm(alpha))
end

--- 1px (or thicker) rectangle outline: t rects
function stx.frame(p, x, y, w, h, color, alpha, t)
	t = t or 1
	stx.solid(p, x, y, w, t, color, alpha)
	stx.solid(p, x, y + h - t, w, t, color, alpha)
	stx.solid(p, x, y + t, t, h - 2 * t, color, alpha)
	stx.solid(p, x + w - t, y + t, t, h - 2 * t, color, alpha)
	if t > 1 then -- crude thickening
		stx.frame(p, x + 1, y + 1, w - 2, h - 2, color, alpha, t - 1)
	end
end

--- horizontal line as a solid rect (kept for readability at call sites)
function stx.hline(p, x, y, w, color, alpha)
	stx.solid(p, x, y, w, 1, color, alpha)
end

--- vertical line
function stx.vline(p, x, y, h, color, alpha)
	stx.solid(p, x, y, 1, h, color, alpha)
end

--- soft glow blob of radius r (quantized) centered at cx, cy
local GLOW_SIZES = { 4, 6, 8, 10, 12, 16, 20, 26, 32, 42, 56, 72 }
local RING_SIZES = { 6, 8, 10, 14, 18, 24, 32, 42, 56 }
local function quant(v, tab)
	local best, bd
	for _, x in ipairs(tab) do
		local d = math.abs(x - v)
		if not bd or d < bd then best, bd = x, d end
	end
	return best
end

function stx.glow(p, cx, cy, r, alpha, color)
	r = quant(r, GLOW_SIZES)
	add(p, cx - r / 2, cy - r / 2,
		("stx_glow.png^[resize:%dx%d"):format(r, r) .. multerm(color) .. opterm(alpha))
end

--- soft ring of radius r (quantized, 1.4x inflation like the base)
function stx.ring(p, cx, cy, r, alpha, color)
	r = quant(r, RING_SIZES)
	add(p, cx - r / 2, cy - r / 2,
		("stx_ring.png^[resize:%dx%d"):format(r, r) .. multerm(color) .. opterm(alpha))
end

--- grayscale TV-noise blit (rgb=true uses the rainbow static base)
function stx.noise(p, x, y, w, h, alpha, rgb)
	local base = rgb and "stx_noise_rgb.png" or "stx_noise.png"
	add(p, x, y, base .. ("^[resize:%dx%d"):format(w, h) .. opterm(alpha))
end

--- diagonal cross glyph / rhombus glyph blits (for ground blocks)
function stx.xglyph(p, x, y, s, alpha)
	add(p, x, y, ("stx_x.png^[resize:%dx%d"):format(s, s) .. opterm(alpha))
end

function stx.rhombus(p, x, y, s, alpha)
	add(p, x, y, ("stx_rhombus.png^[resize:%dx%d"):format(s, s) .. opterm(alpha))
end

--- text from the shared font atlas.  scale 2 = native 8x12 cells,
--- scale 1 = cells resized to 4x6.  Unknown chars advance silently.
function stx.label(p, x, y, str, color, alpha, scale)
	scale = scale or 1
	local adv = (scale == 1) and 4 or 8
	str = tostring(str):lower()
	for i = 1, #str do
		local cell = GLYPH_CELL[string.sub(str, i, i)]
		if cell then
			local term = ("stx_font.png^[sheet:8x%d:%d,%d"):format(GLYPH_ROWS, cell.col, cell.row)
			if scale == 1 then term = term .. "^[resize:4x6" end
			add(p, x + (i - 1) * adv, y, term .. multerm(color) .. opterm(alpha))
		end
	end
end

function stx.text_width(str, scale)
	scale = scale or 1
	return #tostring(str) * ((scale == 1) and 4 or 8)
end

--- append a raw finishing modifier applied to the whole sheet
function stx.finish(p, modifier)
	table.insert(p.finishing, modifier)
end

-- ----------------------------------------------------------------
-- compiler
-- ----------------------------------------------------------------
local function escape(term)
	return (term:gsub("([:%^])", "\\%1"))
end

--- compile to the final texture string, e.g.
--- "([combine:960x32:0,5=stx_glow.png\^[resize\:8x8\^[opacity\:120:...)^^[multiply\:#E0641E"
--- (grouping parens keep trailing modifiers out of the combine args)
function stx.compile(p)
	local prog
	if #p.blits == 0 then
		-- empty combine = fully transparent texture of the right size
		prog = ("[combine:%dx%d"):format(p.w, p.h)
	else
		local parts = { ("[combine:%dx%d"):format(p.w * p.frames, p.h) }
		for _, b in ipairs(p.blits) do
			parts[#parts + 1] = ":"
			-- frame offsets are already baked into b.x by draw()
			parts[#parts + 1] = b.x .. "," .. b.y .. "=" .. escape(b.term)
		end
		prog = table.concat(parts)
	end
	if #p.finishing > 0 then
		prog = "(" .. prog .. ")" .. table.concat(p.finishing)
	end
	return prog
end

return stx
