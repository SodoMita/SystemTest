-- Achievement System with Visual Graph! 🏆✨
-- Track player accomplishments and show them in a beautiful graph~

local achievements = {}
local achievement_by_id = {}

-- Achievement tier system based on XP reward
-- Common: <50 XP, Uncommon: 50-99 XP, Rare: 100-199 XP, Epic: 200-499 XP, Legendary: 500+ XP
local function get_achievement_tier(reward_xp)
    if reward_xp >= 500 then
        return "legendary"
    elseif reward_xp >= 200 then
        return "epic"
    elseif reward_xp >= 100 then
        return "rare"
    elseif reward_xp >= 50 then
        return "uncommon"
    else
        return "common"
    end
end

-- Register an achievement
function register_achievement(def)
    local achievement = {
        id = def.id,
        name = def.name,
        description = def.description,
        icon = def.icon or "🏆",
        category = def.category or "general",
        
        -- Graph position for visual display
        graph_x = def.graph_x or 0,
        graph_y = def.graph_y or 0,
        
        -- Requirements
        requires = def.requires or {}, -- List of achievement IDs that must be unlocked first
        
        -- Progress tracking
        max_progress = def.max_progress or 1, -- How many times action must be done
        
        -- Unlock condition (function that checks if player meets requirements)
        check = def.check,
        
        -- Reward
        reward_xp = def.reward_xp or 50,
        reward_items = def.reward_items or {},
        
        -- Hidden until requirements met?
        hidden = def.hidden or false,
        
        -- Auto-calculate tier
        tier = get_achievement_tier(def.reward_xp or 50),
    }
    
    table.insert(achievements, achievement)
    achievement_by_id[achievement.id] = achievement
end

-- Get number of registered achievements
function get_achievement_count()
    return #achievements
end

-- Get player's achievement data
local function get_achievement_data(player)
    local meta = player:get_meta()
    local data_str = meta:get_string("achievements")
    if data_str == "" then data_str = "{}" end
    local data = minetest.deserialize(data_str) or {}
    
    if not data.unlocked then
        data.unlocked = {} -- {achievement_id = true}
        data.progress = {} -- {achievement_id = current_progress}
    end
    
    return data
end

-- Save achievement data
local function save_achievement_data(player, data)
    local meta = player:get_meta()
    meta:set_string("achievements", minetest.serialize(data))
end

-- Check if achievement requirements are met
local function check_requirements(player, achievement)
    local data = get_achievement_data(player)
    
    for _, req_id in ipairs(achievement.requires) do
        if not data.unlocked[req_id] then
            return false
        end
    end
    
    return true
end

-- Achievement queue for sequential display
local achievement_queue = {} -- {player_name = {achievements}}
local currently_showing = {} -- {player_name = true}

-- Tier value for sorting
local tier_values = {
    common = 1,
    uncommon = 2,
    rare = 3,
    epic = 4,
    legendary = 5,
}

-- Tier-based celebration effects
local tier_config = {
    common = {
        color = "#9a9a9a",
        particle_count = 10,
        particle_size = 2,
        sound_pitch = 1.0,
        sound_gain = 0.7,
        title_color = 0x9a9a9a,
        y_spread_multiplier = 1,  -- Base spread
    },
    uncommon = {
        color = "#4a9a4a",
        particle_count = 25,
        particle_size = 3,
        sound_pitch = 1.1,
        sound_gain = 0.85,
        title_color = 0x4a9a4a,
        y_spread_multiplier = 2,
    },
    rare = {
        color = "#4a7aca",
        particle_count = 50,
        particle_size = 4,
        sound_pitch = 1.2,
        sound_gain = 1.0,
        title_color = 0x4a7aca,
        y_spread_multiplier = 4,
    },
    epic = {
        color = "#9a4aca",
        particle_count = 100,
        particle_size = 5,
        sound_pitch = 1.3,
        sound_gain = 1.2,
        title_color = 0x9a4aca,
        y_spread_multiplier = 8,
    },
    legendary = {
        color = "#ca9a4a",
        particle_count = 200,
        particle_size = 6,
        sound_pitch = 1.5,
        sound_gain = 1.5,
        title_color = 0xca9a4a,
        y_spread_multiplier = 16,  -- MASSIVE spread!
    },
}

