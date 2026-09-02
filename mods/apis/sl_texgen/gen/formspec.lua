-- ================================================================
-- sl_texgen/gen/formspec.lua — sl_formspec skin textures
--
-- Ports the tz_formspec_* skin files.  Odd but true to the stock:
-- "button" is a fully transparent 24x24 (the skin drew buttons
-- through other elements), "hovered" is a dark plate with light
-- corner ticks, "pressed" is a 1x1 white pixel.
-- ================================================================
local C = sl_texgen.canvas

local DARK = { 48, 48, 48, 192 }
local LIGHT = { 240, 240, 240, 192 }

return {
	{ name = "tz_formspec_bg.png", w = 24, h = 24, seed = 0,
		draw = function(c)
			-- near-black plate, faint 1px inner edge and corner ticks
			C.clear(c, { 4, 4, 8, 255 })
			C.frame(c, 0, 0, 24, 24, { 30, 34, 44, 255 })
			C.rect(c, 0, 0, 2, 2, LIGHT)
			C.rect(c, 22, 0, 2, 2, LIGHT)
			C.rect(c, 0, 22, 2, 2, LIGHT)
			C.rect(c, 22, 22, 2, 2, LIGHT)
		end },
	{ name = "tz_formspec_button.png", w = 24, h = 24, seed = 0,
		draw = function(c) end }, -- stock is fully transparent
	{ name = "tz_formspec_button_hovered.png", w = 24, h = 24, seed = 0,
		draw = function(c)
			C.clear(c, DARK)
			C.rect(c, 0, 0, 3, 1, LIGHT)
			C.rect(c, 21, 23, 3, 1, LIGHT)
			C.rect(c, 0, 21, 1, 3, LIGHT)
			C.rect(c, 23, 0, 1, 3, LIGHT)
		end },
	{ name = "tz_formspec_button_pressed.png", w = 1, h = 1, seed = 0,
		draw = function(c) C.clear(c, { 255, 255, 255, 255 }) end },
}
