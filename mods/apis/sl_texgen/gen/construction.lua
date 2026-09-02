-- ================================================================
-- sl_texgen/gen/construction.lua — animated node spritesheets
--
-- Compiles the 30/50-frame 32x32 plantlike effect sheets (fire,
-- smoke, plasma, water, bubbles, ice, sparks, snowflake) in
-- tech/forest/cave palettes to client-side [combine programs.
-- Layout: N frames side by side in one strip, played via
-- tiles.animation = sheet_2d (sl_texgen.sheet()).
--
-- Each family is drawn white and tinted by one sheet-level
-- "^[multiply" finish; alpha does the per-blob shading, so the
-- client's unique-texture cache stays tiny.
-- ================================================================
local stx = sl_texgen.stx

local S = 32

local function sheet(name, frames, seed, draw, tint, opacity)
	local finish = { "^[multiply:" .. tint }
	if opacity then finish[#finish + 1] = "^[opacity:" .. opacity end
	return { name = name, w = S, h = S, frames = frames, seed = seed, draw = draw, _finish = finish }
end

----------------------------------------------------------------
-- fire: rising glow blobs + ember bed
----------------------------------------------------------------
local function draw_fire(p, R, f)
	stx.glow(p, S / 2, S - 3, 8 + (f % 5), 190)
	stx.glow(p, S / 2, S - 2, 4, 160)
	for i = 1, 6 do
		local bx = 3 + R() * (S - 6)
		local life = (f / 30 + R()) % 1
		local y = S - 4 - life * (S - 9)
		local r = (1 - life) * 11 + 3
		stx.glow(p, bx, y, r, math.floor(220 * (1 - life) + 35))
	end
end

----------------------------------------------------------------
-- smoke: rising puffs fading with height
----------------------------------------------------------------
local function draw_smoke(p, R, f)
	for i = 1, 5 do
		local bx = 5 + R() * (S - 10)
		local life = (f / 30 + R() * 0.9) % 1
		local y = S - 5 - life * (S - 12)
		local r = 2.5 + life * 9
		stx.glow(p, bx, y, r, math.floor(165 * (1 - life) + 30))
	end
end

----------------------------------------------------------------
-- plasma: pulsing ring + orbiting blobs + ground haze
----------------------------------------------------------------
local function draw_plasma(p, R, f)
	local t = f / 30
	stx.solid(p, 0, S - 6, S, 6, "#FFFFFF", 120)
	local cyc = t % 1
	local ry = S - 4 - cyc * (S - 8)
	local rr = 3 + 9 * (1 - cyc)
	stx.ring(p, S / 2, ry, rr, 170)
	for i = 1, 3 do
		local ang = t * math.pi * 2 + i * 2.1
		local ox = S / 2 + math.cos(ang) * (7 + i * 2)
		local oy = S - 8 - ((t + i * 0.33) % 1) * (S - 14)
		stx.glow(p, ox, oy, 4, 220)
	end
	local flash = (math.sin(t * math.pi * 6) + 1) / 2
	stx.glow(p, S / 2, S - 4, 4 + flash * 4, math.floor(120 + 100 * flash))
end

----------------------------------------------------------------
-- water: banded surface + sparkle crests
----------------------------------------------------------------
local function draw_water(p, R, f)
	stx.solid(p, 0, 0, S, S, "#FFFFFF", 170)
	for band = 0, 2 do
		local yb = 8 + band * 9
		local ph = f / 30 * math.pi * 2 + band * 1.3
		for seg = 0, 2 do
			local x0 = seg * 11
			local y = yb + math.floor(math.sin(ph + (x0 + 5) * 0.45) * 2)
			stx.solid(p, x0, y, 11, 3, "#FFFFFF", band == 1 and 150 or 110)
		end
		local sx = (f * 3 + band * 9) % S
		stx.solid(p, sx, yb - 2, 1, 1, "#FFFFFF", 200)
	end
end

----------------------------------------------------------------
-- bubbles: rising rings + highlight dot
----------------------------------------------------------------
local function draw_bubbles(p, R, f, cyan)
	for i = 1, 5 do
		local bx = 3 + R() * (S - 6)
		local speed = 0.5 + R()
		local life = (f / 30 * speed + R()) % 1
		local by = S - 3 - life * (S - 6)
		local r = 2 + R() * 3
		stx.ring(p, bx, by, r, math.floor(90 + 120 * life))
		stx.glow(p, bx - r / 2, by - r / 2, 3, 200)
	end
end

----------------------------------------------------------------
-- ice: pulsing crystal (dot spokes + ring + core)
----------------------------------------------------------------
local function draw_ice(p, R, f)
	local t = f / 30
	stx.solid(p, 0, 0, S, S, "#FFFFFF", 150)
	local pulse = 6 + math.floor(math.sin(t * math.pi * 2) * 2 + 2)
	for spoke = 0, 5 do
		local ang = spoke * math.pi / 3 + t * math.pi / 12
		for _, d in ipairs({ 4, 8, 12 }) do
			if d <= pulse + 4 then
				stx.glow(p, S / 2 + math.cos(ang) * d, S / 2 + math.sin(ang) * d, 4, 190)
			end
		end
	end
	stx.ring(p, S / 2, S / 2, pulse - 2, 160)
	stx.glow(p, S / 2, S / 2, 5, 220)
	for i = 1, 3 do
		stx.glow(p, 3 + R() * (S - 6), 3 + R() * (S - 6), 3, 90 + math.floor(100 * R()))
	end
end

----------------------------------------------------------------
-- sparks: radial burst dots + core (loops wrap mid-flight)
----------------------------------------------------------------
local function draw_sparks(p, R, f, frames)
	local t = f / frames
	for i = 1, 9 do
		local ang = R() * math.pi * 2
		local dist = (0.15 + 0.85 * R()) * (S / 2 - 2) * math.sqrt(t)
		local x = S / 2 + math.cos(ang) * dist
		local y = S / 2 + math.sin(ang) * dist - t * 3
		stx.glow(p, x, y, 3, math.floor(230 * (1 - t) + 25))
	end
	stx.glow(p, S / 2, S / 2, 3 * (1 - t) + 2, math.floor(255 * (1 - t)))
	if t > 0.6 then
		-- faint pre-echo of the next burst so loops read as continuous
		stx.glow(p, S / 2, S / 2, 4, math.floor(80 * (t - 0.6) * 2.5))
	end
end

----------------------------------------------------------------
-- snowflake: rotating 6-spoke dot crystal
----------------------------------------------------------------
local function draw_snowflake(p, R, f)
	local t = f / 30
	stx.solid(p, 0, 0, S, S, "#FFFFFF", 200)
	local rot = t * math.pi * 2
	for spoke = 0, 5 do
		local ang = spoke * math.pi / 3 + rot
		for _, d in ipairs({ 5, 9 }) do
			stx.glow(p, S / 2 + math.cos(ang) * d, S / 2 + math.sin(ang) * d,
				d > 5 and 4 or 3, 220)
		end
		local bx = S / 2 + math.cos(ang) * 7
		local by = S / 2 + math.sin(ang) * 7
		stx.glow(p, bx + math.cos(ang + 0.9) * 3, by + math.sin(ang + 0.9) * 3, 3, 190)
		stx.glow(p, bx + math.cos(ang - 0.9) * 3, by + math.sin(ang - 0.9) * 3, 3, 190)
	end
	stx.glow(p, S / 2, S / 2, 5, 230)
end

----------------------------------------------------------------
-- registry (tints sampled from the retired stock sheets)
----------------------------------------------------------------
return {
	sheet("tech_fire_30frames.png", 30, 101, draw_fire, "#E0641E"),
	sheet("forest_fire_30f.png", 30, 102, draw_fire, "#B23814"),
	sheet("cave_fire_30f.png", 30, 103, draw_fire, "#D22014"),
	sheet("tech_smoke_30frames.png", 30, 201, draw_smoke, "#C846C8", 210),
	sheet("forest_smoke_30f.png", 30, 202, draw_smoke, "#962882", 200),
	sheet("cave_smoke_30f.png", 30, 203, draw_smoke, "#644070", 200),
	sheet("tech_plasma_30frames.png", 30, 301, draw_plasma, "#50E050"),
	sheet("cave_plasma_30f.png", 30, 302, draw_plasma, "#40C840"),
	sheet("forest_plasma_8f.png", 8, 303, draw_plasma, "#58D828"),
	sheet("tech_water_30frames.png", 30, 401, draw_water, "#5096F0"),
	sheet("forest_water_30f.png", 30, 402, draw_water, "#3C78C8"),
	sheet("cave_water_30f.png", 30, 403, draw_water, "#285AA0"),
	sheet("tech_bubbles_30frames.png", 30, 501, draw_bubbles, "#28E0E8"),
	sheet("cave_bubbles_30f.png", 30, 502, draw_bubbles, "#187878"),
	sheet("tech_ice_30frames.png", 30, 601, draw_ice, "#28C8E8"),
	sheet("tech_sparks_30frames.png", 30, 701, function(p, R, f) draw_sparks(p, R, f, 30) end, "#F0D828"),
	sheet("tech_sparks_15frames_loop.png", 15, 702, function(p, R, f) draw_sparks(p, R, f, 15) end, "#F0D828"),
	sheet("tech_sparks_50frames_loop.png", 50, 703, function(p, R, f) draw_sparks(p, R, f, 50) end, "#F0D828"),
	sheet("spinning_snowflake_30f.png", 30, 801, draw_snowflake, "#88D0E8"),
}