-- Show achievement popup with particles and effects
local function show_achievement_popup(player, achievement)
    local name = player:get_player_name()
    local tier = tier_config[achievement.tier] or tier_config.common
    
    -- Mark as currently showing
    currently_showing[name] = true
    
    -- Create popup HUD background with border
    local popup_border = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.5, y = 0.2},
        offset = {x = 0, y = 0},
        text = "gui_blank.png^[colorize:#000000:220",
        scale = {x = 21, y = 9},
        alignment = {x = 0, y = 0},
        z_index = 999,
    })
    
    local popup_bg = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.5, y = 0.2},
        offset = {x = 0, y = 0},
        text = "gui_blank.png^[colorize:" .. tier.color .. ":180",
        scale = {x = 300, y = 150},
        alignment = {x = 0, y = 0},
        z_index = 1000,
    })
    
    local popup_icon = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.5, y = 0.18},
        offset = {x = 0, y = 0},
        text = achievement.icon,
        alignment = {x = 0, y = 0},
        scale = {x = 2, y = 2},
        z_index = 1001,
    })
    
    local popup_title = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.2},
        offset = {x = 0, y = 0},
        text = "🏆 ACHIEVEMENT UNLOCKED! 🏆",
        number = 0xFFFFFF,
        alignment = {x = 0, y = 0},
        scale = {x = 150, y = 150},
        z_index = 1001,
    })
    
    local popup_name = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.22},
        offset = {x = 0, y = 0},
        text = achievement.name,
        number = tier.title_color,
        alignment = {x = 0, y = 0},
        scale = {x = 120, y = 120},
        z_index = 1001,
    })
    
    local popup_desc = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.235},
        offset = {x = 0, y = 0},
        text = achievement.description,
        number = 0xCCCCCC,
        alignment = {x = 0, y = 0},
        scale = {x = 100, y = 100},
        z_index = 1001,
    })
    
    -- Spawn 2D GUI confetti particles (always visible!)
    local gui_particle_count = tier.particle_count * 2
    
    -- Calculate Y spread based on tier rarity
    local base_y_min = -60
    local base_y_max = -10
    local y_min = base_y_min * tier.y_spread_multiplier
    local y_max = base_y_max
    
    for i = 1, gui_particle_count do
        local start_x = math.random(0, 100) / 100
        local start_y = math.random(y_min, y_max) / 100  -- Rarity-scaled Y spread!
        
        local hud_particle = player:hud_add({
            hud_elem_type = "image",
            position = {x = start_x, y = start_y},
            offset = {x = 0, y = 0},
            text = "gui_achievement_star.png^[colorize:" .. tier.color .. ":220",
            scale = {x = tier.particle_size * 0.5, y = tier.particle_size * 0.5},
            alignment = {x = 0, y = 0},
            z_index = 1002,
        })
        
        -- Animate GUI particles falling down with increasing acceleration
        local fall_time = 0
        local initial_speed = math.random(3, 8) / 100
        local horizontal_drift = (math.random(-30, 30) / 1000)
        local gravity_accel = 0.15  -- Increased acceleration!
        
        local function animate_particle()
            fall_time = fall_time + 0.05
            local current_x = start_x + (horizontal_drift * fall_time)
            -- Quadratic acceleration for realistic physics
            local current_y = start_y + (initial_speed * fall_time) + (0.5 * gravity_accel * fall_time * fall_time)
            
            if current_y < 1.3 and minetest.get_player_by_name(name) then
                player:hud_change(hud_particle, "position", {x = current_x, y = current_y})
                minetest.after(0.05, animate_particle)
            else
                if minetest.get_player_by_name(name) then
                    player:hud_remove(hud_particle)
                end
            end
        end
        
        minetest.after(0.05, animate_particle)
    end
    
    -- Spawn 3D particles continuously for 2 seconds!
    local particle_spawner
    local particles_spawned = 0
    local max_spawn_time = 2.0
    
    local function spawn_3d_particles()
        if particles_spawned >= max_spawn_time then
            return
        end
        
        local player_pos = player:get_pos()
        if not player_pos then return end
        
        for i = 1, math.ceil(tier.particle_count / 10) do
            minetest.add_particle({
                pos = {
                    x = player_pos.x + math.random(-12, 12),
                    y = player_pos.y + math.random(-5, 20),  -- Much bigger Y spread!
                    z = player_pos.z + math.random(-12, 12)
                },
                velocity = {
                    x = math.random(-4, 4),
                    y = math.random(-2, 5),
                    z = math.random(-4, 4)
                },
                acceleration = {x = 0, y = -4, z = 0},  -- Stronger gravity
                expirationtime = 8,
                size = tier.particle_size,
                collisiondetection = false,
                vertical = false,
                texture = "gui_achievement_star.png^[colorize:" .. tier.color .. ":200",
                playername = name,
                glow = 14,
            })
        end
        
        particles_spawned = particles_spawned + 0.1
        minetest.after(0.1, spawn_3d_particles)
    end
    
    spawn_3d_particles()
    
    -- Play sound based on tier
    minetest.sound_play("achievement_unlock", {
        to_player = name,
        gain = tier.sound_gain,
        pitch = tier.sound_pitch,
    }, true)
    
    -- Remove popup after 10 seconds and process queue
    minetest.after(10, function()
        if minetest.get_player_by_name(name) then
            player:hud_remove(popup_border)
            player:hud_remove(popup_bg)
            player:hud_remove(popup_icon)
            player:hud_remove(popup_title)
            player:hud_remove(popup_name)
            player:hud_remove(popup_desc)
            
            currently_showing[name] = false
            
            -- Process next achievement in queue
            if achievement_queue[name] and #achievement_queue[name] > 0 then
                local next_achievement = table.remove(achievement_queue[name], 1)
                show_achievement_popup(player, next_achievement)
            end
        end
    end)
