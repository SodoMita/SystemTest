-- Ability Tree & Stat Point System! 🌟✨

-- Define abilities and stat upgrades
local abilities = {
    -- Movement upgrades
    {
        id = "speed_1",
        name = "Quick Steps I",
        description = "Increase movement speed by 20%",
        icon = "ability_speed.png",
        category = "movement",
        cost = 1,
        max_level = 3,
        requires = nil,
        effect = function(player, level)
            local physics = player:get_physics_override()
            physics.speed = 1.0 + (0.2 * level)
            player:set_physics_override(physics)
        end
    },
    {
        id = "jump_1",
        name = "High Jump I",
        description = "Increase jump height by 30%",
        icon = "ability_jump.png",
        category = "movement",
        cost = 1,
        max_level = 3,
        requires = nil,
        effect = function(player, level)
            local physics = player:get_physics_override()
            physics.jump = 1.0 + (0.3 * level)
            player:set_physics_override(physics)
        end
    },
    {
        id = "speed_2",
        name = "Quick Steps II",
        description = "Further increase speed by 30%",
        icon = "ability_speed.png",
        category = "movement",
        cost = 2,
        max_level = 2,
        requires = "speed_1",
        effect = function(player, level)
            local physics = player:get_physics_override()
            physics.speed = 1.6 + (0.3 * level)
            player:set_physics_override(physics)
        end
    },
    {
        id = "jump_2",
        name = "High Jump II",
        description = "Further increase jump by 40%",
        icon = "ability_jump.png",
        category = "movement",
        cost = 2,
        max_level = 2,
        requires = "jump_1",
        effect = function(player, level)
            local physics = player:get_physics_override()
            physics.jump = 1.9 + (0.4 * level)
            player:set_physics_override(physics)
        end
    },
    
    -- Utility upgrades
    {
        id = "gravity_1",
        name = "Light Body",
        description = "Reduce gravity by 20%",
        icon = "ability_gravity.png",
        category = "utility",
        cost = 2,
        max_level = 2,
        requires = nil,
        effect = function(player, level)
            local physics = player:get_physics_override()
            physics.gravity = 1.0 - (0.2 * level)
            player:set_physics_override(physics)
        end
    },
    {
        id = "breath_1",
        name = "Deep Breath",
        description = "Increase breath by 5 seconds",
        icon = "ability_breath.png",
        category = "utility",
        cost = 1,
        max_level = 3,
        requires = nil,
        effect = function(player, level)
            player:set_properties({
                breath_max = 10 + (5 * level)
            })
        end
    },
}

