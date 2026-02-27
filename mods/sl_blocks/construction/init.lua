minetest.register_node("construction:fire", {
    description = "Fireplacelike thing",
    drawtype = "plantlike",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_fire_30frames.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},

	sunlight_propagates = true,
	walkable = false,
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})
minetest.register_node("construction:firenode", {
    description = "Firenode",
    -- The critical part is the tiles table
    tiles = {{
        name = "forest_fire_30f.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},

	sunlight_propagates = true,
	walkable = false,
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:smoke", {
    description = "Smoky circles thing",
    drawtype = "plantlike",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_smoke_30frames.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},

	sunlight_propagates = true,
	walkable = false,
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})
minetest.register_node("construction:smoke2", {
    description = "Smoky circles thing",

	use_texture_alpha = "blend",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_smoke_30frames.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},

	sunlight_propagates = true,
	walkable = false,
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})
minetest.register_node("construction:smoke3", {
    description = "Smoky circles thing",

	use_texture_alpha = "blend",

    -- The critical part is the tiles table
    tiles = {{
        name = "forest_smoke_30f.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},

	sunlight_propagates = true,
	walkable = false,
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:bubbles", {
    description = "Smoky circles thing",

	use_texture_alpha = "blend",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_bubbles_30frames.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},

	sunlight_propagates = true,
	walkable = false,
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})
minetest.register_node("construction:bubbles2", {
    description = "Smoky circles thing",

	use_texture_alpha = "blend",

    -- The critical part is the tiles table
    tiles = {{
        name = "cave_bubbles_30f.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},

	sunlight_propagates = true,
	walkable = false,
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:sparks", {
    description = "30 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_sparks_30frames.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:sparks2", {
    description = "50 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_sparks_50frames_loop.png",
        animation = {
            type = "sheet_2d",

            frames_w = 50,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:sparks3", {
    description = "50 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_sparks_15frames_loop.png",
        animation = {
            type = "sheet_2d",

            frames_w = 15,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:water", {
    description = "Waterlike waves",

    -- The critical part is the tiles table
    tiles = {{
        name = "forest_water_30f.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:snowflake", {
    description = "30 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_ice_30frames.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:snowflake2", {
    description = "30 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "spinning_snowflake_30f.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:plasma1", {
    description = "30 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "forest_plasma_8f.png",
        animation = {
            type = "sheet_2d",

            frames_w = 8,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:plasma", {
    description = "30 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "cave_plasma_30f.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.013,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("construction:plasma2", {
    description = "30 Frame Animated Block",

    -- The critical part is the tiles table
    tiles = {{
        name = "tech_plasma_30frames.png",
        animation = {
            type = "sheet_2d",

            frames_w = 30,
            frames_h = 1,

            frame_length = 0.05,  -- Time in seconds for the whole loop to play once
        }
    }},
    -- Standard node properties
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    is_ground_content = false,
    sounds = default.node_sound_stone_defaults(),
})
