-- ================================================================
-- sl_weapons — HUD: the shooter's own state and nobody else's
-- (spec §11: same policy as the stamina HUD — local state only).
-- Ammo readout bottom-right; lash/zoom/busy indicators inline.
-- ================================================================

local W = sl_weapons
local S = W.S

W.hud_ids = {} -- [name] = hud element id

local function hud_line(name)
	local pool = W.peek_pool(name)
	local line = string.format("B %d/%d  S %d/%d  C %d/%d  R %d/%d",
		pool.bullets, W.POOL_MAX.bullets,
		pool.shells, W.POOL_MAX.shells,
		pool.cells, W.POOL_MAX.cells,
		pool.rockets, W.POOL_MAX.rockets)
	if W.lash and W.lash[name] then
		line = line .. "  [LASH]"
	end
	if W.zoom and W.zoom[name] then
		line = line .. "  [ZOOM]"
	end
	if (W.busy_until[name] or 0) > W.now() then
		line = line .. "  [SPIN]"
	end
	return line
end

function W.hud_hide(name)
	local id = W.hud_ids[name]
	if id and minetest.get_player_by_name(name) then
		local player = minetest.get_player_by_name(name)
		player:hud_remove(id)
	end
	W.hud_ids[name] = nil
end

local hud_accum = 0
minetest.register_globalstep(function(dtime)
	hud_accum = hud_accum + dtime
	if hud_accum < 0.3 then return end
	hud_accum = 0
	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local has_weapon = false
		local inv = player:get_inventory()
		if inv then
			for i = 1, inv:get_size("main") do
				local iname = inv:get_stack("main", i):get_name()
				if W.defs_by_item[iname] or iname == W.modname .. ":grapple" then
					has_weapon = true
					break
				end
			end
		end
		local pool = W.peek_pool(name)
		local has_ammo = pool.bullets + pool.shells + pool.cells + pool.rockets > 0
		local show = has_weapon or has_ammo

		local id = W.hud_ids[name]
		if show and not id then
			W.hud_ids[name] = player:hud_add({
				hud_elem_type = "text",
				position = { x = 0.99, y = 0.62 },
				offset = { x = 0, y = 0 },
				alignment = { x = -1, y = 0 },
				scale = { x = 100, y = 100 },
				number = 0x66ddff,
				text = hud_line(name),
				z_index = 100,
			})
		elseif show and id then
			player:hud_change(id, "text", hud_line(name))
		elseif not show and id then
			player:hud_remove(id)
			W.hud_ids[name] = nil
		end
	end
end)
