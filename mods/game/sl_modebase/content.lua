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
-- Ritual components (rare; consumed by the Ghost Altar)
-- ---------------------------------------------------------------
local ritual_items = {
	{ "ritual_ashen_relic", "Ashen Relic", "sl_raw_crystal.png^[colorize:#aa00ff:160" },
	{ "ritual_soul_shard", "Soul Shard", "sl_energy_crystal.png^[colorize:#ff00ff:160" },
	{ "ritual_signal_ink", "Signal Ink", "sl_circuit_board.png^[colorize:#00ffff:140" },
}
for _, item in ipairs(ritual_items) do
	minetest.register_craftitem(modname .. ":" .. item[1], {
		description = S(item[2] .. "\\n(Rare Ritual Component)"),
		inventory_image = item[3],
		groups = { rare = 1, ritual_component = 1 },
	})
end

-- ---------------------------------------------------------------
-- Information items
-- ---------------------------------------------------------------
minetest.register_craftitem(modname .. ":data_pad_security", {
	description = S("Decrypted Security Pad"),
	inventory_image = "sl_circuit_board.png^[colorize:#00ff00:50",
	groups = { information = 1 },
})

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

-- Item pickup: a small glowing object that gives random salvage on
-- right-click. Rolls are weighted; other mods may append entries
-- (sl_weapons adds a small weapons section, spec WEAPONS_SPEC §5 —
-- the Grapple Lash is never on any random table).
local pickup_loot = {
	{ item = modname .. ":scrap_metal", count = 1, weight = 1 },
	{ item = modname .. ":electronic_waste", count = 1, weight = 1 },
	{ item = modname .. ":raw_crystal", count = 1, weight = 1 },
	{ item = modname .. ":plastic_scrap", count = 1, weight = 1 },
}

function game_mode.register_pickup_roll(item, count, weight)
	table.insert(pickup_loot, { item = item, count = count or 1, weight = weight or 1 })
end

function game_mode.get_pickup_rolls()
	local copy = {}
	for i, e in ipairs(pickup_loot) do copy[i] = { item = e.item, count = e.count, weight = e.weight } end
	return copy
end

local function roll_pickup()
	local total = 0
	for _, e in ipairs(pickup_loot) do total = total + (e.weight or 1) end
	local r = math.random() * total
	for _, e in ipairs(pickup_loot) do
		r = r - (e.weight or 1)
		if r <= 0 then return e.item, (e.count or 1) end
	end
	local last = pickup_loot[#pickup_loot]
	return last.item, (last.count or 1)
end

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
		local loot, n = roll_pickup()
		local inv = clicker:get_inventory()
		inv:add_item("main", ItemStack(loot .. " " .. n))
		minetest.remove_node(pos)
		minetest.sound_play("click", { pos = pos, gain = 0.5, max_hear_distance = 8 })
		minetest.chat_send_player(clicker:get_player_name(),
			S("Picked up: @1", minetest.registered_items[loot].description))
		return itemstack
	end,
})

-- ---------------------------------------------------------------
-- Information & Lore Items
-- ---------------------------------------------------------------
local info_items = {
	{ "data_pad_security", "Security Data Pad", "sl_circuit_board.png^[colorize:#ff0000:50", "ENCRYPTED: 'Section 7 seal critical... profit overrides safety...'" },
	{ "data_pad_logistics", "Logistics Data Pad", "sl_circuit_board.png^[colorize:#00ff00:50", "LOG: '340k saved on inspections this month. Tell the families it was an accident.'" },
	{ "data_pad_medical", "Medical Data Pad", "sl_circuit_board.png^[colorize:#0000ff:50", "BIO: 'Dredger Unit 7 confirmed as Maintenance Tech Kowalski. Personality mutated by hydraulic exposure.'" },
}

for _, it in ipairs(info_items) do
	minetest.register_craftitem(modname .. ":" .. it[1], {
		description = S(it[2] .. "\n(Information Item)"),
		inventory_image = it[3],
		groups = { information = 1 },
		on_use = function(itemstack, user, pointed_thing)
			minetest.chat_send_player(user:get_player_name(), minetest.colorize("#00ffff", it[4]))
			return itemstack
		end,
	})
end

-- ---------------------------------------------------------------
-- Monster Master Spawner Tools
-- ---------------------------------------------------------------

