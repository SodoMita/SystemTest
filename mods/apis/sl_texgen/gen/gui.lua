-- ================================================================
-- sl_texgen/gen/gui.lua — sl_gui crafting category icons
--
-- gui_category_* labelled icons (originally written by
-- generate_content_assets.py), now client-side [combine programs.
-- The 16x16 pixel-art tabs/slots/buttons are hand art and stay as
-- texture-packable files.
-- ================================================================
local stx = sl_texgen.stx
local S = 64

local CATS = {
	{ "gui_category_salvage.png", "salvage", "#787882" },
	{ "gui_category_equipment.png", "equip", "#B4B4BE" },
	{ "gui_category_tactical.png", "tactical", "#C8A000" },
	{ "gui_category_objective.png", "objective", "#00FF64" },
	{ "gui_category_basic.png", "basic", "#2D3C55" },
	{ "gui_category_advanced.png", "advanced", "#2D3C55" },
	{ "gui_category_glass.png", "glass", "#2D3C55" },
	{ "gui_category_information.png", "information", "#2D3C55" },
	{ "gui_category_urban.png", "urban", "#2D3C55" },
}

local defs = {}
for _, spec in ipairs(CATS) do
	defs[#defs + 1] = {
		name = spec[1], w = S, h = S, seed = 0,
		draw = function(p)
			stx.solid(p, 0, 0, S, S, "#14161A", 255)
			stx.frame(p, 2, 2, S - 4, S - 4, spec[3], 230, 2)
			stx.solid(p, 8, 8, S - 16, S - 16, spec[3], 55)
			stx.glow(p, S / 2, S - 12, 20, 60, spec[3])
			stx.label(p, 4, S - 9, spec[2], "#F0F5FF", 255, 1)
		end,
	}
end
return defs
