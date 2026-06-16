-- =============================================================
-- System Looting — Ability System (graph-based, PvP-appropriate)
-- =============================================================
-- Abilities are earned with stat points from levelling up.
-- Categories: movement, combat, survival, team
-- NO fly, noclip, teleport, invisibility (breaks competitive PvP)
-- =============================================================

local PAN_STEP = 150

-- Define abilities and stat upgrades
local abilities = {
    -- === MOVEMENT BRANCH ==========================================
    {
        id = "walk_speed", name = "Quick Steps", type = "stat",
        icon = "ability_speed.png",
        description = "+15% walk speed per level",
        category = "movement", cost = 1, max_level = 5,
        requires = nil,
        graph_x = 0, graph_y = 0,
        stat_key = "speed", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.15,
    },
    {
        id = "run_speed", name = "Sprint Boost", type = "stat",
        icon = "ability_speed.png",
        description = "+10% sprint speed per level",
        category = "movement", cost = 1, max_level = 5,
        requires = "walk_speed",
        graph_x = 1, graph_y = 0,
        stat_key = "speed", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.10,
    },
    {
        id = "jump_height", name = "High Jump", type = "stat",
        icon = "ability_jump.png",
        description = "+20% jump height per level",
        category = "movement", cost = 1, max_level = 5,
        requires = "walk_speed",
        graph_x = 0, graph_y = 1,
        stat_key = "jump", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.20,
    },
    {
        id = "sprint_stamina", name = "Endurance", type = "stat",
        icon = "ability_breath.png",
        description = "+20 max sprint stamina per level",
        category = "movement", cost = 1, max_level = 5,
        requires = "walk_speed",
        graph_x = 0, graph_y = 2,
        stat_key = "sprint_stamina", base_min = 100, base_max = 100,
        unlock_per_level = 20,
    },
    {
        id = "sprint_efficiency", name = "Efficient Runner", type = "stat",
        icon = "ability_sprint_efficiency.png",
        description = "-15% sprint stamina drain per level",
        category = "movement", cost = 2, max_level = 3,
        requires = "sprint_stamina",
        graph_x = 1, graph_y = 2,
        stat_key = "sprint_efficiency", base_min = 1.0, base_max = 1.0,
        unlock_per_level = -0.15,
    },
    {
        id = "move_dash", name = "Dash", type = "toggle",
        icon = "ability_speed.png",
        description = "Burst speed, massive stamina cost",
        category = "movement", cost = 3, max_level = 1,
        requires = "run_speed",
        graph_x = 2, graph_y = 0,
        priv = nil,
    },
    {
        id = "light_body", name = "Light Body", type = "stat",
        icon = "ability_gravity.png",
        description = "-15% gravity per level",
        category = "movement", cost = 2, max_level = 3,
        requires = "jump_height",
        graph_x = 1, graph_y = 1,
        stat_key = "gravity", base_min = 1.0, base_max = 1.0,
        unlock_per_level = -0.15,
    },
    {
        id = "sprint_hud", name = "Sprint HUD", type = "toggle",
        icon = "ability_sprint_hud.png",
        description = "Show stamina bar on screen",
        category = "movement", cost = 0, max_level = 1,
        requires = nil,
        graph_x = 3, graph_y = 0,
        priv = nil,
    },

    -- === COMBAT BRANCH ============================================
    {
        id = "melee_damage", name = "Melee Power", type = "stat",
        icon = "ability_attack.png",
        description = "+15% melee damage per level",
        category = "combat", cost = 1, max_level = 5,
        requires = nil,
        graph_x = 0, graph_y = 3,
        stat_key = "melee_damage", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.15,
    },
    {
        id = "attack_speed", name = "Quick Strikes", type = "stat",
        icon = "ability_attack.png",
        description = "+10% attack speed per level",
        category = "combat", cost = 2, max_level = 3,
        requires = "melee_damage",
        graph_x = 1, graph_y = 3,
        stat_key = "attack_speed", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.10,
    },
    {
        id = "defense", name = "Toughness", type = "stat",
        icon = "ability_defense.png",
        description = "+10% damage reduction per level",
        category = "combat", cost = 1, max_level = 5,
        requires = "melee_damage",
        graph_x = 0, graph_y = 4,
        stat_key = "defense", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.10,
    },
    {
        id = "crit_chance", name = "Critical Hit", type = "stat",
        icon = "ability_critical.png",
        description = "+8% crit chance per level",
        category = "combat", cost = 2, max_level = 3,
        requires = "attack_speed",
        graph_x = 2, graph_y = 3,
        stat_key = "crit_chance", base_min = 0.0, base_max = 0.0,
        unlock_per_level = 0.08,
    },
    {
        id = "weapon_mastery", name = "Weapon Mastery", type = "stat",
        icon = "ability_durability.png",
        description = "+20% weapon durability per level",
        category = "combat", cost = 1, max_level = 5,
        requires = "defense",
        graph_x = 1, graph_y = 4,
        stat_key = "durability", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.20,
    },

    -- === SURVIVAL BRANCH ==========================================
    {
        id = "max_health", name = "Vitality", type = "stat",
        icon = "ability_health.png",
        description = "+2 max HP per level",
        category = "survival", cost = 1, max_level = 5,
        requires = nil,
        graph_x = 4, graph_y = 0,
        stat_key = "hp_max", base_min = 20, base_max = 20,
        unlock_per_level = 2,
    },
    {
        id = "health_regen", name = "Regeneration", type = "stat",
        icon = "ability_health.png",
        description = "+0.5 HP/s regen per level",
        category = "survival", cost = 2, max_level = 3,
        requires = "max_health",
        graph_x = 5, graph_y = 0,
        stat_key = "hp_regen", base_min = 0.0, base_max = 0.0,
        unlock_per_level = 0.5,
    },
    {
        id = "breath", name = "Deep Lungs", type = "stat",
        icon = "ability_breath.png",
        description = "+5s breath per level",
        category = "survival", cost = 1, max_level = 3,
        requires = "max_health",
        graph_x = 4, graph_y = 1,
        stat_key = "breath", base_min = 10, base_max = 10,
        unlock_per_level = 5,
    },
    {
        id = "armor_expert", name = "Armor Expert", type = "stat",
        icon = "ability_armor_efficiency.png",
        description = "+15% armor efficiency per level",
        category = "survival", cost = 2, max_level = 3,
        requires = "max_health",
        graph_x = 5, graph_y = 1,
        stat_key = "armor_eff", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.15,
    },

    -- === TEAM BRANCH ==============================================
    {
        id = "scavenger", name = "Scavenger", type = "stat",
        icon = "ability_efficiency.png",
        description = "+20% chance for bonus loot per level",
        category = "team", cost = 1, max_level = 5,
        requires = nil,
        graph_x = 4, graph_y = 3,
        stat_key = "loot_bonus", base_min = 0.0, base_max = 0.0,
        unlock_per_level = 0.20,
    },
    {
        id = "fast_craft", name = "Quick Hands", type = "stat",
        icon = "ability_craft_speed.png",
        description = "+1 extra craft output per 2 levels",
        category = "team", cost = 2, max_level = 4,
        requires = "scavenger",
        graph_x = 5, graph_y = 3,
        stat_key = "craft_bonus", base_min = 0, base_max = 0,
        unlock_per_level = 0.5,
    },
    {
        id = "fast_dig", name = "Efficient Miner", type = "stat",
        icon = "ability_fast_dig.png",
        description = "+15% dig speed per level",
        category = "team", cost = 1, max_level = 5,
        requires = "scavenger",
        graph_x = 4, graph_y = 4,
        stat_key = "dig_speed", base_min = 1.0, base_max = 1.0,
        unlock_per_level = 0.15,
    },
    {
        id = "build_range", name = "Long Reach", type = "stat",
        icon = "ability_reach.png",
        description = "+1 block build range per level",
        category = "team", cost = 2, max_level = 3,
        requires = "fast_dig",
        graph_x = 5, graph_y = 4,
        stat_key = "reach", base_min = 4.0, base_max = 4.0,
        unlock_per_level = 1.0,
    },
}