minetest.register_tool(modname .. ":summon_monster", {
	description = S("Summon Basic Monster\n(Monster Master Only)"),
	inventory_image = "monster_texture.png^[resize:32x32",
	groups = { not_in_creative_inventory = 1 },
	on_use = function(itemstack, user, pointed_thing)
		local name = user:get_player_name()
		if not game_mode.is_monster_master(name) then
			minetest.chat_send_player(name, S("Only the Monster Master can use this."))
			return itemstack
		end

		local pos = user:get_pos()
		if not pos then return itemstack end

		-- Spawn monster a bit in front of player
		local dir = user:get_look_dir()
		local spawn_pos = vector.add(pos, vector.multiply(dir, 3))
		spawn_pos.y = spawn_pos.y + 1

		local obj = game_mode.spawn_monster(spawn_pos, "stalker", name)
		if obj then
			minetest.sound_play("monster_idle", { pos = spawn_pos, gain = 0.8 })
		end

		return itemstack -- Don't consume
	end,
	on_drop = function(itemstack, dropper, pos)
		return itemstack -- Don't allow dropping
	end,
})

-- ---------------------------------------------------------------
-- Monster Master resources
-- ---------------------------------------------------------------
-- Monster Essence is the Monster Master's deployable resource: each
-- spawner unit burns one per creature it produces. Craftable (see
-- sl_gui crafting system) and gifted as a starter stack when a
-- player takes the Monster Master role.
game_mode.ESSENCE_ITEM = modname .. ":monster_essence"

minetest.register_craftitem(game_mode.ESSENCE_ITEM, {
	description = S("Monster Essence\\n(Monster Master resource; spawner fuel)"),
	inventory_image = "sl_monster_essence.png",
	groups = { component = 1, mm_resource = 1 },
})

-- ---------------------------------------------------------------
-- Monster Spawner Unit
-- ---------------------------------------------------------------
-- A placeable, feedable machine. The Monster Master right-clicks it
-- to open the spawner GUI: a list of every creature in
-- game_mode.MONSTER_TYPES. Selecting one burns one Monster Essence
-- from the unit's feed and spawns that creature beside the node.
-- Anyone else who clicks it is told it is out of reach.
-- ---------------------------------------------------------------

-- Counts Monster Essence across a spawner feed inventory.
function game_mode.count_feed_essence(inv)
	local total = 0
	for i = 1, inv:get_size("feed") do
		local stack = inv:get_stack("feed", i)
		if stack:get_name() == game_mode.ESSENCE_ITEM then
			total = total + stack:get_count()
		end
	end
	return total
end

-- Per-node spawner settings (spawn rate + minimal essence), stored in the
-- node's own meta so every unit can be tuned independently. Defaults
-- apply when a node predates the settings.
local SPAWNER_CD_DEFAULT = 5  -- seconds between spawns
local SPAWNER_MIN_DEFAULT = 1 -- minimum essence in the feed

local function spawner_node_settings(meta)
	local cd_raw = meta:get_string("spawner_cd")
	local min_raw = meta:get_string("spawner_min")
	local cooldown = (cd_raw ~= "") and math.max(0, math.floor(tonumber(cd_raw) or SPAWNER_CD_DEFAULT))
		or SPAWNER_CD_DEFAULT
	local min_essence = (min_raw ~= "") and math.max(1, math.floor(tonumber(min_raw) or SPAWNER_MIN_DEFAULT))
		or SPAWNER_MIN_DEFAULT
	return cooldown, min_essence
end

