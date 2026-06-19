-- Character outfit / player info menu
-- Opens from clicking the 3D player preview in any GUI tab.

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

-- Use the System Looting boxman model for previews
local function get_preview_model(player)
    if sl_characters and sl_characters.default_model then
        local tex = sl_characters.default_texture or "sl_boxman_neon.png"
        return sl_characters.default_model, {tex, tex, tex, tex, tex, tex, tex, tex}
    end
    local tex = {"character.png", "character.png", "character.png", "character.png", "character.png", "character.png"}
    if player_api and player_api.get_textures then
        local ptex = player_api.get_textures(player)
        if ptex and #ptex > 0 then
            tex = {}
            for i=1,8 do tex[i] = ptex[1] end
        end
    end
    return "character.b3d", tex
end

-- Helper to find items in the player's inventory that fit a specific slot
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
                    type = "Clothing",
                    weight = def._outfit_weight or 0,
                    desc = def.description,
                    texture = def.inventory_image,
                    inv_index = i,
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
        if id == "" then id = nil end
        equipped[slot.key] = id
    end
    return equipped
end

local function set_equipped(player, slot_key, item_id)
    local meta = player:get_meta()
    meta:set_string("outfit_" .. slot_key, item_id)
end

local function get_item(slot_key, item_id)
    if not item_id or item_id == "" then return nil end
    local def = minetest.registered_items[item_id]
    if def then
        return {
            id = item_id,
            name = def.description,
            type = "Clothing",
            weight = def._outfit_weight or 0,
            desc = def.description,
            texture = def.inventory_image,
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

-- Build player info text for the outfit menu's right-hand panel
local function build_player_info(player)
    local name = player:get_player_name()
    local meta = player:get_meta()

    local exp = tonumber(meta:get_string("experience")) or 0
    local level = math.floor(exp / 100) + 1
    local xp_pct = math.floor((exp % 100))

    local hp = player:get_hp()
    local props = player:get_properties()
    local hp_max = props.hp_max or 20
    local breath = player:get_breath()
    local breath_max = props.breath_max or 10

    local lines = {
        string.format("Name: %s", minetest.formspec_escape(name)),
        string.format("Level: %d  XP: %d/100", level, xp_pct),
        string.format("HP: %d / %d", hp, hp_max),
        string.format("Breath: %d / %d", breath, breath_max),
    }

    if get_player_sprint_stamina then
        local stam, stam_max = get_player_sprint_stamina(player)
        table.insert(lines, string.format("Stamina: %d / %d", math.floor(stam), stam_max))
    end

    local gm = rawget(_G, "game_mode")
    if gm and gm.state then
        local state = gm.state
        local pl = gm.get_player_state(name)

        local role_label = "Player"
        if pl and pl.role == "monster_master" then role_label = "Monster Master" end
        table.insert(lines, "Role: " .. role_label)

        if pl and pl.team then
            local team_label = gm.get_team_label and gm.get_team_label(pl.team) or pl.team
            local team_color = gm.get_team_color and gm.get_team_color(pl.team) or "#cccccc"
            table.insert(lines, "Team: " .. minetest.colorize(team_color, team_label))
        else
            table.insert(lines, "Team: None")
        end

        if pl then
            table.insert(lines, string.format("Lives: %d", pl.lives or 0))
            table.insert(lines, pl.eliminated and "Status: ELIMINATED" or "Status: Active")
        end

        if state.match_active then
            table.insert(lines, string.format("Match #%d — In Progress", state.match_count or 0))
        else
            table.insert(lines, "No active match")
        end
    end

    -- Active abilities (from the graph system)
    local ab_str = meta:get_string("abilities_v2")
    if ab_str ~= "" then
        local ab_data = minetest.deserialize(ab_str) or {}
        local ability_names = {}
        if ab_data.unlocked then
            for ab_id, lvl in pairs(ab_data.unlocked) do
                if lvl > 0 then
                    table.insert(ability_names, string.format("%s Lv%d", ab_id, lvl))
                end
            end
        end
        if #ability_names > 0 then
            table.insert(lines, "Abilities: " .. table.concat(ability_names, ", "))
        else
            table.insert(lines, "No abilities unlocked")
        end
        table.insert(lines, string.format("Stat Points: %d", ab_data.stat_points or 0))
    end

    return table.concat(lines, "\n")
end

-- Returns formspec string for the outfit / player info window.
function get_character_outfit_formspec(player, selected_slot)
    if not selected_slot then
        selected_slot = "HEAD"
    end
    local name = player:get_player_name()
    local model_name, tex = get_preview_model(player)
    local equipped = get_equipped(player)
    local total_weight = calc_total_weight(equipped)
    local meta = player:get_meta()
    local current_tab = meta:get_string("current_tab")
    if current_tab == "" then current_tab = "crafting" end

    local is_valid = false
    for _, s in ipairs(outfit_slots) do
        if s.key == selected_slot then is_valid = true break end
    end
    if not is_valid then selected_slot = "HEAD" end

    local fs = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",
    }

    -- Background boxes FIRST
    table.insert(fs, "box[0,0;12,0.6;#1a1a1aff]")
    table.insert(fs, "box[0.2,1.0;3.5,3.5;#101010ff]")
    table.insert(fs, "box[4.2,0.8;7.5,4.8;#101010ff]")
    table.insert(fs, "box[0.2,6.2;5.6,4.8;#101010ff]")
    table.insert(fs, "box[5.8,6.2;6.0,4.8;#151515ff]")

    -- Reuse the same tab strip as the unified inventory
    if gui_get_tab_buttons then
        table.insert(fs, gui_get_tab_buttons(current_tab, false))
    end

    -- 3D preview using the System Looting boxman model
    table.insert(fs, string.format(
        "model[0.3,1.1;3.3,3.3;outfit_preview;%s;%s;0,170;false;true;0,0]",
        model_name, table.concat(tex, ",")
    ))

    -- Slot buttons around the preview
    table.insert(fs, "button[1.4,0.4;1.0,0.6;slot_HEAD;Head]")
    table.insert(fs, "button[0.0,1.8;0.9,0.6;slot_TORSO;Torso]")
    table.insert(fs, "button[0.0,2.6;0.9,0.6;slot_L_HAND;L]")
    table.insert(fs, "button[3.1,1.8;0.9,0.6;slot_BACK;Back]")
    table.insert(fs, "button[3.1,2.6;0.9,0.6;slot_R_HAND;R]")
    table.insert(fs, "button[0.6,4.6;0.9,0.6;slot_L_LEG;L leg]")
    table.insert(fs, "button[2.4,4.6;0.9,0.6;slot_R_LEG;R leg]")
    table.insert(fs, "button[1.0,5.3;0.9,0.6;slot_L_FOOT;L ft]")
    table.insert(fs, "button[2.0,5.3;0.9,0.6;slot_R_FOOT;R ft]")

    -- Right side: item list for the selected slot
    table.insert(fs, string.format("label[4.4,0.9;Select %s item:]", selected_slot))

    local list = get_player_outfit_items(player, selected_slot)

    table.insert(fs, "scroll_container[4.4,1.3;7.1,4.1;item_list_scroll;vertical]")

    local y = 0
    for idx, it in ipairs(list) do
        local btn_name = string.format("pick_%s_%d", selected_slot, idx)
        local label = it.name

        if equipped[selected_slot] == it.id then
            table.insert(fs, string.format("box[0,%f;6.9,0.8;#2a2a2aff]", y))
            label = "✓ " .. label
        else
            table.insert(fs, string.format("box[0,%f;6.9,0.8;#1a1a1aff]", y))
        end

        table.insert(fs, string.format("style[%s;bgcolor=#00000000;border=false;textcolor=#cccccc]", btn_name))
        table.insert(fs, string.format("button[0,%f;6.9,0.8;%s;%s]", y, btn_name, minetest.formspec_escape(label)))

        y = y + 0.9
    end

    table.insert(fs, "scroll_container_end[]")

    if y > 4.1 then
        table.insert(fs, "scrollbar[11.6,1.3;0.2,4.1;vertical;item_list_scroll;0]")
    end

    -- Bottom: split into equipped-item details (left) and player info (right)
    -- (Boxes moved to top of fs)

    -- Equipped item details
    table.insert(fs, "label[0.5,6.5;Currently equipped:]")
    local equipped_id = equipped[selected_slot]
    local current_item = get_item(selected_slot, equipped_id)

    if current_item then
        table.insert(fs, string.format("label[0.5,7.0;%s]", minetest.formspec_escape(current_item.name)))
        table.insert(fs, string.format("textarea[0.5,7.5;5.3,2.0;;;%s]", minetest.formspec_escape(current_item.desc)))
        table.insert(fs, string.format("label[0.5,9.5;Weight: %.1f kg]", current_item.weight))
    else
        table.insert(fs, "label[0.5,7.0;Nothing equipped]")
    end

    table.insert(fs, string.format("label[3.5,9.5;Total: %.1f kg]", total_weight))
    table.insert(fs, "image_button[3.0,10.2;2.6,0.8;gui_button_done.png;outfit_close;Done]")

    -- Player info panel
    table.insert(fs, "label[6.0,6.5;Player Info]")
    table.insert(fs, string.format("textarea[6.0,7.0;5.8,3.8;;;%s]",
        minetest.formspec_escape(build_player_info(player))))

    return table.concat(fs, "")
