-- Running/Sprint System with Aux1 key support! 🏃💨
-- Integrates with ability_system_new.lua

-- Configuration
local SPRINT_SPEED_MULTIPLIER = 1.5  -- Base sprint speed boost
local SPRINT_JUMP_MULTIPLIER = 1.2   -- Sprint jump boost
local SPRINT_FOV_MULTIPLIER = 1.1    -- Field of view increase when sprinting
local SPRINT_STAMINA_DRAIN = 0.5     -- Stamina drain per second (if stamina system exists)

-- Track player sprint states
local sprint_states = {}
local sprint_huds = {}

-- Get running-related ability modifiers from ability_system_new
local function get_run_ability_modifiers(player)
    if not player then return nil end
    
    -- Access ability data from ability_system_new
    local meta = player:get_meta()
    if not meta then return nil end
    
    local data_str = meta:get_string("abilities_v2")
    if not data_str or data_str == "" then data_str = "{}" end
    
    local data = minetest.deserialize(data_str) or {}
    
    local modifiers = {
        sprint_speed_bonus = 0,
        max_stamina = 100,
        stamina_drain_multiplier = 1.0,
        sprint_enabled = true,
        dash_active = false
    }
    
    -- Check for run-related abilities
    if data.unlocked then
        -- run_speed ability adds to sprint multiplier
        local run_speed_level = data.unlocked["run_speed"] or 0
        if run_speed_level > 0 then
            modifiers.sprint_speed_bonus = run_speed_level * 0.1  -- +10% per level
        end
        
        -- sprint_stamina ability increases max stamina
        local stamina_level = data.unlocked["sprint_stamina"] or 0
        if stamina_level > 0 then
            modifiers.max_stamina = 100 + (stamina_level * 20)
        end
        
        -- sprint_efficiency reduces stamina drain
        local efficiency_level = data.unlocked["sprint_efficiency"] or 0
        if efficiency_level > 0 then
            modifiers.stamina_drain_multiplier = 1.0 - (efficiency_level * 0.15)
        end
        
        -- Check for dash ability (if unlocked and toggled, 10x speed + 500x drain)
        local dash_level = data.unlocked["move_dash"] or 0
        if dash_level > 0 and data.toggles and data.toggles["move_dash"] then
            modifiers.dash_active = true
            modifiers.sprint_speed_bonus = modifiers.sprint_speed_bonus + 9.0  -- Additional +9.0 = 10x total
            modifiers.stamina_drain_multiplier = modifiers.stamina_drain_multiplier * 500  -- 500x drain!
        end
    end
    
    return modifiers
end

-- Get player sprint data
local function get_sprint_data(player)
    if not player then return nil end
    local name = player:get_player_name()
    if not name then return nil end
    
    if not sprint_states[name] then
        local modifiers = get_run_ability_modifiers(player)
        if not modifiers then return nil end
        
        local pos = player:get_pos()
        if not pos then return nil end
        
        sprint_states[name] = {
            is_sprinting = false,
            last_pos = pos,
            stamina = modifiers.max_stamina or 100,
            max_stamina = modifiers.max_stamina or 100
        }
    end
    -- Update max stamina based on abilities
    local modifiers = get_run_ability_modifiers(player)
    if modifiers then
        sprint_states[name].max_stamina = modifiers.max_stamina
    end
    return sprint_states[name]
end