-- Shared spawner activation path (GUI field clicks and tests).
-- Returns true when a creature was produced.
function game_mode.spawner_activate(name, pos, variant)
	if not game_mode.is_monster_master(name) then
		minetest.chat_send_player(name, S("Only the Monster Master can operate this unit."))
		return false
	end

	local def = game_mode.MONSTER_TYPES[variant]
	if not def then
		return false
	end

	local meta = minetest.get_meta(pos)
	local feed = meta:get_inventory()
	local now = game_mode.now()
	local _, min_essence = spawner_node_settings(meta)

	-- Node setting: minimal resource quantity to spawn.
	local in_feed = game_mode.count_feed_essence(feed)
	if in_feed < min_essence then
		minetest.chat_send_player(name,
			S("The unit needs at least @1 Monster Essence in the feed to run (has @2).",
				tostring(min_essence), tostring(in_feed)))
		return false
	end

	-- Node setting: spawn rate — a unit needs cooldown between spawns.
	local ready_at = meta:get_int("sl_spawner_ready_at")
	if now < ready_at then
		minetest.chat_send_player(name,
			S("The spawner is still spooling. (@1 s)",
				tostring(math.ceil(ready_at - now))))
		return false
	end

	local spawn_pos = {
		x = pos.x + (math.random() - 0.5),
		y = pos.y + 1,
		z = pos.z + (math.random() - 0.5),
	}
	local obj = game_mode.spawn_monster(spawn_pos, variant, name)
	if not obj then
		-- No creature came out (e.g. its entity mod is not loaded):
		-- the unit keeps the essence.
		minetest.chat_send_player(name, S("The spawner sputtered and produced nothing."))
		return false
	end

	-- Spawn confirmed: now burn the essence and start the spool-down.
	feed:remove_item("feed", ItemStack(game_mode.ESSENCE_ITEM .. " 1"))
	local cooldown = spawner_node_settings(meta)
	meta:set_int("sl_spawner_ready_at", math.floor(now + cooldown))
	meta:set_string("infotext",
		S("Monster Spawner Unit (feed: @1)", tostring(game_mode.count_feed_essence(feed))))
	minetest.sound_play("monster_idle", { pos = spawn_pos, gain = 0.8, max_hear_distance = 12 })
	game_mode.broadcast(S("The spawner is producing a @1.", def.label))
	return true
end

-- Spawner GUI: one button per creature (the monster list), a stat
-- label per row, the unit's feed below, and the MM's inventory for
-- loading essence. The node position rides in the form name so the
-- field handler can find the clicked unit.
local function spawner_formspec(pos, meta)
	local essence = game_mode.count_feed_essence(meta:get_inventory())
	local _, min_essence = spawner_node_settings(meta)
	local cd_raw = meta:get_string("spawner_cd")
	local min_raw = meta:get_string("spawner_min")
	local fs = {
		"formspec_version[4]",
		"size[9,15.5]",
		"bgcolor[#120a14ee;true]",
		"label[0.3,0.2;MONSTER SPAWNER UNIT]",
		"label[0.3,0.7;Essence in unit: " .. tostring(essence) .. "  (needs "
			.. tostring(min_essence) .. ", 1 per spawn)]",
	}
	local y = 1.3
	for _, id in ipairs(game_mode.MONSTER_TYPE_ORDER) do
		local def = game_mode.MONSTER_TYPES[id]
		table.insert(fs, string.format("button[0.3,%s;2.6,1;spawn_%s;%s]",
			tostring(y), id, minetest.formspec_escape(def.label)))
		table.insert(fs, string.format("label[3.2,%s;HP %d  SPD %s  DMG %d]",
			tostring(y + 0.2), def.hp, tostring(def.speed), def.damage))
		y = y + 1.1
	end
	table.insert(fs, string.format("label[0.3,%s;Load essence into the feed, then select a unit.]",
		tostring(y)))
	local feed_y = y + 0.5
	table.insert(fs, string.format("list[nodemeta:%d,%d,%d;feed;0.3,%s;8,1;]",
		pos.x, pos.y, pos.z, tostring(feed_y)))
	table.insert(fs, string.format("list[current_player;main;0.3,%s;8,4;]",
		tostring(feed_y + 1.1)))
	table.insert(fs, string.format("listring[nodemeta:%d,%d,%d;feed]", pos.x, pos.y, pos.z))
	table.insert(fs, "listring[current_player;main]")
	-- Per-node settings (spawn rate + minimal essence), saved to this unit.
	table.insert(fs, "label[0.3,13.9;UNIT SETTINGS]")
	table.insert(fs, "label[0.3,14.5;Cooldown (s):]")
	table.insert(fs, string.format("field[2.1,14.2;1.2,0.6;spawner_cd;;%s]",
		cd_raw ~= "" and cd_raw or tostring(SPAWNER_CD_DEFAULT)))
	table.insert(fs, "label[3.6,14.5;Min Essence:]")
	table.insert(fs, string.format("field[5.2,14.2;1.2,0.6;spawner_min;;%s]",
		min_raw ~= "" and min_raw or tostring(SPAWNER_MIN_DEFAULT)))
	table.insert(fs, "button[6.7,14.2;2.0,0.6;save_spawner_cfg;Save]")
	table.insert(fs, "button_exit[6,0.2;2.6,0.6;close;Close]")
	return table.concat(fs, "")
