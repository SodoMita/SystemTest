-- ================================================================
-- sl_texgen/gen/construction.lua — animated node spritesheets
--
-- Ports the 30/50-frame 32x32 plantlike effect sheets (fire, smoke,
-- plasma, water, bubbles, ice, sparks, snowflake) in tech/forest/
-- cave palettes.  Layout is the stock one: N frames side by side in
-- one strip, played via tiles.animation = { type = "sheet_2d",
-- frames_w = N, frames_h = 1 }.
--
-- Each family is a small physical model driven by the seeded rng:
--   fire    — rising flame blobs, red->orange->white core
--   smoke   — rising translucent puffs, fading with height
--   plasma  — pulsing rings + orbiting blobs
--   water   — sine-waved surface bands with sparkle crests
--   bubbles — rising bubble rings with highlight dots
--   ice     — crystal spokes on a slow pulse
--   sparks  — radial burst particles, gravity arcs (loop variants)
--   snowflake — rotating 6-spoke crystal
-- ================================================================
local C = sl_texgen.canvas

local S = 32

-- palettes sampled from the retired stock sheets
local PAL = {
	tech   = { bright = { 255, 120, 40 }, mid = { 210, 60, 25 },  dim = { 120, 20, 15 }, glow = { 255, 220, 160 } },
	forest = { bright = { 190, 70, 30 },  mid = { 140, 35, 20 },  dim = { 70, 15, 12 }, glow = { 235, 170, 120 } },
	cave   = { bright = { 235, 40, 30 },  mid = { 150, 20, 18 },  dim = { 60, 8, 10 },  glow = { 255, 190, 150 } },
}

local function alpha(col, a) return { col[1], col[2], col[3], a } end

----------------------------------------------------------------
-- fire
----------------------------------------------------------------
local function draw_fire(pal)
	return function(c, R, f)
		local n = 11
		for i = 1, n do
			local bx = 3 + R() * (S - 6)
			local life = (f / 30 + R()) % 1
			local y = S - 4 - life * (S - 9)
			local r = (1 - life) * (3.2 + R() * 3.5) + 0.8
			local col = life < 0.35 and pal.glow or (life < 0.7 and pal.bright or pal.mid)
			C.radial(c, bx, y, r, alpha(col, math.floor(220 * (1 - life) + 35)), alpha(pal.dim, 0))
		end
		-- base ember bed
		C.radial(c, S / 2, S - 3, 8 + (f % 5) * 0.5, alpha(pal.bright, 190), alpha(pal.dim, 0))
		C.radial(c, S / 2, S - 2, 4, alpha(pal.glow, 160), alpha(pal.mid, 0))
	end
end

----------------------------------------------------------------
-- smoke
----------------------------------------------------------------
local function draw_smoke(pal)
	-- stock tech smoke is magenta/violet puffs; forest/cave reuse the
	-- same shape language in their own tints
	local tint = pal.tech_smoke or { 190, 60, 190 }
	return function(c, R, f)
		for i = 1, 6 do
			local bx = 5 + R() * (S - 10)
			local life = (f / 30 + R() * 0.9) % 1
			local y = S - 5 - life * (S - 12)
			local r = 2.5 + life * 7
			local a = math.floor(165 * (1 - life) + 30)
			C.radial(c, bx, y, r, alpha(tint, a), alpha(tint, 0))
		end
	end
end

----------------------------------------------------------------
-- plasma
----------------------------------------------------------------
local function draw_plasma(green)
	local core = green and { 90, 255, 90 } or { 120, 255, 120 }
	local mid = green and { 40, 180, 40 } or { 40, 160, 40 }
	local dim = green and { 12, 60, 12 } or { 12, 60, 12 }
	return function(c, R, f)
		local t = f / 30
		-- ground haze
		C.rect(c, 0, S - 6, S, 6, alpha(dim, 140))
		-- rising pulse ring
		local ry = S - 4 - ((t * 1.0) % 1) * (S - 8)
		local rr = 3 + 9 * (1 - ((t * 1.0) % 1))
		C.thick_ring(c, S / 2, ry, math.max(2, math.floor(rr)), 2, alpha(mid, 170))
		C.ring(c, S / 2, ry, math.max(2, math.floor(rr)) + 1, alpha(dim, 120))
		-- orbiting blobs
		for i = 1, 3 do
			local ang = t * math.pi * 2 + i * 2.1
			local ox = S / 2 + math.cos(ang) * (7 + i * 2)
			local oy = S - 8 - ((t + i * 0.33) % 1) * (S - 14)
			C.disc(c, ox, oy, 1 + (i % 2), alpha(core, 220))
		end
		-- core flash
		local flash = (math.sin(t * math.pi * 2 * 3) + 1) / 2
		C.radial(c, S / 2, S - 4, 4 + flash * 2, alpha(core, math.floor(120 + 100 * flash)), alpha(dim, 0))
	end
