-- =============================================================
-- System Looting — Ability System (graph-based, PvP-appropriate)
-- =============================================================
-- Abilities are earned with stat points from levelling up.
-- Categories: movement, combat, survival, team
-- NO fly, noclip, teleport, invisibility (breaks competitive PvP)
-- =============================================================

local PAN_STEP = 150

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
        stat_key = "speed", unlock_per_level = 0.10,
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

-- ---- persistence -----------------------------------------------
local function get_ability_data(player)
    local meta = player:get_meta()
    local data_str = meta:get_string("abilities_v2")
    if data_str == "" then data_str = "{}" end
    local data = minetest.deserialize(data_str) or {}
    if not data.unlocked     then data.unlocked     = {} end
    if not data.stat_points  then data.stat_points  = 0  end
    if not data.stat_values  then data.stat_values  = {} end
    if not data.toggles      then data.toggles      = {} end
    if not data.scroll_x     then data.scroll_x     = 0  end
    if not data.scroll_y     then data.scroll_y     = 0  end
    if not data.tooltip      then data.tooltip       = "" end
    return data
end

local function save_ability_data(player, data)
    player:get_meta():set_string("abilities_v2", minetest.serialize(data))
end

-- ---- stat range helper -----------------------------------------
local function get_stat_range(player, stat_key)
    local data = get_ability_data(player)
    local min_val, max_val = 0, 0
    local unclamped = false
    for _, a in ipairs(abilities) do
        if a.stat_key == stat_key then
            local level = data.unlocked[a.id] or 0
            if a.base_min then min_val = a.base_min end
            if a.base_max then max_val = a.base_max end
            max_val = max_val + (a.unlock_per_level * level)
            if a.unclamped then unclamped = true end
        end
    end
    return min_val, max_val, unclamped
end

-- ---- apply stats to physics ------------------------------------
local function apply_stats(player)
    if not player or not player:is_player() then return end
    local data = get_ability_data(player)

    local speed   = data.stat_values.speed   or 1.0
    local jump    = data.stat_values.jump    or 1.0
    local gravity = data.stat_values.gravity or 1.0

    -- Clamp
    local _, max_speed = get_stat_range(player, "speed")
    local _, max_jump  = get_stat_range(player, "jump")
    local min_grav, _  = get_stat_range(player, "gravity")

    speed   = math.min(speed,   max_speed)
    jump    = math.min(jump,    max_jump)
    gravity = math.max(gravity, min_grav)

    player:set_physics_override({speed = speed, jump = jump, gravity = gravity})
end

local function apply_toggles(player)
    if not player or not player:is_player() then return end
    local data = get_ability_data(player)
    -- toggles that grant privs
    for _, a in ipairs(abilities) do
        if a.type == "toggle" and a.priv then
            local privs = minetest.get_player_privs(player:get_player_name())
            if (data.unlocked[a.id] or 0) > 0 and data.toggles[a.id] then
                privs[a.priv] = true
            else
                privs[a.priv] = nil
            end
            minetest.set_player_privs(player:get_player_name(), privs)
        end
    end
end

