-- =============================================================
-- System Looting — Unified Inventory (Tab System)
-- =============================================================
-- Tabs: Crafting | Abilities | Achievements | Player Info
-- =============================================================

local function get_current_tab(player)
    local meta = player:get_meta()
    local tab = meta:get_string("current_tab")
    if tab == "" then tab = "crafting" end
    return tab
end

local function set_current_tab(player, tab)
    player:get_meta():set_string("current_tab", tab)
end

-- Tab button strip (reusable by outfit menu too)
function gui_get_tab_buttons(current_tab, show_label)
    local tabs = {
        {id = "crafting",     icon_img = "gui_tab_crafting.png",     label = "Crafting",     x = 8.3},
        {id = "abilities",    icon_img = "gui_tab_abilities.png",    label = "Abilities",    x = 9.1},
        {id = "achievements", icon_img = "gui_tab_achievements.png", label = "Achievements", x = 9.9},
        {id = "player_info",  icon_img = "gui_tab_player_info.png",  label = "Info",         x = 10.7},
    }

    local formspec = {}

    if show_label ~= false and current_tab ~= "crafting" then
        for _, tab in ipairs(tabs) do
            if tab.id == current_tab then
                table.insert(formspec, string.format("label[0.3,1.5;> %s]", tab.label))
                break
            end
        end
    end

    for _, tab in ipairs(tabs) do
        if tab.id == current_tab then
            table.insert(formspec, string.format("box[%f,0.3;0.75,0.75;#5a9a5aff]", tab.x))
            table.insert(formspec, string.format("box[%f,0.3;0.75,0.75;#7aca7a55]", tab.x))
        else
            table.insert(formspec, string.format("box[%f,0.3;0.75,0.75;#3a3a3aff]", tab.x))
        end
        table.insert(formspec, string.format(
            "image_button[%f,0.3;0.75,0.75;%s;tab_%s;]",
            tab.x, tab.icon_img, tab.id))
    end

    return table.concat(formspec, "")
end

-- Strip the header (formspec_version, size, bgcolor) from a full
-- formspec string so its content can be embedded in the unified
-- inventory which already provides those elements.
local function strip_formspec_header(fs)
    -- Remove formspec_version[...], size[...], bgcolor[...] at the start.
    -- These always appear at the very beginning of the string.
    local stripped = fs
    stripped = stripped:gsub("^formspec_version%[[^%]]*%]", "")
    stripped = stripped:gsub("^size%[[^%]]*%]", "")
    stripped = stripped:gsub("^bgcolor%[[^%]]*%]", "")
    return stripped
end

-- Build the full unified inventory formspec
function get_unified_inventory(player)
    local current_tab = get_current_tab(player)

    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",
    }

    table.insert(formspec, gui_get_tab_buttons(current_tab))

    if current_tab == "crafting" then
        if get_crafting_formspec then
            local meta = player:get_meta()
            local cat = meta:get_string("crafting_category")
            if cat == "" then cat = "salvage" end
            local craft_fs = get_crafting_formspec(player, cat)
            table.insert(formspec, strip_formspec_header(craft_fs))
        else
            table.insert(formspec, "label[4,5;Crafting system loading...]")
        end

    elseif current_tab == "abilities" then
        if get_ability_formspec_new then
            local ability_fs = get_ability_formspec_new(player)
            table.insert(formspec, strip_formspec_header(ability_fs))
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[4,5;Ability system loading...]")
        end

    elseif current_tab == "achievements" then
        if get_achievement_formspec then
            local ach_fs = get_achievement_formspec(player)
            table.insert(formspec, strip_formspec_header(ach_fs))
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[4,5;Achievement system loading...]")
        end

    elseif current_tab == "player_info" then
        if get_player_info_formspec then
            local info_fs = get_player_info_formspec(player)
            table.insert(formspec, strip_formspec_header(info_fs))
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[4,5;Player info loading...]")
        end
    end

    return table.concat(formspec, "")
end

-- Handle tab switching
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "" and formname ~= "crafting_system" and formname ~= "unified_inventory" then
        return
    end
    if fields.quit then return end

    local changed_tab = false

    if fields.tab_crafting then
        set_current_tab(player, "crafting");     changed_tab = true
    elseif fields.tab_abilities then
        set_current_tab(player, "abilities");    changed_tab = true
    elseif fields.tab_achievements then
        set_current_tab(player, "achievements"); changed_tab = true
    elseif fields.tab_player_info then
        set_current_tab(player, "player_info");  changed_tab = true
    end

    if changed_tab then
        player:set_inventory_formspec(get_unified_inventory(player))
        return
    end

    -- Clicking the player preview overlay from any tab
    if fields.open_outfit then
        if get_character_outfit_formspec then
            minetest.show_formspec(player:get_player_name(),
                "character_outfit", get_character_outfit_formspec(player, "HEAD"))
        end
        return
    end
end)

-- Set unified inventory on join
minetest.register_on_joinplayer(function(player)
    minetest.after(0.5, function()
        if minetest.get_player_by_name(player:get_player_name()) then
            set_current_tab(player, "crafting")
            player:set_inventory_formspec(get_unified_inventory(player))
        end
    end)
end)

minetest.log("action", "[unified_inventory] Tab system loaded (4 tabs).")