-- Fast lookup
local ability_by_id = {}
for _, a in ipairs(abilities) do
    ability_by_id[a.id] = a
end

-- Get player's ability data
local function get_ability_data(player)
    if not player then return nil end
    local meta = player:get_meta()
    if not meta then return nil end
    local data_str = meta:get_string("abilities_v2")
    if not data_str or data_str == "" then
        data_str = "return {}"
    end

    local success, data = pcall(minetest.deserialize, data_str)
    if not success or not data or type(data) ~= "table" then
        data = {}
    end

    data.unlocked = data.unlocked or {}
    data.stat_points = data.stat_points or 0
    data.stat_values = data.stat_values or {}
    data.toggles = data.toggles or {}
    data.scroll_x = data.scroll_x or 0
    data.scroll_y = data.scroll_y or 0
    data.tooltip = data.tooltip or ""

    return data
end

-- Save ability data
local function save_ability_data(player, data)
    if not player or not data then return end
    local meta = player:get_meta()
    if not meta then return end
    meta:set_string("abilities_v2", minetest.serialize(data))
end

-- Calculate the effective range for a stat (handles positive and negative per-level changes)
local function get_stat_range(player, stat_key)
    local data = get_ability_data(player)
    local base = nil
    local total = 0
    local unclamped = false

    for _, ability in ipairs(abilities) do
        if ability.type == "stat" and ability.stat_key == stat_key then
            local level = data.unlocked[ability.id] or 0
            local b = ability.base_min or ability.base_max or 0
            if base == nil then base = b end
            total = total + (ability.unlock_per_level or 0) * level
            if ability.unclamped then unclamped = true end
        end
    end

    base = base or 0
    local final = base + total
    return math.min(base, final), math.max(base, final), unclamped
