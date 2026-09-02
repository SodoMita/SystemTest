-- ================================================================
-- sl_chatplay/sense.lua — text vision.
-- Identity-neutral: other players are reported as anonymous bodies
-- ("a boxman") with bearing/distance, exactly what the engine view
-- shows (identical skins, hidden nametags). Names surface only via
-- public channels (roster mirrors the in-game matchmaking formspec).
-- ================================================================

local C = sl_chatplay
local state = game_mode.state

-- Engine convention: +X = east, +Z = north. 8-point bearing, no trig.
function C.bearing(dx, dz)
	local abs_x, abs_z = math.abs(dx), math.abs(dz)
	if abs_x < 0.5 and abs_z < 0.5 then return "here" end
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

function C.dir_from_bearing(bear)
	local b = (bear or ""):lower()
	local dirs = {
		n = { 0, 0, 1 }, s = { 0, 0, -1 }, e = { 1, 0, 0 }, w = { -1, 0, 0 },
		ne = { 0.7071, 0, 0.7071 }, nw = { -0.7071, 0, 0.7071 },
		se = { 0.7071, 0, -0.7071 }, sw = { -0.7071, 0, -0.7071 },
		up = { 0, 1, 0 }, down = { 0, -1, 0 },
	}
	return dirs[b]
end

local function humanize_node(name)
	local def = minetest.registered_nodes[name]
	local label = def and def.description and def.description:gsub("\n.*", "") or name
	return label .. " (" .. name .. ")"
end

local function friendly_entity(label)
	local name = label or "?"
	local known = {
		["sl_modebase:monster"] = "monster",
		["sl_scary:dredger"] = "Dredger",
		["sl_scary:signal_wraith"] = "Signal Wraith",
		["sl_scary:containment"] = "Containment Horror",
		["sl_weapons:turret_head"] = "turret head",
	}
	return known[name] or name
end

-- Describe what the eye ray sees. Returns a string.
function C.cmd_look(player)
	local pos = player:get_pos()
	if not pos then return "No position." end
	local eye = { x = pos.x, y = pos.y + ((player:get_properties() or {}).eye_height or 1.625), z = pos.z }
	local dir = player:get_look_dir()
	if not dir then dir = C.dir_from_bearing("n") end
	local range = 48
	local endpoint = vector.add(eye, vector.multiply(dir, range))

	local hit_desc = {}
	for hit in minetest.raycast(eye, endpoint, true, false) do
		if hit.type == "object" then
			local obj = hit.ref
			local lua = obj.get_luaentity and obj:get_luaentity()
			if lua and (lua.sl_weapon_fx or lua.sl_corpse) then
				-- cosmetic; keep scanning
			elseif obj.is_player and obj:is_player() then
				local d = math.floor(vector.distance(eye, obj:get_pos()) + 0.5)
				local who = (obj:get_player_name() == player:get_player_name()) and "YOU" or "a boxman"
				table.insert(hit_desc, who .. " " .. d .. "m")
			else
				local d = math.floor(vector.distance(eye, obj:get_pos()) + 0.5)
				table.insert(hit_desc, friendly_entity(lua and lua.name) .. " " .. d .. "m")
			end
		elseif hit.type == "node" then
			local node = minetest.get_node(hit.under or hit.pos)
			if node and node.name and node.name ~= "air" then
				local d = math.floor(vector.distance(eye, hit.under or hit.pos) + 0.5)
				table.insert(hit_desc, humanize_node(node.name) .. " " .. d .. "m")
				break
			end
		end
	end

	local under = minetest.get_node({ x = pos.x, y = pos.y - 1, z = pos.z })
	local lines = {
		string.format("At %s you stand over %s.",
			(minetest.pos_to_string(vector.round(pos))),
			under.name and under.name ~= "air" and humanize_node(under.name) or "a void"),
	}
	if #hit_desc == 0 then
		table.insert(lines, "Nothing in the beam.")
	else
		table.insert(lines, "Beam: " .. table.concat(hit_desc, ", "))
	end
	return table.concat(lines, "\n")
end

