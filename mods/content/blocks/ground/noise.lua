local S = minetest.get_translator("sus_nodes")

local animate_noise = minetest.settings:get_bool("sus_animate_noise", true)

local ANIM_LENGTH = 1.5

local WHITE_NOISE_TILES, RAINBOW_NOISE_TILES
if animate_noise then
	WHITE_NOISE_TILES = { { name = "sus_nodes_white_noise_anim_4n.png", align_style = "world", scale = 4, animation = { type = "vertical_frames", aspect_w = 64, aspect_h = 64, length = ANIM_LENGTH } } }
	RAINBOW_NOISE_TILES = { { name = "sus_nodes_rainbow_noise_anim_4n.png", align_style = "world", scale = 4, animation = { type = "vertical_frames", aspect_w = 64, aspect_h = 64, length = ANIM_LENGTH } } }
else
	WHITE_NOISE_TILES = { { name = "sus_nodes_white_noise_noanim_4n.png", align_style = "world", scale = 4 } }
	RAINBOW_NOISE_TILES = { { name = "sus_nodes_rainbow_noise_noanim_4n.png", align_style = "world", scale = 4 } }
end

-- Glowing, passes light but not sunlight
minetest.register_node("sus_nodes:white_noise", {
	description = S("White Noise"),
	tiles = WHITE_NOISE_TILES,
	groups = { noise = 1, dig_creative = 3 },
	light_source = 7,
	paramtype = "light",
	sounds = sus_sounds.node_sound_defaults(),
})

-- White noise that dies after a few seconds
minetest.register_node("sus_nodes:white_noise_temp", {
	description = S("White Noise (temporary)"),
	tiles = WHITE_NOISE_TILES,
	groups = { noise = 1, dig_creative = 3 },
	light_source = 7,
	paramtype = "light",
	sounds = sus_sounds.node_sound_defaults(),
	on_construct = function(pos)
		local timer = minetest.get_node_timer(pos)
		timer:start(math.random(5,8))
	end,
	on_timer = function(pos)
		minetest.remove_node(pos)
	end,
})

-- Glowing, passes light and sunlight (good for ceiling decoration)
minetest.register_node("sus_nodes:white_noise_ceiling", {
	description = S("White Noise (ceiling)"),
	tiles = WHITE_NOISE_TILES,
	groups = { noise = 1, dig_creative = 3 },
	light_source = 7,
	sunlight_propagates = true,
	paramtype = "light",
	sounds = sus_sounds.node_sound_defaults(),
})

-- Doesn't glow and stops light
minetest.register_node("sus_nodes:white_noise_nonglow", {
	description = S("White Noise (non-glowing)"),
	tiles = WHITE_NOISE_TILES,
	groups = { noise = 1, dig_creative = 3 },
	sounds = sus_sounds.node_sound_defaults(),
})

-- Can be moved through; doesn't glow. Good for hiding something
minetest.register_node("sus_nodes:white_noise_movethrough", {
	description = S("White Noise (movethrough)"),
	tiles = WHITE_NOISE_TILES,
	walkable = false,
	groups = { noise = 1, dig_creative = 3 },
	sounds = sus_sounds.node_sound_defaults(),
	post_effect_color = { a = 255, r=127, g=127, b=127 },
})

-- Same as white noise, but slippery and colorful
minetest.register_node("sus_nodes:rainbow_noise", {
	description = S("Rainbow Noise"),
	tiles = RAINBOW_NOISE_TILES,
	groups = { noise = 1, slippery = 6, dig_creative = 3 },
	paramtype = "light",
	light_source = 7,
	sounds = sus_sounds.node_sound_defaults(),
})

