-- Simple button-based crafting system! 💫✨
-- No grid crafting, just click buttons when you have resources~

local crafting_recipes = {}

-- Register a crafting recipe
function register_craft_recipe(def)
    table.insert(crafting_recipes, {
        output = def.output,           -- e.g. "uliza:glass"
        output_count = def.output_count or 1,
        ingredients = def.ingredients, -- e.g. {["uliza:ground"] = 2, ["constructions:beton"] = 1}
        description = def.description or def.output,
        category = def.category or "basic"
    })
end

-- Check if player has required ingredients
local function has_ingredients(player, ingredients)
    local inv = player:get_inventory()
    for item_name, count in pairs(ingredients) do
        if not inv:contains_item("main", ItemStack(item_name.." "..count)) then
            return false
        end
    end
    return true
end

-- Take ingredients from player inventory
local function take_ingredients(player, ingredients)
    local inv = player:get_inventory()
    for item_name, count in pairs(ingredients) do
        inv:remove_item("main", ItemStack(item_name.." "..count))
    end
end

-- Generate crafting GUI formspec
function get_crafting_formspec(player, category)
    category = category or "basic"
    local meta = player:get_meta()
    local search_filter = meta:get_string("craft_search")
    local scroll_pos = tonumber(meta:get_string("craft_scroll")) or 0
    
    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",
        
        -- Search bar with icons
        "field[0.3,0.3;5,0.6;search_field;;" .. minetest.formspec_escape(search_filter) .. "]",
        "field_close_on_enter[search_field;false]",
        "image_button[5.4,0.3;1,0.6;gui_button_search.png;search_btn;]",
        "image_button[6.5,0.3;0.8,0.6;gui_button_clear.png;search_clear;]",
    }
    
    -- Category tabs with glow for active category
    local categories = {
        {id = "basic", label = "Basic", x = 0.3},
        {id = "urban", label = "Urban", x = 2.4},
        {id = "glass", label = "Glass", x = 4.5},
        {id = "advanced", label = "Advanced", x = 6.6},
    }
    
    for _, cat in ipairs(categories) do
        local icon_name = "gui_category_" .. cat.id .. ".png"
        if cat.id == category then
            -- Active category - add glow boxes
            table.insert(formspec, string.format("box[%f,1.1;2,0.5;#5a9a5aff]", cat.x))
            table.insert(formspec, string.format("box[%f,1.1;2,0.5;#7aca7a55]", cat.x))
        end
        -- Use image_button with icon and text
        table.insert(formspec, string.format("image_button[%f,1.1;2,0.5;%s;cat_%s;%s]", cat.x, icon_name, cat.id, cat.label))
    end
    
    -- Crafting recipes area with scrollbar (compact)
    table.insert(formspec, "box[0.2,1.8;11.6,4.2;#0a0a0aff]")
    
    -- Filter recipes by category and search
    local filtered_recipes = {}
    for i, recipe in ipairs(crafting_recipes) do
        if recipe.category == category then
            if search_filter == "" or 
               string.find(string.lower(recipe.description), string.lower(search_filter), 1, true) then
                table.insert(filtered_recipes, {id = i, recipe = recipe})
            end
        end
    end
    
    local recipes_per_page = 5
    local total_recipes = #filtered_recipes
    local max_scroll = math.max(0, total_recipes - recipes_per_page)
    scroll_pos = math.min(scroll_pos, max_scroll)
    
    -- Scrollbar
    if total_recipes > recipes_per_page then
        table.insert(formspec, string.format("scrollbar[11.5,1.8;0.3,4.2;vertical;craft_scroll;%d]", scroll_pos))
        table.insert(formspec, string.format("scroll_container[0.3,2;11,4;craft_scroll;vertical;0.08]" ))
    else
        table.insert(formspec, "scroll_container[0.3,2;11,4;craft_scroll;vertical;0.08]")
    end
    
    local y = 0
    for idx = 1, math.min(total_recipes, recipes_per_page + 3) do
        local entry = filtered_recipes[idx + scroll_pos]
        if not entry then break end
        
        local i = entry.id
        local recipe = entry.recipe
        local can_craft = has_ingredients(player, recipe.ingredients)
        local color = can_craft and "#3a7a3a" or "#4a4a4a"
        
        -- Recipe box (compact)
        table.insert(formspec, string.format("box[0,%f;10.7,0.7;%s]", y, color))
        
        -- Output info
        table.insert(formspec, string.format("item_image[0.1,%f;0.6,0.6;%s]", y + 0.05, recipe.output))
        table.insert(formspec, string.format("label[0.8,%f;%s x%d]", y + 0.35, recipe.description, recipe.output_count))
        
        -- Required ingredients (compact)
        local ingredients_text = ""
        for item, count in pairs(recipe.ingredients) do
            local item_def = minetest.registered_items[item]
            local item_desc = item_def and item_def.description or item
            ingredients_text = ingredients_text .. string.format("%s x%d  ", item_desc, count)
        end
        table.insert(formspec, string.format("label[4.5,%f;%s]", y + 0.35, ingredients_text))
        
        -- Quantity field and craft button with icon
        table.insert(formspec, string.format("field[8.2,%f;0.7,0.6;qty_%d;;1]", y + 0.05, i))
        table.insert(formspec, string.format("field_close_on_enter[qty_%d;false]", i))
        table.insert(formspec, string.format("image_button[9,%f;1.6,0.6;gui_button_craft.png;craft_%d;Craft]", y + 0.05, i))
        
        y = y + 0.75
    end
    
    table.insert(formspec, "scroll_container_end[]")
    
    if total_recipes == 0 then
        table.insert(formspec, "label[5,4;No recipes found! 🌸]")
    end
    
    -- Compact Inventory Display
    table.insert(formspec, "label[0.3,6.2;Inventory:]")
    -- Main inventory (4 rows, compact spacing)
    table.insert(formspec, "list[current_player;main;0.3,6.4;8,4;]")
    table.insert(formspec, "listring[current_player;main]")
    
    return table.concat(formspec, "")
