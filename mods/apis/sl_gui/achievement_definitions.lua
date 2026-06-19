-- =============================================================
-- System Looting — Achievement Definitions
-- =============================================================
-- Categories match the game's systems:
--   getting_started, combat, crafting, abilities,
--   exploration, team_play, challenge, secret
-- =============================================================

-- ===== Getting Started =========================================

register_achievement({
    id = "first_dig",
    name = "First Steps",
    description = "Break your first block",
    icon = "achievement_first_dig.png",
    category = "getting_started",
    max_progress = 1,
    reward_xp = 10,
    graph_x = 0, graph_y = 0,
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
    graph_x = 1, graph_y = 0,
})

register_achievement({
    id = "dig_100_blocks",
    name = "Scavenger",
    description = "Break 100 blocks",
    icon = "achievement_dig_100_blocks.png",
    category = "getting_started",
    max_progress = 100,
    reward_xp = 50,
    requires = {"first_dig"},
    graph_x = 1, graph_y = 1,
})

register_achievement({
    id = "reach_level_5",
    name = "Experienced",
    description = "Reach level 5",
    icon = "achievement_reach_level_5.png",
    category = "getting_started",
    max_progress = 1,
    reward_xp = 100,
    graph_x = 2, graph_y = 0,
})

-- ===== Combat ==================================================

register_achievement({
    id = "first_kill",
    name = "First Blood",
    description = "Defeat your first enemy (player or monster)",
    icon = "achievement_first_ghost.png",
    category = "combat",
    max_progress = 1,
    reward_xp = 25,
    graph_x = 0, graph_y = 2,
})

register_achievement({
    id = "monster_slayer",
    name = "Monster Slayer",
    description = "Defeat 10 monsters",
    icon = "achievement_ghost_hunter.png",
    category = "combat",
    max_progress = 10,
    reward_xp = 75,
    requires = {"first_kill"},
    graph_x = 1, graph_y = 2,
})

register_achievement({
    id = "monster_veteran",
    name = "Monster Veteran",
    description = "Defeat 50 monsters",
    icon = "achievement_ghost_veteran.png",
    category = "combat",
    max_progress = 50,
    reward_xp = 200,
    requires = {"monster_slayer"},
    graph_x = 2, graph_y = 2,
})

register_achievement({
    id = "survive_match",
    name = "Survivor",
    description = "Survive an entire match without being eliminated",
    icon = "achievement_survivor.png",
    category = "combat",
    max_progress = 1,
    reward_xp = 150,
    graph_x = 0, graph_y = 3,
})

-- ===== Crafting ================================================

register_achievement({
    id = "first_craft",
    name = "Craftsman Apprentice",
    description = "Craft your first item",
    icon = "achievement_first_craft.png",
    category = "crafting",
    max_progress = 1,
    reward_xp = 20,
    graph_x = 0, graph_y = 4,
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
    graph_x = 1, graph_y = 4,
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
    graph_x = 2, graph_y = 4,
})

register_achievement({
    id = "craft_equipment",
    name = "Armed Up",
    description = "Craft an equipment item",
    icon = "achievement_craft_urban_item.png",
    category = "crafting",
    max_progress = 1,
    reward_xp = 50,
    requires = {"first_craft"},
    graph_x = 1, graph_y = 5,
})

register_achievement({
    id = "craft_tactical",
    name = "Tactician",
    description = "Craft a tactical item",
    icon = "achievement_craft_glass.png",
    category = "crafting",
    max_progress = 1,
    reward_xp = 75,
    requires = {"first_craft"},
    graph_x = 0, graph_y = 5,
})

register_achievement({
    id = "craft_objective_core",
    name = "Mission Complete",
    description = "Craft the Objective Core",
    icon = "achievement_mission_complete.png",
    category = "crafting",
    max_progress = 1,
    reward_xp = 500,
    requires = {"craft_equipment", "craft_tactical"},
    graph_x = 2, graph_y = 5,
})

-- ===== Abilities ===============================================

register_achievement({
    id = "unlock_first_ability",
    name = "Awakening",
    description = "Unlock your first ability",
    icon = "achievement_unlock_first_ability.png",
    category = "abilities",
    max_progress = 1,
    reward_xp = 50,
    graph_x = 0, graph_y = 6,
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
    graph_x = 1, graph_y = 6,
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
    graph_x = 2, graph_y = 6,
})

register_achievement({
    id = "unlock_all_movement",
    name = "Fleet Foot",
    description = "Unlock every movement ability",
    icon = "achievement_unlock_all_movement.png",
    category = "abilities",
    max_progress = 1,
    reward_xp = 200,
    requires = {"max_ability"},
    graph_x = 3, graph_y = 6,
})

-- ===== Team Play ===============================================

register_achievement({
    id = "win_match",
    name = "Victory!",
    description = "Win a match",
    icon = "achievement_victory.png",
    category = "team_play",
    max_progress = 1,
    reward_xp = 200,
    graph_x = 3, graph_y = 0,
})

register_achievement({
    id = "win_5_matches",
    name = "Champion",
    description = "Win 5 matches",
    icon = "achievement_champion.png",
    category = "team_play",
    max_progress = 5,
    reward_xp = 500,
    requires = {"win_match"},
    graph_x = 4, graph_y = 0,
})

register_achievement({
    id = "play_monster_master",
    name = "Puppeteer",
    description = "Play as the Monster Master",
    icon = "achievement_puppeteer.png",
    category = "team_play",
    max_progress = 1,
    reward_xp = 100,
    graph_x = 3, graph_y = 1,
})

-- ===== Challenge ===============================================

register_achievement({
    id = "reach_level_10",
    name = "Veteran",
    description = "Reach level 10",
    icon = "achievement_reach_level_10.png",
    category = "challenge",
    max_progress = 1,
    reward_xp = 250,
    graph_x = 3, graph_y = 3,
})

register_achievement({
    id = "reach_level_25",
    name = "Expert",
    description = "Reach level 25",
    icon = "achievement_reach_level_25.png",
    category = "challenge",
    max_progress = 1,
    reward_xp = 500,
    graph_x = 4, graph_y = 3,
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
    graph_x = 2, graph_y = 1,
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
    graph_x = 2, graph_y = 2,
})

-- ===== Secret ==================================================

register_achievement({
    id = "secret_find_depths",
    name = "Into the Abyss",
    description = "Descend below y=-100",
    icon = "achievement_secret_find_depths.png",
    category = "secret",
    max_progress = 1,
    reward_xp = 500,
    hidden = true,
    graph_x = 4, graph_y = 4,
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
    graph_x = 5, graph_y = 4,
})

minetest.log("action", "[achievement_definitions] Loaded "
    .. get_achievement_count() .. " achievements.")
