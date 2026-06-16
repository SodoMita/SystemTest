-- ================================================================
-- System Looting — craftable content and interactable nodes
-- ================================================================
-- This file registers the items, tools and nodes that form the
-- core crafting loop and the final-project interactables.  All media
-- is reused from sl_mvp_assets where possible; the rest lives in
-- mods/game/sl_modebase/textures.
-- ================================================================

local S = game_mode.S
local modname = game_mode.modname

-- ---------------------------------------------------------------
-- Salvage materials (raw loot)
-- ---------------------------------------------------------------
local salvage_items = {
	{ "scrap_metal",       "Scrap Metal",       "sl_scrap_metal.png" },
	{ "electronic_waste",  "Electronic Waste",  "sl_electronic_waste.png" },
	{ "raw_crystal",       "Raw Crystal",       "sl_raw_crystal.png" },
	{ "plastic_scrap",     "Plastic Scrap",     "sl_plastic_scrap.png" },
}

for _, it in ipairs(salvage_items) do
	minetest.register_craftitem(modname .. ":" .. it[1], {
		description = S(it[2]),
		inventory_image = it[3],
		groups = { salvage = 1 },
	})
end

-- ---------------------------------------------------------------
-- Crafted components
-- ---------------------------------------------------------------
local component_items = {
	{ "metal_ingot",       "Metal Ingot",       "sl_metal_ingot.png" },
	{ "circuit_board",     "Circuit Board",     "sl_circuit_board.png" },
	{ "energy_crystal",    "Energy Crystal",    "sl_energy_crystal.png" },
	{ "hardened_plate",    "Hardened Plate",    "sl_hardened_plate.png" },
	{ "reinforced_glass",  "Reinforced Glass",  "sl_reinforced_glass.png" },
}

for _, it in ipairs(component_items) do
	minetest.register_craftitem(modname .. ":" .. it[1], {
		description = S(it[2]),
		inventory_image = it[3],
		groups = { component = 1 },
	})
end

-- ---------------------------------------------------------------
-- Equipment (tools / weapons)
-- ---------------------------------------------------------------
local function register_tool_basics(name, desc, tex, caps, extra_groups)
	extra_groups = extra_groups or {}
	minetest.register_tool(modname .. ":" .. name, {
		description = S(desc),
		inventory_image = tex,
		tool_capabilities = caps,
		groups = extra_groups,
	})
end

register_tool_basics("combat_blade", "Combat Blade", "sl_combat_blade.png", {
	full_punch_interval = 0.8,
	max_drop_level = 0,
	groupcaps = {},
	damage_groups = { fleshy = 6 },
})

register_tool_basics("breaching_pick", "Breaching Pick", "sl_breaching_pick.png", {
	full_punch_interval = 1.0,
	max_drop_level = 1,
	groupcaps = {
		cracky = { times = { [1] = 4.0, [2] = 1.60, [3] = 0.80 }, uses = 30, maxlevel = 2 },
	},
	damage_groups = { fleshy = 3 },
})

register_tool_basics("tactical_axe", "Tactical Axe", "sl_tactical_axe.png", {
	full_punch_interval = 1.0,
	max_drop_level = 1,
	groupcaps = {
		choppy = { times = { [1] = 3.00, [2] = 1.40, [3] = 0.80 }, uses = 30, maxlevel = 2 },
	},
	damage_groups = { fleshy = 5 },
})

register_tool_basics("trench_shovel", "Trench Shovel", "sl_trench_shovel.png", {
	full_punch_interval = 1.0,
	max_drop_level = 1,
	groupcaps = {
		crumbly = { times = { [1] = 2.00, [2] = 1.00, [3] = 0.50 }, uses = 30, maxlevel = 2 },
	},
	damage_groups = { fleshy = 2 },
})

register_tool_basics("energy_blade", "Energy Blade", "sl_energy_blade.png", {
	full_punch_interval = 0.6,
	max_drop_level = 1,
	groupcaps = {},
	damage_groups = { fleshy = 12 },
})

register_tool_basics("power_drill", "Power Drill", "sl_power_drill.png", {
	full_punch_interval = 0.8,
	max_drop_level = 1,
	groupcaps = {
		cracky = { times = { [1] = 1.20, [2] = 0.60, [3] = 0.30 }, uses = 50, maxlevel = 3 },
	},
	damage_groups = { fleshy = 4 },
})