end

-- Queue achievement for display
local function queue_achievement_popup(player, achievement)
    local name = player:get_player_name()
    
    if not achievement_queue[name] then
        achievement_queue[name] = {}
    end
    
    table.insert(achievement_queue[name], achievement)
    
    -- Sort queue by tier value (least to most valuable)
    table.sort(achievement_queue[name], function(a, b)
        return tier_values[a.tier] < tier_values[b.tier]
    end)
    
    -- If not currently showing, start displaying
    if not currently_showing[name] then
        local first = table.remove(achievement_queue[name], 1)
        if first then
            show_achievement_popup(player, first)
        end
    end
end

-- Unlock achievement
local function unlock_achievement(player, achievement_id)
    local achievement = achievement_by_id[achievement_id]
    if not achievement then return false end
    
    local data = get_achievement_data(player)
    
    -- Already unlocked?
    if data.unlocked[achievement_id] then
        return false
    end
    
    -- Check requirements
    if not check_requirements(player, achievement) then
        return false
    end
    
    -- Unlock it!
    data.unlocked[achievement_id] = true
    save_achievement_data(player, data)
    
    -- Give rewards
    if achievement.reward_xp > 0 then
        give_experience(player, achievement.reward_xp)
    end
    
    for item, count in pairs(achievement.reward_items) do
        player:get_inventory():add_item("main", ItemStack(item .. " " .. count))
    end
    
    -- Queue epic celebration! 🎉
    queue_achievement_popup(player, achievement)
    
    -- Also send chat message
    local name = player:get_player_name()
    minetest.chat_send_player(name, 
        string.format("🏆 Achievement Unlocked: %s! 🏆", achievement.name))
    minetest.chat_send_player(name, achievement.description)
    
    if achievement.reward_xp > 0 then
        minetest.chat_send_player(name, string.format("+%d XP", achievement.reward_xp))
    end
    
    return true
end

-- Add progress to achievement
function achievement_progress(player, achievement_id, amount)
    amount = amount or 1
    local achievement = achievement_by_id[achievement_id]
    if not achievement then 
        minetest.log("warning", "[achievement_system] Achievement not found: " .. achievement_id)
        return 
    end
    
    local data = get_achievement_data(player)
    
    -- Already unlocked?
    if data.unlocked[achievement_id] then
        minetest.log("action", string.format("[achievement_system] %s already unlocked for %s", 
            achievement_id, player:get_player_name()))
        return
    end
    
    -- Check requirements first
    if not check_requirements(player, achievement) then
        minetest.log("action", string.format("[achievement_system] %s requirements not met for %s", 
            achievement_id, player:get_player_name()))
        return
    end
    
    -- Add progress
    data.progress[achievement_id] = (data.progress[achievement_id] or 0) + amount
    
    minetest.log("action", string.format("[achievement_system] %s progress: %d/%d for %s", 
        achievement_id, data.progress[achievement_id], achievement.max_progress, player:get_player_name()))
    
    -- Check if completed
    if data.progress[achievement_id] >= achievement.max_progress then
        minetest.log("action", string.format("[achievement_system] Unlocking %s for %s!", 
            achievement_id, player:get_player_name()))
        unlock_achievement(player, achievement_id)
    else
        save_achievement_data(player, data)
    end