end

-- Handle formspec input
minetest.register_on_player_receive_fields(function(player, formname, fields)
    -- Handle both named formspec and inventory formspec (empty string)
    if formname ~= "crafting_system" and formname ~= "" then
        return
    end
    
    -- Handle quit (ESC key or window close)
    if fields.quit then
        return
    end
    
    -- Search handling
    local meta = player:get_meta()
    if fields.search_btn and fields.search_field then
        meta:set_string("craft_search", fields.search_field)
    elseif fields.search_clear then
        meta:set_string("craft_search", "")
        meta:set_string("craft_scroll", "0")
    elseif fields.key_enter_field == "search_field" and fields.search_field then
        meta:set_string("craft_search", fields.search_field)
    end
    
    -- Scrollbar handling
    if fields.craft_scroll then
        local event = minetest.explode_scrollbar_event(fields.craft_scroll)
        if event.type == "CHG" then
            meta:set_string("craft_scroll", tostring(event.value))
        end
    end
    
    -- Category switching
    local meta = player:get_meta()
    local category = meta:get_string("crafting_category")
    if category == "" then category = "basic" end
    
    if fields.cat_basic then 
        category = "basic"
        meta:set_string("craft_scroll", "0")
    elseif fields.cat_urban then 
        category = "urban"
        meta:set_string("craft_scroll", "0")
    elseif fields.cat_glass then 
        category = "glass"
        meta:set_string("craft_scroll", "0")
    elseif fields.cat_advanced then 
        category = "advanced"
        meta:set_string("craft_scroll", "0")
    end
    
    meta:set_string("crafting_category", category)
    
    -- Crafting
    for field, _ in pairs(fields) do
        if field:sub(1, 6) == "craft_" then
            local recipe_id = tonumber(field:sub(7))
            local recipe = crafting_recipes[recipe_id]
            
            -- Get quantity from field
            local quantity_field = "qty_" .. recipe_id
            local quantity = tonumber(fields[quantity_field] or "1") or 1
            quantity = math.max(1, math.min(999, math.floor(quantity))) -- Clamp 1-999
            
            if recipe then
                -- Check if we have enough ingredients for the quantity
                local can_craft_all = true
                local inv = player:get_inventory()
                
                for item_name, count in pairs(recipe.ingredients) do
                    local needed = count * quantity
                    if not inv:contains_item("main", ItemStack(item_name.." "..needed)) then
                        can_craft_all = false
                        break
                    end
                end
                
                if can_craft_all then
                    -- Take ingredients for all crafts
                    for item_name, count in pairs(recipe.ingredients) do
                        local needed = count * quantity
                        inv:remove_item("main", ItemStack(item_name.." "..needed))
                    end
                    
                    -- Give output
                    local total_output = recipe.output_count * quantity
                    inv:add_item("main", ItemStack(recipe.output.." "..total_output))
                    
                    -- Give experience!
                    if give_experience then
                        give_experience(player, 5 * quantity)
                    end
                    
                    -- Track achievements! 🏆
                    if achievement_progress then
                        achievement_progress(player, "first_craft", 1)
                        achievement_progress(player, "craft_10_items", quantity)
                        achievement_progress(player, "craft_100_items", quantity)
                        
                        -- Category-specific achievements
                        if recipe.category == "urban" then
                            achievement_progress(player, "craft_urban_item", 1)
                        elseif recipe.category == "glass" then
                            achievement_progress(player, "craft_glass", 1)
                        end
                    end
                    
                    minetest.chat_send_player(player:get_player_name(), 
                        "✨ Crafted "..quantity.."x " .. recipe.description .. "! (+".. (5*quantity) .." XP)")
                else
                    minetest.chat_send_player(player:get_player_name(), 
                        "❌ Not enough ingredients for "..quantity.."x craft!")
                end
            end
        end
    end
    
    -- Refresh formspec (not when quitting)
    if get_unified_inventory then
        player:set_inventory_formspec(get_unified_inventory(player))
    else
        -- Fallback if unified inventory not loaded yet
        local refresh_meta = player:get_meta()
        local refresh_cat = refresh_meta:get_string("crafting_category")
        if refresh_cat == "" then refresh_cat = "basic" end
        player:set_inventory_formspec(get_crafting_formspec(player, refresh_cat))
    end
end)