end

minetest.register_node(modname .. ":monster_spawner", {
	description = S("Monster Spawner Unit"),
	inventory_image = "sl_monster_spawner.png",
	drawtype = "mesh",
	mesh = "ghost_altar.obj",
	tiles = { "sl_monster_spawner.png" },
	paramtype = "light",
	light_source = 10,
	groups = { cracky = 2, oddly_breakable_by_hand = 1 },
	is_ground_content = false,
	selection_box = { type = "fixed", fixed = { -0.55, -0.5, -0.55, 0.55, 0.8, 0.55 } },
	collision_box = { type = "fixed", fixed = { -0.55, -0.5, -0.55, 0.55, 0.8, 0.55 } },

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:get_inventory():set_size("feed", 10)
		-- Per-unit settings, tunable from the spawner GUI.
		meta:set_int("spawner_cd", SPAWNER_CD_DEFAULT)
		meta:set_int("spawner_min", SPAWNER_MIN_DEFAULT)
		meta:set_string("infotext", S("Monster Spawner Unit (feed: 0)"))
	end,

	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker or not clicker:is_player() then return itemstack end
		local name = clicker:get_player_name()
		if game_mode.refuse_if_sabotaged(pos, clicker) then return itemstack end
		if not game_mode.is_monster_master(name) then
			minetest.chat_send_player(name,
				S("Only the Monster Master can operate this unit."))
			return itemstack
		end
		minetest.show_formspec(name,
			"sl_modebase:monster_spawner:" .. game_mode.pos_hash(pos),
			spawner_formspec(pos, minetest.get_meta(pos)))
		return itemstack
	end,
})

-- GUI field handler: the spawner GUI sends one "spawn_<variant>" field
-- per click. Only a live Monster Master, on a real spawner node, gets
-- a creature.
minetest.register_on_player_receive_fields(function(player, formname, fields)
	-- Three captures, three variables (the old `_, _, x, y, z` form
	-- shifted z into x and left y/z nil -> get_node_or_nil crash on
	-- every GUI spawn click; caught in merge review).
	local x, y, z = formname:match("^sl_modebase:monster_spawner:([-]?%d+),([-]?%d+),([-]?%d+)$")
	if not x then return end
	local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
	local node = minetest.get_node_or_nil(pos)
	if not node or node.name ~= modname .. ":monster_spawner" then return end
	local name = player:get_player_name()

	-- Saving this unit's own settings (spawn rate + minimal essence).
	if fields.save_spawner_cfg ~= nil then
		if not game_mode.is_monster_master(name) then
			minetest.chat_send_player(name, S("Only the Monster Master can operate this unit."))
			return
		end
		local meta = minetest.get_meta(pos)
		local cd = math.max(0, math.floor(tonumber(fields.spawner_cd) or SPAWNER_CD_DEFAULT))
		local mn = math.max(1, math.floor(tonumber(fields.spawner_min) or SPAWNER_MIN_DEFAULT))
		meta:set_int("spawner_cd", cd)
		meta:set_int("spawner_min", mn)
		minetest.chat_send_player(name,
			S("Spawner unit configured: cooldown @1 s, minimum @2 essence.",
				tostring(cd), tostring(mn)))
		return
	end

	local variant
	for _, id in ipairs(game_mode.MONSTER_TYPE_ORDER) do
		if fields["spawn_" .. id] ~= nil then
			variant = id
			break
		end
	end
	if not variant then return end
	game_mode.spawner_activate(name, pos, variant)
end)

