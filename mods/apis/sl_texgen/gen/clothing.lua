-- ================================================================
-- sl_texgen/gen/clothing.lua — sl_clothing inventory icons
--
-- Ports the character_tool_* clothing icons: the python generator's
-- shapes (hood, cap, torso, backpack, glove, leg, boot) drawn with
-- canvas primitives on the same rounded-plate + label layout.
-- ================================================================
local C = sl_texgen.canvas

local S = 64

local PLATE  = { 45, 60, 85 }
local FILL   = { 55, 75, 100 }
local FILL2  = { 75, 55, 45 }
local LIGHT  = { 230, 245, 255 }

local function label(c, s)
	C.text(c, 4, S - 8, s, { 245, 255, 255, 215 })
end

local function shape_hood(c)
	C.disc(c, 32, 28, 16, FILL)
	C.thick_ring(c, 32, 28, 16, 2, LIGHT)
	C.rect(c, 18, 28, 28, 22, FILL)
	C.frame(c, 18, 28, 28, 22, LIGHT)
	C.rect(c, 26, 30, 12, 8, { 25, 30, 40, 255 }) -- face shadow
end

local function shape_cap(c)
	C.disc(c, 31, 28, 14, { 80, 55, 90 })
	C.rect(c, 17, 26, 28, 12, { 80, 55, 90 })
	C.frame(c, 17, 26, 28, 12, LIGHT)
	C.rect(c, 38, 28, 18, 4, { 100, 70, 110 }) -- brim
	C.rect(c, 28, 14, 6, 6, LIGHT)              -- button
end

local function shape_torso(c)
	C.rect(c, 20, 12, 24, 12, FILL)      -- shoulders
	C.rect(c, 14, 22, 36, 26, FILL)      -- chest
	C.rect(c, 24, 34, 16, 20, FILL)      -- waist
	C.frame(c, 14, 22, 36, 26, LIGHT)
	C.frame(c, 20, 12, 24, 12, LIGHT)
	C.line(c, 32, 14, 32, 52, LIGHT)     -- zip
end

local function shape_backpack(c)
	C.round_rect(c, 18, 10, 28, 45, 7, { 70, 80, 65 })
	C.frame(c, 18, 10, 28, 45, LIGHT)
	C.frame(c, 22, 18, 20, 14, { 230, 245, 255, 160 })
	C.line(c, 26, 10, 26, 6, LIGHT)
	C.line(c, 38, 10, 38, 6, LIGHT)
end

local function shape_glove(c)
	C.round_rect(c, 20, 27, 28, 26, 7, FILL2)
	for _, x in ipairs({ 22, 28, 34, 40 }) do
		C.round_rect(c, x, 12, 8, 20, 3, FILL2)
		C.frame(c, x, 12, 8, 20, { 230, 245, 255, 150 })
	end
	C.frame(c, 20, 27, 28, 26, LIGHT)
end

local function shape_leg(c)
	C.rect(c, 18, 10, 12, 44, { 45, 65, 85 })
	C.rect(c, 34, 10, 12, 44, { 45, 65, 85 })
	C.frame(c, 18, 10, 12, 44, LIGHT)
	C.frame(c, 34, 10, 12, 44, LIGHT)
end

local function shape_boot(c)
	C.rect(c, 23, 14, 15, 31, { 45, 40, 35 })
	C.rect(c, 18, 41, 33, 13, { 45, 40, 35 })
	C.frame(c, 23, 14, 15, 31, LIGHT)
	C.frame(c, 18, 41, 33, 13, LIGHT)
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
for i, spec in ipairs(SPECS) do
	defs[#defs + 1] = {
		name = spec[1], w = S, h = S, seed = 0,
		draw = function(c)
			C.clear(c, { 0, 0, 0, 0 })
			-- transparent-plate style: soft rounded backdrop then shape
			C.round_rect(c, 3, 3, S - 6, S - 6, 8, { PLATE[1], PLATE[2], PLATE[3], 120 })
			C.frame(c, 3, 3, S - 6, S - 6, { 0, 220, 255, 160 })
			spec[3](c)
			label(c, spec[2])
		end,
	}
end
return defs
