-- ================================================================
-- sl_texgen/gen/workshops.lua — workshop node textures
--
-- Ports the 50 placeholder node textures: palette facade (wood /
-- metal / tech / glass / dark) with a grid accent, styled overlays
-- (front slots/panels, caution diagonals, hazard glyphs, windows)
-- and the item name as a micro-text label — the same recipe as the
-- python generator that made the stock files, now in engine Lua.
-- ================================================================
local C = sl_texgen.canvas

local S = 64

local PALETTES = {
	wood   = { base = { 84, 55, 33 },   accent = { 220, 160, 80 } },
	metal  = { base = { 46, 50, 55 },   accent = { 150, 180, 210 } },
	tech   = { base = { 20, 32, 45 },   accent = { 0, 220, 255 } },
	glass  = { base = { 30, 55, 65 },   accent = { 150, 235, 255 } },
	dark   = { base = { 18, 18, 25 },   accent = { 110, 120, 150 } },
	hazard = { base = { 30, 30, 25 },   accent = { 255, 215, 0 } },
}

local function label_of(name)
	return (name:gsub("_", " "))
end

local function facade(c, R, pal)
	C.speckle(c, R, pal.base, 0.12)
	-- accent grid every 16px
	for x = 0, S - 1, 16 do
		C.line(c, x, 0, x, S - 1, { pal.accent[1], pal.accent[2], pal.accent[3], 95 })
	end
	for y = 0, S - 1, 16 do
		C.line(c, 0, y, S - 1, y, { pal.accent[1], pal.accent[2], pal.accent[3], 70 })
	end
	C.frame(c, 0, 0, S, S, { pal.accent[1], pal.accent[2], pal.accent[3], 210 })
end

local function front_slots(c, pal)
	for i = 0, 2 do
		C.frame(c, 8, 10 + i * 15, 48, 8, { pal.accent[1], pal.accent[2], pal.accent[3], 180 })
		C.rect(c, 9, 11 + i * 15, 46, 6, { 0, 0, 0, 55 })
	end
end

local function caution(c)
	local yellow = { 255, 205, 0, 190 }
	C.stripes_diag(c, 1, yellow, { 10, 10, 10, 255 }, 16)
	C.frame(c, 0, 0, S, S, { 10, 10, 10, 255 })
	-- re-draw frame thick
	C.frame(c, 1, 1, S - 2, S - 2, { 10, 10, 10, 255 })
end

local function glyph_hazard(c)
	local y = { 255, 215, 0, 255 }
	-- triangle outline
	for i = 0, 24 do
		local wdt = math.floor(i * 0.9)
		C.line(c, 32 - wdt, 54 - i, 32 + wdt, 54 - i, (i < 2 or i > 22 or math.abs(i - 12) > 10) and y or { 0, 0, 0, 0 })
	end
	C.line(c, 31, 22, 33, 40, y)
	C.rect(c, 31, 44, 3, 3, y)
end

local function glyph_radiation(c)
	local y = { 255, 215, 0, 190 }
	C.thick_ring(c, 32, 32, 17, 3, y)
	C.disc(c, 32, 32, 5, { 255, 215, 0, 255 })
	for _, ang in ipairs({ 90, 210, 330 }) do
		local a = math.rad(ang)
		local cx, cy = 32 + math.cos(a) * 11, 32 - math.sin(a) * 11
		C.disc(c, cx, cy, 4, y)
	end
end

local function glyph_bio(c)
	local g = { 180, 255, 90, 200 }
	for _, pt in ipairs({ { 32, 20 }, { 22, 39 }, { 42, 39 } }) do
		C.thick_ring(c, pt[1], pt[2], 7, 2, g)
	end
	C.disc(c, 32, 32, 4, g)
end

local function window(c, broken)
	local glasscol = { 120, 220, 255, 80 }
	local framecol = { 190, 245, 255, 230 }
	C.rect(c, 10, 10, 44, 44, glasscol)
	C.frame(c, 10, 10, 44, 44, framecol)
	C.frame(c, 11, 11, 42, 42, framecol)
	if broken then
		C.line(c, 12, 14, 40, 36, { 230, 255, 255, 250 })
		C.line(c, 40, 36, 30, 54, { 230, 255, 255, 250 })
		C.line(c, 52, 20, 35, 37, { 230, 255, 255, 250 })
	end
end

local function pipe(c, end_cap)
	C.rect(c, 20, 0, 24, S, { 70, 80, 95, 255 })
	for y = 0, S - 1, 8 do
		C.line(c, 20, y, 43, y, { 40, 46, 55, 255 })
	end
	C.line(c, 20, 0, 20, S - 1, { 130, 150, 175, 255 })
	C.line(c, 43, 0, 43, S - 1, { 30, 34, 40, 255 })
	if end_cap then
		C.rect(c, 14, 0, 36, 8, { 90, 100, 118, 255 })
		C.frame(c, 14, 0, 36, 8, { 140, 160, 185, 255 })
	end
