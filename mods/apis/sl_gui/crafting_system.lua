-- =============================================================
-- System Looting — Button-based Crafting System
-- =============================================================
-- Categories: salvage, equipment, tactical, objective
-- Uses only items that exist in this game (ground, construction,
-- sl_clothing, sl_scary, sl_modebase).
-- =============================================================

local crafting_recipes = {}

-- Register a crafting recipe (global so other mods can call it)
function register_craft_recipe(def)
    table.insert(crafting_recipes, {
        output       = def.output,
        output_count = def.output_count or 1,
        ingredients  = def.ingredients,
        description  = def.description or def.output,
        category     = def.category or "salvage",
    })
end

-- Helpers
local function has_ingredients(player, ingredients)
    local inv = player:get_inventory()
    for item_name, count in pairs(ingredients) do
        if not inv:contains_item("main", ItemStack(item_name .. " " .. count)) then
            return false
        end
    end
    return true
end

local function take_ingredients(player, ingredients)
    local inv = player:get_inventory()
    for item_name, count in pairs(ingredients) do
        inv:remove_item("main", ItemStack(item_name .. " " .. count))
    end
end

-- Formspec builder
function get_crafting_formspec(player, category)
    category = category or "salvage"
    local meta = player:get_meta()
    local search_filter = meta:get_string("craft_search")
    local scroll_pos = tonumber(meta:get_string("craft_scroll")) or 0

    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",

        -- Search bar
        "field[0.3,0.3;5,0.6;search_field;;" .. minetest.formspec_escape(search_filter) .. "]",
        "field_close_on_enter[search_field;false]",
        "image_button[5.4,0.3;1,0.6;gui_button_search.png;search_btn;]",
        "image_button[6.5,0.3;0.8,0.6;gui_button_clear.png;search_clear;]",
    }

    -- Category tabs
    local categories = {
        {id = "salvage",   label = "Salvage",   x = 0.3},
        {id = "equipment", label = "Equipment", x = 2.4},
        {id = "tactical",  label = "Tactical",  x = 4.5},
        {id = "objective", label = "Objective", x = 6.6},
    }

    for _, cat in ipairs(categories) do
        local icon_name = "gui_category_" .. cat.id .. ".png"
        if cat.id == category then
            table.insert(formspec, string.format("box[%f,1.1;2,0.5;#5a9a5aff]", cat.x))
            table.insert(formspec, string.format("box[%f,1.1;2,0.5;#7aca7a55]", cat.x))
        end
        table.insert(formspec, string.format(
            "image_button[%f,1.1;2,0.5;%s;cat_%s;%s]", cat.x, icon_name, cat.id, cat.label))
    end

    -- Recipe list area
    table.insert(formspec, "box[0.2,1.8;11.6,4.2;#0a0a0aff]")

    local filtered_recipes = {}
    for i, recipe in ipairs(crafting_recipes) do
        if recipe.category == category then
            if search_filter == "" or
               string.find(string.lower(recipe.description),
                            string.lower(search_filter), 1, true) then
                table.insert(filtered_recipes, {id = i, recipe = recipe})
            end
        end
    end

    local recipes_per_page = 5
    local total_recipes = #filtered_recipes
    local max_scroll = math.max(0, total_recipes - recipes_per_page)
    scroll_pos = math.min(scroll_pos, max_scroll)

    if total_recipes > recipes_per_page then
        table.insert(formspec, string.format(
            "scrollbar[11.5,1.8;0.3,4.2;vertical;craft_scroll;%d]", scroll_pos))
    end
    table.insert(formspec, "scroll_container[0.3,2;11,4;craft_scroll;vertical;0.08]")

    local y = 0
    for idx = 1, math.min(total_recipes, recipes_per_page + 3) do
        local entry = filtered_recipes[idx + scroll_pos]
        if not entry then break end

        local i      = entry.id
        local recipe = entry.recipe
        local can_craft = has_ingredients(player, recipe.ingredients)
        local color  = can_craft and "#3a7a3a" or "#4a4a4a"

        table.insert(formspec, string.format("box[0,%f;10.7,0.7;%s]", y, color))
        table.insert(formspec, string.format("item_image[0.1,%f;0.6,0.6;%s]", y + 0.05, recipe.output))
        table.insert(formspec, string.format("label[0.8,%f;%s x%d]",
            y + 0.35, recipe.description, recipe.output_count))

        local ingredients_text = ""
        for item, count in pairs(recipe.ingredients) do
            local item_def  = minetest.registered_items[item]
            local item_desc = item_def and item_def.description or item
            ingredients_text = ingredients_text .. string.format("%s x%d  ", item_desc, count)
        end
        table.insert(formspec, string.format("label[4.5,%f;%s]", y + 0.35, ingredients_text))

        table.insert(formspec, string.format("field[8.2,%f;0.7,0.6;qty_%d;;1]", y + 0.05, i))
        table.insert(formspec, string.format("field_close_on_enter[qty_%d;false]", i))
        table.insert(formspec, string.format(
            "image_button[9,%f;1.6,0.6;gui_button_craft.png;craft_%d;Craft]", y + 0.05, i))

        y = y + 0.75
    end

    table.insert(formspec, "scroll_container_end[]")

    if total_recipes == 0 then
        table.insert(formspec, "label[5,4;No recipes found.]")
    end

    -- Inventory
    table.insert(formspec, "label[0.3,6.2;Inventory:]")
    table.insert(formspec, "list[current_player;main;0.3,6.4;8,4;]")
    table.insert(formspec, "listring[current_player;main]")

    return table.concat(formspec, "")
