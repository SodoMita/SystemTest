
core.register_node("ground:square_neon", {
-- 	description = S("Neon square ground"),
	drawtype = "glasslike",
	tiles = { "square_neon.png" }, -- A mostly white/grey texture works best

	-- This color is multiplied with the texture's color.
	-- Format is 0xRRGGBB (Red, Green, Blue in hexadecimal)
-- 	color = 0x0000FF, -- Pure Blue
	use_texture_alpha = "blend",
	light_source = 15,
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { cracky = 3, oddly_breakable_by_hand = 3 },
	sounds = default.node_sound_glass_defaults(),
})

core.register_node("ground:rhombus_neon", {
-- 	description = S("Neon square ground"),
	drawtype = "glasslike",
	tiles = { "rhombus_neon.png" }, -- A mostly white/grey texture works best

	-- This color is multiplied with the texture's color.
	-- Format is 0xRRGGBB (Red, Green, Blue in hexadecimal)
-- 	color = 0x0000FF, -- Pure Blue
-- 	color = 0xFFFFFF, -- Pure White
	use_texture_alpha = "blend",
	light_source = 15,
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { cracky = 3, oddly_breakable_by_hand = 3 },
	sounds = default.node_sound_glass_defaults(),
})

core.register_node("ground:x_neon", {
-- 	description = S("Neon square ground"),
	drawtype = "glasslike",
	tiles = { "x_neon.png" }, -- A mostly white/grey texture works best

	-- This color is multiplied with the texture's color.
	-- Format is 0xRRGGBB (Red, Green, Blue in hexadecimal)
-- 	color = 0x0000FF, -- Pure Blue
-- 	color = 0xFFFFFF, -- Pure White
	use_texture_alpha = "blend",
	light_source = 15,
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { cracky = 3, oddly_breakable_by_hand = 3 },
	sounds = default.node_sound_glass_defaults(),
})

core.register_node("ground:x2_neon", {
-- 	description = S("Neon square ground"),
	drawtype = "glasslike",
	tiles = { "x2_neon.png" }, -- A mostly white/grey texture works best

	-- This color is multiplied with the texture's color.
	-- Format is 0xRRGGBB (Red, Green, Blue in hexadecimal)
-- 	color = 0x0000FF, -- Pure Blue
-- 	color = 0xFFFFFF, -- Pure White
	use_texture_alpha = "blend",
	light_source = 15,
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { cracky = 3, oddly_breakable_by_hand = 3 },
	sounds = default.node_sound_glass_defaults(),
})