-- ---- formspec --------------------------------------------------
function get_ability_formspec_new(player)
    local data   = get_ability_data(player)
    local meta   = player:get_meta()
    local exp    = tonumber(meta:get_string("experience")) or 0
    local level  = math.floor(exp / 100) + 1

    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",

        -- Header
        "box[0.2,1.1;11.6,0.6;#2a2a2aff]",
        string.format("label[0.5,1.4;Abilities — Level %d]", level),
        string.format("label[9,1.4;SP: %d]", data.stat_points),
    }

    -- Player preview
    local player_textures = (player_api and player_api.get_textures and player_api.get_textures(player))
        or {"character.png"}
    table.insert(formspec, "box[0.2,0.3;1.5,1.5;#1a1a1aff]")
    table.insert(formspec, string.format(
        "model[0.3,0.4;1.3,1.3;player_preview;character.b3d;%s;0,170;false;false;0,0]",
        table.concat(player_textures, ",")))
    table.insert(formspec, "image_button[0.3,0.4;1.3,1.3;;open_outfit;]")

    -- Graph area
    local graph_x = 0.2
    local graph_y = 1.9
    local graph_w = 8.2
    local graph_h = 8.8
    table.insert(formspec, string.format("box[%f,%f;%f,%f;#0a0a0aff]",
        graph_x, graph_y, graph_w, graph_h))

    local grid_sx = 2.0
    local grid_sy = 1.8
    local offset_x = data.scroll_x / 100
    local offset_y = data.scroll_y / 100

    table.insert(formspec, string.format(
        "scroll_container[%f,%f;%f,%f;ability_graph;vertical;0.1]",
        graph_x, graph_y, graph_w, graph_h))

    -- Connection lines first (using boxes)
    for _, a in ipairs(abilities) do
        if a.requires and ability_by_id[a.requires] then
            local parent = ability_by_id[a.requires]
            local x1 = parent.graph_x * grid_sx + 0.6
            local y1 = parent.graph_y * grid_sy + 0.6
            local x2 = a.graph_x * grid_sx + 0.6
            local y2 = a.graph_y * grid_sy + 0.6
            -- Horizontal then vertical L-connector
            if math.abs(x2 - x1) > 0.1 then
                local lx = math.min(x1, x2)
                local lw = math.abs(x2 - x1)
                table.insert(formspec, string.format(
                    "box[%f,%f;%f,0.05;#4a4a4aff]", lx, y1, lw))
            end
            if math.abs(y2 - y1) > 0.1 then
                local ly = math.min(y1, y2)
                local lh = math.abs(y2 - y1)
                table.insert(formspec, string.format(
                    "box[%f,%f;0.05,%f;#4a4a4aff]", x2, ly, lh))
            end
        end
    end

    -- Nodes
    for _, a in ipairs(abilities) do
        local nx = a.graph_x * grid_sx + 0.1
        local ny = a.graph_y * grid_sy + 0.1
        local nw, nh = 1.1, 1.1

        local curr = data.unlocked[a.id] or 0
        local maxl = a.max_level or 1
        local has_req = true
        if a.requires then
            has_req = (data.unlocked[a.requires] or 0) > 0
        end

        local bg
        if curr >= maxl then     bg = "#2a6a2aff"
        elseif curr > 0 then     bg = "#3a5a3aff"
        elseif has_req then      bg = "#3a3a3aff"
        else                     bg = "#2a2a2aff"
        end

        table.insert(formspec, string.format("box[%f,%f;%f,%f;%s]", nx, ny, nw, nh, bg))
        if a.icon then
            table.insert(formspec, string.format("image[%f,%f;0.5,0.5;%s]", nx + 0.05, ny + 0.05, a.icon))
        end
        table.insert(formspec, string.format("label[%f,%f;%s]", nx + 0.6, ny + 0.25, a.name))
        table.insert(formspec, string.format("label[%f,%f;%d/%d]", nx + 0.6, ny + 0.55, curr, maxl))

        if a.type == "toggle" and curr > 0 then
            local tog = data.toggles[a.id] and "ON" or "OFF"
            table.insert(formspec, string.format(
                "button[%f,%f;0.6,0.35;toggle_%s;%s]", nx + 0.45, ny + 0.75, a.id, tog))
        end

        table.insert(formspec, string.format(
            "image_button[%f,%f;%f,%f;;node_%s;]", nx, ny, nw, nh, a.id))
    end

    table.insert(formspec, "scroll_container_end[]")

    -- Stat sliders panel (right side)
    local sp_x = 8.6
    local sp_y = 1.9
    table.insert(formspec, string.format("box[%f,%f;3.2,8.8;#1a1a1aff]", sp_x, sp_y))
    table.insert(formspec, string.format("label[%f,%f;Stat Tuning]", sp_x + 0.2, sp_y + 0.3))

    local stats_to_show = {
        {key = "speed",   label = "Speed"},
        {key = "jump",    label = "Jump"},
        {key = "gravity", label = "Gravity"},
    }
    local sy_offset = 0.6
    for _, st in ipairs(stats_to_show) do
        local min_v, max_v = get_stat_range(player, st.key)
        local cur = data.stat_values[st.key] or max_v
        table.insert(formspec, string.format("label[%f,%f;%s: %.2f]",
            sp_x + 0.2, sp_y + sy_offset + 0.15, st.label, cur))
        table.insert(formspec, string.format(
            "field[%f,%f;1.2,0.4;stat_%s;;%.2f]",
            sp_x + 0.2, sp_y + sy_offset + 0.35, st.key, cur))
        table.insert(formspec, string.format("field_close_on_enter[stat_%s;false]", st.key))
        table.insert(formspec, string.format(
            "button[%f,%f;0.8,0.4;set_%s;Set]",
            sp_x + 1.5, sp_y + sy_offset + 0.35, st.key))
        table.insert(formspec, string.format("label[%f,%f;(%.2f–%.2f)]",
            sp_x + 0.2, sp_y + sy_offset + 0.75, min_v, max_v))
        sy_offset = sy_offset + 1.2
    end

    -- D-pad navigation
    local dp_x = sp_x + 0.5
    local dp_y = sp_y + 5.5
    local btn  = 0.6
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_up.png;nav_up;]",
        dp_x + btn, dp_y, btn, btn))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_left.png;nav_left;]",
        dp_x, dp_y + btn, btn, btn))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_reset.png;nav_reset;]",
        dp_x + btn, dp_y + btn, btn, btn))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_right.png;nav_right;]",
        dp_x + btn * 2, dp_y + btn, btn, btn))
    table.insert(formspec, string.format("image_button[%f,%f;%f,%f;gui_button_nav_down.png;nav_down;]",
        dp_x + btn, dp_y + btn * 2, btn, btn))

    -- Tooltip bar
    table.insert(formspec, "box[0.2,10.9;11.6,0.3;#2a2a2aff]")
    local tooltip_text = data.tooltip ~= "" and data.tooltip or "Click a node for info"
    table.insert(formspec, string.format("label[0.5,11.05;%s]", minetest.formspec_escape(tooltip_text)))

    return table.concat(formspec, "")