end

-- Input handler
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "crafting_system" and formname ~= "" then
        return
    end
    if fields.quit then return end

    local meta = player:get_meta()

    -- Search
    if fields.search_btn and fields.search_field then
        meta:set_string("craft_search", fields.search_field)
    elseif fields.search_clear then
        meta:set_string("craft_search", "")
        meta:set_string("craft_scroll", "0")
    elseif fields.key_enter_field == "search_field" and fields.search_field then
        meta:set_string("craft_search", fields.search_field)
    end

    -- Scrollbar
    if fields.craft_scroll then
        local event = minetest.explode_scrollbar_event(fields.craft_scroll)
        if event.type == "CHG" then
            meta:set_string("craft_scroll", tostring(event.value))
        end
    end

    -- Category switching
    local category = meta:get_string("crafting_category")
    if category == "" then category = "salvage" end

    if fields.cat_salvage then
        category = "salvage";   meta:set_string("craft_scroll", "0")
    elseif fields.cat_equipment then
        category = "equipment"; meta:set_string("craft_scroll", "0")
    elseif fields.cat_tactical then
        category = "tactical";  meta:set_string("craft_scroll", "0")
    elseif fields.cat_objective then
        category = "objective"; meta:set_string("craft_scroll", "0")
    end
    meta:set_string("crafting_category", category)

    -- Crafting
    for field, _ in pairs(fields) do
        if field:sub(1, 6) == "craft_" then
            local id_str = field:sub(7)
            local recipe_id = tonumber(id_str)
            -- Skip non-numeric suffixes like "craft_scroll"
            if not recipe_id then goto continue_craft end
            local recipe = crafting_recipes[recipe_id]

            local quantity_field = "qty_" .. recipe_id
            local quantity = tonumber(fields[quantity_field] or "1") or 1
            quantity = math.max(1, math.min(999, math.floor(quantity)))

            if recipe then
                local can_craft_all = true
                local inv = player:get_inventory()

                for item_name, count in pairs(recipe.ingredients) do
                    local needed = count * quantity
                    if not inv:contains_item("main", ItemStack(item_name .. " " .. needed)) then
                        can_craft_all = false
                        break
                    end
                end

                if can_craft_all then
                    for item_name, count in pairs(recipe.ingredients) do
                        inv:remove_item("main", ItemStack(item_name .. " " .. (count * quantity)))
                    end

                    local total_output = recipe.output_count * quantity
                    inv:add_item("main", ItemStack(recipe.output .. " " .. total_output))

                    if give_experience then
                        give_experience(player, 5 * quantity)
                    end

                    if achievement_progress then
                        achievement_progress(player, "first_craft", 1)
                        achievement_progress(player, "craft_10_items", quantity)
                        achievement_progress(player, "craft_100_items", quantity)
                        if recipe.category == "equipment" then
                            achievement_progress(player, "craft_equipment", 1)
                        elseif recipe.category == "tactical" then
                            achievement_progress(player, "craft_tactical", 1)
                        elseif recipe.category == "objective" then
                            achievement_progress(player, "craft_objective_core", 1)
                        end
                    end

                    minetest.chat_send_player(player:get_player_name(),
                        "Crafted " .. quantity .. "x " .. recipe.description .. " (+" .. (5 * quantity) .. " XP)")
                else
                    minetest.chat_send_player(player:get_player_name(),
                        "Not enough ingredients for " .. quantity .. "x craft!")
                end
            end
            ::continue_craft::
        end
    end

    -- Refresh formspec
    if get_unified_inventory then
        player:set_inventory_formspec(get_unified_inventory(player))
    else
        local refresh_cat = meta:get_string("crafting_category")
        if refresh_cat == "" then refresh_cat = "salvage" end
        player:set_inventory_formspec(get_crafting_formspec(player, refresh_cat))
    end
end)

-- Route /craft command through the unified inventory
local old_show_formspec = minetest.show_formspec
function minetest.show_formspec(player_name, formname, formspec)
    if formname == "crafting_system" then
        local player = minetest.get_player_by_name(player_name)
        if player then
            player:set_inventory_formspec(formspec)
        end
    end
    return old_show_formspec(player_name, formname, formspec)
