-- ================================================================
-- sl_weapons — ranged combat layer for System Looting
-- Spec: WEAPONS_SPEC.md (v1.2). Owner mod of work package WP9.
--
-- File map (see spec §12):
--   api.lua         gates, ammo pools, fire timing, bloom, incident feed
--   hitscan.lua     raycast weapons, tracers, node impacts, exorcism
--   projectiles.lua mortar / pulse entities, splash, knockback
--   weapons.lua     the eight weapons + ammo items
--   hud.lua         ammo readout
--   corpses.lua     corpse entity, incident report, burial/cremation,
--                   residue/mound/scorch, the Deadwalk Puppet
--   pads.lua        weapon / ammo pads with pitched chimes
--   turret.lua      Sentry Kit, turret node, targeting log
--   grapple.lua     the Grapple Lash
--   fabricator.lua  Precision Fabricator station (Lash / Kit jobs)
--   mm_hands.lua    Monster Master bare-hand doctrine + item stripping
-- ================================================================

sl_weapons = rawget(_G, "sl_weapons") or {}

local W = sl_weapons
W.modname = minetest.get_current_modname()
W.modpath = minetest.get_modpath(W.modname)
W.S = minetest.get_translator(W.modname)
local S = W.S

local function include(file)
	dofile(W.modpath .. "/" .. file)
end

include("api.lua")
include("hitscan.lua")
include("projectiles.lua")
include("weapons.lua")
include("corpses.lua")
include("pads.lua")
include("turret.lua")
include("grapple.lua")
include("fabricator.lua")
include("mm_hands.lua")
include("hud.lua")

-- ----------------------------------------------------------------
-- Match lifecycle plumbing. sl_modebase is a hard dependency; the
-- wrappers below are non-invasive (no edits to its functions):
-- start_new_match -> loadout + fresh pools + rearmed pads
-- end_match       -> full scene sweep (spec §7, §8 "match reset" row)
-- ----------------------------------------------------------------
if game_mode then
	local orig_start = game_mode.start_new_match
	if orig_start then
		game_mode.start_new_match = function(...)
			local results = { orig_start(...) }
			if results[1] then
				local ok, err = pcall(W.on_match_start)
				if not ok then
					minetest.log("error", "[sl_weapons] on_match_start: " .. tostring(err))
				end
			end
			return unpack(results)
		end
	end

	local orig_end = game_mode.end_match
	if orig_end then
		game_mode.end_match = function(...)
			local results = { orig_end(...) }
			local ok, err = pcall(W.on_match_end)
			if not ok then
				minetest.log("error", "[sl_weapons] on_match_end: " .. tostring(err))
			end
			return unpack(results)
		end
	end
end

minetest.register_on_leaveplayer(function(player)
	local name = player and player:get_player_name()
	if not name then return end
	W.pools[name] = nil
	W.next_fire[name] = nil
	W.raise_at[name] = nil
	W.busy_until[name] = nil
	W.last_weapon[name] = nil
	W.bloom[name] = nil
	W.lash_detach(name)
	if W.hud_hide then W.hud_hide(name) end
end)

-- ---------------------------------------------------------------
-- Salvage pickup weapons section (spec §5): loot crates / loose
-- items may roll weapon + ammo bundles — Sentry Kit weight ≈ 10 %.
-- The Grapple Lash appears on NO random table, ever (§10.1).
-- ---------------------------------------------------------------
if game_mode and game_mode.register_pickup_roll then
	game_mode.register_pickup_roll(W.modname .. ":sentry_kit", 1, 0.45)
	game_mode.register_pickup_roll(W.modname .. ":ammo_shells", 4, 0.45)
end

-- The Precision Fabricator is a workshop, and mapgen places no
-- workshops: it is assembled through the inventory crafting menu,
-- entirely from monster spoils (team directive 2026-08-29 — the
-- station is rare because its parts are torn out of monsters).
minetest.register_on_mods_loaded(function()
	if not register_craft_recipe then return end
	register_craft_recipe({
		output = W.modname .. ":fabricator",
		output_count = 1,
		ingredients = {
			["sl_modebase:metal_ingot"] = 6,
			["sl_modebase:circuit_board"] = 4,
			["sl_modebase:energy_crystal"] = 2,
			["sl_modebase:plastic_scrap"] = 3,
		},
		description = S("Precision Fabricator (workshop — fabricates the Grapple Lash and Sentry Kits)"),
		category = "tactical",
	})
end)

minetest.log("action", "[sl_weapons] loaded: " .. tostring(W.modpath))