end

----------------------------------------------------------------
-- water
----------------------------------------------------------------
local function draw_water(pal)
	local deep = pal.water_deep or { 10, 30, 60 }
	local bright = pal.water_bright or { 90, 160, 255 }
	return function(c, R, f)
		C.clear(c, alpha(deep, 210))
		for band = 0, 2 do
			local yb = 8 + band * 9
			local ph = f / 30 * math.pi * 2 + band * 1.3
			for x = 0, S - 1 do
				local y = yb + math.floor(math.sin(ph + x * 0.45) * 2)
				C.line(c, x, y, x, y + 3, alpha(bright, band == 1 and 150 or 110))
				if (x + f + band * 7) % 11 == 0 then
					C.set(c, x, y - 1, alpha({ 220, 240, 255 }, 200))
				end
			end
		end
	end
end

----------------------------------------------------------------
-- bubbles
----------------------------------------------------------------
local function draw_bubbles(cyan)
	local rim = cyan and { 40, 235, 235 } or { 30, 90, 90 }
	local hi = cyan and { 190, 255, 255 } or { 120, 190, 190 }
	return function(c, R, f)
		for i = 1, 5 do
			local bx = 3 + R() * (S - 6)
			local speed = 0.5 + R()
			local life = (f / 30 * speed + R()) % 1
			local by = S - 3 - life * (S - 6)
			local r = 1 + R() * 2.6
			C.ring(c, bx, by, r, alpha(rim, math.floor(90 + 120 * life)))
			C.set(c, bx - r / 2, by - r / 2, alpha(hi, 220))
		end
	end
end

----------------------------------------------------------------
-- ice
----------------------------------------------------------------
local function draw_ice(c, R, f)
	local t = f / 30
	local rim = { 40, 210, 240 }
	local glow = { 150, 235, 255 }
	C.clear(c, { 6, 20, 30, 200 })
	-- pulsing crystal
	local cx, cy = S / 2, S / 2
	local pulse = 6 + math.floor(math.sin(t * math.pi * 2) * 2 + 2)
	for spoke = 0, 5 do
		local ang = spoke * math.pi / 3 + t * math.pi / 6
		C.line(c, cx, cy,
			cx + math.floor(math.cos(ang) * pulse),
			cy + math.floor(math.sin(ang) * pulse), alpha(rim, 190))
	end
	C.ring(c, cx, cy, math.max(2, pulse - 3), alpha(glow, 160))
	C.disc(c, cx, cy, 2, alpha(glow, 220))
	-- corner sparkles
	for i = 1, 3 do
		local sx, sy = 3 + R() * (S - 6), 3 + R() * (S - 6)
		C.set(c, sx, sy, alpha(glow, 150 + math.floor(100 * R())))
	end
end

----------------------------------------------------------------
-- sparks (radial burst; 30f one-shot look, 15/50f loop variants)
----------------------------------------------------------------
local function draw_sparks(frames)
	local function one(c, R, f)
		local t = f / frames
		for i = 1, 10 do
			local ang = R() * math.pi * 2
			local dist = (0.15 + 0.85 * R()) * (S / 2 - 2) * math.sqrt(t)
			local x = S / 2 + math.cos(ang) * dist
			local y = S / 2 + math.sin(ang) * dist - t * 3 -- slight rise
			local a = math.floor(230 * (1 - t) + 25)
			local col = R() < 0.25 and { 255, 230, 120 } or { 255, 200, 40 }
			C.set(c, x, y, alpha(col, a))
			if dist > 4 and x > 1 and x < S - 2 and y > 1 and y < S - 2 then
				C.set(c, x + 1, y, alpha(col, a / 2))
			end
		end
		-- core
		C.radial(c, S / 2, S / 2, 3 * (1 - t) + 1, alpha({ 255, 240, 180 }, math.floor(255 * (1 - t))), alpha({ 255, 180, 40 }, 0))
	end
	return function(c, R, f)
		-- wrap particles mid-flight so loops are seamless
		local tt = f / frames
		one(c, R, f)
		if tt > 0.6 then
			-- pre-seed the next burst faintly at the same rng position
			C.radial(c, S / 2, S / 2, 2, alpha({ 255, 200, 60 }, math.floor(80 * (tt - 0.6) * 2.5)), alpha({ 255, 180, 40 }, 0))
		end
	end