end

-- Apply unlocked stat values to the player
local function apply_stats(player)
    if not player then return end
    local data = get_ability_data(player)
    if not data then return end

    local min_speed, max_speed = get_stat_range(player, "speed")
    local min_jump, max_jump = get_stat_range(player, "jump")
    local min_grav, max_grav = get_stat_range(player, "gravity")
    local _, max_hp = get_stat_range(player, "hp_max")
    local _, max_breath = get_stat_range(player, "breath")

    local speed = data.stat_values.speed or 1.0
    local jump = data.stat_values.jump or 1.0
    local gravity = data.stat_values.gravity or 1.0

    speed = math.max(min_speed, math.min(max_speed, speed))
    jump = math.max(min_jump, math.min(max_jump, jump))
    gravity = math.max(min_grav, math.min(max_grav, gravity))

    pcall(function()
        player:set_physics_override({
            speed = speed,
            jump = jump,
            gravity = gravity,
        })
    end)

    pcall(function()
        player:set_properties({
            hp_max = max_hp,
            breath_max = max_breath,
        })
    end)
end

-- Apply toggle abilities (privileges only)
local function apply_toggles(player)
    if not player then return end
    local data = get_ability_data(player)
    if not data then return end

    local name = player:get_player_name()
    if not name then return end

    local privs = minetest.get_player_privs(name)
    if not privs then return end

    for _, ability in ipairs(abilities) do
        if ability.type == "toggle" and ability.priv then
            local level = (data.unlocked and data.unlocked[ability.id]) or 0
            if level > 0 then
                if data.toggles and data.toggles[ability.id] then
                    privs[ability.priv] = true
                else
                    privs[ability.priv] = nil
                end
            end
        end
    end

    pcall(function()
        minetest.set_player_privs(name, privs)
    end)
