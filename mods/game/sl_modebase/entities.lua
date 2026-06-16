-- ================================================================
-- System Looting — mode entities
-- ================================================================
-- Monster that hunts beacon-team players, plus utility entities for
-- the scanner pulse and the flare light.  All models are provided by
-- sl_mvp_assets.
-- ================================================================

local S = game_mode.S
local modname = game_mode.modname
local state = game_mode.state

-- Monster entity that chases beacon-team players.
local MONSTER_NAME = modname .. ":monster"
game_mode.MONSTER_NAME = MONSTER_NAME

minetest.register_entity(MONSTER_NAME, {
	initial_properties = {
		hp_max = 30,
		physical = true,
		collide_with_objects = true,
		collisionbox = { -0.4, 0.0, -0.4, 0.4, 1.8, 0.4 },
		visual = "mesh",
		mesh = "monster.obj",
		textures = { "monster_texture.png" },
		visual_size = { x = 1, y = 1 },
	},

	monster_owner = nil,
	timer = 0,
	sound_timer = 0,
	attack_timer = 0,

	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		self.attack_timer = self.attack_timer + dtime
		self.sound_timer = self.sound_timer + dtime

		if self.timer < 0.5 then
			return
		end
		self.timer = 0

		local pos = self.object:get_pos()
		if not pos then return end

		-- Idle sound occasionally
		if self.sound_timer > 4 then
			self.sound_timer = 0
			minetest.sound_play("monster_idle", {
				pos = pos,
				gain = 0.6,
				max_hear_distance = 16,
			})
		end

		-- Find nearest beacon-team player
		local nearest
		local nearest_dist_sq = math.huge
		for _, player in ipairs(minetest.get_connected_players()) do
			local name = player:get_player_name()
			local pl = state.players[name]
			if pl and pl.team and game_mode.is_beacon_team(pl.team) then
				local ppos = player:get_pos()
				if ppos then
					local dist_sq = vector.distance(pos, ppos) ^ 2
					if dist_sq < nearest_dist_sq then
						nearest = player
						nearest_dist_sq = dist_sq
					end
				end
			end
		end

		if nearest then
			local ppos = nearest:get_pos()
			local dir = vector.normalize(vector.subtract(ppos, pos))
			self.object:set_velocity({
				x = dir.x * 2.5,
				y = dir.y * 2.5,
				z = dir.z * 2.5,
			})
			self.object:set_rotation(vector.dir_to_rotation(dir))

			local dist = math.sqrt(nearest_dist_sq)
			if dist < 1.5 and self.attack_timer >= 1.0 then
				self.attack_timer = 0
				nearest:punch(self.object, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = { fleshy = 4 },
				}, nil)
				minetest.sound_play("monster_chase", {
					pos = pos,
					gain = 0.8,
					max_hear_distance = 12,
				})
			end
		else
			self.object:set_velocity({ x = 0, y = 0, z = 0 })
		end
	end,

	on_punch = function(self, hitter, time_from_last_punch, tool_capabilities, dir)
		minetest.sound_play("hit", { pos = self.object:get_pos(), gain = 0.6, max_hear_distance = 10 })
	end,

	on_death = function(self, killer)
		minetest.sound_play("monster_chase", { pos = self.object:get_pos(), gain = 0.8, max_hear_distance = 14 })
	end,
})

-- Expanding scanner pulse (used by the tactical Signal Relay / Sensor Array)
minetest.register_entity(modname .. ":scanner_pulse", {
	initial_properties = {
		visual = "mesh",
		mesh = "scanner_pulse.obj",
		textures = { "pulse_texture.png" },
		physical = false,
		collide_with_objects = false,
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		visual_size = { x = 1, y = 1 },
		glow = 12,
	},

	timer = 0,

	on_activate = function(self, staticdata, dtime_s)
		self.timer = 0
	end,

	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		local scale = 1 + self.timer * 2.5
		self.object:set_properties({
			visual_size = { x = scale, y = scale, z = scale }
		})
		if self.timer > 1.5 then
			self.object:remove()
		end
	end,
})

-- Flare light that hangs in the air for a short while
minetest.register_entity(modname .. ":flare_light", {
	initial_properties = {
		visual = "mesh",
		mesh = "flare_light.obj",
		textures = { "flare_light_texture.png" },
		physical = false,
		collide_with_objects = false,
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		visual_size = { x = 1, y = 1 },
		glow = 14,
	},

	timer = 0,

	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		if self.timer > 30 then
			self.object:remove()
		end
	end,
})

minetest.log("action", "[sl_modebase] entities registered.")