-- Evil ghost sabotage: one bounded charge per revival, targeting a nearby node.
minetest.register_tool(modname .. ":sabotage_charge", {
	description = S("Sabotage Charge\n(Evil Ghost Only)"),
	inventory_image = "sl_circuit_board.png^[colorize:#ff00ff:150",
	groups = { not_in_creative_inventory = 1 },
	on_use = function(itemstack, user, pointed_thing)
		local pl = game_mode.get_player_state(user:get_player_name())
		if pl.phase ~= "evil_ghost" then return itemstack end
		if not pointed_thing or pointed_thing.type ~= "node" then return itemstack end
		local pos = pointed_thing.under
		local node = minetest.get_node_or_nil(pos)
		if not node or node.name == "air" then return itemstack end
		if game_mode.is_sabotaged(pos) then return itemstack end

		local kind, team_id = "node", nil
		if node.name == game_mode.modname .. ":beacon_a" then
			kind, team_id = "beacon", "beacon_a"
		elseif node.name == game_mode.modname .. ":beacon_b" then
			kind, team_id = "beacon", "beacon_b"
		end

		game_mode.register_sabotage(pos, kind, team_id)
		minetest.sound_play("alert", {pos = pos, gain = 0.7, max_hear_distance = 12})
		game_mode.broadcast(S("A system has been corrupted."))
		return ItemStack("")
	end,
})

-- Evil-ghost loadout top-up. WP2's spawn.lua owns the base spawn kit
-- (one bounded sabotage charge); WP3 adds its possession focus here rather
-- than editing another package's file.
function game_mode.grant_evil_ghost_kit(player)
	if not player or not player:is_player() then return false end
	local pl = game_mode.get_player_state(player:get_player_name())
	if pl.phase ~= "evil_ghost" then return false end
	local inv = player:get_inventory()
	local focus = ItemStack(modname .. ":possession_focus")
	if not inv:contains_item("main", focus) then
		inv:add_item("main", focus)
	end
	return true
end

-- Re-issue the focus after any respawn that leaves the player evil.
minetest.register_on_respawnplayer(function(player)
	minetest.after(0, function()
		local p = player and player:get_player_name()
			and minetest.get_player_by_name(player:get_player_name())
		if p then game_mode.grant_evil_ghost_kit(p) end
	end)
end)

-- Evil ghost possession: seize one object at a time, on a cooldown.
-- Reusable (unlike the one-shot sabotage charge) because the cooldown,
-- the single-object limit, and punch-exorcism already bound it.
minetest.register_tool(modname .. ":possession_focus", {
	description = S("Possession Focus\n(Evil Ghost Only; one object at a time)"),
	inventory_image = "sl_raw_crystal.png^[colorize:#ff00ff:150",
	groups = { not_in_creative_inventory = 1 },
	on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() then return itemstack end
		local name = user:get_player_name()
		local pl = game_mode.get_player_state(name)
		if pl.phase ~= "evil_ghost" then
			minetest.chat_send_player(name, S("Only a revived evil ghost can possess objects."))
			return itemstack
		end
		if not pointed_thing or pointed_thing.type ~= "node" then
			minetest.chat_send_player(name, S("Aim the focus at an object."))
			return itemstack
		end

		local ok, err = game_mode.possess_object(pointed_thing.under, name)
		if not ok then
			minetest.chat_send_player(name, err or S("Possession failed."))
		else
			minetest.chat_send_player(name, S("You slip inside the object."))
		end
		return itemstack -- Not consumed; the cooldown is the limit.
	end,
	on_drop = function(itemstack, dropper, pos)
		return itemstack -- Don't allow dropping
	end,
})

-- ================================================================
-- Signal Scanner — detection counterplay for sabotage and possession.
--
-- Spec ("Evil revival state"): every sabotage action needs "a way for
-- living players to detect, prevent, or recover from it." Possession's
-- visible cause (infotext, slamming doors) works at arm's length; the
-- scanner is the at-range detector. It is an information-class tool:
-- non-placeable, personally craftable, and strictly identity-neutral —
-- it reports what is corrupted or possessed and how long it will last,
-- never who corrupted or possessed it.
--
-- Additive to the WP3 possession registry (nodes.lua): reads only the
-- public state tables and never mutates them.
-- ================================================================

local SCAN_RANGE = 24
local SCAN_COOLDOWN = 5
local scanner_ready_at = {} -- [player_name] = time of next allowed scan

-- 8-point bearing without trig (portable across Lua 5.1 / LuaJIT).
-- Engine convention: +X = east, +Z = north.
local function compass_bearing(dx, dz)
	local abs_x, abs_z = math.abs(dx), math.abs(dz)
	if abs_x < 0.5 and abs_z < 0.5 then return "right here" end
	local primary, secondary
	if abs_x >= abs_z then
		primary = (dx > 0) and "E" or "W"
		if abs_z >= abs_x * 0.5 then
			secondary = (dz > 0) and "N" or "S"
		end
	else
		primary = (dz > 0) and "N" or "S"
		if abs_x >= abs_z * 0.5 then
			secondary = (dx > 0) and "E" or "W"
		end
	end
	return primary .. (secondary or "")