-- Scan radius: nodes by kind + entities + anonymous players.
function C.cmd_sense(player, radius)
	local pos = player:get_pos()
	if not pos then return "No position." end
	radius = math.max(4, math.min(48, math.floor(tonumber(radius) or 20)))

	local me_name = player:get_player_name()
	local lines = {}

	-- Interesting nodes near me (objective/system objects, not raw terrain)
	local wanted = {
		["sl_modebase:beacon_a"] = "BEACON A",
		["sl_modebase:beacon_b"] = "BEACON B",
		["sl_modebase:loot_crate"] = "loot crate",
		["sl_modebase:ghost_altar"] = "ghost altar",
		["sl_modebase:monster_spawner"] = "monster spawner",
		["sl_modebase:item_pickup"] = "pickup",
		["sl_modebase:terminal"] = "terminal",
		["sl_weapons:pad_weapon"] = "weapon pad",
		["sl_weapons:pad_weapon_dim"] = "weapon pad (empty)",
		["sl_weapons:pad_ammo"] = "ammo pad",
		["sl_weapons:pad_ammo_dim"] = "ammo pad (empty)",
		["sl_weapons:turret"] = "sentry turret",
	}
	local node_hits = {}
	for node_name, label in pairs(wanted) do
		local found = minetest.find_nodes_in_area(
			{ x = pos.x - radius, y = pos.y - radius, z = pos.z - radius },
			{ x = pos.x + radius, y = pos.y + radius, z = pos.z + radius },
			node_name)
		for _, n in ipairs(found) do
			local d = vector.distance(pos, n)
			if d <= radius then
				table.insert(node_hits, {
					d = d, label = label, pos = n,
					hash = C.pos_key(n),
				})
			end
		end
	end
	table.sort(node_hits, function(a, b) return a.d < b.d end)
	for i, h in ipairs(node_hits) do
		if i <= 14 then
			local dx, dz = h.pos.x - pos.x, h.pos.z - pos.z
			lines[#lines + 1] = string.format("  N%d  %-16s %3dm %s",
				i, h.label, math.floor(h.d + 0.5), C.bearing(dx, dz))
		end
	end

	-- Entities (monsters, corpses, projectiles) — they are visible bodies.
	local ecount = 0
	for _, obj in ipairs(minetest.get_objects_inside_radius(pos, radius)) do
		local lua = obj.get_luaentity and obj:get_luaentity()
		if lua and not (lua.sl_weapon_fx or lua.sl_corpse) then
			ecount = ecount + 1
			local op = obj.get_pos and obj:get_pos()
			if op and ecount <= 10 then
				local d = vector.distance(pos, op)
				local dx, dz = op.x - pos.x, op.z - pos.z
				lines[#lines + 1] = string.format("  E%d  %-16s %3dm %s",
					ecount, friendly_entity(lua.name), math.floor(d + 0.5), C.bearing(dx, dz))
			end
		end
	end

	-- Players: anonymous bodies, identity-neutral.
	local bodies = 0
	local pcount = 0
	for _, p in ipairs(minetest.get_connected_players()) do
		pcount = pcount + 1
		local pname = p:get_player_name()
		if pname ~= me_name and p:get_pos() then
			local d = vector.distance(pos, p:get_pos())
			if d <= radius then
				bodies = bodies + 1
				local dx, dz = p:get_pos().x - pos.x, p:get_pos().z - pos.z
				lines[#lines + 1] = string.format("  P%d  %-16s %3dm %s",
					bodies, "a boxman", math.floor(d + 0.5), C.bearing(dx, dz))
			end
		end
	end

	local head = string.format("Sense @ %s (r=%dm): %d systems, %d air, %d bodies, %d sensors.",
		minetest.pos_to_string(vector.round(pos)), radius,
		#node_hits, ecount, bodies, pcount)
	if #lines == 0 then
		return head .. "\n  (nothing notable)"
	end
	return head .. "\n" .. table.concat(lines, "\n")
end

function C.pos_key(pos)
	return string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
end

-- Nearest node of a set of names within radius of player.
function C.nearest_node(player, names, radius, exclude_pos)
	local pos = player:get_pos()
	if not pos then return nil end
	radius = radius or 12
	local best, best_d
	for _, node_name in ipairs(names) do
		local found = minetest.find_nodes_in_area(
			{ x = pos.x - radius, y = pos.y - radius, z = pos.z - radius },
			{ x = pos.x + radius, y = pos.y + radius, z = pos.z + radius },
			node_name)
		for _, n in ipairs(found) do
			if not exclude_pos or C.pos_key(n) ~= C.pos_key(exclude_pos) then
				local d = vector.distance(pos, n)
				if not best_d or d < best_d then
					best, best_d = n, d
				end
			end
		end
	end
	return best
end
