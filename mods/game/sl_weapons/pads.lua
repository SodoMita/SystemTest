-- ================================================================
-- sl_weapons — weapon & ammo pads (spec §5)
-- Quake item pads in ownership-neutral clothing. Chimes identify
-- the weapon by pitch (council resolution #1): the arena is a radio
-- station, the chime is the headline. Pads are possessable — an
-- evil ghost can silence a pad; two weapon hits exorcise it.
-- ================================================================

local W = sl_weapons
local S = W.S

local PAD_RESPAWN_WEAPON = function()
	return W.get_setting_number("sl_weapons_pad_respawn", 30)
end
local PAD_RESPAWN_AMMO = 20

-- Pitch per weapon / ammo kind: mortar low and long, cells high and
-- quick. A player with three matches of ears knows through a wall.
W.CHIME_PITCH = {
	pistol = 1.0, chatter = 1.1, scatter = 0.8, lance = 1.2,
	mortar = 0.6, driver = 1.4, six = 0.7, repeater = 0.9,
	bullets = 1.0, shells = 0.8, cells = 1.5, rockets = 0.6,
}

W.pads = {} -- [phash] = { pos, kind, item, armed, rearm_at }

local function pad_meta_fields(entry)
	return {
		kind = entry.kind,
		item = entry.item,
		armed = entry.armed and "1" or "0",
		rearm_at = tostring(math.floor(entry.rearm_at or 0)),
	}
end

local function pad_write_meta(pos, entry)
	local meta = minetest.get_meta(pos)
	for k, v in pairs(pad_meta_fields(entry)) do
		meta:set_string("sl_pad_" .. k, v)
	end
	meta:set_string("infotext", entry.armed
		and S("Supply Pad (@1)", tostring(entry.item))
		or S("Supply Pad (depleted)"))
end

local function register_pad_pair(kind, desc, tile)
	local armed_name = W.modname .. ":pad_" .. kind
	local dim_name = armed_name .. "_dim"
	local base = {
		description = S(desc),
		tiles = { tile },
		paramtype = "light",
		groups = { cracky = 2, possessable = 1 },
		is_ground_content = false,
		walkable = false,
		drop = "",
	}
	minetest.register_node(armed_name, {
		description = base.description,
		tiles = base.tiles,
		paramtype = base.paramtype,
		light_source = 8,
		groups = { cracky = 2, possessable = 1 },
		is_ground_content = false,
		walkable = false,
		on_construct = function(pos)
			-- Hand-placed defaults; builders with the API override.
			W.pad_register(pos, kind, kind == "weapon" and "pistol" or "bullets", true)
		end,
		on_rightclick = function(pos, node, clicker)
			if game_mode and game_mode.refuse_if_possessed
				and game_mode.refuse_if_possessed(pos, clicker) then
				return
			end
			if game_mode and game_mode.refuse_if_sabotaged
				and game_mode.refuse_if_sabotaged(pos, clicker) then
				return
			end
			local entry = W.pads[W.phash(pos)]
			if entry then
				minetest.chat_send_player(clicker:get_player_name(),
					entry.armed and S("The pad is armed. Step on it.") or S("Depleted. It will return."))
			end
		end,
	})
	minetest.register_node(dim_name, {
		description = S(desc .. " (depleted)"),
		tiles = { tile .. "^[opacity:60" },
		paramtype = base.paramtype,
		light_source = 1,
		groups = { cracky = 2, possessable = 1, not_in_creative_inventory = 1 },
		is_ground_content = false,
		walkable = false,
		drop = "",
	})
end

register_pad_pair("weapon", "Weapon Pad", sl_texgen.texture("sl_weapons_pad_ring.png"))
register_pad_pair("ammo", "Ammo Pad", sl_texgen.texture("sl_weapons_pad_ammo_ring.png"))

function W.pad_register(pos, kind, item, armed, rearm_at)
	local entry = {
		pos = vector.round(pos),
		kind = kind,
		item = item,
		armed = armed ~= false,
		rearm_at = rearm_at or 0,
	}
	W.pads[W.phash(entry.pos)] = entry
	pad_write_meta(entry.pos, entry)
	return entry
end

function W.place_weapon_pad(pos, weapon_id)
	assert(W.weapons[weapon_id], "unknown weapon id: " .. tostring(weapon_id))
	minetest.set_node(vector.round(pos), { name = W.modname .. ":pad_weapon" })
	return W.pad_register(pos, "weapon", weapon_id, true)
end

function W.place_ammo_pad(pos, ammo_kind)
	assert(W.AMMO_YIELD[ammo_kind], "unknown ammo kind: " .. tostring(ammo_kind))
	minetest.set_node(vector.round(pos), { name = W.modname .. ":pad_ammo" })
	return W.pad_register(pos, "ammo", ammo_kind, true)
end

local function pad_set_armed(entry, armed, rearm_at)
	entry.armed = armed
	entry.rearm_at = rearm_at or 0
	local want = W.modname .. ":pad_" .. entry.kind .. (armed and "" or "_dim")
	if minetest.get_node(entry.pos).name ~= want then
		minetest.set_node(entry.pos, { name = want })
	end
	pad_write_meta(entry.pos, entry)
end

function W.pads_rearm_all()
	for _, entry in pairs(W.pads) do
		pad_set_armed(entry, true, 0)
	end
end

local function chime(pos, item, gain)
	minetest.sound_play("sl_weapons_pad_chime", {
		pos = pos,
		gain = gain or 0.9,
		max_hear_distance = 32,
		pitch = W.CHIME_PITCH[item] or 1.0,
	})
end

local function try_dispense(player, pos, entry)
	local name = player:get_player_name()
	if game_mode then
		local pl = game_mode.get_player_state(name)
		if not pl or pl.role == "monster_master" or pl.phase ~= "alive" then return end
		if not (game_mode.state and game_mode.state.match_active) then return end
		if game_mode.is_possessed and game_mode.is_possessed(pos) then return end
		if game_mode.is_sabotaged and game_mode.is_sabotaged(pos) then return end
	end
	local inv = player:get_inventory()
	if entry.kind == "weapon" then
		local itemname = W.modname .. ":" .. W.weapons[entry.item].item
		if inv:contains_item("main", itemname) then return end -- no dupe hoarding
		-- Weapons come off the pad loaded (v1.3).
		inv:add_item("main", W.defs_by_item[itemname]
			and W.loaded_stack(itemname) or ItemStack(itemname))
	elseif entry.kind == "ammo" then
		local added = W.add_ammo(name, entry.item, W.AMMO_YIELD[entry.item])
		if added <= 0 then return end -- full pools leave the pad armed
	end
	chime(pos, entry.item)
	pad_set_armed(entry, false, W.now()
		+ (entry.kind == "weapon" and PAD_RESPAWN_WEAPON() or PAD_RESPAWN_AMMO))
end

local pad_accum = 0
minetest.register_globalstep(function(dtime)
	pad_accum = pad_accum + dtime
	if pad_accum < 0.25 then return end
	pad_accum = 0

	-- Rearm timers: the chime on re-arm is the arena's heartbeat.
	local now = W.now()
	for _, entry in pairs(W.pads) do
		if not entry.armed and entry.rearm_at > 0 and now >= entry.rearm_at then
			pad_set_armed(entry, true, 0)
			chime(entry.pos, entry.item, 0.6)
		end
	end

	for _, player in ipairs(minetest.get_connected_players()) do
		local p = player:get_pos()
		local candidates = {
			vector.round(p),
			vector.round({ x = p.x, y = p.y - 1, z = p.z }),
		}
		for _, pos in ipairs(candidates) do
			local node = minetest.get_node(pos)
			local entry = W.pads[W.phash(pos)]
			if entry and entry.armed
				and (node.name == W.modname .. ":pad_" .. entry.kind) then
				try_dispense(player, pos, entry)
			end
		end
	end
end)
