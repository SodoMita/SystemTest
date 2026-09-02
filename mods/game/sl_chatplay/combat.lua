-- ================================================================
-- sl_chatplay/combat.lua -- fire / melee resolution.
-- Honest pipeline: gates, timing, magazines and node/entity hits run
-- through the REAL sl_weapons code (same on_use the mouse calls).
-- Fake-player targets (harness players) cannot be seen by engine
-- raycasts, so damage is routed through the same registered
-- on_punchplayer chain the botmatch harness uses, then applied with
-- set_hp exactly like botmatch.punch_player does.
-- ================================================================

local C = sl_chatplay
local W = rawget(_G, "sl_weapons")
local state = game_mode.state

function C.ref_is_console(player)
	return player and player.is_console == true
end

-- botmatch fake players (and the console) are plain Lua tables; the
-- engine's real PlayerRefs are userdata. Raycasts cannot see tables and
-- their :punch() is a no-op, so combat against them must go through the
-- synthetic punch_event path (the same one botmatch uses).
-- NOTE: is_player resolves via the metatable to a FUNCTION on fakes, so
-- it never equals true; the type check alone is the robust discriminator.
function C.ref_is_fake(player)
	return player and type(player) == "table" and player.get_player_name ~= nil
end

-- Aim the "suit": for the console player this sets the look vector the
-- weapon pipeline reads; for real players the engine owns the look.
function C.set_aim(player, dir)
	local console = C.ref_is_console(player)
	if console and player.set_aim then
		player:set_aim(dir)
		return true
	end
	return false
end

-- Point the player (console) at a world position.
function C.face_target(player, pos)
	local me = player:get_pos()
	if not me or not pos then return end
	-- Must match W.aim()'s eye height exactly, or the fired ray (from
	-- eye_height 1.625) passes over / under the target's hitbox.
	local eye_h = 1.625
	local props = player.get_properties and player:get_properties()
	if props and props.eye_height then eye_h = props.eye_height end
	local d = vector.subtract(pos, { x = me.x, y = me.y + eye_h, z = me.z })
	local n = vector.normalize(d)
	C.set_aim(player, n)
end

-- Line of sight: sample the segment; only solid nodes block.
function C.los_clear(from, to)
	local dist = vector.distance(from, to)
	local steps = math.max(1, math.floor(dist / 1.5))
	for i = 1, steps - 1 do
		local p = vector.add(from, vector.multiply(vector.subtract(to, from), i / steps))
		local node = minetest.get_node(p)
		if node and node.name ~= "air" and node.name ~= "ignore" then
			local desc = minetest.registered_nodes[node.name]
			return false, (desc and desc.description or node.name):gsub("\n.*", "")
		end
	end
	return true
end

-- Set the console's wielded stack (real players use /cp wield, which
-- moves a knife into the hand themselves).
function C.set_wield(player, stack)
	if C.ref_is_console(player) and player.set_wielded then
		player:set_wielded(stack)
	end
end

-- Weapon shot at a NODE or real ENTITY: real on_use path (raycast).
-- Returns reply text on failure, nil on success.
function C.real_shot(player, def, stack)
	if not def then return "Empty hands. Wield a weapon first (/cp wield)." end
	local pname = player:get_player_name()
	local gate_err = W.fire_gate(player)
	if gate_err then return gate_err end
	local ok, reason = W.fire_timing_ok(pname, def.id, def.refire or 0.5)
	if not ok then
		return reason == "raising" and "Raising weapon..." or (def.busy_msg or "Charging...")
	end
	local loaded = W.mag_get and W.mag_get(stack) or 1
	if loaded < 1 then
		minetest.sound_play("sl_weapons_dry_click", { pos = player:get_pos(), gain = 0.9, max_hear_distance = 16 })
		return "Dry. Load it. (/cp load)"
	end
	if W.mag_set then W.mag_set(stack, loaded - 1) end
	-- persist to the inventory slot (console _wield is the live object,
	-- but the inventory keeps a string snapshot)
	if player.set_wielded_item then player:set_wielded_item(stack) end
	-- rounds_then_pause (mirrors weapons.lua on_use tail)
	if def.rounds_then_pause then
		W.rounds_fired[pname] = (W.rounds_fired[pname] or 0) + 1
		if W.rounds_fired[pname] >= def.rounds_then_pause then
			W.rounds_fired[pname] = 0
			W.busy_until[pname] = W.now() + def.rounds_then_pause_time
			minetest.sound_play(def.pause_sound or "sl_weapons_spin", {
				pos = player:get_pos(), gain = 0.8, max_hear_distance = 16 })
		end
	end
	if def.blooms and W.bloom_advance then W.bloom_advance(pname) end
	-- IMPORTANT: do NOT call tool_def.on_use here. on_use re-checks
	-- fire_timing_ok, which we already advanced above — it would fail
	-- with "refire" and bail before W.fire_hitscan, spending the round
	-- without ever firing. Dispatch to the weapon's firing kind directly.
	if def.kind == "hitscan" then
		W.fire_hitscan(player, def)
	elseif def.kind == "mortar" or def.kind == "pulse" then
		if W.spawn_projectile and W.projectiles then
			W.spawn_projectile(player, W.projectiles[def.kind])
		end
	end
	return nil
end

