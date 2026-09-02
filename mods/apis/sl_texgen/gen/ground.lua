-- ================================================================
-- sl_texgen/gen/ground.lua — sl_blocks/ground textures
--
-- sus_nodes TV-static (grayscale + rainbow bases), soft neon
-- squares / x / rhombus glyphs.  All client-side [combine programs
-- over the shared stx_* bases.
-- ================================================================
local stx = sl_texgen.stx
local G = 64

local function noise(p, R, rgb)
	stx.noise(p, 0, 0, G, G, 255, rgb)
end

local function draw_square(p, R)
	stx.solid(p, 2, 2, G - 4, G - 4, "#FFFFFF", 26)
	-- soft rim: two nested bright frames
	stx.frame(p, 2, 2, G - 4, G - 4, "#FFFFFF", 235)
	stx.frame(p, 3, 3, G - 6, G - 6, "#FFFFFF", 120)
end

local function draw_square_opaque(p, R)
	-- dark plate under the same glowing grid
	stx.solid(p, 0, 0, G, G, "#08090C", 255)
	stx.solid(p, 2, 2, G - 4, G - 4, "#FFFFFF", 20)
	stx.frame(p, 2, 2, G - 4, G - 4, "#FFFFFF", 235)
	stx.frame(p, 3, 3, G - 6, G - 6, "#FFFFFF", 120)
end

return {
	{ name = "sus_nodes_white_noise_noanim_4n.png", w = G, h = G, seed = 11, draw = function(p, R) noise(p, R, false) end },
	{ name = "sus_nodes_rainbow_noise_noanim_4n.png", w = G, h = G, seed = 12, draw = function(p, R) noise(p, R, true) end },
	{ name = "sus_nodes_white_noise_anim_4n.png", w = G, h = G, frames = 4, vertical = true, seed = 11,
		draw = function(p, R) noise(p, R, false) end },
	{ name = "sus_nodes_rainbow_noise_anim_4n.png", w = G, h = G, frames = 4, vertical = true, seed = 12,
		draw = function(p, R) noise(p, R, true) end },
	{ name = "square_neon.png", w = G, h = G, seed = 0, draw = draw_square },
	{ name = "square_neon_opaque.png", w = G, h = G, seed = 0, draw = draw_square_opaque },
	{ name = "x_neon.png", w = G, h = G, seed = 0, draw = function(p) stx.xglyph(p, 0, 0, G, 255) end },
	{ name = "x2_neon.png", w = G, h = G, seed = 0, draw = function(p) stx.xglyph(p, 0, 0, G, 190) end },
	{ name = "rhombus_neon.png", w = G, h = G, seed = 0, draw = function(p) stx.rhombus(p, 0, 0, G, 255) end },
}
