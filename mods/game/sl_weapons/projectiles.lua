-- ================================================================
-- sl_weapons — projectile pipeline (spec §4)
-- Mortar and Pulse bolts are entities with swept collision: each
-- on_step raycasts from last to next position, so nothing tunnels
-- at 26 n/s. Projectiles inherit the shooter's velocity (council
-- resolution #10): a shell fired from a sprint carries the sprint.
-- Splash: linear falloff, knockback via add_player_velocity,
-- mortar-jump included; cremates corpses (spec §7.3).
-- ================================================================

local W = sl_weapons
local S = W.S

W.projectiles = {} -- [id] = cfg

function W.register_projectile(id, cfg)
	W.projectiles[id] = cfg
	cfg.id = id
	local entity_name = "sl_weapons:" .. id

	minetest.register_entity(entity_name, {
		-- Engine ignores these bookkeeping fields; the headless stub
		-- uses them for ray hit radii.
		_stub_ray_radius = 0.15,
		sl_weapon_fx = true,

		visual = "sprite",
		textures = { cfg.texture or "sl_weapons_tracer.png" },
		visual_size = { x = 0.6, y = 0.6 },
		physical = false,
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		pointable = false,
		static_save = false,

		on_step = function(self, dtime)
			local obj = self.object
			local pos = obj:get_pos()
			local vel = obj:get_velocity() or { x = 0, y = 0, z = 0 }

			if cfg.grav and cfg.grav > 0 then
				vel.y = vel.y - cfg.grav * dtime
				obj:set_velocity(vel)
			end

			self.shooter_obj = self.shooter_obj
				or (self.shooter_name and minetest.get_player_by_name(self.shooter_name)) or nil

			local newpos = vector.add(pos, vector.multiply(vel, dtime))
			for hit in minetest.raycast(pos, newpos, true, false) do
				if hit.type == "object" then
					local target = hit.ref
					local tlua = target.get_luaentity and target:get_luaentity()
					local is_shooter = self.shooter_name
						and target.is_player and target:is_player()
						and target:get_player_name() == self.shooter_name
					if target ~= obj and not is_shooter and not (tlua and tlua.sl_weapon_fx) then
						if tlua and tlua.sl_corpse then
							-- Bullets pass through bodies; fire does not.
							if cfg.splash then
								W.explode(hit.pos or pos, self.shooter_name, cfg, nil)
								obj:remove()
							end
						else
							local dist = hit.pos and vector.distance(pos, hit.pos) or 0
							W.punch_object(self.shooter_obj, target, cfg.damage, cfg.cause, dist)
							if cfg.knock then
								W.knockback(target, vector.multiply(
									vector.normalize(vel), cfg.knock))
							end
							if cfg.splash then
								W.explode(hit.pos or pos, self.shooter_name, cfg, target)
							end
							obj:remove()
							return
						end
					end
				elseif hit.type == "node" then
					local at = hit.under or hit.pos or pos
					if cfg.splash then
						W.explode(at, self.shooter_name, cfg, nil)
					else
						W.impact_fx(at, cfg.impact_texture)
						minetest.sound_play("sl_weapons_spark_hit", {
							pos = at, gain = 0.4, max_hear_distance = 12,
						})
					end
					obj:remove()
					return
				end
			end

			obj:set_pos(newpos)
			self.life = (self.life or 0) + dtime
			if self.life > 10 then
				obj:remove()
			end
		end,
	})
end

function W.spawn_projectile(user, cfg)
	local eye, dir = W.aim(user)
	local name = user:get_player_name()
	local muzzle = vector.add(eye, vector.multiply(dir, 0.6))
	local vel = vector.multiply(dir, cfg.speed)
	if cfg.inherit then
		vel = vector.add(vel, W.player_velocity(user))
	end
	local obj = minetest.add_entity(muzzle, "sl_weapons:" .. cfg.id)
	if not obj then return end
	obj:set_velocity(vel)
	local lua = obj.get_luaentity and obj:get_luaentity()
	if lua then
		lua.shooter_name = name
		lua.sl_weapon_fx = true
	end
	minetest.sound_play(cfg.launch_sound or "sl_weapons_launch", {
		pos = muzzle, gain = 0.8, max_hear_distance = cfg.hear or 28,
	})
	return obj
end