end

-- Determine the correct player model and textures for previews
local function get_preview_model(player)
    if sl_characters and sl_characters.default_model then
        return sl_characters.default_model, {sl_characters.default_texture}
    end
    local tex = {"character.png"}
    if player_api and player_api.get_textures then
        tex = player_api.get_textures(player) or tex
    end
    return "character.b3d", tex
end

-- Generate the ability graph formspec
function get_ability_formspec_new(player)
    if not player then return "" end

    local data = get_ability_data(player)
    if not data then return "" end

    local meta = player:get_meta()
    if not meta then return "" end

    local exp = tonumber(meta:get_string("experience")) or 0
    local level = math.floor(exp / 100) + 1

    local model_name, textures = get_preview_model(player)
    local tex_str = table.concat(textures, ",")

    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#0a0a0aff;true]",

        -- 3D Player preview (System Looting boxman model)
        "box[0.2,0.3;1.5,1.5;#1a1a1aff]",
        string.format("model[0.3,0.4;1.3,1.3;player_preview;%s;%s;0,170;false;true;0,0]",
            model_name, tex_str),
        "image_button[0.3,0.4;1.3,1.3;;open_outfit;]",

        -- Header
        "box[0.2,1.9;11.6,0.6;#2a2a2aff]",
        "label[0.5,2.2;Abilities — Level " .. level .. "]",
        "label[9,2.2;SP: " .. data.stat_points .. "]",
    }

    -- LEFT SIDE: stat panel and toggle list
    table.insert(formspec, "box[0.2,2.8;4.5,7.9;#1a1a1aff]")
    table.insert(formspec, "label[0.5,3.1;Stats & Abilities]")

    local y = 3.5
    local stat_types = {
        {key = "speed", label = "Movement Speed", icon = "🏃"},
        {key = "jump", label = "Jump Height", icon = "⬆️"},
        {key = "gravity", label = "Gravity", icon = "🪶"},
        {key = "sneak_speed", label = "Crouch Speed", icon = "🐢"},
    }

    for _, stat in ipairs(stat_types) do
        local min_val, max_val, unclamped = get_stat_range(player, stat.key)
        local current = data.stat_values[stat.key] or 1.0

        if not unclamped then
            current = math.max(min_val, math.min(max_val, current))
        end

        table.insert(formspec, string.format("label[0.5,%f;%s %s]", y, stat.icon, stat.label))
        table.insert(formspec, string.format("field[0.5,%f;1.8,0.5;stat_%s;;%.2f]", y + 0.3, stat.key, current))
        table.insert(formspec, string.format("field_close_on_enter[stat_%s;false]", stat.key))
        table.insert(formspec, string.format("button[2.4,%f;1,0.5;set_%s;Set]", y + 0.3, stat.key))

        if unclamped then
            table.insert(formspec, string.format("label[3.5,%f;∞]", y + 0.5))
        else
            table.insert(formspec, string.format("label[3.5,%f;%.1f-%.1f]", y + 0.5, min_val, max_val))
        end

        y = y + 1
    end

    y = y + 0.3
    table.insert(formspec, string.format("label[0.5,%f;Toggle Abilities]", y))
    y = y + 0.4

    for _, ability in ipairs(abilities) do
        if ability.type == "toggle" then
            local lvl = data.unlocked[ability.id] or 0
            if lvl > 0 then
                local enabled = data.toggles[ability.id] or false
                local checkbox = enabled and "☑" or "☐"
                table.insert(formspec, string.format("button[0.5,%f;4,0.5;toggle_%s;%s %s]",
                    y, ability.id, checkbox, ability.name))
                y = y + 0.6
            end
        end
    end

    -- RIGHT SIDE: ability graph
    local graph_x = 4.9
    local graph_y = 3.2
    local graph_w = 7.0
    local graph_h = 7.0
    local node_size = 0.8
    local grid_spacing_x = 1.2
    local grid_spacing_y = 1.8

    table.insert(formspec, string.format("box[%f,%f;%f,%f;#0a0a0aff]", graph_x, graph_y, graph_w, graph_h))
    table.insert(formspec, string.format("label[%f,%f;Ability Tree (D-pad to pan)]", graph_x + 0.3, graph_y + 0.3))

    local min_x, max_x = 0, 0
    local min_y, max_y = 0, 0
    for _, ability in ipairs(abilities) do
        min_x = math.min(min_x, ability.graph_x)
        max_x = math.max(max_x, ability.graph_x)
        min_y = math.min(min_y, ability.graph_y)
        max_y = math.max(max_y, ability.graph_y)
    end

    local total_width = (max_x - min_x + 1) * grid_spacing_x + node_size
    local total_height = (max_y - min_y + 1) * grid_spacing_y + node_size

    local scroll_x = tonumber(data.scroll_x) or 0
    local scroll_y = tonumber(data.scroll_y) or 0

    local max_offset_x = math.max(0, total_width - graph_w)
    local max_offset_y = math.max(0, total_height - graph_h)
    local offset_x = -(scroll_x / 1000) * max_offset_x - (min_x * grid_spacing_x)
    local offset_y = -(scroll_y / 1000) * max_offset_y - (min_y * grid_spacing_y)

    -- Clip box
    table.insert(formspec, string.format("box[%f,%f;%f,%f;#000000ff]",
        graph_x - 0.2, graph_y - 0.2, graph_w + 0.2, graph_h + 0.2))

    -- Edges
    for _, ability in ipairs(abilities) do
        if ability.requires then
            local parent = ability_by_id[ability.requires]
            if parent then
                local unlocked = (data.unlocked[ability.id] or 0) > 0
                local parent_unlocked = (data.unlocked[parent.id] or 0) > 0

                local x1 = graph_x + offset_x + parent.graph_x * grid_spacing_x + node_size / 2
                local y1 = graph_y + offset_y + parent.graph_y * grid_spacing_y + node_size / 2
                local x2 = graph_x + offset_x + ability.graph_x * grid_spacing_x + node_size / 2
                local y2 = graph_y + offset_y + ability.graph_y * grid_spacing_y + node_size / 2

                if x1 >= graph_x - 0.5 and x1 <= graph_x + graph_w + 0.5 and
                   y1 >= graph_y - 0.5 and y1 <= graph_y + graph_h + 0.5 then
                    local steps = 20
                    local color = (unlocked and parent_unlocked) and "#9a9a9aff" or "#4a4a4aff"
                    for i = 0, steps do
                        local t = i / steps
                        local x = x1 + (x2 - x1) * t
                        local y = y1 + (y2 - y1) * t
                        table.insert(formspec, string.format("box[%f,%f;0.05,0.05;%s]", x, y, color))
                    end
                end
            end
        end
    end

    -- Nodes
    for _, ability in ipairs(abilities) do
        local x = graph_x + offset_x + ability.graph_x * grid_spacing_x
        local y = graph_y + offset_y + ability.graph_y * grid_spacing_y

        if x + node_size >= graph_x and x <= graph_x + graph_w and
           y + node_size >= graph_y and y <= graph_y + graph_h then

            local lvl = data.unlocked[ability.id] or 0
            local unlocked = lvl > 0

            local can_unlock = true
            if ability.requires then
                local req_level = data.unlocked[ability.requires] or 0
                can_unlock = req_level > 0
            end
            can_unlock = can_unlock and data.stat_points >= (ability.cost or 1)

            local bg_color
            if unlocked then
                bg_color = "#2a5a2aff"
            elseif can_unlock then
                bg_color = "#5a5a2aff"
            else
                bg_color = "#2a2a2aff"
            end

            table.insert(formspec, string.format("box[%f,%f;%f,%f;%s]",
                x, y, node_size, node_size, bg_color))
            table.insert(formspec, string.format("image_button[%f,%f;%f,%f;%s;node_%s;]",
                x, y, node_size, node_size, ability.icon, ability.id))

            if unlocked then
                if ability.max_level and ability.max_level > 1 then
                    table.insert(formspec, string.format("label[%f,%f;%d/%d]",
                        x + 0.05, y + node_size - 0.2, lvl, ability.max_level))
                else
                    table.insert(formspec, string.format("label[%f,%f;✓]",
                        x + 0.3, y + node_size - 0.2))
                end
            end
        end
    end

    -- D-pad controls
    local dp_cx = graph_x + 0.75
    local dp_cy = 1
    local btn_size = 0.7
    local btn_gap = 0.8

    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_up.png;nav_up;]",
        dp_cx, dp_cy - btn_gap, btn_size, btn_size))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_down.png;nav_down;]",
        dp_cx, dp_cy + btn_gap, btn_size, btn_size))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_left.png;nav_left;]",
        dp_cx - btn_gap, dp_cy, btn_size, btn_size))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_right.png;nav_right;]",
        dp_cx + btn_gap, dp_cy, btn_size, btn_size))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_reset.png;nav_reset;]",
        dp_cx, dp_cy, btn_size, btn_size))

    -- Tooltip area
    table.insert(formspec, "box[0.2,10.7;11.6,0.3;#2a2a2aff]")
    table.insert(formspec, string.format("label[0.5,10.9;%s]",
        minetest.formspec_escape(data.tooltip or "Click a node for info / unlock")))

    return table.concat(formspec, "")
