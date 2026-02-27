-- Achievement Auto-Tracking! 🏆✨
-- Automatically track player actions and grant achievements~

-- Track block breaking
minetest.register_on_dignode(function(pos, oldnode, digger)
    if not digger or not digger:is_player() then return end
    
    -- First dig achievement
    achievement_progress(digger, "first_dig", 1)
    
    -- Dig 100 blocks
    achievement_progress(digger, "dig_100_blocks", 1)
    
    -- Dig 1000 blocks
    achievement_progress(digger, "dig_1000_blocks", 1)
end)

-- Track block placing
minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
    if not placer or not placer:is_player() then return end
    
    -- Place 10 blocks
    achievement_progress(placer, "place_10_blocks", 1)
    
    -- Place 1000 blocks
    achievement_progress(placer, "place_1000_blocks", 1)
end)

-- Track level ups - modified experience system
local old_give_experience = give_experience
function give_experience(player, amount)
    local leveled_up = old_give_experience(player, amount)
    
    -- Always check all level-based achievements when XP is gained
    local meta = player:get_meta()
    local exp = tonumber(meta:get_string("experience")) or 0
    local level = math.floor(exp / 100) + 1
    
    minetest.log("action", string.format("[achievement_tracking] Player %s gained XP. Level: %d, Leveled up: %s", 
        player:get_player_name(), level, tostring(leveled_up)))
    
    -- Trigger ALL level milestones (achievement_progress handles duplicates and requirements)
    if level >= 5 then
        minetest.log("action", "[achievement_tracking] Attempting reach_level_5")
        achievement_progress(player, "reach_level_5", 1)
    end
    if level >= 10 then
        minetest.log("action", "[achievement_tracking] Attempting reach_level_10")
        achievement_progress(player, "reach_level_10", 1)
    end
    if level >= 25 then
        minetest.log("action", "[achievement_tracking] Attempting reach_level_25")
        achievement_progress(player, "reach_level_25", 1)
    end
    if level >= 50 then
        minetest.log("action", "[achievement_tracking] Attempting reach_level_50")
        achievement_progress(player, "reach_level_50", 1)
    end
    
    return leveled_up
end

-- Track position for exploration achievements
local player_spawn_positions = {}

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    local spawn_str = meta:get_string("spawn_pos")
    if spawn_str == "" then
        local pos = player:get_pos()
        meta:set_string("spawn_pos", minetest.serialize(pos))
        player_spawn_positions[name] = pos
    else
        player_spawn_positions[name] = minetest.deserialize(spawn_str)
    end
end)

-- Check exploration achievements periodically
local exploration_timer = 0
minetest.register_globalstep(function(dtime)
    exploration_timer = exploration_timer + dtime
    if exploration_timer >= 10 then -- Check every 10 seconds
        exploration_timer = 0
        
        for _, player in ipairs(minetest.get_connected_players()) do
            local name = player:get_player_name()
            local pos = player:get_pos()
            local spawn = player_spawn_positions[name]
            
            if spawn then
                local distance = vector.distance(pos, spawn)
                
                -- Travel 1000 blocks achievement
                if distance >= 1000 then
                    check_achievement(player, "travel_1000_blocks")
                end
            end
            
            -- Check if player is on floating island (high Y coordinate)
            if pos.y > 100 then
                check_achievement(player, "visit_floating_island")
            end
            
            -- Check if player is in city (around ground level)
            if pos.y >= -10 and pos.y <= 50 then
                check_achievement(player, "find_city")
            end
            
            -- Check if in depths (below city)
            if pos.y < -100 then
                check_achievement(player, "secret_find_depths")
            end
        end
    end
end)

-- Track island visits (simplified - you can expand this)
local visited_islands = {}

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    local visited_str = meta:get_string("visited_islands")
    if visited_str == "" then visited_str = "{}" end
    visited_islands[name] = minetest.deserialize(visited_str) or {}
end)

-- Helper to mark island visit (call this when player lands on island)
function mark_island_visit(player, island_id)
    local name = player:get_player_name()
    if not visited_islands[name] then
        visited_islands[name] = {}
    end
    
    if not visited_islands[name][island_id] then
        visited_islands[name][island_id] = true
        local meta = player:get_meta()
        meta:set_string("visited_islands", minetest.serialize(visited_islands[name]))
        
        local count = 0
        for _ in pairs(visited_islands[name]) do
            count = count + 1
        end
        
        -- Update island hopper achievement
        local data = meta:get_string("achievements")
        if data ~= "" then
            local ach_data = minetest.deserialize(data) or {}
            ach_data.progress = ach_data.progress or {}
            ach_data.progress["visit_10_islands"] = count
            meta:set_string("achievements", minetest.serialize(ach_data))
            
            if count >= 10 then
                check_achievement(player, "visit_10_islands")
            end
        end
    end
end

minetest.log("action", "[achievement_tracking] Achievement auto-tracking loaded! 🏆")
