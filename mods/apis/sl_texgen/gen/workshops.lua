-- ================================================================
-- sl_texgen/gen/workshops.lua — workshop node textures
--
-- Compiles the 50 placeholder node facades (palette base + speckle
-- noise + accent grid, styled overlays for fronts / caution tape /
-- hazard signs / windows / pipes / vents, plus the item label from
-- the shared font atlas) to client-side [combine programs.
-- ================================================================
local stx = sl_texgen.stx
local S = 64

local PALETTES = {
	wood   = { "#54371F",  "#DCA050" },
	metal  = { "#2E3237",  "#96B4D2" },
	tech   = { "#142028",  "#00D8FF" },
	glass  = { "#1E3741",  "#96EBFF" },
	dark   = { "#12121A",  "#6E7896" },
	hazard = { "#1E1E19",  "#FFD700" },
}

local ACC_A = 95
local ACC_B = 70

local function facade(p, base, accent)
	stx.solid(p, 0, 0, S, S, base, 255)
	stx.noise(p, 0, 0, S, S, 46)
	for x = 0, S - 1, 16 do
		stx.vline(p, x, 0, S, accent, ACC_A)
	end
	for y = 0, S - 1, 16 do
		stx.hline(p, 0, y, S, accent, ACC_B)
	end
	stx.frame(p, 0, 0, S, S, accent, 210)
end

local function front_slots(p, accent)
	for i = 0, 2 do
		local y = 10 + i * 15
		stx.solid(p, 8, y, 48, 8, "#000000", 55)
		stx.hline(p, 8, y, 48, accent, 180)
	end
end

local function caution(p)
	-- alternating hazard bars
	for i = 0, 7 do
		local col = (i % 2 == 0) and "#FFCD00" or "#0A0A0A"
		stx.solid(p, 0, i * 8, S, 8, col, 200)
	end
	stx.frame(p, 0, 0, S, S, "#0A0A0A", 255)
end

local function glyph_hazard(p)
	local Y = "#FFD700"
	stx.solid(p, 24, 30, 16, 6, Y, 255)
	stx.solid(p, 20, 36, 24, 6, Y, 255)
	stx.solid(p, 16, 42, 32, 6, Y, 255)
	stx.solid(p, 30, 20, 4, 2, Y, 255)
	stx.solid(p, 30, 23, 4, 6, Y, 255)
	stx.solid(p, 30, 30, 4, 2, Y, 255)
end

local function glyph_radiation(p)
	local Y = "#FFD700"
	stx.ring(p, 32, 32, 34, 220, Y)
	stx.glow(p, 32, 32, 10, 255, Y)
	stx.glow(p, 32, 20, 9, 220, Y)
	stx.glow(p, 22, 39, 9, 220, Y)
	stx.glow(p, 42, 39, 9, 220, Y)
end

local function glyph_bio(p)
	local G = "#B4FF5A"
	stx.ring(p, 32, 20, 14, 220, G)
	stx.ring(p, 22, 39, 14, 220, G)
	stx.ring(p, 42, 39, 14, 220, G)
	stx.glow(p, 32, 32, 9, 220, G)
end

local function window(p, broken)
	stx.solid(p, 10, 10, 44, 44, "#78DCFF", 80)
	stx.frame(p, 10, 10, 44, 44, "#BEF5FF", 230, 2)
	if broken then
		stx.solid(p, 12, 14, 2, 12, "#E6FFFF", 250)
		stx.solid(p, 22, 24, 2, 10, "#E6FFFF", 250)
		stx.solid(p, 38, 20, 8, 2, "#E6FFFF", 250)
	end
end

local function pipe(p, end_cap)
	stx.solid(p, 20, 0, 24, S, "#46505F", 255)
	for y = 0, S - 1, 8 do
		stx.hline(p, 20, y, 24, "#282E37", 255)
	end
	stx.vline(p, 20, 0, S, "#8296AF", 255)
	stx.vline(p, 43, 0, S, "#1E2228", 255)
	if end_cap then
		stx.solid(p, 14, 0, 36, 8, "#5A6476", 255)
		stx.frame(p, 14, 0, 36, 8, "#8CA0B9", 255)
	end
end

local function vent_grate(p)
	stx.solid(p, 0, 0, S, S, "#2E3237", 255)
	stx.noise(p, 0, 0, S, S, 40)
	for row = 0, 5 do
		stx.solid(p, 10, 8 + row * 9, 44, 5, "#0C0E12", 255)
		stx.hline(p, 10, 8 + row * 9, 44, "#788CA5", 255)
	end
	stx.frame(p, 0, 0, S, S, "#96B4D2", 210)
end

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

local OVERLAYS = {
	front = front_slots,
	caution = caution,
	hazard = glyph_hazard,
	radiation = glyph_radiation,
	bio = glyph_bio,
	window = function(p) window(p, false) end,
	window_broken = function(p) window(p, true) end,
	pipe = function(p) pipe(p, false) end,
	pipe_end = function(p) pipe(p, true) end,
	vent = vent_grate,
}

local defs = {}
for i, spec in ipairs(SPECS) do
	local name, palname, overlay = spec[1], spec[2], spec[3]
	local label = (name:gsub("_", " "):gsub("%.png$", ""))
	local base, accent = PALETTES[palname][1], PALETTES[palname][2]
	defs[#defs + 1] = {
		name = name, w = S, h = S, seed = 500 + i,
		draw = function(p, R)
			facade(p, base, accent)
			if overlay then OVERLAYS[overlay](p) end
			if label:len() > 12 then label = label:sub(1, 12) end
			stx.label(p, 3, S - 9, label, "#EBFAFF", 215, 1)
		end,
	}
end
return defs
