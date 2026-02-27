-- Register clothing items for testing the outfit system

-- Helper to register simple clothing
local function register_clothing(name, desc, slot, weight, texture, model, bone)
    minetest.register_craftitem("clothing:" .. name, {
        description = desc,
        inventory_image = texture or "clothing_" .. name .. ".png",
        groups = { ["outfit_" .. slot:lower()] = 1, clothing = 1 },
        _outfit_weight = weight,
        _outfit_slot = slot,
        _outfit_model = model, -- e.g., "clothing_hood.b3d"
        _outfit_bone = bone,   -- e.g., "Head"
        _outfit_texture = texture
    })
end

-- HEAD
register_clothing("hood_plain", "Plain Hood", "HEAD", 1.2, "character_tool_head_01.png", "hood.b3d", "Head")
register_clothing("cap_brim", "Cap with Brim", "HEAD", 0.6, "character_tool_head_02.png", "cap.b3d", "Head")

-- TORSO
register_clothing("jacket_light", "Light Jacket", "TORSO", 2.8, "character_tool_body_01.png", "jacket.b3d", "Body")
register_clothing("coat_work", "Work Coat", "TORSO", 3.9, "character_tool_body_02.png", "coat.b3d", "Body")

-- BACK
register_clothing("backpack_small", "Small Backpack", "BACK", 1.5, "character_tool_back_01.png", "backpack.b3d", "Body")

-- HANDS
register_clothing("glove_fingerless", "Fingerless Gloves", "L_HAND", 0.2, "character_tool_hand_01.png", "glove_l.b3d", "Arm_Left")
register_clothing("glove_leather", "Leather Gloves", "R_HAND", 0.3, "character_tool_hand_02.png", "glove_r.b3d", "Arm_Right")

-- LEGS
register_clothing("trousers_plain", "Plain Trousers", "L_LEG", 0.4, "character_tool_legs_01.png", "trousers_l.b3d", "Leg_Left")
register_clothing("trousers_camo", "Camo Trousers", "R_LEG", 0.4, "character_tool_legs_02.png", "trousers_r.b3d", "Leg_Right")

-- FEET
register_clothing("boots_everyday", "Everyday Boots", "L_FOOT", 0.9, "character_tool_feet_01.png", "boot_l.b3d", "Foot_Left")
register_clothing("boots_combat", "Combat Boots", "R_FOOT", 1.1, "character_tool_feet_02.png", "boot_r.b3d", "Foot_Right")


-- Give initial stuff for testing
minetest.register_on_joinplayer(function(player)
    local inv = player:get_inventory()
    if inv:is_empty("main") then
        inv:add_item("main", "clothing:hood_plain")
        inv:add_item("main", "clothing:jacket_light")
        inv:add_item("main", "clothing:boots_everyday")
    end
end)
