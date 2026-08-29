-- ================================================================
-- sl_weapons — the arsenal (spec §3, §3.1)
-- Six core weapons + the Neon Frontier pair. No reloads, ever; the
-- Neon Six's cylinder pause belongs to the gun, not the player.
-- Ammo items load into the shooter's pools on use.
-- ================================================================

local W = sl_weapons
local S = W.S

W.weapons = {}      -- [weapon_id] = def
W.defs_by_item = {} -- [item name] = def

function W.register_weapon(def)
	assert(def.id and def.item, "weapon needs id and item")
	W.weapons[def.id] = def
	W.defs_by_item[W.modname .. ":" .. def.item] = def

	local kind = def.kind or "hitscan"
	local refire = def.refire or 0.5

	minetest.register_tool(W.modname .. ":" .. def.item, {
		description = S(def.desc),
		inventory_image = def.texture,
		groups = { weapon = 1, not_in_crafting_guide = 1 },
		-- The blade is the melee answer; guns never punch as tools.
		tool_capabilities = nil,

		on_use = function(itemstack, user, pointed_thing)
			if not user or not user.is_player or not user:is_player() then
				return itemstack
			end
			local name = user:get_player_name()

			local gate_err = W.fire_gate(user)
			if gate_err then
				minetest.chat_send_player(name, minetest.colorize("#ff8844", gate_err))
				return itemstack
			end

			local ok, reason = W.fire_timing_ok(name, def.id, refire)
			if not ok then
				if reason == "raising" then
					minetest.chat_send_player(name, S("Raising weapon…"))
				elseif reason == "busy" then
					minetest.chat_send_player(name, def.busy_msg or S("Charging…"))
				end
				return itemstack
			end

			-- The magazine (v1.3): rounds live in the weapon stack;
			-- the pool is only the reserve a load pulls from. No
			-- round leaves the barrel on reserve alone.
			if def.pool then
				local loaded = W.mag_get(itemstack)
				if loaded < 1 then
					-- Dry. The click is loud: emptiness is information
					-- (council resolution #6) and ghosts gossip about it.
					minetest.sound_play("sl_weapons_dry_click", {
						pos = user:get_pos(), gain = 0.9, max_hear_distance = 16,
					})
					minetest.chat_send_player(name, S("Dry. Load it."))
					if def.id ~= "pistol" then
						W.autoswitch_pistol(user, def)
					end
					return itemstack
				end
				W.mag_set(itemstack, loaded - 1)
				if def.rounds_then_pause then
					W.rounds_fired[name] = (W.rounds_fired[name] or 0) + 1
					if W.rounds_fired[name] >= def.rounds_then_pause then
						W.rounds_fired[name] = 0
						W.busy_until[name] = W.now() + def.rounds_then_pause_time
						minetest.sound_play(def.pause_sound or "sl_weapons_spin", {
							pos = user:get_pos(), gain = 0.8, max_hear_distance = 16,
						})
					end
				end
			end

			-- Bloom is advanced before firing so the first shot of a
			-- burst is exact and the rest follow the published curve.
			if def.blooms then W.bloom_advance(name) end

			if kind == "hitscan" then
				W.fire_hitscan(user, def)
			elseif kind == "mortar" or kind == "pulse" then
				W.spawn_projectile(user, W.projectiles[kind])
			end
			return itemstack
		end,

		on_place = function(itemstack, placer, pointed_thing)
			if placer and placer.is_player and placer:is_player() then
				if def.zoom then
					-- Scoped weapons zoom; load them with a cache use.
					W.toggle_zoom(placer, def)
				elseif def.pool then
					-- Everyone else: right-click loads from the reserve.
					itemstack = W.mag_load(placer, def, itemstack)
				end
			end
			return itemstack
		end,

		on_secondary_use = function(itemstack, user, pointed_thing)
			if user and user.is_player and user:is_player() then
				if def.zoom then
					W.toggle_zoom(user, def)
				elseif def.pool then
					itemstack = W.mag_load(user, def, itemstack)
				end
			end
			return itemstack
		end,

		on_drop = def.no_drop and function(itemstack, dropper, pos)
			-- Loadout pistol is drop-locked: it dissolves instead of
			-- disarming newcomers (spec §5).
			minetest.sound_play("sl_weapons_dissolve", {
				pos = pos, gain = 0.5, max_hear_distance = 8,
			})
			return ItemStack("")
		end or nil,
	})
end

W.rounds_fired = {} -- Neon Six cylinder count

function W.autoswitch_pistol(user, fired_def)
	local name = user:get_player_name()
	local inv = user:get_inventory()
	if not inv then return end
	-- v1.3: the dry weapon steps aside for the pistol the player
	-- actually owns -- the most loaded one, moved into its slot. No
	-- free rounds are ever conjured by a dry click; with no pistol at
	-- all, an empty one parks there and the blade is the truth.
	local dry_slot
	local best_slot, best_mag
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		local iname = stack:get_name()
		if iname == "sl_weapons:" .. fired_def.item and not dry_slot then
			dry_slot = i
		elseif iname == "sl_weapons:pistol" then
			local m = W.mag_get(stack)
			if not best_slot or m > best_mag then
				best_slot, best_mag = i, m
			end
		end
	end
	if not dry_slot then return end
	if best_slot then
		inv:set_stack("main", dry_slot, inv:get_stack("main", best_slot))
		inv:set_stack("main", best_slot, ItemStack(""))
	else
		inv:set_stack("main", dry_slot, ItemStack("sl_weapons:pistol"))
	end
	minetest.chat_send_player(name, S("Switched to Pulsar Pistol."))
end

-- Scoped weapons: RMB toggles zoom (engine set_fov where available).
W.zoom = {} -- [name] = true
function W.toggle_zoom(user, def)
	local name = user:get_player_name()
	local on = not W.zoom[name]
	W.zoom[name] = on or nil
	if on then
		if user.set_fov then
			pcall(user.set_fov, user, 1.0 / (def.zoom or 2.5), false, 0.15)
		end
		minetest.sound_play("sl_weapons_zoom_in", {
			to_player = name, gain = 0.4,
		}, true)
	else
		if user.set_fov then
			pcall(user.set_fov, user, 0, true, 0.1)
		end
		minetest.sound_play("sl_weapons_zoom_out", {
			to_player = name, gain = 0.4,
		}, true)
	end
end

-- ----------------------------------------------------------------
-- The six (spec §3 table) — damage / refire / pools exactly as
-- specced against the 20 HP pool.
-- ----------------------------------------------------------------
W.register_weapon({
	id = "pistol", item = "pistol", desc = "Pulsar Pistol",
	texture = "sl_weapons_pistol.png",
	kind = "hitscan", damage = 4, refire = 0.35,
	range = 60, cause = "pistol", beacon_dmg = 1,
	pool = "bullets", mag = 12,
	sound = "sl_weapons_pistol_fire", hear = 28,
	no_drop = true,
})

W.register_weapon({
	id = "chatter", item = "chatter", desc = "Chatter SMG",
	texture = "sl_weapons_chatter.png",
	kind = "hitscan", damage = 2, refire = 0.09,
	range = 48, cause = "chatter", beacon_dmg = 1,
	pool = "bullets", mag = 30,
	-- Published bloom function (spec §3): first shot exact.
	spread = function(_name) return W.bloom_current(_name) end,
	blooms = true,
	sound = "sl_weapons_chatter_fire", hear = 36,
})

W.register_weapon({
	id = "scatter", item = "scatter", desc = "Riot Scatter",
	texture = "sl_weapons_scatter.png",
	kind = "hitscan", damage = 1.5, refire = 0.9,
	pellets = 8, spread = 9, range = 24,
	cause = "scatter", beacon_dmg = 1,
	pool = "shells", mag = 8,
	sound = "sl_weapons_scatter_fire", hear = 40,
})

W.register_weapon({
	id = "lance", item = "lance", desc = "Arc Lance",
	texture = "sl_weapons_lance.png",
	kind = "hitscan", damage = 18, refire = 1.6,
	range = 90, cause = "lance", beacon_dmg = 3,
	pool = "cells", mag = 6,
	zoom = 2.5,
	sound = "sl_weapons_lance_fire", hear = 48,
})

W.register_weapon({
	id = "mortar", item = "mortar", desc = "Fusion Mortar",
	texture = "sl_weapons_mortar.png",
	kind = "mortar", refire = 0.9,
	pool = "rockets", mag = 3, cause = "mortar",
	beacon_dmg = 4,
})

W.register_weapon({
	id = "driver", item = "driver", desc = "Pulse Driver",
	texture = "sl_weapons_driver.png",
	kind = "pulse", refire = 0.15,
	pool = "cells", mag = 20, cause = "driver",
	beacon_dmg = 1,
})

-- ----------------------------------------------------------------
-- The Neon Frontier (spec §3.1): frontier classics rebuilt as
-- system-era neon. Sidegrades — the metagame louder, not stronger.
-- ----------------------------------------------------------------
W.register_weapon({
	id = "six", item = "neon_six", desc = "Neon Six",
	texture = "sl_weapons_neon_six.png",
	kind = "hitscan", damage = 7, refire = 0.55,
	range = 60, cause = "six", beacon_dmg = 1,
	pool = "bullets", mag = 6,
	-- Six shots of light, then the cylinder spins itself for 2.5 s.
	-- The pause belongs to the gun; the hum belongs to the corridor.
	rounds_then_pause = 6,
	rounds_then_pause_time = 2.5,
	busy_msg = S("The cylinder spins…"),
	sound = "sl_weapons_six_fire", hear = 32,
})

W.register_weapon({
	id = "repeater", item = "neon_repeater", desc = "Neon Repeater",
	texture = "sl_weapons_repeater.png",
	kind = "hitscan", damage = 6, refire = 0.8,
	range = 72, cause = "repeater", beacon_dmg = 1,
	pool = "bullets", mag = 8,
	zoom = 2.0,
	sound = "sl_weapons_repeater_fire", hear = 24,
})

-- ----------------------------------------------------------------
-- Ammo items: trade bait (spec §1 — "ammunition without guns is
-- trade bait"). Using one loads it into the shooter's pools.
-- ----------------------------------------------------------------
local ammo_items = {
	{ "ammo_bullets", "Bullet Cache", "sl_weapons_ammo_bullets.png", "bullets" },
	{ "ammo_shells", "Shell Cache", "sl_weapons_ammo_shells.png", "shells" },
	{ "ammo_cells", "Cell Cache", "sl_weapons_ammo_cells.png", "cells" },
	{ "ammo_rockets", "Rocket Cache", "sl_weapons_ammo_rockets.png", "rockets" },
}

for _, a in ipairs(ammo_items) do
	minetest.register_craftitem(W.modname .. ":" .. a[1], {
		description = S(a[2]),
		inventory_image = a[3],
		on_use = function(itemstack, user, pointed_thing)
			if not user or not user.is_player or not user:is_player() then
				return itemstack
			end
			local name = user:get_player_name()
			local yield = W.AMMO_YIELD[a[4]]
			local added = W.add_ammo(name, a[4], yield)
			if added <= 0 then
				minetest.chat_send_player(name, S("Pools already full."))
				return itemstack
			end
			minetest.sound_play("sl_weapons_ammo_load", {
				to_player = name, gain = 0.5,
			}, true)
			-- One click, both jobs: while holding a matching weapon the
			-- cache tops up its magazine too (loading is convenient).
			if user.get_wielded_item then
				local wielded = user:get_wielded_item()
				local wdef = W.defs_by_item[wielded:get_name()]
				if wdef and wdef.pool == a[4] then
					user:set_wielded_item(W.mag_load(user, wdef, wielded))
				end
			end
			itemstack:take_item()
			return itemstack
		end,
	})
end


-- ----------------------------------------------------------------
-- Melee is consumable (team directive 2026-08-29): ranged weapons
-- burn magazines, knives burn themselves. Landed hits wear the
-- blade; a spent blade breaks. The Monster Master's doctrine hands
-- wear nothing -- they are not equipment.
-- ----------------------------------------------------------------
local MELEE_USES = {
	["sl_modebase:combat_blade"] = 40,
}

minetest.register_on_punchplayer(function(victim, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	if not hitter or not hitter.is_player or not hitter:is_player() then return end
	if not damage or damage <= 0 then return end
	if not hitter.get_wielded_item then return end
	local wield = hitter:get_wielded_item()
	local uses = MELEE_USES[wield:get_name()]
	if not uses then return end
	wield:add_wear(math.ceil(65535 / uses))
	local name = hitter:get_player_name()
	if wield:get_wear() >= 65535 then
		minetest.chat_send_player(name, S("The blade is spent."))
		minetest.sound_play("sl_weapons_blade_break", {
			to_player = name, gain = 0.8,
		}, true)
		hitter:set_wielded_item(ItemStack(""))
	else
		hitter:set_wielded_item(wield)
	end
end)
