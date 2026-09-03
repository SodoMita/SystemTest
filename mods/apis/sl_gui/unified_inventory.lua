-- =============================================================
-- System Looting — Unified Inventory (Tab System)
-- Tabs: Crafting | Abilities | Achievements | System | Comms | Players
-- WP5 UPGRADE: Inventory now exposes majority of sl_ commands via GUI
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

-- Tab button strip (reusable by the outfit menu too)
-- Now 6 tabs: crafting, abilities, achievements, system, comms, players
-- System tab exposes majority of sl_ commands, Comms tab for DM,
-- Players tab lists the connected operators (roster).
local TAB_W, TAB_PITCH = 0.75, 0.8

function gui_get_tab_buttons(current_tab, show_label, x0, y0)
    -- The defaults reproduce the original top-right placement used by the
    -- outfit menu, shifted left so all six tab buttons end inside the
    -- 12-unit frame (6 * 0.8 pitch + 0.75 width = 5.55 units of strip).
    -- The unified inventory passes its own origin because it reserves a
    -- header band for the tabs and the character preview.
    x0 = x0 or 6.4
    y0 = y0 or 0.3

    local tabs = {
        {id = "crafting",     icon_img = "gui_tab_crafting.png",     label = "Crafting"},
        {id = "abilities",    icon_img = "gui_tab_abilities.png",    label = "Abilities"},
        {id = "achievements", icon_img = "gui_tab_achievements.png", label = "Achievements"},
        {id = "system",       icon_img = "gui_tab_system.png",       label = "System"},
        {id = "comms",        icon_img = "gui_tab_comms.png",        label = "Comms"},
        {id = "players",      icon_img = "gui_tab_players.png",      label = "Players"},
    }

    local formspec = {}

    if show_label ~= false then
        for _, tab in ipairs(tabs) do
            if tab.id == current_tab then
                table.insert(formspec, string.format("label[%g,%g;> %s]",
                    x0, y0 + TAB_W + 0.2, tab.label))
                break
            end
        end
    end

    for i, tab in ipairs(tabs) do
        local x = x0 + (i - 1) * TAB_PITCH
        if tab.id == current_tab then
            table.insert(formspec, string.format("box[%g,%g;%g,%g;#5a9a5aff]", x, y0, TAB_W, TAB_W))
            table.insert(formspec, string.format("box[%g,%g;%g,%g;#7aca7a55]", x, y0, TAB_W, TAB_W))
        else
            table.insert(formspec, string.format("box[%g,%g;%g,%g;#3a3a3aff]", x, y0, TAB_W, TAB_W))
        end
        table.insert(formspec, string.format(
            "image_button[%g,%g;%g,%g;%s;tab_%s;]",
            x, y0, TAB_W, TAB_W, tab.icon_img, tab.id))
    end

    return table.concat(formspec, "")
end

-- Build the `model[]` element that shows the player character.
--
-- The documented layout of this element ends with the animation frame loop
-- range and then the animation speed, and has done so since at least 5.4 --
-- every release this game can run on. The formspecs here were written for the
-- older `initial rotation X,Y,Z` form, so they passed `0,0` where the engine
-- reads a frame loop range: that pins the mesh to a single animation frame
-- instead of the documented default of "the full range of all available
-- frames". Leave the frame loop empty and give the element a real speed.
-- The model[] element's `frame loop range` selects which animation the preview
-- plays. Left empty, the engine defaults to the full range of all available
-- frames (guiFormSpecMenu::parseModel seeds frame_loop_end with infinity), and
-- SimpleOutlinedBoxman.glb packs every animation into a single 102-keyframe
-- track -- walk at 1-40, mine at 41-60, walk_mine at 61-99, then the
-- crawl/sit/die poses at 100-102. So the preview ran, mined and died on a loop
-- instead of standing still.
--
-- Pinning the range to the animation the player is actually using fixes that.
-- The ranges come from player_api's registered model, so they follow the model
-- rather than being duplicated here; `stand` is a single keyframe in this model,
-- which the engine handles (TrackAnimSpec::advance special-cases a zero-length
-- range), and it means the preview shows a still idle pose.
local function gui_character_frame_loop(player, model_name)
    local anim_name = "stand"
    if player and player_api and player_api.get_animation then
        -- player_api.get_animation asserts on a player it has never seen
        -- (bots, the stub), so guard it rather than let it break the formspec.
        local ok, data = pcall(player_api.get_animation, player)
        if ok and type(data) == "table" then
            anim_name = data.animation or anim_name
            model_name = data.model or model_name
        end
    end
    local models = player_api and player_api.registered_models
    local model = models and models[model_name]
    local range = model and model.animations
        and (model.animations[anim_name] or model.animations.stand)
    if not (range and range.x and range.y) then
        return "" -- unknown model: keep the engine default rather than guess
    end
    return string.format("%g,%g", range.x, range.y)
end

