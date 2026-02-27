-- Unified Inventory with Tabs! 💫✨
-- Brings together Crafting, Abilities, and future tabs

-- Get current tab for player
local function get_current_tab(player)
    local meta = player:get_meta()
    local tab = meta:get_string("current_tab")
    if tab == "" then tab = "crafting" end
    return tab
end

-- Set current tab
local function set_current_tab(player, tab)
    player:get_meta():set_string("current_tab", tab)
end

-- Generate tab buttons (square icons on right side)
-- Made global so other GUIs (like the outfit menu) can reuse it.
function gui_get_tab_buttons(current_tab, show_label)
    local tabs = {
        {id = "crafting", icon = "🔨", icon_img = "gui_tab_crafting.png", label = "Crafting", x = 9.5},
        {id = "abilities", icon = "⚡", icon_img = "gui_tab_abilities.png", label = "Abilities", x = 10.3},
        {id = "achievements", icon = "🏆", icon_img = "gui_tab_achievements.png", label = "Achievements", x = 11.1},
    }
    
    local formspec = {}
    
    -- Show current location label only if not on crafting tab
    if show_label ~= false and current_tab ~= "crafting" then
        for _, tab in ipairs(tabs) do
            if tab.id == current_tab then
                table.insert(formspec, string.format("label[0.3,1.5;► %s]", tab.label))
                break
            end
        end
    end
    
    -- Draw square tab buttons (0.75 size) with icons
    for _, tab in ipairs(tabs) do
        if tab.id == current_tab then
            -- Active tab - bright green with glow
            table.insert(formspec, string.format("box[%f,0.3;0.75,0.75;#5a9a5aff]", tab.x))
            table.insert(formspec, string.format("box[%f,0.3;0.75,0.75;#7aca7a55]", tab.x))
        else
            -- Inactive tab - dark gray
            table.insert(formspec, string.format("box[%f,0.3;0.75,0.75;#3a3a3aff]", tab.x))
        end
        -- Use image_button with icon image
        table.insert(formspec, string.format("image_button[%f,0.3;0.75,0.75;%s;tab_%s;]", 
            tab.x, tab.icon_img, tab.id))
    end
    
    return table.concat(formspec, "")
end

-- Generate unified inventory formspec
function get_unified_inventory(player)
    local current_tab = get_current_tab(player)
    
    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",
    }
    
    -- Add tab buttons
    table.insert(formspec, gui_get_tab_buttons(current_tab))
    
    -- Add content based on current tab
    if current_tab == "crafting" then
        -- Get crafting content (without its own header)
        if get_crafting_formspec then
            local meta = player:get_meta()
            local cat = meta:get_string("crafting_category")
            if cat == "" then cat = "basic" end
            local craft_fs = get_crafting_formspec(player, cat)
            -- Extract just the content part (skip size, bgcolor, first few lines)
            local content_start = craft_fs:find("-- Search bar") or craft_fs:find("field%[0%.3")
            if content_start then
                -- Get everything from search bar onwards
                local content = craft_fs:sub(content_start)
                table.insert(formspec, content)
            end
        else
            table.insert(formspec, "label[4,5;Crafting system loading...]")
        end
        
    elseif current_tab == "abilities" then
        -- Get NEW ability content with graph!
        if get_ability_formspec_new then
            local ability_fs = get_ability_formspec_new(player)
            -- Extract content (skip size, bgcolor, formspec_version)
            local content_start = ability_fs:find("box%[0%.2,0%.3")
            if content_start then
                local content = ability_fs:sub(content_start)
                table.insert(formspec, content)
            else
                table.insert(formspec, ability_fs)
            end
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[4,5;Ability system loading...]")
        end
        
    elseif current_tab == "achievements" then
        -- Get achievement content
        if get_achievement_formspec then
            local ach_fs = get_achievement_formspec(player)
            -- The formspec is returned as concatenated string - we need to extract elements
            -- Skip header (formspec_version, size, bgcolor) - find first actual element
            local content_start = ach_fs:find("box%[0%.2")
            if content_start then
                local content = ach_fs:sub(content_start)
                table.insert(formspec, content)
            else
                -- Fallback - just add the whole thing
                table.insert(formspec, ach_fs)
            end
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[4,5;Achievement system loading...]")  
        end
    end
    
    return table.concat(formspec, "")
end

-- Handle tab switching
minetest.register_on_player_receive_fields(function(player, formname, fields)
    -- Only handle empty formname (inventory formspec)
    if formname ~= "" and formname ~= "crafting_system" and formname ~= "unified_inventory" then
        return
    end
    
    if fields.quit then
        return
    end
    
    local name = player:get_player_name()
    local changed_tab = false
    
    -- Tab switching
    if fields.tab_crafting then
        set_current_tab(player, "crafting")
        changed_tab = true
    elseif fields.tab_abilities then
        set_current_tab(player, "abilities")
        changed_tab = true
    elseif fields.tab_achievements then
        set_current_tab(player, "achievements")
        changed_tab = true
    end
    
    -- If tab changed, update inventory formspec
    if changed_tab then
        player:set_inventory_formspec(get_unified_inventory(player))
        return
    end

    -- Clicking the player preview overlay button from any tab
    if fields.open_outfit then
        minetest.show_formspec(player:get_player_name(), "character_outfit", get_character_outfit_formspec(player, "HEAD"))
        return
    end
    
    -- Let other systems handle their own fields
    -- Crafting system will handle craft buttons, search, etc
    -- Ability system will handle unlock buttons, stat changes, toggles, graph panning, etc
end)

-- Set unified inventory on join
minetest.register_on_joinplayer(function(player)
    minetest.after(0.5, function()
        if minetest.get_player_by_name(player:get_player_name()) then
            set_current_tab(player, "crafting") -- Default to crafting tab
            player:set_inventory_formspec(get_unified_inventory(player))
        end
    end)
end)

minetest.log("action", "[unified_inventory] Tab system loaded! 💫")
