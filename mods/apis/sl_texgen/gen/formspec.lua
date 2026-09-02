-- ================================================================
-- sl_texgen/gen/formspec.lua — sl_formspec skin textures
--
-- Ports the tz_formspec_* skin.  Odd but true to the stock: "button"
-- is a fully transparent 24x24 (compiled as an empty [combine),
-- "hovered" is a dark plate with light corner ticks, "pressed" is a
-- 1x1 white pixel, "bg" is a near-black plate with corner ticks.
-- ================================================================
local stx = sl_texgen.stx

return {
	{ name = "tz_formspec_bg.png", w = 24, h = 24, seed = 0,
		draw = function(p)
			stx.solid(p, 0, 0, 24, 24, "#040408", 255)
			stx.frame(p, 0, 0, 24, 24, "#1E222C", 255)
			stx.solid(p, 0, 0, 2, 2, "#F0F0F0", 192)
			stx.solid(p, 22, 0, 2, 2, "#F0F0F0", 192)
			stx.solid(p, 0, 22, 2, 2, "#F0F0F0", 192)
			stx.solid(p, 22, 22, 2, 2, "#F0F0F0", 192)
		end },
	{ name = "tz_formspec_button.png", w = 24, h = 24, seed = 0,
		draw = function(p) end }, -- stock is fully transparent
	{ name = "tz_formspec_button_hovered.png", w = 24, h = 24, seed = 0,
		draw = function(p)
			stx.solid(p, 0, 0, 24, 24, "#303030", 192)
			stx.hline(p, 0, 0, 3, "#F0F0F0", 192)
			stx.hline(p, 21, 23, 3, "#F0F0F0", 192)
			stx.vline(p, 0, 21, 3, "#F0F0F0", 192)
			stx.vline(p, 23, 0, 3, "#F0F0F0", 192)
		end },
	{ name = "tz_formspec_button_pressed.png", w = 1, h = 1, seed = 0,
		draw = function(p) stx.solid(p, 0, 0, 1, 1, "#FFFFFF", 255) end },
}