-- Apply sprint physics
local function apply_sprint(player, enable)
    if not player then return end
    
    local sprint_data = get_sprint_data(player)
    if not sprint_data then return end
    
    local modifiers = get_run_ability_modifiers(player)
    if not modifiers then return end
    
    -- Get current physics from ability system
    local meta = player:get_meta()
    if not meta then return end
    
    local data_str = meta:get_string("abilities_v2")
    if not data_str or data_str == "" then data_str = "{}" end
    
    local ability_data = minetest.deserialize(data_str) or {}
    
    -- Get base speed from ability system or default
    local base_speed = (ability_data.stat_values and ability_data.stat_values.speed) or 1.0
    local base_jump = (ability_data.stat_values and ability_data.stat_values.jump) or 1.0
    
    if enable then
        -- Apply sprint multipliers
        local sprint_mult = SPRINT_SPEED_MULTIPLIER + modifiers.sprint_speed_bonus
        player:set_physics_override({
            speed = base_speed * sprint_mult,
            jump = base_jump * SPRINT_JUMP_MULTIPLIER,
        })
        
        -- Apply FOV effect
        player:set_fov(0, false, SPRINT_FOV_MULTIPLIER)
        
        sprint_data.is_sprinting = true
    else
        -- Restore base physics from ability system
        player:set_physics_override({
            speed = base_speed,
            jump = base_jump,
        })
        
        -- Reset FOV
        player:set_fov(0, false, 0)
        
        sprint_data.is_sprinting = false
    end
end