end

minetest.register_chatcommand("craft", {
    description = "Open crafting menu",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            local meta = player:get_meta()
            local category = meta:get_string("crafting_category")
            if category == "" then category = "salvage" end
            player:set_inventory_formspec(get_crafting_formspec(player, category))
            return true, "Crafting menu updated."
        end
        return false, "Player not found"
    end
})

-- ================================================================
-- RECIPES — System Looting items only
-- ================================================================

-- SALVAGE: raw neon ground blocks -> useful components
register_craft_recipe({
    output       = "sl_modebase:loot_crate",
    output_count = 1,
    ingredients  = {["ground:square_neon"] = 4},
    description  = "Salvage Crate",
    category     = "salvage",
})

register_craft_recipe({
    output       = "construction:sparks",
    output_count = 2,
    ingredients  = {["ground:rhombus_neon"] = 4},
    description  = "Sparks Component",
    category     = "salvage",
})

register_craft_recipe({
    output       = "construction:plasma",
    output_count = 2,
    ingredients  = {["ground:x_neon"] = 4},
    description  = "Plasma Component",
    category     = "salvage",
})

register_craft_recipe({
    output       = "construction:fire",
    output_count = 2,
    ingredients  = {["ground:x2_neon"] = 4},
    description  = "Fire Component",
    category     = "salvage",
})

-- EQUIPMENT: clothing from the sl_clothing mod
register_craft_recipe({
    output       = "sl_clothing:hood_plain",
    output_count = 1,
    ingredients  = {["sl_modebase:loot_crate"] = 1, ["construction:sparks"] = 1},
    description  = "Plain Hood",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:cap_brim",
    output_count = 1,
    ingredients  = {["sl_clothing:hood_plain"] = 1, ["construction:plasma"] = 1},
    description  = "Cap with Brim",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:jacket_light",
    output_count = 1,
    ingredients  = {["sl_modebase:loot_crate"] = 1, ["construction:smoke"] = 1},
    description  = "Light Jacket",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:coat_work",
    output_count = 1,
    ingredients  = {["sl_clothing:jacket_light"] = 1, ["construction:plasma"] = 1},
    description  = "Work Coat",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:backpack_small",
    output_count = 1,
    ingredients  = {["sl_modebase:loot_crate"] = 1, ["construction:fire"] = 1},
    description  = "Small Backpack",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:glove_fingerless",
    output_count = 1,
    ingredients  = {["construction:sparks"] = 1, ["ground:square_neon"] = 2},
    description  = "Fingerless Gloves",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:glove_leather",
    output_count = 1,
    ingredients  = {["sl_clothing:glove_fingerless"] = 1, ["construction:plasma"] = 1},
    description  = "Leather Gloves",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:trousers_plain",
    output_count = 1,
    ingredients  = {["construction:smoke"] = 1, ["ground:rhombus_neon"] = 2},
    description  = "Plain Trousers",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:trousers_camo",
    output_count = 1,
    ingredients  = {["sl_clothing:trousers_plain"] = 1, ["construction:sparks"] = 1},
    description  = "Camo Trousers",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:boots_everyday",
    output_count = 1,
    ingredients  = {["construction:fire"] = 1, ["ground:x2_neon"] = 2},
    description  = "Everyday Boots",
    category     = "equipment",
})

register_craft_recipe({
    output       = "sl_clothing:boots_combat",
    output_count = 1,
    ingredients  = {["sl_clothing:boots_everyday"] = 1, ["construction:plasma"] = 1},
    description  = "Combat Boots",
    category     = "equipment",
})

-- TACTICAL: traps and team utilities
register_craft_recipe({
    output       = "sl_scary:hide_spot",
    output_count = 2,
    ingredients  = {["construction:fire"] = 1, ["construction:smoke"] = 1},
    description  = "Hiding Spot",
    category     = "tactical",
})

register_craft_recipe({
    output       = "construction:bubbles",
    output_count = 4,
    ingredients  = {["construction:plasma"] = 1, ["ground:x_neon"] = 1},
    description  = "Smoke Screen",
    category     = "tactical",
})

register_craft_recipe({
    output       = "construction:snowflake",
    output_count = 4,
    ingredients  = {["construction:sparks"] = 1, ["ground:rhombus_neon"] = 1},
    description  = "Distraction Flare",
    category     = "tactical",
})

-- OBJECTIVE: the win-condition item
register_craft_recipe({
    output       = "sl_modebase:objective_core",
    output_count = 1,
    ingredients  = {
        ["sl_modebase:loot_crate"] = 1,
        ["construction:plasma"]    = 1,
        ["ground:x2_neon"]         = 4,
    },
    description  = "Objective Core",
    category     = "objective",
})

minetest.log("action", "[crafting_system] System Looting crafting loaded — "
    .. #crafting_recipes .. " recipes.")
