-- ================================================================
-- sl_weapons — the Monster Master's doctrine (spec §6.1)
-- No towers. No ranged weapons, ever — stripped on grant, stripped
-- from the inventory, refused at input. Bare hands evolve through
-- the skill tree; items never do. Tyrant Grip ships here (4/7/10);
-- Long Arm and Tremor Palm are specced and parked pending the
-- sl_gui ability-tree bridge (W3 numbers check).
-- ================================================================

local W = sl_weapons
local S = W.S

-- Tyrant Grip damage by level (0 = baseline hand). Two punches kill
-- an outpositioned player at tier III — strong, but the MM had to
-- arrive, against six guns, floating.
W.MM_GRIP_DAMAGE = { [0] = 3, 4, 7, 10 }

function W.get_mm_levels(player)
	local meta = player.get_meta and player:get_meta()
	if not meta then return { grip = 0 } end
	local raw = meta:get_string("sl_mm_hands")
	local data = raw ~= "" and minetest.deserialize(raw) or nil
	return { grip = (data and data.grip) or 0 }
end

function W.set_mm_levels(player, levels)
	local meta = player.get_meta and player:get_meta()
	if not meta then return end
	local cur = W.get_mm_levels(player)
	local grip = math.max(0, math.min(3, tonumber(levels.grip) or cur.grip))
	meta:set_string("sl_mm_hands", minetest.serialize({ grip = grip }))
end

-- MM hand damage overrides the engine's default punch through the
-- standard guard pipeline (guards replicated: lobby, immortals).
minetest.register_on_punchplayer(function(victim, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	if not victim or not hitter or not hitter.is_player or not hitter:is_player() then
		return
	end
	if not (game_mode and game_mode.state and game_mode.state.match_active) then
		return
	end
	local hname = hitter:get_player_name()
	local pl = game_mode.get_player_state(hname)
	if not pl or pl.role ~= "monster_master" then return end
	local wield = hitter.get_wielded_item and hitter:get_wielded_item():get_name() or ""
	if wield ~= "" then return end -- bare hands only: the doctrine
	local varmor = victim.get_armor_groups and victim:get_armor_groups() or {}
	if (varmor.immortal or 0) > 0 then return end

	local dmg = W.MM_GRIP_DAMAGE[W.get_mm_levels(hitter).grip] or 3
	victim:set_hp(math.max(0, victim:get_hp() - dmg))
	minetest.sound_play("sl_weapons_mm_strike", {
		pos = victim:get_pos(), gain = 0.7, max_hear_distance = 18,
	})
	return true -- cancel the engine's default hand damage
end)

-- Strip ranged items from the MM's inventory: refused at pickup is
-- the ideal, the 1 s sweep is the enforcement (spec §4 MM gate).
local strip_accum = 0
minetest.register_globalstep(function(dtime)
	strip_accum = strip_accum + dtime
	if strip_accum < 1.0 then return end
	strip_accum = 0
	if not game_mode then return end
	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local pl = game_mode.get_player_state(name)
		if pl and pl.role == "monster_master" then
			local inv = player:get_inventory()
			if inv then
				for i = 1, inv:get_size("main") do
					local stack = inv:get_stack("main", i)
					local iname = stack:get_name()
					local is_ranged = W.defs_by_item[iname] ~= nil
						or iname == W.modname .. ":sentry_kit"
						or iname == W.modname .. ":grapple"
					if is_ranged and not pl._mm_strip_warned then
						pl._mm_strip_warned = true
						minetest.chat_send_player(name, minetest.colorize("#ff8844",
							S("Your hands are the doctrine.")))
					end
					if is_ranged then
						inv:set_stack("main", i, ItemStack(""))
					end
				end
			end
		else
			local plx = game_mode.get_player_state(name)
			if plx then plx._mm_strip_warned = nil end
		end
	end
end)

-- Grant-time strip: wrap set_monster_master if present.
if game_mode and game_mode.set_monster_master then
	local orig_smm = game_mode.set_monster_master
	game_mode.set_monster_master = function(...)
		local results = { orig_smm(...) }
		local name = select(1, ...)
		if name then
			local player = minetest.get_player_by_name(name)
			if player then
				local inv = player:get_inventory()
				if inv then
					for i = 1, inv:get_size("main") do
						local stack = inv:get_stack("main", i)
						local iname = stack:get_name()
						if W.defs_by_item[iname]
							or iname == W.modname .. ":sentry_kit"
							or iname == W.modname .. ":grapple" then
							inv:set_stack("main", i, ItemStack(""))
						end
					end
				end
			end
			minetest.chat_send_player(name, minetest.colorize("#ff8844",
				S("Your hands are the doctrine.")))
		end
		return unpack(results)
	end
end
