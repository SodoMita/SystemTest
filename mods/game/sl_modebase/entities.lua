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
		backface_culling = false,
		static_save = true,
	},

	monster_owner = nil,
	timer = 0,
	sound_timer = 0,
	attack_timer = 0,
	target_change_timer = 0,
	current_target = nil, -- {type = "player"|"beacon", name = ..., pos = ...}

	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		self.attack_timer = self.attack_timer + dtime
		self.sound_timer = self.sound_timer + dtime
		self.target_change_timer = self.target_change_timer + dtime

		if self.timer < 0.2 then
			return
		end
		self.timer = 0

		local pos = self.object:get_pos()
		if not pos then return end

		-- Target picking logic (pick every 10 seconds or if target lost)
		if self.target_change_timer > 10 or not self.current_target then
			self.target_change_timer = 0
			local candidates = {}

			-- Candidate: Alive players
			for _, player in ipairs(minetest.get_connected_players()) do
				local name = player:get_player_name()
				local pl = game_mode.get_player_state(name)
				if pl and pl.team and game_mode.is_beacon_team(pl.team) and pl.phase == "alive" then
					local ppos = player:get_pos()
					if ppos then
						table.insert(candidates, {type = "player", name = name, pos = ppos})
					end
				end
			end

			-- Candidate: Beacons (even if unloaded, use spawn pos from state)
			for team_id, team_def in pairs(state.teams) do
				if team_def.spawn then
					-- Check if beacon node is actually there (if loaded)
					local bpos = {x=team_def.spawn.x, y=team_def.spawn.y-1, z=team_def.spawn.z}
					table.insert(candidates, {type = "beacon", team_id = team_id, pos = bpos})
				end
			end

			if #candidates > 0 then
				self.current_target = candidates[math.random(1, #candidates)]
				-- Small random delay to start moving so they don't all move in perfect sync
				self.timer = -math.random() * 0.5
			else
				self.current_target = nil
			end
		end

		if self.current_target then
			local tpos = self.current_target.pos
			
			-- Update player position if target is player
			if self.current_target.type == "player" then
				local p = minetest.get_player_by_name(self.current_target.name)
				if p then
					tpos = p:get_pos()
					self.current_target.pos = tpos
					
					-- Check if player became ghost or eliminated
					local pl = game_mode.get_player_state(self.current_target.name)
					if not pl or pl.phase ~= "alive" or pl.eliminated then
						self.current_target = nil
						return
					end
				else
					self.current_target = nil -- Lost player
					return
				end
			end
			
			if tpos then
				local dist = vector.distance(pos, tpos)
				local dir = vector.normalize(vector.subtract(tpos, pos))
				
				-- Add slight jitter to movement
				local jitter = {x=(math.random()-0.5)*0.5, y=0, z=(math.random()-0.5)*0.5}
				local move_dir = vector.add(dir, jitter)
				
				self.object:set_velocity({
					x = move_dir.x * 2.5,
					y = move_dir.y * 2.5,
					z = move_dir.z * 2.5,
				})
				self.object:set_rotation(vector.dir_to_rotation(dir))

				-- Attack logic
				if dist < 2.5 and self.attack_timer >= 1.2 then
					self.attack_timer = 0
					if self.current_target.type == "player" then
						local p = minetest.get_player_by_name(self.current_target.name)
						if p then
							p:punch(self.object, 1.0, {
								full_punch_interval = 1.0,
								damage_groups = { fleshy = 4 },
							}, nil)
						end
					else
						-- Attack Beacon (uses state directly for unloaded nodes)
						game_mode.damage_beacon(self.current_target.team_id, 5, "A Monster")
					end
					
					minetest.sound_play("monster_chase", {
						pos = pos,
						gain = 0.8,
						max_hear_distance = 12,
					})
				end

				-- If stuck or taking too long, switch target
				-- If further than 3 blocks and haven't reached in 7 seconds, pick new
				if dist > 3 and self.target_change_timer > 7 then
					self.current_target = nil
				end
			end
		else
			self.object:set_velocity({ x = 0, y = 0, z = 0 })
		end
	end,

	on_punch = function(self, hitter, time_from_last_punch, tool_capabilities, dir)
		minetest.sound_play("hit", { pos = self.object:get_pos(), gain = 0.6, max_hear_distance = 10 })
	end,

	on_death = function(self, killer)
		local pos = self.object:get_pos()
		minetest.sound_play("monster_chase", { pos = pos, gain = 0.8, max_hear_distance = 14 })
		minetest.add_entity(pos, modname .. ":death_particle")
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

-- Death particle: a brief expanding shatter used when agents or monsters die
minetest.register_entity(modname .. ":death_particle", {
	initial_properties = {
		visual = "mesh",
		mesh = "death_particle.obj",
		textures = { "particle_texture.png" },
		physical = false,
		collide_with_objects = false,
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		visual_size = { x = 1, y = 1 },
		glow = 12,
	},

	timer = 0,

	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		local scale = 1 + self.timer * 3
		self.object:set_properties({
			visual_size = { x = scale, y = scale, z = scale }
		})
		if self.timer > 1.0 then
			self.object:remove()
		end
	end,
})

minetest.log("action", "[sl_modebase] entities registered.")