end

-- Handle fields from this formspec
function handle_character_outfit_fields(player, formname, fields)
    if formname ~= "character_outfit" then
        return false
    end

    if fields.outfit_close or fields.quit then
        minetest.close_formspec(player:get_player_name(), "character_outfit")
        return true
    end

    local selected_slot = nil

    -- Tab switching: close this and return to the unified inventory
    if fields.tab_crafting or fields.tab_abilities or fields.tab_achievements then
        local meta = player:get_meta()
        local new_tab = "crafting"
        if fields.tab_abilities then new_tab = "abilities"
        elseif fields.tab_achievements then new_tab = "achievements" end

        meta:set_string("current_tab", new_tab)
        minetest.close_formspec(player:get_player_name(), "character_outfit")

        if get_unified_inventory then
            minetest.after(0.1, function()
                player:set_inventory_formspec(get_unified_inventory(player))
            end)
        end
        return true
    end

    -- Slot selection buttons
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

    minetest.show_formspec(player:get_player_name(), "character_outfit",
        get_character_outfit_formspec(player, selected_slot))
    return true
end

-- Register the handler
minetest.register_on_player_receive_fields(function(player, formname, fields)
    return handle_character_outfit_fields(player, formname, fields)
end)

minetest.log("action", "[character_outfit] Outfit & player info system loaded.")