-- Shot at a FAKE (harness) player: mag/timing/gates identical, damage
-- routed through the registered punch chain.
function C.synthetic_shot(player, def, stack, victim, victim_name)
	local pname = player:get_player_name()
	local gate_err = W.fire_gate(player)
	if gate_err then return gate_err end
	local ok, reason = W.fire_timing_ok(pname, def.id, def.refire or 0.5)
	if not ok then
		return reason == "raising" and "Raising weapon..." or (def.busy_msg or "Charging...")
	end
	local loaded = W.mag_get and W.mag_get(stack) or 1
	if loaded < 1 then
		minetest.sound_play("sl_weapons_dry_click", { pos = player:get_pos(), gain = 0.9, max_hear_distance = 16 })
		return "Dry. Load it. (/cp load)"
	end
	if W.mag_set then W.mag_set(stack, loaded - 1) end
	if player.set_wielded_item then player:set_wielded_item(stack) end
	if def.blooms and W.bloom_advance then W.bloom_advance(pname) end

	local eye = player:get_pos()
	local vpos = victim:get_pos()
	if not eye or not vpos then return "No position." end
	local range = def.range or 60
	local dist = vector.distance(eye, vpos)
	if dist > range then
		return string.format("Out of range: %dm (max %dm).", math.floor(dist), range)
	end
	local ok_los, block = C.los_clear(eye, vpos)
	if not ok_los then return "Blocked by " .. (block or "terrain") .. "." end

	local dmg = (def.damage or 4) * (def.pellets or 1)
	if W.last_cause then W.last_cause[victim_name] = def.cause or def.id end

	C.punch_event(player, victim, dmg, def.refire or 0.5, def.cause or def.id)
	if def.sound then
		minetest.sound_play(def.sound, { pos = eye, gain = 0.7, max_hear_distance = def.hear or 32 })
	end
	return nil
end

-- Drive the punch chain + HP (identical to botmatch.punch_player).
function C.punch_event(hitter, victim, dmg, interval, cause)
	local name = hitter:get_player_name()
	local vname = victim:get_player_name()
	local dir = vector.subtract(victim:get_pos(), hitter:get_pos())
	local before = victim:get_hp() or 20
	local canceled = false
	if botmatch and botmatch.fire then
		canceled = botmatch.fire("punchplayer", victim, hitter, 1.0,
			{ full_punch_interval = interval or 1.0, damage_groups = { fleshy = dmg } }, dir, dmg)
	elseif victim.punch then
		victim:punch(hitter, 1.0, { full_punch_interval = interval or 1.0, damage_groups = { fleshy = dmg } }, dir)
	end
	if canceled then return end
	victim:set_hp(before - dmg)
	if before - dmg <= 0 and before > 0 then
		if botmatch and botmatch.attribute_kill then
			botmatch.attribute_kill(name, vname)
		end
		if W and W.incident then
			W.incident(vname, cause,
				{ range = W.range_bucket and W.range_bucket(vector.distance(hitter:get_pos(), victim:get_pos())) or "close" })
		end
	end
end

-- Melee on a player/entity (blade wear runs through the registered
-- on_punchplayer melee handlers).
function C.melee(player, victim, victim_name)
	local wield = player:get_wielded_item()
	local iname = wield:get_name()
	local dmg = 1
	local interval = 0.8
	if iname ~= "" then
		local tool_def = minetest.registered_tools[iname]
		local caps = tool_def and tool_def.tool_capabilities
		if caps and caps.damage_groups and caps.damage_groups.fleshy then
			dmg = caps.damage_groups.fleshy
		end
		interval = caps and caps.full_punch_interval or 0.8
	end
	if iname == "sl_weapons:severance" then dmg = 200 end
	C.punch_event(player, victim, dmg, interval, "melee")
	return nil
end

-- Right-click a node through the real on_rightclick.
function C.rightclick(pos, player)
	local node = minetest.get_node(pos)
	if not node or node.name == "air" then return "Nothing there." end
	local def = minetest.registered_nodes[node.name]
	if not def or not def.on_rightclick then
		return (def and def.description or node.name) .. " has no interface."
	end
	local wield = player:get_wielded_item()
	def.on_rightclick(pos, node, player, wield, { type = "node", under = pos, above = pos })
	return nil
end

-- Punch a node (repair / exorcism / beacon siege): fires the registered
-- on_punchnode handlers exactly like botmatch.repair_node.
function C.punch_node(pos, player, times)
	local node = minetest.get_node(pos)
	if not node or node.name == "air" then return "Nothing there." end
	local def = minetest.registered_nodes[node.name]
	times = times or 1
	for _ = 1, times do
		-- The engine calls BOTH the node's on_punch AND the global
		-- register_on_punchnode hooks. botmatch.fire("punchnode") only
		-- dispatches the global hooks, so call the node callback too —
		-- otherwise beacons (damage in on_punch) never take melee hits.
		if def and def.on_punch then
			def.on_punch(pos, node, player, 1.0, { type = "node", under = pos })
		end
		if botmatch and botmatch.fire then
			botmatch.fire("punchnode", pos, node, player, { type = "node", under = pos })
		end
	end
	local name = def and def.description and def.description:gsub("\n.*", "") or node.name
	return "Interaction with " .. name .. "."
end