end

-- Handle formspec input
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "ability_tree_new" and formname ~= "" and formname ~= "unified_inventory" then
        return
    end

    if (formname == "" or formname == "unified_inventory") then
        local current_tab = player:get_meta():get_string("current_tab")
        if current_tab ~= "abilities" then
            return
        end
    end

    if fields.quit then
        return
    end

    local data = get_ability_data(player)
    local name = player:get_player_name()
    local changed = false

    -- Stat value changes
    for _, stat in ipairs({"speed", "jump", "gravity", "sneak_speed"}) do
        if fields["set_" .. stat] and fields["stat_" .. stat] then
            local value = tonumber(fields["stat_" .. stat])
            if value then
                local min_val, max_val, unclamped = get_stat_range(player, stat)
                if not unclamped then
                    value = math.max(min_val, math.min(max_val, value))
                end
                data.stat_values[stat] = value
                changed = true
                apply_stats(player)
            end
        end
    end

    -- Toggle abilities
    for _, ability in ipairs(abilities) do
        if ability.type == "toggle" and fields["toggle_" .. ability.id] then
            data.toggles[ability.id] = not (data.toggles[ability.id] or false)
            changed = true
            apply_toggles(player)
        end
    end

    -- Node clicks (tooltip / unlock)
    for _, ability in ipairs(abilities) do
        if fields["node_" .. ability.id] then
            local current_level = data.unlocked[ability.id] or 0
            local max_level = ability.max_level or 1

            local tooltip = string.format("%s | Cost: %d SP | Level: %d/%d",
                ability.name, ability.cost or 1, current_level, max_level)
            if ability.requires then
                local req = ability_by_id[ability.requires]
                if req then
                    tooltip = tooltip .. " | Requires: " .. req.name
                end
            end
            tooltip = tooltip .. " | " .. ability.description
            data.tooltip = tooltip
            changed = true

            if current_level < max_level then
                local can_unlock = true
                if ability.requires then
                    local req_level = data.unlocked[ability.requires] or 0
                    if req_level == 0 then
                        can_unlock = false
                        minetest.chat_send_player(name, "Requires: " .. (ability_by_id[ability.requires].name or ability.requires))
                    end
                end

                local cost = ability.cost or 1
                if data.stat_points < cost then
                    can_unlock = false
                    minetest.chat_send_player(name, "Need " .. cost .. " stat points!")
                end

                if can_unlock then
                    data.unlocked[ability.id] = current_level + 1
                    data.stat_points = data.stat_points - cost
                    changed = true

                    minetest.chat_send_player(name, "Unlocked: " .. ability.name .. " Level " .. (current_level + 1) .. "!")
                    data.tooltip = "Unlocked " .. ability.name .. " to Level " .. (current_level + 1) .. "!"

                    if achievement_progress then
                        achievement_progress(player, "unlock_first_ability", 1)
                    end
                end
            end
        end
    end

    -- D-pad navigation
    if fields.nav_up then
        data.scroll_y = math.max(0, data.scroll_y - PAN_STEP)
        changed = true
    elseif fields.nav_down then
        data.scroll_y = math.min(1000, data.scroll_y + PAN_STEP)
        changed = true
    elseif fields.nav_left then
        data.scroll_x = math.max(0, data.scroll_x - PAN_STEP)
        changed = true
    elseif fields.nav_right then
        data.scroll_x = math.min(1000, data.scroll_x + PAN_STEP)
        changed = true
    elseif fields.nav_reset then
        data.scroll_x = 0
        data.scroll_y = 0
        changed = true
    end

    if changed then
        save_ability_data(player, data)
    end

    -- Refresh formspec
    if formname == "" or formname == "unified_inventory" then
        if get_unified_inventory then
            player:set_inventory_formspec(get_unified_inventory(player))
        end
    else
        minetest.show_formspec(name, "ability_tree_new", get_ability_formspec_new(player))
    end