end

minetest.register_tool(modname .. ":scanner", {
	description = S("Signal Scanner\n(Living players: sweep for corrupted or possessed systems)"),
	inventory_image = "sl_sensor_array.png^[colorize:#00ffff:100",
	groups = { information = 1 },

	on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() then return itemstack end
		local name = user:get_player_name()
		local pl = game_mode.get_player_state(name)
		local state = game_mode.state

		if not state.match_active or pl.phase ~= "alive" then
			minetest.chat_send_player(name, S("The scanner is silent outside of a live match."))
			return itemstack
		end

		local now = game_mode.now()
		if (scanner_ready_at[name] or 0) > now then
			minetest.chat_send_player(name, S("The scanner is still recharging."))
			return itemstack
		end
		scanner_ready_at[name] = now + SCAN_COOLDOWN

		-- Nearest anomaly across both registries: sabotage (corruption /
		-- beacon corrosion) and possession. Entries in both carry pos and
		-- until_time; identity fields (team_id / ghost) are never read.
		local origin = user:get_pos()
		local best, best_dist, best_kind = nil, SCAN_RANGE, nil
		for _, entry in pairs(state.sabotage) do
			local dist = vector.distance(origin, entry.pos)
			if dist <= best_dist then
				best, best_dist = entry, dist
				best_kind = (entry.kind == "beacon") and "beacon" or "sabotage"
			end
		end
		for _, entry in pairs(state.possession or {}) do
			local dist = vector.distance(origin, entry.pos)
			if dist <= best_dist then
				best, best_dist, best_kind = entry, dist, "possession"
			end
		end

		if not best then
			minetest.chat_send_player(name,
				S("SIGNAL SWEEP: no corrupted or possessed systems within @1 meters.",
					tostring(SCAN_RANGE)))
			return itemstack
		end

		local kind_label = (best_kind == "possession") and S("POSSESSION")
			or (best_kind == "beacon") and S("BEACON CORROSION")
			or S("CORRUPTION")
		local remaining = math.max(0, math.ceil(best.until_time - now))
		local delta = vector.subtract(best.pos, origin)
		minetest.chat_send_player(name, minetest.colorize("#00ffff",
			S("SIGNAL SWEEP: @1 — @2m @3, @4s remaining.",
				kind_label,
				tostring(math.floor(best_dist + 0.5)),
				compass_bearing(delta.x, delta.z),
				tostring(remaining))))
		minetest.sound_play("click", { to_player = name, gain = 0.4 })
		return itemstack
	end,
})

-- Personal crafting: the scanner is non-placeable information equipment,
-- which the ROADMAP keeps in the personal inventory crafting class.
minetest.register_craft({
	output = modname .. ":scanner",
	recipe = {
		{ "",                              modname .. ":raw_crystal",     "" },
		{ modname .. ":electronic_waste", modname .. ":circuit_board",   modname .. ":electronic_waste" },
		{ "",                              modname .. ":plastic_scrap",   "" },
	},
})

-- Reincarnation item for ghosts to become evil ghosts
minetest.register_craftitem(modname .. ":reincarnate", {
	description = S("Revive as Evil Ghost\n(Ghost Only; lose match points)"),
	inventory_image = "monster_texture.png^[resize:32x32^[colorize:#ffffff:50",
	groups = { not_in_creative_inventory = 1 },
	on_use = function(itemstack, user, pointed_thing)
		local name = user:get_player_name()
		local pl = game_mode.get_player_state(name)
		if pl.phase ~= "ghost" then
			return itemstack
		end

		pl.phase = "evil_ghost"
		pl.points = 0
		pl.possession_pos = nil
		pl.possession_ready_at = nil
		game_mode.broadcast(S("A containment breach has been detected."))
		game_mode.spawn_player(user)
		game_mode.grant_evil_ghost_kit(user)

		return ItemStack("") -- Consumed
	end,
	on_drop = function(itemstack, dropper, pos)
		return itemstack -- Don't allow dropping
	end,
})

minetest.log("action", "[sl_modebase] content items/nodes registered.")
