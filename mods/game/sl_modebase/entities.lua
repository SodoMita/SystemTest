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

-- ================================================================
-- Monster variant catalog
-- ================================================================
-- The Monster Spawner unit exposes exactly this catalog through its
-- GUI list. Entries without an `entity` field are variants of the
-- shared monster below (re-stats/re-skin at spawn time); entries
-- with an `entity` field deploy that entity as-is (the sl_scary
-- horror mobs manage their own stats and AI). The /sl_mm_spawn
-- command deploys the same creatures via game_mode.spawn_monster.
-- ================================================================
game_mode.MONSTER_TYPES = {
	stalker = {
		label = "Stalker",
		texture = "monster_texture.png",
		hp = 30,
		speed = 2.5,
		damage = 4,
		size = { x = 1, y = 1 },
	},
	scout = {
		label = "Scout",
		texture = "monster_texture.png^[colorize:#33ffcc:100",
		hp = 15,
		speed = 3.8,
		damage = 3,
		size = { x = 0.7, y = 0.7 },
	},
	brute = {
		label = "Brute",
		texture = "monster_texture.png^[colorize:#ff5522:120",
		hp = 60,
		speed = 1.6,
		damage = 8,
		size = { x = 1.4, y = 1.4 },
	},
	-- sl_scary horror mobs (deployed as their own entities)
	dredger = {
		label = "Dredger",
		entity = "sl_scary:dredger",
		hp = 40,
		speed = 3.0,
		damage = 4,
	},
	wraith = {
		label = "Signal Wraith",
		entity = "sl_scary:signal_wraith",
		hp = 20,
		speed = 2.5,
		damage = 3,
	},
	containment = {
		label = "Containment Horror",
		entity = "sl_scary:containment",
		hp = 80,
		speed = 1.0,
		damage = 10,
	},
}

game_mode.MONSTER_TYPE_ORDER = { "stalker", "scout", "brute", "dredger", "wraith", "containment" }

-- ================================================================
-- Monster spoils — the workshop economy
-- ================================================================
-- Mapgen places no workshops, so the stations are assembled by hand:
-- every ingredient of a station recipe is torn out of a monster
-- (team directive 2026-08-29; sl_weapons' Precision Fabricator is
-- built entirely from these). The table is deterministic and
-- published — a kill is worth exactly what it is worth, no rolls.
game_mode.MONSTER_LOOT = {
	stalker     = { { "metal_ingot", 1 }, { "plastic_scrap", 1 } },
	scout       = { { "circuit_board", 1 }, { "plastic_scrap", 1 } },
	brute       = { { "metal_ingot", 2 }, { "energy_crystal", 1 } },
	dredger     = { { "energy_crystal", 1 }, { "circuit_board", 1 } },
	wraith      = { { "circuit_board", 1 } },
	containment = { { "metal_ingot", 2 }, { "circuit_board", 2 }, { "energy_crystal", 1 } },
}

function game_mode.drop_monster_loot(pos, variant)
	local loot = game_mode.MONSTER_LOOT[variant]
	if not loot or not pos then return end
	for _, e in ipairs(loot) do
		local obj = minetest.add_item(pos, ItemStack(modname .. ":" .. e[1] .. " " .. e[2]))
		if obj and obj.set_velocity then
			-- A public fountain: the spoils land beside the wreck and
			-- belong to whoever survives the scramble.
			obj:set_velocity({
				x = (math.random() - 0.5) * 3,
				y = 2.5 + math.random() * 1.5,
				z = (math.random() - 0.5) * 3,
			})
		end
	end
end

-- Spawn one monster of the given variant at pos, owned by owner_name.
-- Unknown variants fall back to "stalker". Returns the object or nil.
function game_mode.spawn_monster(pos, variant, owner_name)
	variant = variant or "stalker"
	local def = game_mode.MONSTER_TYPES[variant] or game_mode.MONSTER_TYPES.stalker
	local entity_name = def.entity or MONSTER_NAME
	local obj = minetest.add_entity(pos, entity_name)
	if not obj then return nil end

	-- Shared-mode variants get re-stats/re-skin per instance; external
	-- entities (sl_scary mobs) run their own stats and animation.
	if not def.entity and obj.set_properties then
		local scale = def.size.x
		obj:set_properties({
			hp_max = def.hp,
			hp = def.hp,
			textures = { def.texture },
			visual_size = { x = def.size.x, y = def.size.y },
			collisionbox = { -0.4 * scale, 0.0, -0.4 * scale, 0.4 * scale, 1.8 * scale, 0.4 * scale },
		})
	end
	local lua = obj:get_luaentity()
	if lua then
		lua.monster_variant = variant
		if not def.entity then
			lua.move_speed = def.speed
			lua.attack_damage = def.damage
		end
		lua.monster_owner = owner_name
	end
	return obj
end

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
		-- Match entities never persist in static data: the map system
		-- purges every mob at match end and respawns the initial
		-- population at match start, and a restart mid-match must not
		-- resurrect stale monsters into the lobby.
		static_save = false,
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

		-- Lobby safety (owner directive): monsters stand down outside an
		-- active match — no target acquisition, no attacks. The lobby
		-- punch-guard in match.lua backstops this at the damage layer.
		if not state.match_active then
			self.current_target = nil
		end

		-- Target picking logic (pick every 10 seconds or if target lost)
		if state.match_active and (self.target_change_timer > 10 or not self.current_target) then
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
				-- A monster standing exactly on its target must stand
				-- still, not sprint toward NaN.
				local dir = vector.safe_dir(vector.subtract(tpos, pos))
				
			-- Add slight jitter to movement
			local jitter = {x=(math.random()-0.5)*0.5, y=0, z=(math.random()-0.5)*0.5}
			local move_dir = vector.add(dir, jitter)
			local move_speed = self.move_speed or 2.5
			self.object:set_velocity({
				x = move_dir.x * move_speed,
				y = move_dir.y * move_speed,
				z = move_dir.z * move_speed,
			})
				self.object:set_rotation(vector.dir_to_rotation(dir))

				-- Attack logic (never during the lobby stage)
				if state.match_active and dist < 2.5 and self.attack_timer >= 1.2 then
					self.attack_timer = 0
					if self.current_target.type == "player" then
						local p = minetest.get_player_by_name(self.current_target.name)
						if p then
							p:punch(self.object, 1.0, {
								full_punch_interval = 1.0,
								damage_groups = { fleshy = self.attack_damage or 4 },
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
		-- Consumable melee (Severance) and blade wear apply to monsters
		-- too, through the shared sl_weapons hook when present.
		if sl_weapons and sl_weapons.melee_entity_hit then
			sl_weapons.melee_entity_hit(hitter)
		end
	end,

	on_death = function(self, killer)
		local pos = self.object:get_pos()
		minetest.sound_play("monster_chase", { pos = pos, gain = 0.8, max_hear_distance = 14 })
		minetest.add_entity(pos, modname .. ":death_particle")
		-- The wreck pays out its parts wherever it falls (catalog
		-- spawns only — ambient monsters carry nothing).
		if self.monster_variant then
			game_mode.drop_monster_loot(pos, self.monster_variant)
		end
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