-- NOTE: Inventory formspec now handled by unified_inventory.lua
-- This function is called by unified_inventory to get crafting content

-- Also update formspec when it changes
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

-- Command to open crafting menu (now just updates the inventory formspec)
minetest.register_chatcommand("craft", {
    description = "Open crafting menu",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if player then
            local meta = player:get_meta()
            local category = meta:get_string("crafting_category")
            if category == "" then category = "basic" end
            player:set_inventory_formspec(get_crafting_formspec(player, category))
            return true, "Crafting menu updated!"
        end
        return false, "Player not found"
    end
})

-- Register some example recipes using existing blocks! 🌟
register_craft_recipe({
    output = "uliza:glass",
    output_count = 2,
    ingredients = {["uliza:ground"] = 4},
    description = "Clear Glass",
    category = "glass"
})

register_craft_recipe({
    output = "uliza:framed_glass",
    output_count = 4,
    ingredients = {["uliza:glass"] = 2, ["constructions:beton"] = 1},
    description = "Framed Glass",
    category = "glass"
})

register_craft_recipe({
    output = "uliza:purple_glass",
    output_count = 2,
    ingredients = {["uliza:glass"] = 2, ["flowers:rose"] = 1},
    description = "Purple Glass",
    category = "glass"
})

register_craft_recipe({
    output = "uliza:blue_glass",
    output_count = 2,
    ingredients = {["uliza:glass"] = 2, ["uliza:water_source"] = 1},
    description = "Blue Glass",
    category = "glass"
})

register_craft_recipe({
    output = "uliza:block",
    output_count = 4,
    ingredients = {["uliza:ground"] = 8},
    description = "Transparent Block",
    category = "basic"
})

register_craft_recipe({
    output = "constructions:beton",
    output_count = 8,
    ingredients = {["uliza:ground"] = 12},
    description = "Concrete Block",
    category = "urban"
})

register_craft_recipe({
    output = "kawaii_village:ladder_wood",
    output_count = 4,
    ingredients = {["default:wood"] = 2},
    description = "Wooden Ladder",
    category = "basic"
})

register_craft_recipe({
    output = "default:torch",
    output_count = 4,
    ingredients = {["default:wood"] = 1, ["default:coal_lump"] = 1},
    description = "Torch (temporary)",
    category = "basic"
})

minetest.log("action", "[crafting_system] Simple crafting system loaded! ✨")
