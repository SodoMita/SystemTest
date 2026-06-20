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
    
    -- Trigger ALL level milestones (achievement_progress handles duplicates and requirements)
    if level >= 5 then achievement_progress(player, "reach_level_5", 1) end
    if level >= 10 then achievement_progress(player, "reach_level_10", 1) end
    if level >= 25 then achievement_progress(player, "reach_level_25", 1) end
    if level >= 50 then achievement_progress(player, "reach_level_50", 1) end
    
    return leveled_up
end

-- Track position for exploration achievements
local player_spawn_positions = {}
local player_highest_y = {}
local player_looped = {}
local player_last_y = {}

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
end)

-- ========================================================
-- Reliable world-loop detection via sl_teleport callback
-- ========================================================
minetest.register_on_mods_loaded(function()
    if sl_teleport and sl_teleport.register_on_teleport then
        sl_teleport.register_on_teleport(function(entity, old_pos, new_pos, looped)
            if not entity or not entity:is_player() then return end
            local name = entity:get_player_name()

            if looped.x or looped.y or looped.z then
                unlock_achievement(entity, "secret_world_loop")
                player_looped[name] = true
                minetest.log("action", "[achievement_tracking] World loop detected for " .. name)
            end
        end)
    end
end)

-- Helper to check if player is on solid ground (not air, not ignore)
local function is_on_real_ground(player)
    local pos = player:get_pos()
    -- Check a small area around the feet
    for dx = -0.3, 0.3, 0.3 do
        for dz = -0.3, 0.3, 0.3 do
            local p = {x=pos.x + dx, y=pos.y - 0.1, z=pos.z + dz}
            local node = minetest.get_node(p)
            if node.name ~= "air" and node.name ~= "ignore" then
                local def = minetest.registered_nodes[node.name]
                if def and def.walkable then
                    return true
                end
            end
        end
    end
    
    -- Check for entities below
    local objs = minetest.get_objects_inside_radius({x=pos.x, y=pos.y-0.5, z=pos.z}, 0.7)
    for _, obj in ipairs(objs) do
        if obj ~= player then
            return true
        end
    end
    
    return false
end

local exploration_timer = 0
minetest.register_globalstep(function(dtime)
    exploration_timer = exploration_timer + dtime
    local check_exploration = (exploration_timer >= 5)
    if check_exploration then exploration_timer = 0 end

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos  = player:get_pos()
        if not pos then goto next_player end

        -- Skip tracking for ghosts if game_mode is available
        if game_mode and game_mode.get_player_state then
            local pl = game_mode.get_player_state(name)
            if pl and pl.phase == "ghost" then
                player_highest_y[name] = nil
                player_looped[name] = nil
                player_last_y[name] = pos.y
                goto next_player
            end
        end

        local last_y = player_last_y[name] or pos.y
        local v = player:get_velocity()
        
        -- Fall Detection
        if v and v.y < -5 then
            -- Falling downwards with significant speed
            player_highest_y[name] = math.max(player_highest_y[name] or pos.y, pos.y)
        elseif player_highest_y[name] then
            -- Stopped falling or moving up. Check for landing.
            local wrap_detected = (pos.y - last_y) > 10000 -- World wrap
            
            if not wrap_detected then
                if is_on_real_ground(player) then
                    local fall_dist = player_highest_y[name] - pos.y
                    if fall_dist >= 10000 then
                        unlock_achievement(player, "challenge_fall_10k")
                    elseif fall_dist >= 1000 then
                        unlock_achievement(player, "challenge_fall_1k")
                    elseif fall_dist >= 100 then
                        unlock_achievement(player, "challenge_fall_100")
                    end

                    if player_looped[name] then
                        unlock_achievement(player, "challenge_loop_land")
                    end
                    
                    player_highest_y[name] = nil
                    player_looped[name] = nil
                elseif v and v.y >= 0 then
                    -- Moving up without hitting ground (jump/fly), reset fall
                    player_highest_y[name] = nil
                    player_looped[name] = nil
                end
            end
        end

        player_last_y[name] = pos.y

        if check_exploration then
            -- Depth achievements
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
                if vector.distance(pos, spawn) >= 1000 then
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

minetest.log("action", "[achievement_tracking] Achievement auto-tracking loaded! 🏆")