-- Check if player can sprint
local function can_sprint(player)
    if not player then return false end
    
    local sprint_data = get_sprint_data(player)
    if not sprint_data then return false end
    
    local modifiers = get_run_ability_modifiers(player)
    if not modifiers then return false end
    
    -- Always allow if infinite sprint is enabled
    if modifiers.infinite_sprint then
        return true
    end
    
    -- Check stamina
    if sprint_data.stamina <= 0 then
        return false
    end
    
    -- If dash is active and stamina is very low, warn by disabling sprint
    if modifiers.dash_active and sprint_data.stamina < 5 then
        return false
    end
    
    -- Check if player is moving
    local controls = player:get_player_control()
    if not controls then return false end
    if not (controls.up or controls.down or controls.left or controls.right) then
        return false
    end
    
    -- Check if player is in liquid (can't sprint in water without swim ability)
    local pos = player:get_pos()
    if not pos then return false end
    
    local node_at_feet = minetest.get_node({x=pos.x, y=pos.y, z=pos.z})
    if not node_at_feet then return true end  -- Can't check, assume OK
    
    local node_def = minetest.registered_nodes[node_at_feet.name]
    if node_def and node_def.liquidtype ~= "none" then
        return false
    end
    
    return true
end

-- Update sprint HUD
local function update_sprint_hud(player)
    if not player then return end
    
    local name = player:get_player_name()
    if not name then return end
    
    local sprint_data = get_sprint_data(player)
    if not sprint_data then return end
    
    local modifiers = get_run_ability_modifiers(player)
    if not modifiers then return end
    
    -- Check if HUD should be shown
    local meta = player:get_meta()
    if not meta then return end
    
    local data_str = meta:get_string("abilities_v2")
    if not data_str or data_str == "" then data_str = "{}" end
    
    local ability_data = minetest.deserialize(data_str) or {}
    
    local show_hud = true  -- Default to showing HUD
    if ability_data.unlocked and ability_data.unlocked["sprint_hud"] then
        show_hud = ability_data.toggles and ability_data.toggles["sprint_hud"] or false
    end
    
    -- Remove HUD if it should be hidden
    if not show_hud and sprint_huds[name] then
        pcall(function()
            player:hud_remove(sprint_huds[name])
        end)
        sprint_huds[name] = nil
        return
    end
    
    -- Don't create HUD if it shouldn't be shown
    if not show_hud then
        return
    end
    
    -- Create HUD if it doesn't exist
    if not sprint_huds[name] then
        local success, hud_id = pcall(function()
            return player:hud_add({
                hud_elem_type = "text",
                position = {x = 0.5, y = 0.95},
                offset = {x = 0, y = 0},
                text = "🏃 Stamina: 100/100",
                alignment = {x = 0, y = 0},
                scale = {x = 100, y = 100},
                number = 0xFFFFFF,
            })
        end)
        if success then
            sprint_huds[name] = hud_id
        end
    end
    
    -- Update stamina display
    if sprint_huds[name] then
        local stamina_text
        
        -- Calculate stamina bar (used by both modes)
        local bar_length = 10
        local filled = math.floor((sprint_data.stamina / sprint_data.max_stamina) * bar_length)
        local bar = string.rep("█", filled) .. string.rep("░", bar_length - filled)
        
        -- Show dash mode indicator
        if modifiers.dash_active then
            stamina_text = string.format("💨 DASH MODE [%s] %d/%d", 
                bar, math.floor(sprint_data.stamina), sprint_data.max_stamina)
            -- Always show red when in dash mode to indicate danger
            pcall(function()
                player:hud_change(sprint_huds[name], "number", 0xFF6600)  -- Orange
            end)
        else
            
            -- Color based on stamina level
            local color
            local percentage = sprint_data.stamina / sprint_data.max_stamina
            if percentage > 0.6 then
                color = 0x00FF00  -- Green
            elseif percentage > 0.3 then
                color = 0xFFFF00  -- Yellow
            else
                color = 0xFF0000  -- Red
            end
            
            stamina_text = string.format("🏃 Stamina: [%s] %d/%d", 
                bar, math.floor(sprint_data.stamina), sprint_data.max_stamina)
            pcall(function()
                player:hud_change(sprint_huds[name], "number", color)
            end)
        end
        
        pcall(function()
            player:hud_change(sprint_huds[name], "text", stamina_text)
        end)
    end
end

-- Combined globalstep for sprint mechanics and HUD updates
local hud_update_timer = 0
minetest.register_globalstep(function(dtime)
    hud_update_timer = hud_update_timer + dtime
    
    for _, player in ipairs(minetest.get_connected_players()) do
        if player then
            local controls = player:get_player_control()
            if not controls then goto continue end
            
            local sprint_data = get_sprint_data(player)
            if not sprint_data then goto continue end
            
            local modifiers = get_run_ability_modifiers(player)
            if not modifiers then goto continue end
            
            -- Check if Aux1 is pressed (sprint key)
            if controls.aux1 and can_sprint(player) then
                if not sprint_data.is_sprinting then
                    apply_sprint(player, true)
                end
                
                -- Drain stamina (unless infinite sprint)
                if not modifiers.infinite_sprint then
                    local drain_rate = SPRINT_STAMINA_DRAIN * modifiers.stamina_drain_multiplier
                    sprint_data.stamina = math.max(0, sprint_data.stamina - (drain_rate * dtime))
                end
            else
                if sprint_data.is_sprinting then
                    apply_sprint(player, false)
                end
                
                -- Regenerate stamina when not sprinting
                sprint_data.stamina = math.min(sprint_data.max_stamina, 
                    sprint_data.stamina + (SPRINT_STAMINA_DRAIN * 2 * dtime))
            end
            
            -- Update HUD every 0.1 seconds
            if hud_update_timer >= 0.1 then
                update_sprint_hud(player)
            end
        end
        ::continue::
    end
    
    if hud_update_timer >= 0.1 then
        hud_update_timer = 0
    end
end)

-- Clean up on player leave
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    sprint_states[name] = nil
    sprint_huds[name] = nil
end)

-- Restore physics when player joins (in case they logged out while sprinting)
minetest.register_on_joinplayer(function(player)
    minetest.after(0.5, function()
        if minetest.get_player_by_name(player:get_player_name()) then
            apply_sprint(player, false)
        end
    end)
end)

-- Export function to check if player is sprinting (for other mods)
function is_player_sprinting(player)
    if not player then return false end
    local sprint_data = get_sprint_data(player)
    if not sprint_data then return false end
    return sprint_data.is_sprinting
end

-- Export function to get sprint stamina (for HUD display)
function get_player_sprint_stamina(player)
    if not player then return 0, 100 end
    local sprint_data = get_sprint_data(player)
    if not sprint_data then return 0, 100 end
    return sprint_data.stamina, sprint_data.max_stamina
end

minetest.log("action", "[running_system] Sprint system with Aux1 key loaded! 🏃💨")
