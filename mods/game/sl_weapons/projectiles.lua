-- ================================================================
-- sl_weapons — projectile pipeline (spec §4)
-- Mortar and Pulse bolts are entities with swept collision: each
-- on_step raycasts from last to next position, so nothing tunnels
-- at 26 n/s. Projectiles inherit the shooter's velocity (council
-- resolution #10): a shell fired from a sprint carries the sprint.
-- Splash: linear falloff, knockback via add_velocity,
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

		initial_properties = {
			visual = "sprite",
			textures = { cfg.texture or "sl_weapons_tracer.png" },
			visual_size = { x = 0.6, y = 0.6 },
			physical = false,
			collisionbox = { 0, 0, 0, 0, 0, 0 },
			pointable = false,
			static_save = false,
		},

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
									vector.safe_dir(vel), cfg.knock))
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
	-- A poisoned velocity (NaN from anywhere upstream) must never
	-- reach an entity: refuse the shot instead of crashing clients.
	if vector.finite and not vector.finite(vel) then return end
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

-- MT CTF jump-grenade push (ctf_mode_nade_fight knockback grenade,
-- read 2026-08-29): the engine's vector.direction is zero-safe — a
-- blast centred exactly on the target yields a zero vector, never the
-- NaN that Lua-side normalize produces — it points at the HEAD so a
-- point-blank blast is a pure upward jump, and the y-clamp means a
-- blast above you shoves you aside, never pins you into the floor.
local function blast_push(obj, opos, pos, power)
	local props = obj.get_properties and obj:get_properties() or {}
	local eye = props.eye_height or 1.625
	local headpos = vector.offset(opos, 0, eye, 0)
	local dir = vector.direction(pos, headpos)
	if dir.y < 0 then dir.y = 0 end
	W.knockback(obj, vector.multiply(dir, power))
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
	-- The boom is a public event: flash, then a rising smoke column.
	for _ = 1, 32 do
		minetest.add_particle({
			pos = pos,
			velocity = {
				x = (math.random() - 0.5) * 10,
				y = math.random() * 8,
				z = (math.random() - 0.5) * 10,
			},
			acceleration = { x = 0, y = -9, z = 0 },
			expirationtime = 0.8,
			size = 4,
			collisiondetection = false,
			texture = "sl_weapons_blast.png",
			glow = 14,
		})
	end
	for _ = 1, 16 do
		minetest.add_particle({
			pos = { x = pos.x + (math.random() - 0.5) * 0.6,
				y = pos.y + 0.2,
				z = pos.z + (math.random() - 0.5) * 0.6 },
			velocity = { x = (math.random() - 0.5) * 1.2, y = 2 + math.random() * 2.5, z = (math.random() - 0.5) * 1.2 },
			acceleration = { x = 0, y = 1.2, z = 0 },
			expirationtime = 1.6 + math.random() * 0.8,
			size = 5,
			collisiondetection = false,
			texture = "sl_weapons_grit.png",
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
				-- CTF gates: the dead and the unpointable are not targets.
				if dist <= radius and obj:get_hp() > 0
					and (not obj.get_properties
						or obj:get_properties().pointable ~= false) then
					local dmg = math.max(1, math.floor(splash.max * (1 - dist / radius) + 0.5))
					-- Flat power, headward, never down (jump grenade).
					blast_push(obj, opos, pos, splash.knock or 11)
					W.punch_object(shooter_obj, obj, dmg, cause_key, dist)
				end
			elseif obj == shooter_obj then
				-- Self-splash: half damage, full knockback — the
				-- mortar-jump (spec §10).
				local opos = obj:get_pos()
				local dist = math.max(0.1, vector.distance(pos, opos))
				if dist <= radius then
					local dmg = math.max(1, math.floor(
						(splash.max * (1 - dist / radius) + 0.5) * (cfg.self_dmg or 0.5)))
					-- CTF-style on both axes: the push is the engine direction
					-- from the blast to the shooter's HEAD — (0,1,0) at
					-- point-blank, a pure jump, immune to the NaN that crashed
					-- clients in v1.3.6 — and the punch goes through the
					-- SHOOTER's own ObjectRef, exactly like a CTF throw against
					-- itself. Never nil: a nil puncher segfaults the engine
					-- whenever an on_punchplayer handler returns true (the
					-- 2026-08-29 crash; see W.punch_object).
					blast_push(obj, opos, pos, splash.knock or 11)
					W.punch_object(shooter_obj, obj, dmg, "mortar_self", dist)
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
	speed = 24,
	-- Real mortar ballistics (team decision 2026-08-29, second sitting):
	-- a lobbed parabola at full engine gravity — this reverses the v1.2
	-- "safe flat arc" constant. You aim ABOVE what you want to hit.
	grav = 8,
	damage = 28, -- doubled: a direct hit settles any 20 HP argument
	cause = "mortar",
	splash = { radius = 3, max = 10, beacon = 2 },
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
