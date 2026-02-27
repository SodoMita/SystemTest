-- Character outfit configuration menu
-- Opens from clicking the 3d player preview in any GUI tab

local function get_player_textures(player)
    local tex = {"character.png"}
    if player_api and player_api.get_textures then
        tex = player_api.get_textures(player) or tex
    end
    return tex
end

-- Slots and their human labels
local outfit_slots = {
    { key = "HEAD",   label = "Head" },
    { key = "TORSO",  label = "Torso" },
    { key = "BACK",   label = "Back" },
    { key = "L_HAND", label = "L hand" },
    { key = "R_HAND", label = "R hand" },
    { key = "L_LEG",  label = "L leg" },
    { key = "R_LEG",  label = "R leg" },
    { key = "L_FOOT", label = "L foot" },
    { key = "R_FOOT", label = "R foot" },
}

-- Helper to find items in player's inventory that fit a specific slot
local function get_player_outfit_items(player, slot_key)
    local inv = player:get_inventory()
    if not inv then return {} end
    
    local candidates = {}
    local list = inv:get_list("main")
    local target_group = "outfit_" .. slot_key:lower()
    
    for i, stack in ipairs(list) do
        if not stack:is_empty() then
            local def = stack:get_definition()
            if def and def.groups and def.groups[target_group] then
                table.insert(candidates, {
                    id = stack:get_name(),
                    name = def.description,
                    type = "Clothing", -- Could be refined based on more groups
                    weight = def._outfit_weight or 0,
                    desc = def.description, -- Use description as desc for now
                    texture = def.inventory_image,
                    inv_index = i -- Store index to potentially grab/move it later
                })
            end
        end
    end
    return candidates
end

local function get_equipped(player)
    local meta = player:get_meta()
    local equipped = {}
    for _, slot in ipairs(outfit_slots) do
        local key = "outfit_" .. slot.key
        local id = meta:get_string(key)
    if id == "" then
        -- No default for real inventory items if nothing found
        id = nil
    end
        equipped[slot.key] = id
    end
    return equipped
end

local function set_equipped(player, slot_key, item_id)
    local meta = player:get_meta()
    meta:set_string("outfit_" .. slot_key, item_id)
end

local function get_item(slot_key, item_id)
    -- For real items, we can just check minetest.registered_items
    if not item_id or item_id == "" then return nil end
    
    local def = minetest.registered_items[item_id]
    if def then
        return {
            id = item_id,
            name = def.description,
            type = "Clothing",
            weight = def._outfit_weight or 0,
            desc = def.description,
            texture = def.inventory_image
        }
    end
    return nil
end

local function calc_total_weight(equipped)
    local total = 0
    for _, slot in ipairs(outfit_slots) do
        local id = equipped[slot.key]
        local it = id and get_item(slot.key, id)
        if it and it.weight then
            total = total + it.weight
        end
    end
    return total
end