end

-- ---- input handler ---------------------------------------------
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "ability_tree_new" and formname ~= "" and formname ~= "unified_inventory" then
        return
    end
    if (formname == "" or formname == "unified_inventory") then
        local current_tab = player:get_meta():get_string("current_tab")
        if current_tab ~= "abilities" then return end
    end
    if fields.quit then return end

    local data = get_ability_data(player)
    local name = player:get_player_name()
    local changed = false

    -- Stat value changes
    for _, stat in ipairs({"speed", "jump", "gravity"}) do
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
    for _, a in ipairs(abilities) do
        if a.type == "toggle" and fields["toggle_" .. a.id] then
            data.toggles[a.id] = not (data.toggles[a.id] or false)
            changed = true
            apply_toggles(player)
        end
    end

    -- Node clicks (unlock / tooltip)
    for _, a in ipairs(abilities) do
        if fields["node_" .. a.id] then
            local curr = data.unlocked[a.id] or 0
            local maxl = a.max_level or 1

            data.tooltip = string.format("%s | Cost: %d SP | Level: %d/%d | %s",
                a.name, a.cost, curr, maxl, a.description)
            if a.requires then
                data.tooltip = data.tooltip .. " | Req: " .. ability_by_id[a.requires].name
            end
            changed = true

            if curr < maxl then
                local can_unlock = true
                if a.requires then
                    if (data.unlocked[a.requires] or 0) == 0 then
                        can_unlock = false
                        minetest.chat_send_player(name, "Requires: " .. ability_by_id[a.requires].name)
                    end
                end
                if data.stat_points < (a.cost or 1) then
                    can_unlock = false
                    minetest.chat_send_player(name, "Need " .. a.cost .. " stat points!")
                end
                if can_unlock then
                    data.unlocked[a.id] = curr + 1
                    data.stat_points = data.stat_points - (a.cost or 1)
                    -- Auto-set stat value to new max
                    if a.stat_key then
                        local _, new_max = get_stat_range(player, a.stat_key)
                        data.stat_values[a.stat_key] = new_max
                    end
                    changed = true
                    minetest.chat_send_player(name,
                        "Unlocked: " .. a.name .. " Level " .. (curr + 1) .. "!")
                    data.tooltip = string.format("Unlocked %s to Level %d!", a.name, curr + 1)
                    if achievement_progress then
                        achievement_progress(player, "unlock_first_ability", 1)
                    end
                    apply_stats(player)
                    apply_toggles(player)
                end
            end
        end
    end

    -- D-pad navigation
    if fields.nav_up then
        data.scroll_y = math.max(0, data.scroll_y - PAN_STEP); changed = true
    elseif fields.nav_down then
        data.scroll_y = math.min(1000, data.scroll_y + PAN_STEP); changed = true
    elseif fields.nav_left then
        data.scroll_x = math.max(0, data.scroll_x - PAN_STEP); changed = true
    elseif fields.nav_right then
        data.scroll_x = math.min(1000, data.scroll_x + PAN_STEP); changed = true
    elseif fields.nav_reset then
        data.scroll_x = 0; data.scroll_y = 0; changed = true
    end

    if changed then save_ability_data(player, data) end

    if formname == "" or formname == "unified_inventory" then
        if get_unified_inventory then
            player:set_inventory_formspec(get_unified_inventory(player))
        end
    else
        minetest.show_formspec(name, "ability_tree_new", get_ability_formspec_new(player))
    end