end)

-- Chat command to open the advanced abilities screen
minetest.register_chatcommand("abilities2", {
    description = "Open advanced abilities screen",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            minetest.show_formspec(name, "ability_tree_new", get_ability_formspec_new(player))
            return true, "Opening abilities!"
        end
        return false, "Player not found"
    end
})

-- Admin commands
minetest.register_chatcommand("givestatpoints", {
    description = "Grant stat points (admin)",
    params = "<points>",
    privs = {server = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        local points = tonumber(param) or 0
        local data = get_ability_data(player)
        data.stat_points = data.stat_points + points
        save_ability_data(player, data)
        return true, "Gave " .. points .. " stat points."
    end
})

minetest.register_chatcommand("resetprogress", {
    description = "Reset all player progress (admin)",
    privs = {server = true},
    func = function(name, param)
        local target_name = param:match("^%s*(%S+)%s*$") or name
        local player = minetest.get_player_by_name(target_name)
        if not player then return false, "Player not found" end
        local data = get_ability_data(player)
        data.unlocked = {}
        data.stat_points = 0
        data.stat_values = {}
        data.toggles = {}
        save_ability_data(player, data)
        apply_stats(player)
        apply_toggles(player)
        return true, "Reset progress for " .. target_name
    end
})

-- Hook into experience system to grant stat points on level up
local original_give_experience = give_experience
if original_give_experience then
    function give_experience(player, amount)
        local name = player:get_player_name()
        local meta = player:get_meta()
        local old_exp = tonumber(meta:get_string("experience")) or 0
        local old_level = math.floor(old_exp / 100) + 1

        local leveled_up = original_give_experience(player, amount)

        if leveled_up then
            local data = get_ability_data(player)
            data.stat_points = data.stat_points + 2
            save_ability_data(player, data)
            minetest.chat_send_player(name, "Gained 2 stat points! Use them in the Abilities tab.")
        end

        return leveled_up
    end
end

-- Apply abilities on join
minetest.register_on_joinplayer(function(player)
    minetest.after(2, function()
        pcall(function()
            apply_stats(player)
            apply_toggles(player)
        end)
    end)
end)

minetest.log("action", "[ability_system_new] System Looting ability graph loaded.")