-- Returns formspec string for the outfit window.
function get_character_outfit_formspec(player, selected_slot)
    if not selected_slot then
        selected_slot = "HEAD"
    end
    local name = player:get_player_name()
    local tex = get_player_textures(player)
    local equipped = get_equipped(player)
    local total_weight = calc_total_weight(equipped)
    local meta = player:get_meta()
    local current_tab = meta:get_string("current_tab")
    if current_tab == "" then current_tab = "crafting" end

    -- ensure selected_slot is valid
    local is_valid = false
    for _, s in ipairs(outfit_slots) do
        if s.key == selected_slot then is_valid = true break end
    end
    if not is_valid then selected_slot = "HEAD" end

    local current_item = get_item(selected_slot, equipped[selected_slot])

    local fs = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",
    }

    -- Reuse the same tab strip as the unified inventory so it feels like a sub-page
    if gui_get_tab_buttons then
        -- Pass false to NOT show the text label, just the square icons to match other pages
        table.insert(fs, gui_get_tab_buttons(current_tab, false))
    end

    -- subtle top band
    table.insert(fs, "box[0,0;12,0.6;#1a1a1aff]")

    -- bigger preview model
    table.insert(fs, "box[0.2,1.0;3.5,3.5;#101010ff]")
    table.insert(fs, string.format(
        "model[0.3,1.1;3.3,3.3;outfit_preview;character.b3d;%s;0,170;false;true;0,0]",
        table.concat(tex, ",")
    ))

    -- body slot buttons - pushed slightly right/down to account for bigger model
    -- head (above)
    table.insert(fs, "button[1.4,0.4;1.0,0.6;slot_HEAD;Head]")
    
    -- left side
    table.insert(fs, "button[0.0,1.8;0.9,0.6;slot_TORSO;Torso]")
    table.insert(fs, "button[0.0,2.6;0.9,0.6;slot_L_HAND;L]")
    
    -- right side
    table.insert(fs, "button[3.1,1.8;0.9,0.6;slot_BACK;Back]")
    table.insert(fs, "button[3.1,2.6;0.9,0.6;slot_R_HAND;R]")

    -- below
    table.insert(fs, "button[0.6,4.6;0.9,0.6;slot_L_LEG;L leg]")
    table.insert(fs, "button[2.4,4.6;0.9,0.6;slot_R_LEG;R leg]")
    table.insert(fs, "button[1.0,5.3;0.9,0.6;slot_L_FOOT;L ft]")
    table.insert(fs, "button[2.0,5.3;0.9,0.6;slot_R_FOOT;R ft]")

    -- right side: vertical list of items for current slot
    table.insert(fs, "box[4.2,0.8;7.5,4.8;#101010ff]")
    table.insert(fs, string.format("label[4.4,0.9;Select %s item:]", selected_slot))

    local list = get_player_outfit_items(player, selected_slot)
    
    -- Scroll container for the item list
    table.insert(fs, "scroll_container[4.4,1.3;7.1,4.1;item_list_scroll;vertical]")
    
    local y = 0
    for idx, it in ipairs(list) do
        local btn_name = string.format("pick_%s_%d", selected_slot, idx)
        local label = it.name
        
        -- Different style for equipped item
        if equipped[selected_slot] == it.id then
            table.insert(fs, string.format("box[0,%f;6.9,0.8;#2a2a2aff]", y))
            label = "✓ " .. label
        else
            table.insert(fs, string.format("box[0,%f;6.9,0.8;#1a1a1aff]", y))
        end
        
        -- Button acts as list item row
        table.insert(fs, string.format("style[%s;bgcolor=#00000000;border=false;textcolor=#cccccc]", btn_name))
        table.insert(fs, string.format("button[0,%f;6.9,0.8;%s;%s]", y, btn_name, minetest.formspec_escape(label)))
        
        y = y + 0.9
    end
    
    table.insert(fs, "scroll_container_end[]")
    
    -- Scrollbar if needed
    if y > 4.1 then
        table.insert(fs, "scrollbar[11.6,1.3;0.2,4.1;vertical;item_list_scroll;0]")
    end

    -- bottom: details and equipped slot
    table.insert(fs, "box[0.2,6.2;11.6,4.8;#101010ff]")

    -- Show the currently equipped item in this slot (detached inventory or meta)
    table.insert(fs, "label[0.5,6.5;Currently equipped:]")
    -- We display the item icon if we can, or just name
    local equipped_id = equipped[selected_slot]
    local current_item = get_item(selected_slot, equipped_id)
    
    if current_item then
        table.insert(fs, string.format("label[0.5,7.0;%s]", minetest.formspec_escape(current_item.name)))
        table.insert(fs, string.format("textarea[0.5,7.5;11.0,2.0;;;%s]", minetest.formspec_escape(current_item.desc)))
        table.insert(fs, string.format("label[0.5,9.5;Weight: %.1f kg]", current_item.weight))
    else
        table.insert(fs, "label[0.5,7.0;Nothing equipped]")
    end
    
    table.insert(fs, string.format("label[8.5,9.5;Total carried: %.1f kg]", total_weight))
    table.insert(fs, "image_button[9.0,10.2;2.6,0.8;gui_button_done.png;outfit_close;Done]")

    return table.concat(fs, "")
end

-- Handle fields from this formspec
function handle_character_outfit_fields(player, formname, fields)
    if formname ~= "character_outfit" then
        return false
    end

    if fields.outfit_close or fields.quit then
        -- Just close; unified inventory will still be open behind
        return true
    end

    local selected_slot = nil

    -- Tab switching: properly close this formspec and open unified inventory
    if fields.tab_crafting or fields.tab_abilities or fields.tab_achievements then
        local meta = player:get_meta()
        local new_tab = "crafting"
        if fields.tab_abilities then new_tab = "abilities"
        elseif fields.tab_achievements then new_tab = "achievements" end
        
        meta:set_string("current_tab", new_tab)
        
        -- Close current formspec
        minetest.close_formspec(player:get_player_name(), "character_outfit")
        
        -- Open unified inventory (after a tiny delay to ensure clean switch if needed, or direct)
        if get_unified_inventory then
             minetest.after(0.1, function()
                player:set_inventory_formspec(get_unified_inventory(player))
             end)
        end
        return true
    end

    -- Slot selection buttons around the preview
    for _, slot in ipairs(outfit_slots) do
        local field_name = "slot_" .. slot.key
        if fields[field_name] then
            selected_slot = slot.key
            break
        end
    end

    -- Item picking buttons
    if not selected_slot then
        for _, slot in ipairs(outfit_slots) do
            local list = get_player_outfit_items(player, slot.key)
            for idx, it in ipairs(list) do
                local field_name = string.format("pick_%s_%d", slot.key, idx)
                if fields[field_name] then
                    set_equipped(player, slot.key, it.id)
                    selected_slot = slot.key
                    break
                end
            end
            if selected_slot then break end
        end
    end

    if not selected_slot then
        selected_slot = "HEAD"
    end

    minetest.show_formspec(player:get_player_name(), "character_outfit", get_character_outfit_formspec(player, selected_slot))
    return true
end
