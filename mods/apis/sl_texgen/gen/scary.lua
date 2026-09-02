-- ================================================================
-- sl_texgen/gen/scary.lua — sl_scary mob strips + hide spots
--
-- Compiles the three 9-frame 16x16 upright-sprite strips (dredger:
-- black body / rust-orange armor / neon-green accents; wraith:
-- void-purple / cyan; containment: black / crimson / amber) plus
-- hide spot crate faces.  Frame grammar: 1-3 idle, 4-6 walk,
-- 7-8 attack, 9 death.
-- ================================================================
local stx = sl_texgen.stx

local W, H = 16, 16

local MOBS = {
	dredger = { body = "#08080A", armor = "#CC6622", accent = "#00FF41" },
	wraith = { body = "#1A0033", armor = "#1A0033", accent = "#00FFFF" },
	containment = { body = "#0A0606", armor = "#8B0000", accent = "#FFBF00" },
}

local function paint_mob(p, spec, f)
	local B, A, K = spec.body, spec.armor, spec.accent
	local phase = (f - 1) % 9
	local kind = phase <= 2 and "idle" or (phase <= 5 and "walk" or (phase <= 7 and "attack" or "death"))
	local swing = (kind == "walk") and (((phase - 3) % 2 == 0) and 1 or -1) or 0
	local bob = (kind ~= "idle") and 1 or 0
	local sink = (kind == "death") and 4 or 0
	local y0 = bob + sink

	-- legs (walk swing)
	stx.solid(p, 4 + swing, 11 - bob + sink, 2, 5 + bob, B)
	stx.solid(p, 10 - swing, 11 - bob + sink, 2, 5 + bob, B)
	stx.solid(p, 4 + swing, 14 + sink, 2, 2, A)
	stx.solid(p, 10 - swing, 14 + sink, 2, 2, A)
	-- torso + shoulder yoke
	stx.solid(p, 5, 6 + y0, 6, 6, B)
	stx.solid(p, 5, 6 + y0, 6, 2, A)
	-- arms
	stx.solid(p, 3, 7 + y0, 2, 5, B)
	stx.solid(p, 11, 7 + y0, 2, 5, B)
	if kind == "attack" then
		stx.solid(p, 11, 5 + sink, 2, 3, A)
	end
	-- head + brim + eyes
	stx.solid(p, 6, 2 + y0, 4, 4, B)
	stx.solid(p, 6, 2 + y0, 4, 1, A)
	stx.solid(p, 7, 3 + y0, 2, 1, K)
	if spec == MOBS.dredger then
		stx.solid(p, 8, 9 + y0, 1, 1, K) -- chest LED
	elseif spec == MOBS.wraith then
		-- drifting data fragments
		stx.glow(p, 2, 4 + ((f * 3) % 8), 4, 130, K)
		stx.glow(p, 13, 6 + ((f * 5) % 7), 4, 110, K)
		stx.glow(p, 12, 2 + ((f * 2) % 5), 3, 80, K)
	elseif spec == MOBS.containment then
		stx.solid(p, 7, 4 + y0, 2, 1, K) -- maw
		stx.glow(p, 5, 3 + y0, 3, 220, K)
		stx.glow(p, 10, 3 + y0, 3, 220, K)
	end
end

local function mob_strip(key)
	local spec = MOBS[key]
	return function(p, R, f)
		paint_mob(p, spec, f)
	end
end

local function mob_icon(key)
	local spec = MOBS[key]
	return function(p)
		paint_mob(p, spec, 1)
	end
end

----------------------------------------------------------------
-- hide spots: dark planked crate faces with steel corners
----------------------------------------------------------------
local PLANK = "#101012"
local PLANK2 = "#18181E"
local STEEL = "#607090"
local STEEL2 = "#70808F"

local function hide_face(p, R, ox, oy, top_vent)
	p._ox = (p._ox or 0) + ox
	p._oy = (p._oy or 0) + oy
	stx.solid(p, 0, 0, 16, 16, PLANK)
	stx.noise(p, 0, 0, 16, 16, 60)
	stx.solid(p, 0, 7, 16, 1, PLANK2, 255)
	stx.solid(p, 0, 0, 2, 2, STEEL)
	stx.solid(p, 14, 0, 2, 2, STEEL)
	stx.solid(p, 0, 14, 2, 2, STEEL)
	stx.solid(p, 14, 14, 2, 2, STEEL)
	stx.frame(p, 0, 0, 16, 16, STEEL2, 255)
	if top_vent then
		stx.solid(p, 5, 6, 6, 1, STEEL)
		stx.solid(p, 5, 9, 6, 1, STEEL)
	end
	p._ox = (p._ox or 0) - ox
	p._oy = (p._oy or 0) - oy
end

return {
	{ name = "sl_scary_dredger_strip.png", w = W, h = H, frames = 9, seed = 31, draw = mob_strip("dredger") },
	{ name = "sl_scary_wraith_strip.png", w = W, h = H, frames = 9, seed = 32, draw = mob_strip("wraith") },
	{ name = "sl_scary_containment_strip.png", w = W, h = H, frames = 9, seed = 33, draw = mob_strip("containment") },
	{ name = "sl_scary_signal_wraith.png", w = W, h = H, seed = 34, draw = mob_icon("wraith") },
	{ name = "scary_mob_texture.png", w = W, h = H, seed = 35, draw = mob_icon("dredger") },
	{ name = "hide_spot_side.png", w = 64, h = 64, seed = 41,
		draw = function(p, R)
			stx.solid(p, 0, 0, 64, 64, "#0A0A0C")
			for y = 0, 3 do
				hide_face(p, R, 0, y * 16, false)
			end
		end },
	{ name = "hide_spot_top.png", w = 64, h = 64, seed = 42,
		draw = function(p, R)
			stx.solid(p, 0, 0, 64, 64, "#0A0A0C")
			for yy = 0, 3 do
				for xx = 0, 3 do
					hide_face(p, R, xx * 16, yy * 16, yy == 0)
				end
			end
		end },
	{ name = "hide_spot_bottom.png", w = 64, h = 64, seed = 43,
		draw = function(p, R)
			stx.solid(p, 0, 0, 64, 64, "#0A0A0C")
			for yy = 0, 3 do
				for xx = 0, 3 do
					hide_face(p, R, xx * 16, yy * 16, false)
				end
			end
		end },
}
