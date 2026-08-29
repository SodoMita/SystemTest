-- ================================================================
-- aaa_botmatch/mob_player.lua — mob players with engine pathfinding.
--
-- Loaded by init.lua only when sl_botmatch.mob_mode = true.
--
-- A mob player = the same logical FakePlayerRef every bot uses (so all
-- game rules — teams, phases, rituals, chat seal — apply
-- identically) PLUS a physical entity body:
--   * identical visual identity to real players (same boxman model and
--     texture — matches the game's identity-ambiguity design),
--   * real collision + gravity while alive,
--   * movement via minetest.find_path (A*) along behavior nav targets,
--   * punchable by the admin: damage routes through the same registered
--     punchplayer handlers as any combat (botmatch.external_punch).
--
-- Position truth: while alive, the BODY owns the position — on_step
-- writes the entity position back into the logical ref, so game logic
-- (range checks, spawns, beacon distance) sees where the mob really is.
-- Teleports (spawn_player, cage transfers) go ref -> body via _pos_hook.
-- ================================================================

local MOB_NAME = "aaa_botmatch:player_mob"
botmatch.mobs = botmatch.mobs or {}

local NEON = "sl_boxman_neon.png"
local NEON_TEX = { NEON, NEON, NEON, NEON, NEON, NEON, NEON, NEON }
local EVIL_TEX = {}
for i = 1, 8 do EVIL_TEX[i] = NEON .. "^[colorize:#ff00ff:120" end

local PLAYER_BOX = { -0.3, 0.0, -0.3, 0.3, 1.75, 0.3 }

local function apply_phase_props(self, phase, pl)
	local obj = self.object
	if phase == "alive" then
		obj:set_properties({
			visual_size = { x = 1, y = 1 },
			textures = NEON_TEX,
			collisionbox = PLAYER_BOX,
			selectionbox = PLAYER_BOX,
			physical = true,
		})
	elseif phase == "evil_ghost" and not (pl and pl.eliminated) then
		obj:set_properties({
			visual_size = { x = 1.2, y = 1.2 },
			textures = EVIL_TEX,
			collisionbox = { 0, 0, 0, 0, 0, 0 },
			selectionbox = PLAYER_BOX, -- purgeable by the living
			physical = false,
		})
		obj:set_velocity({ x = 0, y = 0, z = 0 })
	else
		-- Contained ghost (or eliminated): invisible, intangible.
		obj:set_properties({
			visual_size = { x = 0, y = 0 },
			collisionbox = { 0, 0, 0, 0, 0, 0 },
			selectionbox = { 0, 0, 0, 0, 0, 0 },
			physical = false,
		})
		obj:set_velocity({ x = 0, y = 0, z = 0 })
	end
end

-- Walk one step along an A* path toward the behavior nav target.
local function pathfind_walk(self, bot, dtime)
	local obj = self.object
	local pos = obj:get_pos()
	local target = bot.bm.nav_target
	if not target then
		obj:set_velocity({ x = 0, y = obj:get_velocity().y, z = 0 })
		return
	end

	local now = minetest.get_us_time() / 1000000
	local need_path = (not self.path) or now >= (self.repath_at or 0)
		or (self.path[#self.path] and vector.distance(pos, self.path[#self.path]) < 1.0)
	if need_path then
		self.path = minetest.find_path(pos, target, 64, 1, 2, "A*_single")
		self.path_i = 2
		self.repath_at = now + 1.5
		if not self.path or #self.path < 2 then
			self.path = nil
		end
	end

	local speed = botmatch.config.bot_speed
	local dir
	if self.path and self.path[self.path_i or 1] then
		local wp = self.path[self.path_i]
		if vector.distance(pos, wp) < 0.6 then
			self.path_i = self.path_i + 1
			if not self.path[self.path_i] then
				self.path = nil
			end
		end
	end
	if self.path and self.path[self.path_i or 1] then
		local wp = self.path[self.path_i]
		dir = vector.safe_dir(vector.subtract(wp, pos))
	else
		-- Straight-line fallback (open floor or path exhausted).
		local flat = { x = target.x - pos.x, y = 0, z = target.z - pos.z }
		local d = math.sqrt(flat.x * flat.x + flat.z * flat.z)
		if d < 0.3 then
			obj:set_velocity({ x = 0, y = obj:get_velocity().y, z = 0 })
			return
		end
		dir = { x = flat.x / d, y = 0, z = flat.z / d }
	end

	obj:set_velocity({ x = dir.x * speed, y = obj:get_velocity().y, z = dir.z * speed })
	if dir.x ~= 0 or dir.z ~= 0 then
		obj:set_yaw(math.atan2(-dir.x, dir.z))
	end
end

-- Ghosts/evil ghosts fly: move the body kinematically toward nav target.
local function fly_toward(self, bot, dtime)
	local obj = self.object
	local target = bot.bm.nav_target
	if not target then return end
	local pos = obj:get_pos()
	local delta = vector.subtract(target, pos)
	local d = vector.distance(pos, target)
	if d < 0.2 then return end
	local speed = botmatch.config.bot_speed * 1.2 * dtime
	local step = math.min(speed, d) / d
	obj:set_pos({
		x = pos.x + delta.x * step,
		y = pos.y + delta.y * step,
		z = pos.z + delta.z * step,
	})
end

minetest.register_entity(MOB_NAME, {
	initial_properties = {
		visual = "mesh",
		mesh = "SimpleOutlinedBoxman.glb",
		textures = NEON_TEX,
		physical = true,
		collide_with_objects = true,
		collisionbox = PLAYER_BOX,
		selectionbox = PLAYER_BOX,
		hp_max = 20,
		makes_footstep_sound = true,
		static_save = false,
		nametag = "",
	},

	bot_name = nil,
	path = nil,
	path_i = 1,
	repath_at = 0,
	sync_accum = 0,
	last_phase = nil,

	on_activate = function(self, staticdata)
		self.bot_name = (staticdata ~= nil and staticdata ~= "") and staticdata or nil
		if self.bot_name then
			botmatch.mobs[self.bot_name] = self.object
			self.object:set_armor_groups({ immortal = 1 }) -- damage flows through handlers, not entity HP
		end
	end,

	on_step = function(self, dtime)
		local name = self.bot_name
		if not name or not rawget(_G, "game_mode") then return end
		local bot = botmatch.bots[name]
		if not bot then return end
		local pl = game_mode.get_player_state(name)

		if pl.phase ~= self.last_phase then
			self.last_phase = pl.phase
			apply_phase_props(self, pl.phase, pl)
			self.path = nil
		end

		if pl.phase == "alive" and not pl.eliminated then
			pathfind_walk(self, bot, dtime)
		elseif pl.phase == "evil_ghost" and not pl.eliminated then
			fly_toward(self, bot, dtime)
		end

		-- Body owns the truth: sync into the logical ref (bypass set_pos
		-- to avoid teleport feedback into the entity).
		self.sync_accum = self.sync_accum + dtime
		if self.sync_accum >= 0.2 then
			self.sync_accum = 0
			local p = self.object:get_pos()
			if p then bot._pos = { x = p.x, y = p.y, z = p.z } end
		end
	end,

	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		if not self.bot_name then return end
		local attacker_name = puncher and puncher.get_player_name
			and puncher:get_player_name() or nil
		local dmg = damage
		if (not dmg or dmg == 0) and tool_capabilities and tool_capabilities.damage_groups then
			dmg = tool_capabilities.damage_groups.fleshy
		end
		botmatch.external_punch(self.bot_name, attacker_name, dmg or 5)
	end,

	on_rightclick = function(self, clicker)
		-- Mobs are test bodies, not interactables.
	end,
})

-- Spawn (or reuse) the body for a bot and wire the teleport hook.
function botmatch.spawn_mob_body(name, bot)
	local state = game_mode.state
	local pos = { x = state.lobby_spawn.x, y = state.lobby_spawn.y + 1, z = state.lobby_spawn.z }
	local obj = minetest.add_entity(pos, MOB_NAME, name)
	if not obj then
		minetest.log("error", "[botmatch][BUG] failed to spawn mob body for " .. name)
		return
	end
	botmatch.mobs[name] = obj
	bot._pos = { x = pos.x, y = pos.y, z = pos.z }
	bot._pos_hook = function(ref, p)
		local body = botmatch.mobs[ref:get_player_name()]
		if body then body:set_pos({ x = p.x, y = p.y, z = p.z }) end
	end
	minetest.log("action", "[botmatch] mob body spawned for " .. name)
end