function gui_character_model_element(name, x, y, w, h, player)
    local model_name = "character.b3d"
    local texture = "character.png"
    if sl_characters and sl_characters.default_model then
        model_name = sl_characters.default_model
        texture = sl_characters.default_texture or "sl_boxman_neon.png"
    end

    -- One texture per mesh buffer, the same way player_api dresses the model.
    local textures = {}
    for _ = 1, 8 do textures[#textures + 1] = texture end

    return string.format("model[%g,%g;%g,%g;%s;%s;%s;0,20;true;false;%s;30]",
        x, y, w, h, name, model_name, table.concat(textures, ","),
        gui_character_frame_loop(player, model_name))
end

-- Strip the header (formspec_version, size, bgcolor) from a full
-- formspec string so its content can be embedded in the unified
-- inventory which already provides those elements.
local function strip_formspec_header(fs)
    local stripped = fs
    stripped = stripped:gsub("^formspec_version%[[^%]]*%]", "")
    stripped = stripped:gsub("^size%[[^%]]*%]", "")
    stripped = stripped:gsub("^bgcolor%[[^%]]*%]", "")
    return stripped
end

-- The per-tab formspecs are laid out for this height.
local CONTENT_H = 11.8
-- Header band reserved above them. The tab strip and the character preview
-- used to share a single 0.9-unit strip at the top, so the tabs were painted
-- straight over the preview and hid the character. Giving the band real
-- height means both fit side by side without moving any tab's own layout.
local HEADER_H = 1.8
local PREVIEW_X, PREVIEW_Y, PREVIEW_SIZE = 0.2, 0.1, 1.6
local PREVIEW_PAD = 0.1

-- Build the full unified inventory formspec
function get_unified_inventory(player)
    local current_tab = get_current_tab(player)

    local inner_x = PREVIEW_X + PREVIEW_PAD
    local inner_y = PREVIEW_Y + PREVIEW_PAD
    local inner_size = PREVIEW_SIZE - 2 * PREVIEW_PAD

    local formspec = {
        "formspec_version[4]",
        string.format("size[12,%g]", CONTENT_H + HEADER_H),
        "bgcolor[#1a1a1aff;true]",

        -- 3D Player preview (always visible to reach Information/Outfit menu)
        string.format("box[%g,%g;%g,%g;#2a2a2aff]",
            PREVIEW_X, PREVIEW_Y, PREVIEW_SIZE, PREVIEW_SIZE),
        gui_character_model_element("player_preview", inner_x, inner_y,
            inner_size, inner_size, player),
        -- Click target over the preview. border=false means the engine draws
        -- no button pane, so the mesh behind it stays visible; the element
        -- still receives the click that opens the outfit / player info menu.
        "style[open_outfit;border=false;bgcolor=#00000000]",
        string.format("image_button[%g,%g;%g,%g;;open_outfit;]",
            inner_x, inner_y, inner_size, inner_size),
    }

    table.insert(formspec, gui_get_tab_buttons(current_tab, true, 2.1, 0.5))

    -- Shift the tab's own layout below the header band instead of overlapping it.
    table.insert(formspec, string.format("container[0,%g]", HEADER_H))

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

    elseif current_tab == "system" then
        if get_system_formspec then
            local sys_fs = get_system_formspec(player)
            table.insert(formspec, sys_fs)
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[0.4,1.3;System tab loading... install system_tab.lua]")
        end

    elseif current_tab == "comms" then
        if get_comms_formspec then
            local comms_fs = get_comms_formspec(player)
            table.insert(formspec, comms_fs)
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[0.4,1.3;Comms tab loading... install system_tab.lua]")
        end

    elseif current_tab == "players" then
        if get_players_formspec then
            local players_fs = get_players_formspec(player)
            table.insert(formspec, players_fs)
        else
            table.insert(formspec, "box[0.2,1.1;11.6,9.8;#1a1a1aff]")
            table.insert(formspec, "label[0.4,1.3;Players tab loading... install players_tab.lua]")
        end
    end

    table.insert(formspec, "container_end[]")

    return table.concat(formspec, "")
end

-- Handle tab switching and the player preview overlay + system/comms actions
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
    elseif fields.tab_system then
        set_current_tab(player, "system");       changed_tab = true
    elseif fields.tab_comms then
        set_current_tab(player, "comms");        changed_tab = true
    elseif fields.tab_players then
        set_current_tab(player, "players");      changed_tab = true
    end

    if changed_tab then
        player:set_inventory_formspec(get_unified_inventory(player))
        return
    end

    -- Delegate to system tab handler if available
    if _G.sl_gui_system_handle_fields then
        local handled = _G.sl_gui_system_handle_fields(player, fields)
        if handled then
            -- Refresh inventory to show updated state (HP, MM, etc)
            player:set_inventory_formspec(get_unified_inventory(player))
            return
        end
    end

    -- Delegate to comms tab handler
    if _G.sl_gui_comms_handle_fields then
        local handled = _G.sl_gui_comms_handle_fields(player, fields)
        if handled then
            player:set_inventory_formspec(get_unified_inventory(player))
            return
        end
    end

    -- Delegate to players (roster) tab handler
    if _G.sl_gui_players_handle_fields then
        local handled = _G.sl_gui_players_handle_fields(player, fields)
        if handled then
            player:set_inventory_formspec(get_unified_inventory(player))
            return
        end
    end

    -- Clicking the player preview overlay opens the outfit/info screen
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

minetest.log("action", "[unified_inventory] Tab system loaded (6 tabs: crafting, abilities, achievements, system, comms, players).")
