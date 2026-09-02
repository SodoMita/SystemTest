-- ================================================================
-- sl_texgen/gen/scary.lua — sl_scary mob sprite strips + nodes
--
-- Ports the three 144x16 (9-frame) upright-sprite strips:
--   dredger    black body, rust-orange armor, neon-green visor/LEDs
--   wraith     deep-purple void body, neon-cyan eyes/fragments
--   containment black body, crimson flesh, neon-amber maw/eyes
-- Frame grammar matches the pipeline that produced the stock strips:
--   1-3 idle, 4-6 walk, 7-8 attack, 9 death (sink/collapse).
--
-- Also ports hide_spot node textures (dark planked crate faces with
-- cold steel corners) and the two 16x16 mob body textures.
-- ================================================================
local C = sl_texgen.canvas

local W, H = 16, 16

local function alpha(col, a) return { col[1], col[2], col[3], a } end

local MOBS = {
	dredger = {
		body = { 8, 8, 10 }, armor = { 204, 102, 34 }, accent = { 0, 255, 65 },
	},
	wraith = {
		body = { 26, 0, 51 }, armor = { 26, 0, 51 }, accent = { 0, 255, 255 },
	},
	containment = {
		body = { 10, 6, 6 }, armor = { 139, 0, 0 }, accent = { 255, 191, 0 },
	},
}

-- paint one 16x16 humanoid silhouette; pose varies by frame phase
local function paint_mob(c, spec, f)
	local B, A, K = spec.body, spec.armor, spec.accent
	local phase = (f - 1) % 9
	local kind = phase <= 2 and "idle" or (phase <= 5 and "walk" or (phase <= 7 and "attack" or "death"))
	local swing = 0
	local bob = 0
	local sink = 0
	if kind == "walk" then
		swing = ((phase - 3) % 2 == 0) and 1 or -1
		bob = (phase % 2)
	elseif kind == "attack" then
		bob = 1
	elseif kind == "death" then
		sink = 4
	end

	local function leg(x)
		C.rect(c, x, 11 + sink - bob, 2, 5 + bob, B)
		C.rect(c, x, 14 + sink, 2, 2, A) -- boots
	end
	-- legs (walk swing)
	leg(4 + swing)
	leg(10 - swing)
	-- torso
	C.rect(c, 5, 6 + bob + sink, 6, 6, B)
	C.rect(c, 5, 6 + bob + sink, 6, 2, A) -- shoulder yoke
	-- arms
	C.rect(c, 3, 7 + bob + sink, 2, 5, B)
	C.rect(c, 11, 7 + bob + sink, 2, 5, B)
	if kind == "attack" then
		C.rect(c, 11, 5 + sink, 2, 3, A) -- raised arm
	end
	-- head
	C.rect(c, 6, 2 + bob + sink, 4, 4, B)
	C.rect(c, 6, 2 + bob + sink, 4, 1, A) -- helmet brim
	-- eyes / visor
	C.rect(c, 7, 3 + bob + sink, 2, 1, K)
	if spec == MOBS.dredger then
		C.set(c, 8, 9 + bob + sink, K) -- chest LED
	elseif spec == MOBS.wraith then
		-- data fragments around the body
		C.set(c, 2, 4 + ((f * 3) % 8), alpha(K, 140))
		C.set(c, 13, 6 + ((f * 5) % 7), alpha(K, 120))
		C.set(c, 12, 2 + ((f * 2) % 5), alpha(K, 90))
	elseif spec == MOBS.containment then
		C.rect(c, 7, 4 + bob + sink, 2, 1, K) -- maw
		C.set(c, 5, 3 + bob + sink, K)        -- sensor eyes
		C.set(c, 10, 3 + bob + sink, K)
	end
end

local function mob_strip(key)
	local spec = MOBS[key]
	return function(c, R, f)
		-- frames compose side by side; draw this frame's 16x16 cell
		C.rect(c, 0, 0, W, H, { 0, 0, 0, 0 })
		paint_mob(c, spec, f)
	end
end

local function mob_icon(key)
	local spec = MOBS[key]
	return function(c)
		C.rect(c, 0, 0, W, H, { 0, 0, 0, 0 })
		paint_mob(c, spec, 1)
	end
end

----------------------------------------------------------------
-- hide spots: dark planked crate faces + steel corners
----------------------------------------------------------------
local PLANK   = { 16, 16, 18, 255 }
local PLANK2  = { 24, 24, 30, 255 }
local STEEL   = { 96, 112, 144, 255 }
local STEEL2  = { 112, 128, 148, 255 }

local function hide_face(c, R, top_vent)
	for y = 0, 15 do
		for x = 0, 15 do
			local p = ((x + (y % 2) * 7) % 8 == 0) and PLANK2 or PLANK
			local f = 0.9 + R() * 0.2
			C.set(c, x, y, { math.floor(p[1] * f), math.floor(p[2] * f), math.floor(p[3] * f), 255 })
		end
	end
	-- steel corner brackets
	C.rect(c, 0, 0, 2, 2, STEEL)
	C.rect(c, 14, 0, 2, 2, STEEL)
	C.rect(c, 0, 14, 2, 2, STEEL)
	C.rect(c, 14, 14, 2, 2, STEEL)
	C.frame(c, 0, 0, 16, 16, STEEL2)
	if top_vent then
		C.rect(c, 5, 6, 6, 1, STEEL)
		C.rect(c, 5, 9, 6, 1, STEEL)
	end
end

return {
	{ name = "sl_scary_dredger_strip.png", w = W, h = H, frames = 9, seed = 31, draw = mob_strip("dredger") },
	{ name = "sl_scary_wraith_strip.png", w = W, h = H, frames = 9, seed = 32, draw = mob_strip("wraith") },
	{ name = "sl_scary_containment_strip.png", w = W, h = H, frames = 9, seed = 33, draw = mob_strip("containment") },
	{ name = "sl_scary_signal_wraith.png", w = W, h = H, seed = 34, draw = mob_icon("wraith") },
	{ name = "scary_mob_texture.png", w = W, h = H, seed = 35, draw = mob_icon("dredger") },
	{ name = "hide_spot_side.png", w = 64, h = 64, seed = 41,
		draw = function(c, R) C.rect(c, 0, 0, 64, 64, { 0, 0, 0, 0 }); for y = 0, 48, 16 do C.paste(c, (function() local t = C.new(16, 16); hide_face(t, R, false); return t end)(), 0, y + 8) end end },
	{ name = "hide_spot_top.png", w = 64, h = 64, seed = 42,
		draw = function(c, R) C.rect(c, 0, 0, 64, 64, { 0, 0, 0, 0 }); for yy = 0, 3 do for xx = 0, 3 do local t = C.new(16, 16); hide_face(t, R, yy == 0); C.paste(c, t, xx * 16, yy * 16) end end end },
	{ name = "hide_spot_bottom.png", w = 64, h = 64, seed = 43,
		draw = function(c, R) C.rect(c, 0, 0, 64, 64, { 0, 0, 0, 0 }); for yy = 0, 3 do for xx = 0, 3 do local t = C.new(16, 16); hide_face(t, R, false); C.paste(c, t, xx * 16, yy * 16) end end end },
}