end

-- Check achievement condition
function check_achievement(player, achievement_id)
    local achievement = achievement_by_id[achievement_id]
    if not achievement or not achievement.check then return end
    
    if achievement.check(player) then
        unlock_achievement(player, achievement_id)
    end
end

-- Generate achievement graph formspec
function get_achievement_formspec(player)
    local data = get_achievement_data(player)
    
    -- Debug
    minetest.log("action", "[achievement_system] Generating formspec for player. Total achievements: " .. #achievements)
    
    -- Get player model info
    local player_name = player:get_player_name()
    local player_textures = player_api.get_textures(player) or {"character.png"}
    
    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#0a0a0aff;true]",
        
        -- 3D Player Model Preview Box (square, static)
        "box[0.2,0.3;1.5,1.5;#1a1a1aff]",
        "model[0.3,0.4;1.3,1.3;player_preview;character.b3d;" .. table.concat(player_textures, ",") .. ";0,170;false;false;0,0]",
        "image_button[0.3,0.4;1.3,1.3;;open_outfit;]",
        
        -- Header with stats
        "box[0.2,1.8;11.6,0.6;#2a2a2aff]",
        "label[0.5,2.1;🏆 Achievements]",
    }
    
    -- Count unlocked achievements
    local unlocked_count = 0
    for _ in pairs(data.unlocked) do
        unlocked_count = unlocked_count + 1
    end
    
    table.insert(formspec, string.format(
        "label[9,2.1;%d / %d Unlocked]", 
        unlocked_count, #achievements
    ))
    
    -- Categories
    local categories = {}
    for _, achievement in ipairs(achievements) do
        if not categories[achievement.category] then
            categories[achievement.category] = {}
        end
        table.insert(categories[achievement.category], achievement)
    end
    
    -- Scrollable achievement list view
    table.insert(formspec, "scroll_container[0.3,2.6;11.4,8.8;ach_scroll;vertical;0.1]")
    
    local y = 0
    for category_name, category_achievements in pairs(categories) do
        -- Category header
        table.insert(formspec, string.format("box[0,%f;11,0.5;#3a3a3aff]", y))
        table.insert(formspec, string.format("label[0.2,%f;%s]", y + 0.25, category_name:upper()))
        y = y + 0.6
        
        for _, achievement in ipairs(category_achievements) do
            local is_unlocked = data.unlocked[achievement.id]
            local requirements_met = check_requirements(player, achievement)
            local progress = data.progress[achievement.id] or 0
            
            -- Should we show this achievement?
            local visible = true
            if achievement.hidden and not requirements_met and not is_unlocked then
                visible = false
            end
            
            if visible then
                local color
                if is_unlocked then
                    color = "#2a5a2aff" -- Green for unlocked
                elseif requirements_met then
                    color = "#4a4a2aff" -- Yellow-ish for available
                else
                    color = "#2a2a2aff" -- Dark gray for locked
                end
                
                -- Achievement box
                table.insert(formspec, string.format("box[0,%f;11,1.2;%s]", y, color))
                
                -- Icon
                table.insert(formspec, string.format("image[0.1,%f;1,1;%s]", y + 0.1, achievement.icon))
                
                -- Name and description
                local display_name = achievement.name
                if is_unlocked then
                    display_name = "✓ " .. display_name
                elseif not requirements_met then
                    display_name = "🔒 " .. display_name
                end
                
                table.insert(formspec, string.format("label[1,%f;%s]", y + 0.3, display_name))
                table.insert(formspec, string.format("label[1,%f;%s]", y + 0.7, 
                    minetest.formspec_escape(achievement.description)))
                
                -- Progress bar for incomplete achievements
                if not is_unlocked and achievement.max_progress > 1 and progress > 0 then
                    local progress_pct = progress / achievement.max_progress
                    local bar_width = 3
                    local bar_x = 7.5
                    
                    -- Background
                    table.insert(formspec, string.format("box[%f,%f;%f,0.3;#1a1a1aff]", 
                        bar_x, y + 0.5, bar_width))
                    -- Progress
                    table.insert(formspec, string.format("box[%f,%f;%f,0.3;#4a9a4aff]", 
                        bar_x, y + 0.5, bar_width * progress_pct))
                    -- Text
                    table.insert(formspec, string.format("label[%f,%f;%d/%d]", 
                        bar_x + bar_width/2 - 0.3, y + 0.55, progress, achievement.max_progress))
                end
                
                -- Reward display
                if not is_unlocked and achievement.reward_xp > 0 then
                    table.insert(formspec, string.format("label[7.5,%f;+%d XP]", 
                        y + 0.3, achievement.reward_xp))
                end
                
                y = y + 1.3
            end
        end
        
        y = y + 0.2 -- spacing between categories
    end
    
    table.insert(formspec, "scroll_container_end[]")
    
    -- Scrollbar
    table.insert(formspec, "scrollbar[11.5,2.6;0.3,8.8;vertical;ach_scroll;0]")
    
    return table.concat(formspec, "")