-- Radial splash with linear falloff (spec §3 mortar row):
-- 6 -> 0 over 3 m, 50% self-damage, up to 9 n/s knockback with the
-- mortar-jump as the intended use. Cremates corpses. Chip damage on
-- beacons via game_mode.damage_beacon (spec §9).
function W.explode(pos, shooter_name, cfg, exclude_obj)
	pos = pos or { x = 0, y = 0, z = 0 }
	local splash = cfg.splash or { radius = 3, max = 6 }
	local radius = splash.radius or 3
	local cause_key = cfg.cause or "mortar"
	minetest.sound_play("sl_weapons_explosion", {
		pos = pos, gain = 1.0, max_hear_distance = 48,
	})
	for _ = 1, 18 do
		minetest.add_particle({
			pos = pos,
			velocity = {
				x = (math.random() - 0.5) * 10,
				y = math.random() * 8,
				z = (math.random() - 0.5) * 10,
			},
			acceleration = { x = 0, y = -9, z = 0 },
			expirationtime = 0.8,
			size = 3,
			collisiondetection = false,
			texture = "sl_weapons_blast.png",
			glow = 14,
		})
	end

	local shooter_obj = shooter_name and minetest.get_player_by_name(shooter_name) or nil
	for _, obj in ipairs(minetest.get_objects_inside_radius(pos, radius + 1.5)) do
		if obj ~= exclude_obj and obj.get_pos then
			local lua = obj.get_luaentity and obj:get_luaentity()
			if lua and lua.sl_corpse then
				W.cremate_corpse(lua)
			elseif not (lua and lua.sl_weapon_fx) and obj ~= shooter_obj then
				local opos = obj:get_pos()
				local dist = vector.distance(pos, opos)
				if dist <= radius then
					local dmg = math.max(1, math.floor(splash.max * (1 - dist / radius) + 0.5))
					local cause = cause_key
					local away = vector.subtract(opos, pos)
					if vector.distance(away, { x = 0, y = 0, z = 0 }) < 0.01 then
						away = { x = 0, y = 1, z = 0 }
					end
					away = vector.normalize(away)
					W.knockback(obj, vector.multiply(away, 9 * (1 - dist / radius)))
					W.punch_object(shooter_obj, obj, dmg, cause, dist)
				end
			elseif obj == shooter_obj then
				-- Self-splash: half damage, full knockback — the
				-- mortar-jump (spec §10).
				local opos = obj:get_pos()
				local dist = math.max(0.1, vector.distance(pos, opos))
				if dist <= radius then
					local dmg = math.max(1, math.floor(
						(splash.max * (1 - dist / radius) + 0.5) * (cfg.self_dmg or 0.5)))
					local away = vector.normalize(vector.subtract(opos, pos))
					W.knockback(obj, vector.multiply(away, 9 * (1 - dist / radius)))
					W.punch_object(nil, obj, dmg, "mortar_self", dist)
				end
			end
		end
	end

	-- Beacon splash chip (spec §9): 1.
	if splash.beacon and game_mode and game_mode.damage_beacon then
		for _, off in ipairs({
			{ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = -1, y = 0, z = 0 },
			{ x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = -1 },
		}) do
			local npos = vector.add(vector.round(pos), off)
			local team = W.beacon_team_of(minetest.get_node(npos).name)
			if team then
				game_mode.damage_beacon(team, splash.beacon, shooter_name)
				break
			end
		end
	end
end

-- ----------------------------------------------------------------
-- The two projectiles (numbers: spec §3 table)
-- ----------------------------------------------------------------
W.register_projectile("mortar", {
	speed = 18,
	grav = 2, -- flat, safe arc constant (team decision 2026-08-29)
	damage = 14,
	cause = "mortar",
	splash = { radius = 3, max = 6, beacon = 1 },
	self_dmg = 0.5,
	inherit = true,
	texture = "sl_weapons_mortar_shell.png",
	launch_sound = "sl_weapons_mortar_launch",
	hear = 40,
})

W.register_projectile("pulse", {
	speed = 26,
	grav = 0,
	damage = 5,
	cause = "driver",
	knock = 0.4, -- pulse-juggle (spec §10)
	texture = "sl_weapons_pulse_bolt.png",
	launch_sound = "sl_weapons_pulse_fire",
	hear = 24,
})
