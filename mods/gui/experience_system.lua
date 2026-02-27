-- Experience and Leveling System! 🌟✨

local huds = {}

-- Calculate level from experience
local function get_level(exp)
    return math.floor(exp / 100) + 1
end

-- Calculate XP needed for next level
local function xp_for_next_level(level)
    return (level) * 100
end

-- Get current level progress (0-1)
local function get_level_progress(exp)
    local level = get_level(exp)
    local current_level_xp = (level - 1) * 100
    local next_level_xp = level * 100
    local progress = (exp - current_level_xp) / (next_level_xp - current_level_xp)
    return math.max(0, math.min(1, progress))
end

-- Update player's HUD
local function update_hud(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    local exp = tonumber(meta:get_string("experience")) or 0
    local level = get_level(exp)
    local progress = get_level_progress(exp)
    local xp_needed = xp_for_next_level(level)
    local current_xp = exp - ((level - 1) * 100)
    
    if not huds[name] then
        huds[name] = {}
        
        -- Level display
        huds[name].level = player:hud_add({
            hud_elem_type = "text",
            position = {x = 1, y = 0},
            offset = {x = -120, y = 20},
            text = "Level " .. level,
            number = 0xFFFFFF,
            alignment = {x = -1, y = 0},
            scale = {x = 100, y = 100},
        })
        
        -- XP text (moved much higher to avoid HP/hunger bars)
        huds[name].xp_text = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.5, y = 1},
            offset = {x = 0, y = -120},
            text = string.format("%d / %d XP", current_xp, xp_needed),
            number = 0x4a9aff,
            alignment = {x = 0, y = 0},
            scale = {x = 100, y = 100},
        })
    else
        -- Update existing HUD elements
        player:hud_change(huds[name].level, "text", "Level " .. level)
        player:hud_change(huds[name].xp_text, "text", 
            string.format("%d / %d XP", current_xp, xp_needed))
    end
end

-- Initialize player
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    
    -- Initialize experience if not set
    if meta:get_string("experience") == "" then
        meta:set_string("experience", "0")
    end
    
    -- Create HUD after short delay to ensure player is fully loaded
    minetest.after(0.5, function()
        if minetest.get_player_by_name(name) then
            update_hud(player)
        end
    end)
end)

-- Clean up on leave
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    huds[name] = nil
end)

-- Give experience function (can be called from other mods)
function give_experience(player, amount)
    local name = player:get_player_name()
    local meta = player:get_meta()
    local old_exp = tonumber(meta:get_string("experience")) or 0
    local old_level = get_level(old_exp)
    local new_exp = old_exp + amount
    local new_level = get_level(new_exp)
    
    meta:set_string("experience", tostring(new_exp))
    update_hud(player)
    
    -- Check for level up!
    if new_level > old_level then
        minetest.chat_send_player(name, 
            "✨ LEVEL UP! ✨ You are now level " .. new_level .. "!")
        -- Play sound effect if available
        minetest.sound_play("level_up", {
            to_player = name,
            gain = 1.0,
        }, true)
    end
    
    return new_level > old_level
end

-- Give XP for various actions
minetest.register_on_dignode(function(pos, oldnode, digger)
    if digger and digger:is_player() then
        give_experience(digger, 1) -- Small XP for digging
    end
end)

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
    if placer and placer:is_player() then
        give_experience(placer, 1) -- Small XP for placing
    end
end)

-- Update HUD periodically (in case of manual changes)
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer >= 5 then
        timer = 0
        for _, player in ipairs(minetest.get_connected_players()) do
            update_hud(player)
        end
    end
end)

-- Command to check XP
minetest.register_chatcommand("xp", {
    description = "Check your experience and level",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            local meta = player:get_meta()
            local exp = tonumber(meta:get_string("experience")) or 0
            local level = get_level(exp)
            local progress = get_level_progress(exp) * 100
            return true, string.format("Level %d | %d XP | %.1f%% to next level", 
                level, exp, progress)
        end
        return false, "Player not found"
    end
})

-- Admin command to give XP
minetest.register_chatcommand("givexp", {
    params = "<player> <amount>",
    description = "Give experience to a player",
    privs = {server = true},
    func = function(name, param)
        local target_name, amount_str = param:match("^(%S+)%s+(%S+)$")
        if not target_name or not amount_str then
            return false, "Usage: /givexp <player> <amount>"
        end
        
        local amount = tonumber(amount_str)
        if not amount then
            return false, "Invalid amount"
        end
        
        local target = minetest.get_player_by_name(target_name)
        if not target then
            return false, "Player not found"
        end
        
        give_experience(target, amount)
        return true, string.format("Gave %d XP to %s", amount, target_name)
    end
})

minetest.log("action", "[experience_system] Experience system loaded! 🌟")
