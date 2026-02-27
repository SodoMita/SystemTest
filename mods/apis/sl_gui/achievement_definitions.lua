-- Achievement Definitions! 🏆✨
-- Define all the achievements in your game~

-- ===============================
-- Getting Started Category
-- ===============================

register_achievement({
    id = "first_dig",
    name = "First Steps",
    description = "Break your first block",
    icon = "achievement_first_dig.png",
    category = "getting_started",
    max_progress = 1,
    reward_xp = 10,
    graph_x = 0,
    graph_y = 0,
})

register_achievement({
    id = "place_10_blocks",
    name = "Builder's Start",
    description = "Place 10 blocks",
    icon = "achievement_place_10_blocks.png",
    category = "getting_started",
    max_progress = 10,
    reward_xp = 25,
    requires = {"first_dig"},
    graph_x = 1,
    graph_y = 0,
})

register_achievement({
    id = "dig_100_blocks",
    name = "Miner",
    description = "Break 100 blocks",
    icon = "achievement_dig_100_blocks.png",
    category = "getting_started",
    max_progress = 100,
    reward_xp = 50,
    requires = {"first_dig"},
    graph_x = 1,
    graph_y = 1,
})

register_achievement({
    id = "reach_level_5",
    name = "Experienced",
    description = "Reach level 5",
    icon = "achievement_reach_level_5.png",
    category = "getting_started",
    max_progress = 1,
    reward_xp = 100,
    requires = {},  -- No requirements - just reach the level!
    graph_x = 2,
    graph_y = 0,
})

-- ===============================
-- Exploration Category
-- ===============================

register_achievement({
    id = "first_ghost",
    name = "Spooked!",
    description = "Encounter your first ghost in the labyrinth",
    icon = "achievement_first_ghost.png",
    category = "exploration",
    max_progress = 1,
    reward_xp = 25,
    graph_x = 0,
    graph_y = 2.5,
})

register_achievement({
    id = "ghost_hunter",
    name = "Ghost Hunter",
    description = "Trigger 10 ghosts",
    icon = "achievement_ghost_hunter.png",
    category = "exploration",
    max_progress = 10,
    reward_xp = 75,
    requires = {"first_ghost"},
    graph_x = 1,
    graph_y = 2.5,
})

register_achievement({
    id = "ghost_veteran",
    name = "Ghost Veteran",
    description = "Trigger 50 ghosts",
    icon = "achievement_ghost_veteran.png",
    category = "exploration",
    max_progress = 50,
    reward_xp = 200,
    requires = {"ghost_hunter"},
    graph_x = 2,
    graph_y = 2.5,
})

register_achievement({
    id = "visit_floating_island",
    name = "Sky Explorer",
    description = "Visit a floating island",
    icon = "achievement_visit_floating_island.png",
    category = "exploration",
    max_progress = 1,
    reward_xp = 75,
    graph_x = 0,
    graph_y = 2,
})

register_achievement({
    id = "find_city",
    name = "Urban Explorer",
    description = "Discover the ground-level city",
    icon = "achievement_find_city.png",
    category = "exploration",
    max_progress = 1,
    reward_xp = 50,
    graph_x = 0,
    graph_y = 3,
})

register_achievement({
    id = "travel_1000_blocks",
    name = "Wanderer",
    description = "Travel 1000 blocks from spawn",
    icon = "achievement_travel_1000_blocks.png",
    category = "exploration",
    max_progress = 1,
    reward_xp = 100,
    requires = {"find_city"},
    graph_x = 1,
    graph_y = 3,
})

register_achievement({
    id = "visit_10_islands",
    name = "Island Hopper",
    description = "Visit 10 different floating islands",
    icon = "achievement_visit_10_islands.png",
    category = "exploration",
    max_progress = 10,
    reward_xp = 200,
    requires = {"visit_floating_island"},
    graph_x = 1,
    graph_y = 2,
})

-- ===============================
-- Crafting Category
-- ===============================

register_achievement({
    id = "first_craft",
    name = "Craftsman Apprentice",
    description = "Craft your first item",
    icon = "achievement_first_craft.png",
    category = "crafting",
    max_progress = 1,
    reward_xp = 20,
    graph_x = 0,
    graph_y = 4,
})

register_achievement({
    id = "craft_10_items",
    name = "Craftsman",
    description = "Craft 10 items",
    icon = "achievement_craft_10_items.png",
    category = "crafting",
    max_progress = 10,
    reward_xp = 50,
    requires = {"first_craft"},
    graph_x = 1,
    graph_y = 4,
})

register_achievement({
    id = "craft_100_items",
    name = "Master Craftsman",
    description = "Craft 100 items",
    icon = "achievement_craft_100_items.png",
    category = "crafting",
    max_progress = 100,
    reward_xp = 200,
    requires = {"craft_10_items"},
    graph_x = 2,
    graph_y = 4,
})