end)

-- Chat commands
minetest.register_chatcommand("abilities", {
    description = "Open abilities screen",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            minetest.show_formspec(name, "ability_tree_new", get_ability_formspec_new(player))
            return true, "Opening abilities."
        end
        return false, "Player not found."
    end
})

minetest.register_chatcommand("givestatpoints", {
    params = "<player> <amount>",
    description = "Give stat points to a player",
    privs = {server = true},
    func = function(name, param)
        local target_name, amount_str = param:match("^(%S+)%s+(%S+)$")
        if not target_name or not amount_str then
            return false, "Usage: /givestatpoints <player> <amount>"
        end
        local amount = tonumber(amount_str)
        if not amount then return false, "Invalid amount" end
        local target = minetest.get_player_by_name(target_name)
        if not target then return false, "Player not found" end
        local data = get_ability_data(target)
        data.stat_points = data.stat_points + amount
        save_ability_data(target, data)
        minetest.chat_send_player(target_name,
            string.format("You received %d stat points!", amount))
        return true, string.format("Gave %d stat points to %s", amount, target_name)
    end
})

-- Hook: grant stat points on level-up
local original_give_experience = give_experience
if original_give_experience then
    function give_experience(player, amount)
        local meta = player:get_meta()
        local old_exp = tonumber(meta:get_string("experience")) or 0
        local old_level = math.floor(old_exp / 100) + 1
        local leveled_up = original_give_experience(player, amount)
        if leveled_up then
            local data = get_ability_data(player)
            data.stat_points = data.stat_points + 3
            save_ability_data(player, data)
            minetest.chat_send_player(player:get_player_name(),
                "Gained 3 stat points! Open inventory (I) > Abilities tab to spend them.")
        end
        return leveled_up
    end
end

-- Apply on join
minetest.register_on_joinplayer(function(player)
    minetest.after(2, function()
        pcall(function()
            local p = minetest.get_player_by_name(player:get_player_name())
            if p and p:is_player() then
                apply_stats(p)
                apply_toggles(p)
            end
        end)
    end)
end)

minetest.log("action", "[ability_system] System Looting abilities loaded — "
    .. #abilities .. " abilities.")
