-- sl_gui — System Looting GUI systems
-- Loads all sub-systems in dependency order.
local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Experience and leveling system
dofile(modpath .. "/experience_system.lua")

-- Achievement system (load before tracking)
dofile(modpath .. "/achievement_system.lua")

-- Achievement definitions
dofile(modpath .. "/achievement_definitions.lua")

-- Achievement tracking
dofile(modpath .. "/achievement_tracking.lua")

-- Button-based crafting system
dofile(modpath .. "/crafting_system.lua")

-- Ability system (game-design-aligned, single file)
dofile(modpath .. "/ability_system.lua")

-- Running / Sprint system with Aux1 key
dofile(modpath .. "/running_system.lua")

-- Player info panel (team, role, lives, match status)
dofile(modpath .. "/player_info.lua")

-- Unified inventory with tabs
dofile(modpath .. "/unified_inventory.lua")

-- Character outfit / appearance menu
dofile(modpath .. "/character_outfit.lua")

minetest.log("action", "[sl_gui] All GUI systems loaded.")