register_achievement({
    id = "craft_urban_item",
    name = "Urban Designer",
    description = "Craft an urban-category item",
    icon = "achievement_craft_urban_item.png",
    category = "crafting",
    max_progress = 1,
    reward_xp = 75,
    requires = {"first_craft"},
    graph_x = 1,
    graph_y = 5,
})

register_achievement({
    id = "craft_glass",
    name = "Glassmaker",
    description = "Craft glass",
    icon = "achievement_craft_glass.png",
    category = "crafting",
    max_progress = 1,
    reward_xp = 50,
    requires = {"first_craft"},
    graph_x = 0,
    graph_y = 5,
})

-- ===============================
-- Abilities Category
-- ===============================

register_achievement({
    id = "unlock_first_ability",
    name = "Awakening",
    description = "Unlock your first ability",
    icon = "achievement_unlock_first_ability.png",
    category = "abilities",
    max_progress = 1,
    reward_xp = 50,
    graph_x = 0,
    graph_y = 6,
})

register_achievement({
    id = "unlock_5_abilities",
    name = "Power Seeker",
    description = "Unlock 5 abilities",
    icon = "achievement_unlock_5_abilities.png",
    category = "abilities",
    max_progress = 5,
    reward_xp = 150,
    requires = {"unlock_first_ability"},
    graph_x = 1,
    graph_y = 6,
})

register_achievement({
    id = "max_ability",
    name = "Mastery",
    description = "Max out an ability to its highest level",
    icon = "achievement_max_ability.png",
    category = "abilities",
    max_progress = 1,
    reward_xp = 200,
    requires = {"unlock_5_abilities"},
    graph_x = 2,
    graph_y = 6,
})

register_achievement({
    id = "unlock_all_movement",
    name = "Speed Demon",
    description = "Unlock all movement abilities",
    icon = "achievement_unlock_all_movement.png",
    category = "abilities",
    max_progress = 1,
    reward_xp = 250,
    requires = {"unlock_5_abilities"},
    hidden = false,
    graph_x = 1,
    graph_y = 7,
})

-- ===============================
-- Challenge Category
-- ===============================

register_achievement({
    id = "reach_level_10",
    name = "Veteran",
    description = "Reach level 10",
    icon = "achievement_reach_level_10.png",
    category = "challenge",
    max_progress = 1,
    reward_xp = 250,
    requires = {},  -- No requirements
    graph_x = 3,
    graph_y = 0,
})

register_achievement({
    id = "reach_level_25",
    name = "Expert",
    description = "Reach level 25",
    icon = "achievement_reach_level_25.png",
    category = "challenge",
    max_progress = 1,
    reward_xp = 500,
    requires = {},  -- No requirements
    graph_x = 4,
    graph_y = 0,
})

register_achievement({
    id = "reach_level_50",
    name = "Legend",
    description = "Reach level 50",
    icon = "achievement_reach_level_50.png",
    category = "challenge",
    max_progress = 1,
    reward_xp = 1000,
    requires = {},  -- No requirements
    graph_x = 5,
    graph_y = 0,
})

register_achievement({
    id = "dig_1000_blocks",
    name = "Excavator",
    description = "Break 1000 blocks",
    icon = "achievement_dig_1000_blocks.png",
    category = "challenge",
    max_progress = 1000,
    reward_xp = 300,
    requires = {"dig_100_blocks"},
    graph_x = 2,
    graph_y = 1,
})

register_achievement({
    id = "place_1000_blocks",
    name = "Architect",
    description = "Place 1000 blocks",
    icon = "achievement_place_1000_blocks.png",
    category = "challenge",
    max_progress = 1000,
    reward_xp = 300,
    requires = {"place_10_blocks"},
    graph_x = 2,
    graph_y = 2,
})

-- ===============================
-- Secret Category (Hidden)
-- ===============================

register_achievement({
    id = "secret_find_depths",
    name = "Into the Abyss",
    description = "Discover the depths below the city",
    icon = "achievement_secret_find_depths.png",
    category = "secret",
    max_progress = 1,
    reward_xp = 500,
    hidden = true,
    graph_x = 3,
    graph_y = 3,
})

register_achievement({
    id = "secret_easter_egg",
    name = "Curious Mind",
    description = "Find a hidden easter egg",
    icon = "achievement_secret_easter_egg.png",
    category = "secret",
    max_progress = 1,
    reward_xp = 100,
    hidden = true,
    graph_x = 4,
    graph_y = 3,
})

minetest.log("action", "[achievement_definitions] Loaded " .. get_achievement_count() .. " achievements! 🏆")