end

----------------------------------------------------------------
-- snowflake (rotating 6-spoke crystal, stock is cyan on black)
----------------------------------------------------------------
local function draw_snowflake(c, R, f)
	local t = f / 30
	local rim = { 130, 215, 235 }
	local soft = { 70, 150, 180 }
	C.clear(c, { 4, 10, 16, 230 })
	local cx, cy = S / 2, S / 2
	local rot = t * math.pi * 2
	for spoke = 0, 5 do
		local ang = spoke * math.pi / 3 + rot
		local dx, dy = math.cos(ang), math.sin(ang)
		C.line(c, cx, cy, cx + dx * 11, cy + dy * 11, alpha(rim, 220))
		-- barbs
		for b = 4, 10, 3 do
			local bx, by = cx + dx * b, cy + dy * b
			C.line(c, bx, by, bx + math.cos(ang + 0.9) * 3, by + math.sin(ang + 0.9) * 3, alpha(soft, 190))
			C.line(c, bx, by, bx + math.cos(ang - 0.9) * 3, by + math.sin(ang - 0.9) * 3, alpha(soft, 190))
		end
	end
	C.disc(c, cx, cy, 2, alpha({ 200, 240, 250 }, 230))
end

----------------------------------------------------------------
-- registry
----------------------------------------------------------------

local defs = {}

local function add(name, w, h, frames, seed, draw, vertical)
	defs[#defs + 1] = {
		name = name, w = w, h = h, frames = frames,
		vertical = vertical, seed = seed, draw = draw,
	}
end

-- fires
add("tech_fire_30frames.png", S, S, 30, 101, draw_fire(PAL.tech))
add("forest_fire_30f.png", S, S, 30, 102, draw_fire(PAL.forest))
add("cave_fire_30f.png", S, S, 30, 103, draw_fire(PAL.cave))
-- smokes (tech smoke keeps the stock magenta tint)
PAL.tech_smoke = { 200, 70, 200 }
add("tech_smoke_30frames.png", S, S, 30, 201, draw_smoke(PAL))
PAL.tech_smoke = { 150, 40, 130 }
add("forest_smoke_30f.png", S, S, 30, 202, draw_smoke(PAL))
PAL.tech_smoke = { 90, 60, 100 }
add("cave_smoke_30f.png", S, S, 30, 203, draw_smoke(PAL))
-- plasma (green family)
add("tech_plasma_30frames.png", S, S, 30, 301, draw_plasma(true))
add("cave_plasma_30f.png", S, S, 30, 302, draw_plasma(true))
add("forest_plasma_8f.png", S, S, 8, 303, draw_plasma(true))
-- water
PAL.water_deep = { 8, 24, 48 }
PAL.water_bright = { 80, 150, 240 }
add("tech_water_30frames.png", S, S, 30, 401, draw_water(PAL))
PAL.water_deep = { 6, 16, 30 }
PAL.water_bright = { 60, 120, 200 }
add("forest_water_30f.png", S, S, 30, 402, draw_water(PAL))
PAL.water_deep = { 4, 10, 22 }
PAL.water_bright = { 40, 90, 160 }
add("cave_water_30f.png", S, S, 30, 403, draw_water(PAL))
-- bubbles
add("tech_bubbles_30frames.png", S, S, 30, 501, draw_bubbles(true))
add("cave_bubbles_30f.png", S, S, 30, 502, draw_bubbles(false))
-- ice
add("tech_ice_30frames.png", S, S, 30, 601, draw_ice)
-- sparks
add("tech_sparks_30frames.png", S, S, 30, 701, draw_sparks(30))
add("tech_sparks_15frames_loop.png", S, S, 15, 702, draw_sparks(15))
add("tech_sparks_50frames_loop.png", S, S, 50, 703, draw_sparks(50))
-- snowflake
add("spinning_snowflake_30f.png", S, S, 30, 801, draw_snowflake)

return defs
