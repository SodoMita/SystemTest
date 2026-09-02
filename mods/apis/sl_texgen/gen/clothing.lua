-- ================================================================
-- sl_texgen/gen/clothing.lua — sl_clothing inventory icons
--
-- character_tool_* clothing icons: python-generator shapes (hood,
-- cap, torso, backpack, glove, leg, boot) redrawn as client-side
-- [combine programs over plate + shape rects/glows + font label.
-- ================================================================
local stx = sl_texgen.stx
local S = 64

local PLATE = "#2D3C55"
local FILL = "#374B64"
local FILL2 = "#4B372D"
local LIGHT = "#E6F5FF"

local function label(p, s)
	stx.label(p, 4, S - 9, s, "#F5FFFF", 215, 1)
end

local function shape_hood(p)
	stx.glow(p, 32, 28, 32, 255, FILL)
	stx.ring(p, 32, 28, 30, 255, LIGHT)
	stx.solid(p, 18, 28, 28, 22, FILL, 255)
	stx.frame(p, 18, 28, 28, 22, LIGHT, 255)
	stx.solid(p, 26, 30, 12, 8, "#192838", 255)
end

local function shape_cap(p)
	stx.glow(p, 31, 26, 28, 255, "#50325A")
	stx.solid(p, 17, 26, 28, 12, "#50325A", 255)
	stx.frame(p, 17, 26, 28, 12, LIGHT, 255)
	stx.solid(p, 38, 28, 18, 4, "#64466E", 255)
	stx.solid(p, 28, 14, 6, 6, LIGHT, 255)
end

local function shape_torso(p)
	stx.solid(p, 20, 12, 24, 12, FILL, 255)
	stx.solid(p, 14, 22, 36, 26, FILL, 255)
	stx.solid(p, 24, 34, 16, 20, FILL, 255)
	stx.frame(p, 14, 22, 36, 26, LIGHT, 255)
	stx.frame(p, 20, 12, 24, 12, LIGHT, 255)
	stx.vline(p, 32, 14, 38, LIGHT, 255)
end

local function shape_backpack(p)
	stx.solid(p, 18, 10, 28, 45, "#464F41", 255)
	stx.frame(p, 18, 10, 28, 45, LIGHT, 255, 2)
	stx.frame(p, 22, 18, 20, 14, "#E6F5FF", 160)
	stx.solid(p, 26, 4, 1, 6, LIGHT, 255)
	stx.solid(p, 38, 4, 1, 6, LIGHT, 255)
end

local function shape_glove(p)
	stx.solid(p, 20, 27, 28, 26, FILL2, 255)
	for _, x in ipairs({ 22, 28, 34, 40 }) do
		stx.solid(p, x, 12, 8, 20, FILL2, 255)
		stx.frame(p, x, 12, 8, 20, "#E6F5FF", 150)
	end
	stx.frame(p, 20, 27, 28, 26, LIGHT, 255)
end

local function shape_leg(p)
	stx.solid(p, 18, 10, 12, 44, "#2D4155", 255)
	stx.solid(p, 34, 10, 12, 44, "#2D4155", 255)
	stx.frame(p, 18, 10, 12, 44, LIGHT, 255)
	stx.frame(p, 34, 10, 12, 44, LIGHT, 255)
end

local function shape_boot(p)
	stx.solid(p, 23, 14, 15, 31, "#2D2823", 255)
	stx.solid(p, 18, 41, 33, 13, "#2D2823", 255)
	stx.frame(p, 23, 14, 15, 31, LIGHT, 255)
	stx.frame(p, 18, 41, 33, 13, LIGHT, 255)
end

local SPECS = {
	{ "character_tool_head_01.png", "hood", shape_hood },
	{ "character_tool_head_02.png", "cap", shape_cap },
	{ "character_tool_body_01.png", "jacket", shape_torso },
	{ "character_tool_body_02.png", "coat", shape_torso },
	{ "character_tool_back_01.png", "pack", shape_backpack },
	{ "character_tool_hand_01.png", "glove l", shape_glove },
	{ "character_tool_hand_02.png", "glove r", shape_glove },
	{ "character_tool_legs_01.png", "pants l", shape_leg },
	{ "character_tool_legs_02.png", "pants r", shape_leg },
	{ "character_tool_feet_01.png", "boot l", shape_boot },
	{ "character_tool_feet_02.png", "boot r", shape_boot },
}

local defs = {}
for _, spec in ipairs(SPECS) do
	defs[#defs + 1] = {
		name = spec[1], w = S, h = S, seed = 0,
		draw = function(p)
			stx.solid(p, 3, 3, S - 6, S - 6, PLATE, 120)
			stx.frame(p, 3, 3, S - 6, S - 6, "#00DCFF", 160)
			spec[3](p)
			label(p, spec[2])
		end,
	}
end
return defs
