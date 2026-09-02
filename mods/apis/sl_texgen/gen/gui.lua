-- ================================================================
-- sl_texgen/gen/modebase.lua — sl_modebase placeholder item icons
--
-- Ports the sl_* prototype item icons: dark rounded plate, colored
-- box outline/fill, and the item label in the micro font (exactly
-- what generate_content_assets.py produced as stock files).
-- sl_warning_sign.png and sl_objective_core_icon.png are AI-drawn
-- art and stay as real files — this generator claims only the
-- generated placeholders.
-- ================================================================
local C = sl_texgen.canvas

local S = 64

-- gui_category_* icons (originally written by generate_content_assets.py)

local function draw_icon(label, color)
	return function(c)
		C.round_rect(c, 0, 0, S, S, 6, { 20, 22, 26, 255 })
		C.frame(c, 2, 2, S - 4, S - 4, { color[1], color[2], color[3], 230 })
		-- thicken the outline
		C.frame(c, 3, 3, S - 6, S - 6, { color[1], color[2], color[3], 160 })
		C.rect(c, 8, 8, S - 16, S - 16, { color[1], color[2], color[3], 55 })
		-- label, up to 3 lines of ~7 chars, like the python layout
		C.text(c, 4, S - 8, label, { 240, 245, 255, 255 })
	end
end


local CATS = {
	{ "gui_category_salvage.png", "salvage", { 120, 120, 130 } },
	{ "gui_category_equipment.png", "equip", { 180, 180, 190 } },
	{ "gui_category_tactical.png", "tactical", { 200, 160, 0 } },
	{ "gui_category_objective.png", "objective", { 0, 255, 100 } },
	{ "gui_category_basic.png", "basic", { 45, 60, 85 } },
	{ "gui_category_advanced.png", "advanced", { 45, 60, 85 } },
	{ "gui_category_glass.png", "glass", { 45, 60, 85 } },
	{ "gui_category_information.png", "information", { 45, 60, 85 } },
	{ "gui_category_urban.png", "urban", { 45, 60, 85 } },
}

local defs = {}
for _, spec in ipairs(CATS) do
	defs[#defs + 1] = {
		name = spec[1], w = S, h = S, seed = 0,
		draw = draw_icon(spec[2], spec[3]),
	}
end
return defs
