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

-- Check exploration achievements periodically
local exploration_timer = 0
local player_last_y = {}
local player_highest_y = {}
local player_looped = {}
local visited_islands = {}

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local pos = player:get_pos()
    player_last_y[name] = pos.y
    player_highest_y[name] = nil
    player_looped[name] = nil

    local meta = player:get_meta()
    local spawn_str = meta:get_string("spawn_pos")
    if spawn_str == "" then
        meta:set_string("spawn_pos", minetest.serialize(pos))
        player_spawn_positions[name] = pos
    else
        player_spawn_positions[name] = minetest.deserialize(spawn_str)
    end

    local visited_str = meta:get_string("visited_islands")
    if visited_str == "" then visited_str = "{}" end
    visited_islands[name] = minetest.deserialize(visited_str) or {}
end)

-- ========================================================
-- Reliable world-loop detection via sl_teleport callback
-- Uses the SAME function/logic the teleport mod uses, so
-- the trigger can no longer "miss" Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
-- ========================================================
minetest.register_on_mods_loaded(function()
    if sl_teleport and sl_teleport.register_on_teleport then
        sl_teleport.register_on_teleport(function(entity, old_pos, new_pos, looped)
            if not entity or not entity:is_player() then return end
            local name = entity:get_player_name()

            -- World loop achievement — fires on ANY axis wrap
            if looped.x or looped.y or looped.z then
                unlock_achievement(entity, "secret_world_loop")
                player_looped[name] = true
                minetest.log("action",
                    string.format("[achievement_tracking] %s world-looped via teleport "
                                  .. "(x:%s y:%s z:%s)", name,
                                  tostring(looped.x), tostring(looped.y), tostring(looped.z)))
            end
        end)
        minetest.log("action",
            "[achievement_tracking] Hooked into sl_teleport for world-loop detection ✅")
    else
        minetest.log("warning",
            "[achievement_tracking] sl_teleport API not found — "
            .. "world-loop achievements will be unreliable!")
    end
end)

-- Helper to check if player is on solid ground (not air, not ignore)
local function is_on_real_ground(player)
    local pos = player:get_pos()
    -- Check center and 4 corners for better accuracy
    local checks = {
        {x=pos.x, y=pos.y-0.1, z=pos.z},
        {x=pos.x+0.3, y=pos.y-0.1, z=pos.z},
        {x=pos.x-0.3, y=pos.y-0.1, z=pos.z},
        {x=pos.x, y=pos.y-0.1, z=pos.z+0.3},
        {x=pos.x, y=pos.y-0.1, z=pos.z-0.3},
    }
    for _, p in ipairs(checks) do
        local node = minetest.get_node_or_nil(p)
        if node and node.name ~= "air" and node.name ~= "ignore" then
            local def = minetest.registered_nodes[node.name]
            if def and def.walkable then
                return true
            end
        end
    end
    
    -- Check for entities (platforms, other players, etc)
    local objs = minetest.get_objects_inside_radius({x=pos.x, y=pos.y-0.5, z=pos.z}, 0.6)
    for _, obj in ipairs(objs) do
        if obj ~= player then
            return true
        end
    end
    
    return false
end

minetest.register_globalstep(function(dtime)
    exploration_timer = exploration_timer + dtime
    local check_exploration = (exploration_timer >= 10)
    if check_exploration then exploration_timer = 0 end

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos  = player:get_pos()
        if not pos then goto next_player end

        local pl = game_mode.get_player_state(name)
        if pl.phase == "ghost" then
            -- Ghosts can't trigger landing/fall achievements
            player_highest_y[name] = nil
            player_looped[name] = nil
            player_last_y[name] = pos.y
            goto next_player
        end

        local last_y = player_last_y[name] or pos.y
        
        -- Fall tracking
        if pos.y < last_y then
            -- Falling
            player_highest_y[name] = math.max(player_highest_y[name] or last_y, last_y)
        else
            -- Not falling (hit ground, jumping up, or looped)
            if player_highest_y[name] then
                -- Check if it was a world loop (very large jump up)
                local wrap_detected = (pos.y - last_y) > 10000 
                
                if not wrap_detected then
                    -- Potential landing. Verify we actually hit something "real"
                    if is_on_real_ground(player) then
                        local fall_dist = player_highest_y[name] - pos.y
                        if fall_dist >= 10000 then
                            unlock_achievement(player, "challenge_fall_10k")
                        elseif fall_dist >= 1000 then
                            unlock_achievement(player, "challenge_fall_1k")
                        elseif fall_dist >= 100 then
                            unlock_achievement(player, "challenge_fall_100")
                        end

                        -- Check if we landed after a loop
                        if player_looped[name] then
                            unlock_achievement(player, "challenge_loop_land")
                            player_looped[name] = nil
                        end
                    elseif pos.y == last_y then
                        -- Stuck in mid-air (e.g. ignore node)? 
                        -- Keep peak height but don't grant yet.
                    else
                        -- Moving up (jump/fly), reset fall distance
                        player_highest_y[name] = nil
                    end
                end
                
                -- Reset peak if we jumped up or moved significantly after landing
                if not wrap_detected and pos.y > last_y then
                    player_highest_y[name] = nil
                end
            end
        end

        player_last_y[name] = pos.y

        if check_exploration then
            -- Depth achievements (multi-tier)
            if pos.y < -20000 then
                unlock_achievement(player, "secret_depth_20k")
            elseif pos.y < -10000 then
                unlock_achievement(player, "secret_depth_10k")
            elseif pos.y < -5000 then
                unlock_achievement(player, "secret_depth_5k")
            elseif pos.y < -1000 then
                unlock_achievement(player, "secret_depth_1k")
            end

            local spawn = player_spawn_positions[name]
            if spawn then
                local distance = vector.distance(pos, spawn)
                if distance >= 1000 then
                    unlock_achievement(player, "travel_1000_blocks")
                end
            end

            if pos.y > 100 then
                unlock_achievement(player, "visit_floating_island")
            end

            if pos.y >= -10 and pos.y <= 50 then
                unlock_achievement(player, "find_city")
            end
        end
        ::next_player::
    end
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
                unlock_achievement(player, "visit_10_islands")
            end
        end
    end
end

minetest.log("action", "[achievement_tracking] Achievement auto-tracking loaded! 🏆")
