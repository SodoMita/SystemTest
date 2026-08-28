-- ============================================================
-- Sky / cloud nodes.
--
-- Sky textures belong in the sl_blocks modpack, not in the
-- upstream `default` mod. This mod is also the home for any
-- future sky-layer nodes (void, high-altitude fog, etc.).
--
-- Old worlds that stored `default:cloud` are remapped here via
-- aliases so they keep loading after the node moved.
-- ============================================================

minetest.register_node("sky:cloud", {
	description = "Cloud",
	tiles = {"cloud.png"},
	use_texture_alpha = "clip",
	is_ground_content = false,
	sounds = default.node_sound_defaults(),
	groups = {not_in_creative_inventory = 1, choppy = 3},
})

minetest.register_alias("default:cloud", "sky:cloud")
minetest.register_alias("cloud", "sky:cloud")