-- Get player's ability data
local function get_ability_data(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    local data_str = meta:get_string("abilities")
    if data_str == "" then data_str = "{}" end
    local data = minetest.deserialize(data_str) or {}
    
    -- Initialize if needed
    if not data.unlocked then
        data.unlocked = {}
        data.stat_points = 0
    end
    
    return data
end

-- Save ability data
local function save_ability_data(player, data)
    local meta = player:get_meta()
    meta:set_string("abilities", minetest.serialize(data))
end

-- Apply all unlocked abilities
local function apply_abilities(player)
    local data = get_ability_data(player)
    
    -- Reset physics first
    player:set_physics_override({
        speed = 1.0,
        jump = 1.0,
        gravity = 1.0
    })
    
    -- Apply each unlocked ability
    for _, ability in ipairs(abilities) do
        local level = data.unlocked[ability.id] or 0
        if level > 0 and ability.effect then
            ability.effect(player, level)
        end
    end
end

-- Check if ability can be unlocked
local function can_unlock(player, ability_id)
    local data = get_ability_data(player)
    
    for _, ability in ipairs(abilities) do
        if ability.id == ability_id then
            local current_level = data.unlocked[ability.id] or 0
            
            -- Check max level
            if current_level >= ability.max_level then
                return false, "Already at max level!"
            end
            
            -- Check stat points
            if data.stat_points < ability.cost then
                return false, "Not enough stat points!"
            end
            
            -- Check requirements
            if ability.requires then
                local req_level = data.unlocked[ability.requires] or 0
                if req_level <= 0 then
                    return false, "Requires: " .. ability.requires
                end
            end
            
            return true
        end
    end
    
    return false, "Ability not found"
end

-- Generate ability tree formspec
local function get_ability_formspec(player)
    local data = get_ability_data(player)
    local meta = player:get_meta()
    local exp = tonumber(meta:get_string("experience")) or 0
    local level = math.floor(exp / 100) + 1
    
    local formspec = {
        "formspec_version[4]",
        "size[14,10]",
        "bgcolor[#0a0a0aff;true]",
        
        -- Header
        "box[0.2,0.2;13.6,0.8;#2a2a2aff]",
        "label[0.5,0.6;✨ Ability Tree - Level " .. level .. " ✨]",
        "label[10,0.6;Stat Points: " .. data.stat_points .. "]",
        
        -- Movement category
        "box[0.2,1.2;6.6,8.3;#1a1a1aff]",
        "label[0.5,1.5;Movement Abilities]",
    }
    
    local y_movement = 2
    local y_utility = 2
    
    for _, ability in ipairs(abilities) do
        local current_level = data.unlocked[ability.id] or 0
        local can_buy, msg = can_unlock(player, ability.id)
        
        local x, y
        if ability.category == "movement" then
            x = 0.5
            y = y_movement
            y_movement = y_movement + 1.3
        else
            x = 7.3
            y = y_utility
            y_utility = y_utility + 1.3
        end
        
        -- Ability box
        local color = current_level > 0 and "#3a5a3a" or "#3a3a3a"
        table.insert(formspec, string.format("box[%f,%f;6,1.2;%s]", x, y, color))
        
        -- Icon
        if ability.icon then
            table.insert(formspec, string.format("image[%f,%f;1,1;%s]", x + 0.1, y + 0.1, ability.icon))
        end
        
        -- Name and level
        table.insert(formspec, string.format("label[%f,%f;%s [%d/%d]]", 
            x + 1.2, y + 0.25, ability.name, current_level, ability.max_level))
        
        -- Description
        table.insert(formspec, string.format("label[%f,%f;%s]", 
            x + 1.2, y + 0.6, ability.description))
        
        -- Cost and requirements
        local info = "Cost: " .. ability.cost .. " SP"
        if ability.requires then
            info = info .. " | Requires: " .. ability.requires
        end
        table.insert(formspec, string.format("label[%f,%f;%s]", x + 1.2, y + 0.95, info))
        
        -- Unlock/upgrade button
        if current_level < ability.max_level then
            local btn_text = current_level > 0 and "Upgrade" or "Unlock"
            table.insert(formspec, string.format("button[%f,%f;1.5,0.5;unlock_%s;%s]", 
                x + 4.3, y + 0.1, ability.id, btn_text))
        else
            table.insert(formspec, string.format("label[%f,%f;MAX]", x + 5, y + 0.35))
        end
    end
    
    -- Utility category header
    table.insert(formspec, "box[7.2,1.2;6.6,8.3;#1a1a1aff]")
    table.insert(formspec, "label[7.5,1.5;Utility Abilities]")
    
    -- Reset button
    table.insert(formspec, "button[11,0.3;2.5,0.6;reset_abilities;Reset (Cost: 5 SP)]")
    
    return table.concat(formspec, "")
end

-- Handle formspec input
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "ability_tree" then
        return
    end
    
    if fields.quit then
        return
    end
    
    local data = get_ability_data(player)
    local name = player:get_player_name()
    
    -- Handle unlock/upgrade buttons
    for field, _ in pairs(fields) do
        if field:sub(1, 7) == "unlock_" then
            local ability_id = field:sub(8)
            local can_buy, msg = can_unlock(player, ability_id)
            
            if can_buy then
                -- Find the ability
                for _, ability in ipairs(abilities) do
                    if ability.id == ability_id then
                        -- Unlock/upgrade
                        data.unlocked[ability_id] = (data.unlocked[ability_id] or 0) + 1
                        data.stat_points = data.stat_points - ability.cost
                        
                        save_ability_data(player, data)
                        apply_abilities(player)
                        
                        -- Track achievements! 🏆
                        if achievement_progress then
                            achievement_progress(player, "unlock_first_ability", 1)
                            
                            -- Count total abilities unlocked
                            local total_unlocked = 0
                            for _, lvl in pairs(data.unlocked) do
                                if lvl > 0 then
                                    total_unlocked = total_unlocked + 1
                                end
                            end
                            
                            if total_unlocked >= 5 then
                                achievement_progress(player, "unlock_5_abilities", 1)
                            end
                            
                            -- Check if maxed out
                            if data.unlocked[ability_id] >= ability.max_level then
                                achievement_progress(player, "max_ability", 1)
                            end
                            
                            -- Check if all movement abilities unlocked
                            local all_movement = true
                            for _, ab in ipairs(abilities) do
                                if ab.category == "movement" and (data.unlocked[ab.id] or 0) == 0 then
                                    all_movement = false
                                    break
                                end
                            end
                            if all_movement then
                                achievement_progress(player, "unlock_all_movement", 1)
                            end
                        end
                        
                        minetest.chat_send_player(name, 
                            "✨ Unlocked " .. ability.name .. " Level " .. data.unlocked[ability_id] .. "!")
                        break
                    end
                end
            else
                minetest.chat_send_player(name, "❌ " .. msg)
            end
        end
    end
    
    -- Handle reset
    if fields.reset_abilities then
        if data.stat_points >= 5 then
            -- Refund all spent points
            local refund = 0
            for _, ability in ipairs(abilities) do
                local level = data.unlocked[ability.id] or 0
                refund = refund + (level * ability.cost)
            end
            
            -- Reset
            data.unlocked = {}
            data.stat_points = data.stat_points - 5 + refund
            
            save_ability_data(player, data)
            apply_abilities(player)
            
            minetest.chat_send_player(name, "✨ Abilities reset! Refunded " .. refund .. " stat points.")
        else
            minetest.chat_send_player(name, "❌ Need 5 stat points to reset!")
        end
    end
    
    -- Refresh formspec
    minetest.show_formspec(name, "ability_tree", get_ability_formspec(player))
end)