-- ---------------------------------------------------------------
-- Tactical consumables
-- ---------------------------------------------------------------
minetest.register_craftitem(modname .. ":flare", {
	description = S("Flare"),
	inventory_image = "sl_flare.png",
	on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() then return itemstack end
		local pos = user:get_pos()
		if pos then
			minetest.add_particle({
				pos = vector.add(pos, { x = 0, y = 1, z = 0 }),
				velocity = { x = 0, y = 1, z = 0 },
				acceleration = { x = 0, y = -0.5, z = 0 },
				expirationtime = 2,
				size = 4,
				collisiondetection = false,
				vertical = false,
				texture = "sl_flare.png",
				glow = 14,
			})
			minetest.sound_play("place", { pos = pos, gain = 0.5, max_hear_distance = 10 })
		end
		itemstack:take_item()
		return itemstack
	end,
})

minetest.register_craftitem(modname .. ":medkit", {
	description = S("Medkit"),
	inventory_image = "sl_medkit.png",
	on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() then return itemstack end
		local hp = user:get_hp()
		local hp_max = user:get_properties().hp_max or 20
		if hp < hp_max then
			user:set_hp(math.min(hp_max, hp + 8))
			minetest.sound_play("hit", { to_player = user:get_player_name(), gain = 0.5 }, true)
			itemstack:take_item()
		end
		return itemstack
	end,
})

-- ---------------------------------------------------------------
-- Tactical / objective nodes
-- ---------------------------------------------------------------
local tactical_nodes = {
	{ "power_cell",   "Power Cell",   "sl_power_cell.png",   { cracky = 1, oddly_breakable_by_hand = 1 }, 10 },
	{ "blast_shield", "Blast Shield", "sl_blast_shield.png", { cracky = 1 }, 14 },
	{ "barricade",    "Barricade",    "sl_barricade.png",    { choppy = 1, cracky = 2 }, 0 },
	{ "signal_relay", "Signal Relay", "sl_signal_relay.png", { cracky = 1, oddly_breakable_by_hand = 1 }, 8 },
	{ "sensor_array", "Sensor Array", "sl_sensor_array.png", { cracky = 1, oddly_breakable_by_hand = 1 }, 12 },
}

for _, t in ipairs(tactical_nodes) do
	minetest.register_node(modname .. ":" .. t[1], {
		description = S(t[2]),
		tiles = { t[3] },
		paramtype = "light",
		light_source = t[5] or 0,
		groups = t[4],
		is_ground_content = false,
	})
end

-- ---------------------------------------------------------------
-- Interactable world nodes (terminal, door, platform, pickup)
-- ---------------------------------------------------------------

-- Terminal: right-click to "access" (sends a chat cue for now)
minetest.register_node(modname .. ":terminal", {
	description = S("Terminal"),
	drawtype = "mesh",
	mesh = "terminal.obj",
	tiles = { "terminal_texture.png" },
	paramtype = "light",
	light_source = 8,
	groups = { cracky = 2, oddly_breakable_by_hand = 1 },
	selection_box = { type = "fixed", fixed = { -0.4, -0.5, -0.3, 0.4, 0.6, 0.3 } },
	collision_box = { type = "fixed", fixed = { -0.4, -0.5, -0.3, 0.4, 0.6, 0.3 } },

	on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
		if not clicker or not clicker:is_player() then return itemstack end
		local name = clicker:get_player_name()
		minetest.chat_send_player(name, S("Terminal accessed — systems nominal."))
		minetest.sound_play("click", { pos = pos, gain = 0.5, max_hear_distance = 8 })
		return itemstack
	end,
})

-- Door: closed and open variants.  Right-click toggles.
local door_closed = modname .. ":door_closed"
local door_open = modname .. ":door_open"

local function toggle_door(pos, node, clicker)
	if not clicker or not clicker:is_player() then return end
	local new_name = (node.name == door_closed) and door_open or door_closed
	minetest.set_node(pos, { name = new_name, param2 = node.param2 })
	minetest.sound_play("place", { pos = pos, gain = 0.4, max_hear_distance = 8 })
end