end

-- Handle formspec input
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "achievement_system" then
        return
    end
    
    -- Handle scrolling
    if fields.ach_scroll then
        local event = minetest.explode_scrollbar_event(fields.ach_scroll)
        if event.type == "CHG" then
            player:set_attribute("ach_scroll", tostring(event.value))
        end
    end
end)

-- Initialize player data on join
minetest.register_on_joinplayer(function(player)
    local meta = player:get_meta()
    if meta:get_string("achievements") == "" then
        meta:set_string("achievements", minetest.serialize({
            unlocked = {},
            progress = {}
        }))
    end
end)

-- Clean up achievement queue on leave
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    achievement_queue[name] = nil
    currently_showing[name] = nil
end)

-- Chat command to view achievements
minetest.register_chatcommand("achievements", {
    description = "View your achievements",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            minetest.show_formspec(name, "achievement_system", 
                get_achievement_formspec(player))
            return true
        end
        return false, "Player not found"
    end
})

-- Admin command to grant achievement
minetest.register_chatcommand("giveachievement", {
    params = "<player> <achievement_id>",
    description = "Grant an achievement to a player",
    privs = {server = true},
    func = function(name, param)
        local target_name, ach_id = param:match("^(%S+)%s+(%S+)$")
        if not target_name or not ach_id then
            return false, "Usage: /giveachievement <player> <achievement_id>"
        end
        
        local target = minetest.get_player_by_name(target_name)
        if not target then
            return false, "Player not found"
        end
        
        if unlock_achievement(target, ach_id) then
            return true, string.format("Granted achievement '%s' to %s", ach_id, target_name)
        else
            return false, "Failed to grant achievement (already unlocked or doesn't exist?)"
        end
    end
})

-- Admin command to reset achievements
minetest.register_chatcommand("resetachievements", {
    params = "<player>",
    description = "Reset a player's achievements",
    privs = {server = true},
    func = function(name, param)
        local target = minetest.get_player_by_name(param)
        if not target then
            return false, "Player not found"
        end
        
        local meta = target:get_meta()
        meta:set_string("achievements", minetest.serialize({
            unlocked = {},
            progress = {}
        }))
        
        return true, string.format("Reset achievements for %s", param)
    end
})

-- Admin command to reset EVERYTHING (experience, abilities, achievements)
minetest.register_chatcommand("resetprogress", {
    params = "<player>",
    description = "Reset ALL player progress (XP, abilities, achievements)",
    privs = {server = true},
    func = function(name, param)
        local target = minetest.get_player_by_name(param)
        if not target then
            return false, "Player not found"
        end
        
        local meta = target:get_meta()
        
        -- Reset experience
        meta:set_string("experience", "0")
        
        -- Reset abilities
        meta:set_string("abilities", minetest.serialize({
            unlocked = {},
            stat_points = 0
        }))
        
        -- Reset achievements
        meta:set_string("achievements", minetest.serialize({
            unlocked = {},
            progress = {}
        }))
        
        -- Clear achievement queue
        achievement_queue[param] = nil
        currently_showing[param] = nil
        
        -- Reset physics
        target:set_physics_override({
            speed = 1.0,
            jump = 1.0,
            gravity = 1.0
        })
        
        -- Update HUD
        if give_experience then
            -- Trigger HUD update by giving 0 XP
            give_experience(target, 0)
        end
        
        minetest.chat_send_player(param, "✨ Your progress has been completely reset! ✨")
        return true, string.format("Reset ALL progress for %s", param)
    end
})

minetest.log("action", "[achievement_system] Achievement system loaded! 🏆")