-- Hook into the give_experience function from experience_system
local original_give_experience = give_experience
if original_give_experience then
    function give_experience(player, amount)
        local name = player:get_player_name()
        local meta = player:get_meta()
        local old_exp = tonumber(meta:get_string("experience")) or 0
        local old_level = math.floor(old_exp / 100) + 1
        
        -- Call original function
        local leveled_up = original_give_experience(player, amount)
        
        if leveled_up then
            -- Grant 2 stat points per level
            local data = get_ability_data(player)
            data.stat_points = data.stat_points + 2
            save_ability_data(player, data)
            
            minetest.chat_send_player(name, 
                "🌟 Gained 2 stat points! Type /abilities to spend them!")
        end
        
        return leveled_up
    end
end

-- Apply abilities on join
minetest.register_on_joinplayer(function(player)
    minetest.after(1, function()
        if minetest.get_player_by_name(player:get_player_name()) then
            apply_abilities(player)
        end
    end)
end)

-- Command to open ability tree
minetest.register_chatcommand("abilities", {
    description = "Open ability tree",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            minetest.show_formspec(name, "ability_tree", get_ability_formspec(player))
            return true, "Opening ability tree!"
        end
        return false, "Player not found"
    end
})

minetest.log("action", "[ability_system] Ability tree system loaded! 🌟")