minetest.register_node(door_closed, {
	description = S("Door"),
	drawtype = "nodebox",
	tiles = { "door_texture.png" },
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { choppy = 2, oddly_breakable_by_hand = 1 },
	is_ground_content = false,
	walkable = true,
	node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.08, 0.5, 1.5, 0.08 } },
	selection_box = { type = "fixed", fixed = { -0.5, -0.5, -0.08, 0.5, 1.5, 0.08 } },
	on_rightclick = toggle_door,
})

minetest.register_node(door_open, {
	description = S("Door (Open)"),
	drawtype = "nodebox",
	tiles = { "door_texture.png" },
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { choppy = 2, oddly_breakable_by_hand = 1, not_in_creative_inventory = 1 },
	is_ground_content = false,
	walkable = false,
	node_box = { type = "fixed", fixed = { 0.42, -0.5, -0.5, 0.58, 1.5, 0.5 } },
	selection_box = { type = "fixed", fixed = { 0.42, -0.5, -0.5, 0.58, 1.5, 0.5 } },
	drop = door_closed,
	on_rightclick = toggle_door,
})

-- Hatch: floor/ceiling access using the MVP hatch mesh
local hatch_closed = modname .. ":hatch"
local hatch_open = modname .. ":hatch_open"

local function toggle_hatch(pos, node, clicker)
	if not clicker or not clicker:is_player() then return end
	local new_name = (node.name == hatch_closed) and hatch_open or hatch_closed
	minetest.set_node(pos, { name = new_name, param2 = node.param2 })
	minetest.sound_play("place", { pos = pos, gain = 0.4, max_hear_distance = 8 })
end

minetest.register_node(hatch_closed, {
	description = S("Hatch"),
	drawtype = "mesh",
	mesh = "hatch.obj",
	tiles = { "door_texture.png" },
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { choppy = 2, oddly_breakable_by_hand = 1 },
	is_ground_content = false,
	walkable = true,
	selection_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, -0.38, 0.5 } },
	collision_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, -0.38, 0.5 } },
	on_rightclick = toggle_hatch,
})

minetest.register_node(hatch_open, {
	description = S("Hatch (Open)"),
	drawtype = "nodebox",
	tiles = { "door_texture.png" },
	paramtype = "light",
	paramtype2 = "facedir",
	groups = { choppy = 2, oddly_breakable_by_hand = 1, not_in_creative_inventory = 1 },
	is_ground_content = false,
	walkable = false,
	node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, -0.4, -0.45, -0.4 } },
	selection_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, -0.4, -0.45, -0.4 } },
	drop = hatch_closed,
	on_rightclick = toggle_hatch,
})

-- Platform: walkable building piece with the placeholder mesh
minetest.register_node(modname .. ":platform", {
	description = S("Platform"),
	drawtype = "mesh",
	mesh = "platform.obj",
	tiles = { "platform_texture.png" },
	paramtype = "light",
	groups = { cracky = 2, oddly_breakable_by_hand = 1 },
	is_ground_content = false,
	selection_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 } },
	collision_box = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 } },
})

-- Item pickup: a small glowing object that gives random salvage on right-click
local pickup_loot = {
	modname .. ":scrap_metal",
	modname .. ":electronic_waste",
	modname .. ":raw_crystal",
	modname .. ":plastic_scrap",
}

minetest.register_node(modname .. ":item_pickup", {
	description = S("Loose Item"),
	drawtype = "mesh",
	mesh = "item.obj",
	tiles = { "item_texture.png" },
	paramtype = "light",
	light_source = 6,
	groups = { oddly_breakable_by_hand = 1, dig_immediate = 3 },
	is_ground_content = false,
	selection_box = { type = "fixed", fixed = { -0.25, -0.25, -0.25, 0.25, 0.25, 0.25 } },
	collision_box = { type = "fixed", fixed = { -0.2, -0.2, -0.2, 0.2, 0.2, 0.2 } },

	on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
		if not clicker or not clicker:is_player() then return itemstack end
		local loot = pickup_loot[math.random(1, #pickup_loot)]
		local inv = clicker:get_inventory()
		inv:add_item("main", ItemStack(loot .. " 1"))
		minetest.remove_node(pos)
		minetest.sound_play("click", { pos = pos, gain = 0.5, max_hear_distance = 8 })
		minetest.chat_send_player(clicker:get_player_name(),
			S("Picked up: @1", minetest.registered_items[loot].description))
		return itemstack
	end,
})

minetest.log("action", "[sl_modebase] content items/nodes registered.")