end

local function vent_grate(c)
	C.speckle(c, C.rng(9), PALETTES.metal.base, 0.1)
	for row = 0, 5 do
		C.rect(c, 10, 8 + row * 9, 44, 5, { 12, 14, 18, 255 })
		C.line(c, 10, 8 + row * 9, 53, 8 + row * 9, { 120, 140, 165, 255 })
	end
	C.frame(c, 0, 0, S, S, { 150, 180, 210, 210 })
end

-- per-texture spec: palette + optional overlay + label
local SPECS = {
	{ "advanced_workbench_top.png", "wood" }, { "advanced_workbench_bottom.png", "wood" },
	{ "advanced_workbench_side.png", "wood" }, { "advanced_workbench_front.png", "wood", "front" },
	{ "precision_anvil_top.png", "metal" }, { "precision_anvil_bottom.png", "metal" },
	{ "precision_anvil_side.png", "metal" },
	{ "assembly_table_top.png", "tech" }, { "assembly_table_bottom.png", "metal" },
	{ "assembly_table_side.png", "metal" },
	{ "tool_rack_top.png", "wood" }, { "tool_rack_side.png", "wood", "front" },
	{ "chemical_station_top.png", "tech" }, { "chemical_station_bottom.png", "metal" },
	{ "chemical_station_side.png", "glass", "front" },
	{ "blueprint_drawer_top.png", "wood" }, { "blueprint_drawer_side.png", "wood" },
	{ "blueprint_drawer_front.png", "wood", "front" },
	{ "metal_locker_top.png", "metal" }, { "metal_locker_side.png", "metal" },
	{ "metal_locker_front.png", "metal", "front" },
	{ "filing_cabinet_top.png", "metal" }, { "filing_cabinet_side.png", "metal" },
	{ "filing_cabinet_front.png", "metal", "front" },
	{ "metal_desk_top.png", "metal" }, { "metal_desk_bottom.png", "metal" },
	{ "metal_desk_side.png", "metal" }, { "metal_desk_front.png", "metal", "front" },
	{ "metal_desk_back.png", "metal" },
	{ "lab_shelf_top.png", "metal" }, { "lab_shelf_bottom.png", "metal" },
	{ "lab_shelf_side.png", "metal", "front" },
	{ "server_rack_top.png", "tech" }, { "server_rack_side.png", "tech" },
	{ "server_rack_front.png", "tech", "front" }, { "server_rack_back.png", "tech" },
	{ "control_panel_side.png", "tech" }, { "control_panel_front.png", "tech", "front" },
	{ "control_panel_back.png", "tech" },
	{ "vent_grate.png", "metal", "vent" },
	{ "pipe_end.png", "metal", "pipe_end" }, { "pipe_side.png", "metal", "pipe" },
	{ "caution_tape.png", "hazard", "caution" },
	{ "warning_sign_back.png", "metal", "front" },
	{ "warning_sign_hazard.png", "hazard", "hazard" },
	{ "warning_sign_radiation.png", "hazard", "radiation" },
	{ "warning_sign_biohazard.png", "hazard", "bio" },
	{ "window_frame.png", "glass", "window" },
	{ "window_glass.png", "glass", "window" },
	{ "window_broken.png", "glass", "window_broken" },
}

local function apply_overlay(c, kind, pal)
	if kind == "front" then
		front_slots(c, pal)
	elseif kind == "caution" then
		caution(c)
	elseif kind == "hazard" then
		glyph_hazard(c)
	elseif kind == "radiation" then
		glyph_radiation(c)
	elseif kind == "bio" then
		glyph_bio(c)
	elseif kind == "window" then
		window(c, false)
	elseif kind == "window_broken" then
		window(c, true)
	elseif kind == "pipe" then
		pipe(c, false)
	elseif kind == "pipe_end" then
		pipe(c, true)
	elseif kind == "vent" then
		vent_grate(c)
	end
end

local defs = {}
for i, spec in ipairs(SPECS) do
	local name, palname, overlay = spec[1], spec[2], spec[3]
	local label = label_of(name:gsub("%.png$", ""))
	defs[#defs + 1] = {
		name = name, w = S, h = S, seed = 500 + i,
		draw = function(c, R)
			local pal = PALETTES[palname]
			facade(c, R, pal)
			if overlay then apply_overlay(c, overlay, pal) end
			-- micro label, as the stock placeholders had
			C.text(c, 3, S - 8, label, { 235, 250, 255, 215 })
		end,
	}
end
return defs
