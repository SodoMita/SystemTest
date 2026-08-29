-- ================================================================
-- sl_weapons — hitscan pipeline (spec §4)
-- Raycast from the eye, tracer + report sound, damage applied via
-- object:punch so the sl_modebase guards stay authoritative.
-- Node impacts: beacon chip damage (spec §9), ranged exorcism of
-- possessed objects (council resolution #5 — two hits, same rule as
-- two punches, longer reach).
-- ================================================================

local W = sl_weapons
local S = W.S

-- Ranged exorcism hit counting: [pos_hash] = hits. Two weapon hits
-- release the ghost, mirroring the two-punch rule in sl_modebase.
W.possession_hits = {}

function W.possession_shot(pos, user)
	if not (game_mode and game_mode.is_possessed and game_mode.release_possession) then return end
	local h = game_mode.pos_hash(pos)
	W.possession_hits[h] = (W.possession_hits[h] or 0) + 1
	if W.possession_hits[h] >= 2 then
		W.possession_hits[h] = nil
		game_mode.release_possession(pos, "exorcised at range")
		if user and user.get_player_name then
			minetest.sound_play("sl_weapons_exorcise", {
				pos = pos, gain = 0.6, max_hear_distance = 16,
			})
		end
	end
end

function W.beacon_team_of(node_name)
	if node_name == "sl_modebase:beacon_a" then return "beacon_a" end
	if node_name == "sl_modebase:beacon_b" then return "beacon_b" end
	return nil
end

-- Weapon hits a node: beacons take deliberately poor chip damage
-- (melee stays the siege tool — spec §9); possessed objects take
-- exorcism hits; everything else just sparks.
function W.node_impact(user, hit, def, origin)
	local pos = hit.under or hit.pos
	if not pos then return end
	local node = minetest.get_node(pos)
	local nname = node and node.name or "air"

	local team = W.beacon_team_of(nname)
	if team and game_mode and game_mode.damage_beacon then
		local attacker = user and user.get_player_name and user:get_player_name()
		game_mode.damage_beacon(team, def.beacon_dmg or 1, attacker)
		W.impact_fx(pos, "sl_weapons_spark.png")
		return
	end

	if game_mode and game_mode.is_possessed and game_mode.is_possessed(pos) then
		W.possession_shot(pos, user)
		W.impact_fx(pos, "sl_weapons_spark.png")
		return
	end

	W.impact_fx(pos, def.impact_texture or "sl_weapons_spark.png")
end

function W.impact_fx(pos, texture)
	minetest.add_particle({
		pos = pos,
		velocity = { x = 0, y = 1, z = 0 },
		acceleration = { x = 0, y = -3, z = 0 },
		expirationtime = 0.4,
		size = 2,
		collisiondetection = false,
		texture = texture or "sl_weapons_spark.png",
		glow = 10,
	})
end

function W.tracer_fx(from, to)
	local dir = vector.subtract(to, from)
	local len = vector.distance(from, to)
	if len < 0.5 then return end
	local steps = math.min(24, math.max(2, math.floor(len / 1.5)))
	for i = 0, steps do
		minetest.add_particle({
			pos = vector.add(from, vector.multiply(dir, i / steps)),
			velocity = { x = 0, y = 0, z = 0 },
			acceleration = { x = 0, y = 0, z = 0 },
			expirationtime = 0.15,
			size = 1.5,
			collisiondetection = false,
			texture = "sl_weapons_tracer.png",
			glow = 12,
		})
	end
end

-- One hitscan attack: pellets, spread (a value or a function of the
-- shooter, used for the Chatter's published bloom curve), tracer,
-- sound, punch routing. Returns the first object hit, if any.
function W.fire_hitscan(user, def)
	local eye, dir = W.aim(user)
	local name = user:get_player_name()
	local range = def.range or 60
	local spread_deg = def.spread
	if type(spread_deg) == "function" then
		spread_deg = spread_deg(name)
	end

	for _ = 1, (def.pellets or 1) do
		local d = W.spread_dir(dir, spread_deg)
		local endpoint = vector.add(eye, vector.multiply(d, range))
		local hit_obj, hit_pos
		for hit in minetest.raycast(eye, endpoint, true, false) do
			if hit.type == "object" then
				local obj = hit.ref
				if obj ~= user and not W.is_fx_object(obj) then
					hit_obj = obj
					hit_pos = hit.pos or (obj.get_pos and obj:get_pos()) or endpoint
					break
				end
			elseif hit.type == "node" then
				W.node_impact(user, hit, def, eye)
				hit_pos = hit.pos or hit.under
				break
			end
		end
		if hit_obj then
			local dist = vector.distance(eye, hit_pos or eye)
			W.punch_object(user, hit_obj, def.damage, def.cause, dist)
			W.tracer_fx(eye, hit_pos or eye)
			W.impact_fx(hit_pos or eye, "sl_weapons_hit.png")
		else
			W.tracer_fx(eye, hit_pos or endpoint)
		end
	end

	minetest.sound_play(def.sound or "sl_weapons_pistol", {
		pos = eye,
		gain = 0.7,
		max_hear_distance = def.hear or 32,
	})
end
