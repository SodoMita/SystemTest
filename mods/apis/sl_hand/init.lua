-- sl_hand
-- Replaces the old/plain empty-hand setup with a neon System Looting hand.

local HAND_TEXTURE = "sl_hand_neon.png"

minetest.override_item("", {
	description = "Neon Hand",
	inventory_image = HAND_TEXTURE,
	wield_image = HAND_TEXTURE,
	wield_scale = {x = 1, y = 1, z = 2.2},
	range = 4.0,
	tool_capabilities = {
		full_punch_interval = 0.1,
		max_drop_level = 0,
		groupcaps = {
			crumbly = {times = {[2] = 3.00, [3] = 0.70}, uses = 0, maxlevel = 1},
			snappy = {times = {[3] = 0.40}, uses = 0, maxlevel = 1},
			oddly_breakable_by_hand = {times = {[1] = 3.50, [2] = 2.00, [3] = 0.70}, uses = 0},
		},
		damage_groups = {fleshy = 1},
	},
})

minetest.log("action", "[sl_hand] neon empty hand enabled")
