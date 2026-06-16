-- =============================================================
-- System Looting — Button-based Crafting System
-- =============================================================
-- Categories match the game's competitive survival loop:
--   salvage   – raw materials → basic components
--   equipment – tools, weapons, armour pieces
--   tactical  – traps, consumables, team utilities
--   objective – the final goal item that wins the match
-- =============================================================

local crafting_recipes = {}

-- Register a crafting recipe (global so other mods can call it)
function register_craft_recipe(def)
    table.insert(crafting_recipes, {
        output       = def.output,
        output_count = def.output_count or 1,
        ingredients  = def.ingredients,    -- {["item:name"] = count, ...}
        description  = def.description or def.output,
        category     = def.category or "salvage",
    })
end

-- Helpers -------------------------------------------------------
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

-- Formspec builder ----------------------------------------------
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
        {id = "objective", label = "Objective",  x = 6.6},
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

    -- Filter
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

-- Input handler -------------------------------------------------
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

    -- Craft button handler
    for field, _ in pairs(fields) do
        if field:sub(1, 6) == "craft_" then
            local recipe_id = tonumber(field:sub(7))
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
        end
    end

    -- Refresh
    if get_unified_inventory then
        player:set_inventory_formspec(get_unified_inventory(player))
    else
        local refresh_cat = meta:get_string("crafting_category")
        if refresh_cat == "" then refresh_cat = "salvage" end
        player:set_inventory_formspec(get_crafting_formspec(player, refresh_cat))
    end
end)

-- Crafting chat command
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
        return false, "Player not found."
    end
})

-- ================================================================
-- RECIPES — aligned with System Looting's game design
-- ================================================================
-- The loop: scavenge raw materials → craft components → craft
-- equipment/tactical items → craft the Objective Core to win.
-- Uses existing items from default (temporary MTG scaffolding).
-- ================================================================

-- ===== SALVAGE: raw → basic components ==========================

register_craft_recipe({
    output       = "default:steel_ingot",
    output_count = 1,
    ingredients  = {["default:stone"] = 4},
    description  = "Salvaged Metal",
    category     = "salvage",
})

register_craft_recipe({
    output       = "default:copper_ingot",
    output_count = 1,
    ingredients  = {["default:stone"] = 3, ["default:coal_lump"] = 1},
    description  = "Salvaged Copper",
    category     = "salvage",
})

register_craft_recipe({
    output       = "default:mese_crystal",
    output_count = 1,
    ingredients  = {["default:steel_ingot"] = 2, ["default:copper_ingot"] = 2},
    description  = "Energy Crystal",
    category     = "salvage",
})

register_craft_recipe({
    output       = "default:gold_ingot",
    output_count = 1,
    ingredients  = {["default:copper_ingot"] = 3, ["default:coal_lump"] = 2},
    description  = "Circuit Alloy",
    category     = "salvage",
})

register_craft_recipe({
    output       = "default:glass",
    output_count = 2,
    ingredients  = {["default:sand"] = 4},
    description  = "Reinforced Glass",
    category     = "salvage",
})

register_craft_recipe({
    output       = "default:obsidian",
    output_count = 1,
    ingredients  = {["default:steel_ingot"] = 4, ["default:coal_lump"] = 4},
    description  = "Hardened Plating",
    category     = "salvage",
})

-- ===== EQUIPMENT: tools, weapons, armour ========================

register_craft_recipe({
    output       = "default:sword_steel",
    output_count = 1,
    ingredients  = {["default:steel_ingot"] = 3, ["default:stick"] = 1},
    description  = "Combat Blade",
    category     = "equipment",
})

register_craft_recipe({
    output       = "default:pick_steel",
    output_count = 1,
    ingredients  = {["default:steel_ingot"] = 3, ["default:stick"] = 2},
    description  = "Breaching Pick",
    category     = "equipment",
})

register_craft_recipe({
    output       = "default:axe_steel",
    output_count = 1,
    ingredients  = {["default:steel_ingot"] = 2, ["default:stick"] = 2},
    description  = "Tactical Axe",
    category     = "equipment",
})

register_craft_recipe({
    output       = "default:shovel_steel",
    output_count = 1,
    ingredients  = {["default:steel_ingot"] = 1, ["default:stick"] = 2},
    description  = "Trench Shovel",
    category     = "equipment",
})

register_craft_recipe({
    output       = "default:sword_mese",
    output_count = 1,
    ingredients  = {["default:mese_crystal"] = 3, ["default:steel_ingot"] = 2, ["default:stick"] = 1},
    description  = "Energy Blade",
    category     = "equipment",
})

register_craft_recipe({
    output       = "default:pick_mese",
    output_count = 1,
    ingredients  = {["default:mese_crystal"] = 3, ["default:steel_ingot"] = 2, ["default:stick"] = 2},
    description  = "Power Drill",
    category     = "equipment",
})

register_craft_recipe({
    output       = "default:torch",
    output_count = 4,
    ingredients  = {["default:stick"] = 1, ["default:coal_lump"] = 1},
    description  = "Flare Torch",
    category     = "equipment",
})

register_craft_recipe({
    output       = "default:ladder_steel",
    output_count = 4,
    ingredients  = {["default:steel_ingot"] = 2},
    description  = "Steel Ladder",
    category     = "equipment",
})

-- ===== TACTICAL: consumables, traps, team utilities =============

register_craft_recipe({
    output       = "default:mese_block",
    output_count = 1,
    ingredients  = {["default:mese_crystal"] = 9},
    description  = "Power Cell",
    category     = "tactical",
})

register_craft_recipe({
    output       = "default:obsidian_glass",
    output_count = 4,
    ingredients  = {["default:obsidian"] = 1, ["default:glass"] = 2},
    description  = "Blast Shield",
    category     = "tactical",
})

register_craft_recipe({
    output       = "default:steelblock",
    output_count = 1,
    ingredients  = {["default:steel_ingot"] = 9},
    description  = "Barricade Panel",
    category     = "tactical",
})

register_craft_recipe({
    output       = "default:copperblock",
    output_count = 1,
    ingredients  = {["default:copper_ingot"] = 9},
    description  = "Signal Relay",
    category     = "tactical",
})

register_craft_recipe({
    output       = "default:goldblock",
    output_count = 1,
    ingredients  = {["default:gold_ingot"] = 9},
    description  = "Sensor Array",
    category     = "tactical",
})

-- ===== OBJECTIVE: the final win-condition item ==================

register_craft_recipe({
    output       = "sl_modebase:objective_core",
    output_count = 1,
    ingredients  = {
        ["default:mese_block"]   = 1,   -- Power Cell
        ["default:goldblock"]    = 1,   -- Sensor Array
        ["default:obsidian"]     = 2,   -- Hardened Plating
        ["default:gold_ingot"]   = 4,   -- Circuit Alloy
    },
    description  = "Objective Core",
    category     = "objective",
})

minetest.log("action", "[crafting_system] System Looting crafting loaded — "
    .. #crafting_recipes .. " recipes.")
