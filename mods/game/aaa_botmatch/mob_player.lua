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

-- Visual size matches the real player's boxman (see spawn.lua and
-- mods/content/sl_characters/model_boxman.lua). The mob used to
-- render at 1x and looked like a tiny figurine; now it matches.
local VISUAL_SCALE = { x = 10, y = 10 }

-- SimpleOutlinedBoxman.glb animation ranges.
--
-- IMPORTANT — these are the SAME ranges declared for real players in
-- mods/content/sl_characters/model_boxman.lua, expressed as
-- frame_index / 60 (seconds along the animation track). The mob is
-- a luaentity, so player_api.globalstep does NOT touch it (it only
-- iterates connected real players); the mob has to call
-- set_animation itself with the canonical ranges so it stays in
-- visual sync with the player_api's frame of reference.
--
-- The third arg of set_animation is frame_loop_blend — a NUMBER,
-- not a boolean. 0 means "play the range once and hold the last
-- frame" (no blend into a loop). A previous version of this file
-- passed `true` here, which Luanti silently accepted on the first
-- call but rejected on the next phase transition with
-- "bad argument #3 to set_animation (number expected, got boolean)".
local ANIM_STAND     = { x = 0,         y = 0 }            -- rest pose
local ANIM_WALK      = { x = 1/60,      y = 40/60 }        -- frames 1..40
local ANIM_MINE      = { x = 41/60,     y = 60/60 }        -- frames 41..60
local ANIM_WALK_MINE = { x = 61/60,     y = 99/60 }        -- frames 61..99
local ANIM_SPEED_STAND = 2  -- matches model_boxman.lua: animation_speed = 2
local ANIM_SPEED_WALK  = 2
local ANIM_NO_LOOP_BLEND = 0  -- third arg MUST be a number, never a boolean

local function apply_phase_props(self, phase, pl)
	local obj = self.object
	if phase == "alive" then
		obj:set_properties({
			visual_size = VISUAL_SCALE,
			textures = NEON_TEX,
			collisionbox = PLAYER_BOX,
			selectionbox = PLAYER_BOX,
			physical = true,
			collide_with_objects = false, -- players pass through bots
		})
		obj:set_animation(ANIM_STAND, ANIM_SPEED_STAND, ANIM_NO_LOOP_BLEND)
	elseif phase == "evil_ghost" and not (pl and pl.eliminated) then
		-- Evil ghosts are PURGEABLE by the living: keep the
		-- selectionbox so they can be targeted, but make the mesh
		-- fully invisible (visual_size 0) so they don't render as
		-- solid figures flying around the arena. No animation call
		-- there is nothing to animate.
		obj:set_properties({
			visual_size = { x = 0, y = 0 },
			textures = EVIL_TEX,
			collisionbox = { 0, 0, 0, 0, 0, 0 },
			selectionbox = PLAYER_BOX, -- purgeable by the living
			physical = false,
			collide_with_objects = false,
		})
		obj:set_velocity({ x = 0, y = 0, z = 0 })
	else
		-- Contained ghost (or eliminated): invisible, intangible.
		obj:set_properties({
			visual_size = { x = 0, y = 0 },
			collisionbox = { 0, 0, 0, 0, 0, 0 },
			selectionbox = { 0, 0, 0, 0, 0, 0 },
			physical = false,
			collide_with_objects = false,
		})
		obj:set_velocity({ x = 0, y = 0, z = 0 })
	end
	self.anim_walking = false
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
		-- minetest.find_path tuning for the botmatch arena:
		--   searchdistance = 80: the auto-arena scales with
		--     sl_botmatch.beacon_spacing (default 24, turbo 4).
		--     A spacing of 24 puts the beacons 24 nodes apart, plus
		--     ~6 nodes of midfield per side, so the worst-case
		--     point-to-point distance is ~36 nodes. 80 is a
		--     comfortable ceiling for the largest layout AND for
		--     future handmade maps whose bastions are 30+ apart.
		--   max_jump = 1: bots are full-size player entities
		--     (collisionbox 1.75 tall, half-width 0.3) and can't
		--     step over the 2-block-tall cobble cover that
		--     build_arena drops in the midfield; routing AROUND is
		--     the right behavior. If a future map needs bots that
		--     jump 2+, the caller can override via
		--     sl_botmatch.path_max_jump.
		--   max_drop = 2: the team spawn is at y = 2 (beacon top)
		--     and the arena floor is at y = 0, so the bot must
		--     drop 2 to reach the floor. 2 is the minimum that
		--     works on every current layout; bumping it is fine.
		--   algorithm = "A*": the engine accepts "A*" (pre-fetch
		--     variant), "A*_noprefetch" (default), and "Dijkstra".
		--     The previous value "A*_single" is NOT a valid
		--     algorithm name and find_path silently returned nil
		--     for it, which made the bot fall through to the
		--     straight-line fallback every tick. "A*" matches
		--     what mods/content/sl_scary/init.lua uses for the
		--     horror mobs, so the arena's pathfinder surface is
		--     uniform.
		-- The searchdistance, max_jump, and max_drop can be
		-- overridden via sl_botmatch.path_searchdistance /
		-- .path_max_jump / .path_max_drop in minetest.conf for
		-- bespoke handmade maps. Defaults here are tuned for the
		-- build_arena auto-arena.
		local cfg = botmatch.config
		local searchdist = (cfg and cfg.path_searchdistance) or 80
		local max_jump   = (cfg and cfg.path_max_jump)       or 1
		local max_drop   = (cfg and cfg.path_max_drop)       or 2
		self.path = minetest.find_path(pos, target,
			searchdist, max_jump, max_drop, "A*")
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
		dir = vector.normalize(vector.subtract(wp, pos))
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
		-- Switch from stand to walk only on the rising edge so we don't
		-- hammer set_animation every tick. See the ANIM_* comment
		-- block at the top of this file for the type contract on
		-- the third arg (frame_loop_blend MUST be a number).
		if not self.anim_walking then
			obj:set_animation(ANIM_WALK, ANIM_SPEED_WALK, ANIM_NO_LOOP_BLEND)
			self.anim_walking = true
		end
	elseif self.anim_walking then
		obj:set_animation(ANIM_STAND, ANIM_SPEED_STAND, ANIM_NO_LOOP_BLEND)
		self.anim_walking = false
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
		visual_size = VISUAL_SCALE,
		physical = true,
		-- Bots are unwalkable: real players pass through them so the
		-- admin isn't pushed off course when a bot body happens to be
		-- between them and the beacon. Selectionbox stays, so the bot
		-- is still punchable.
		collide_with_objects = false,
		collisionbox = PLAYER_BOX,
		selectionbox = PLAYER_BOX,
		hp_max = 20,
		makes_footstep_sound = true,
		static_save = false,
		-- The mob body shows its name in-world so the admin can
		-- tell which bot is which. The default sl_modebase
		-- spawn_player path hides player nametags; we override
		-- that with a bright yellow tag in on_activate so mob
		-- bots stand out from real players. (Stub bots have no
		-- body and so are invisible in-world by design — they're
		-- a headless harness, not a presence.)
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
			-- Show the display name in-world so the admin can
			-- distinguish bots from real players at a glance.
			-- The [mob] tag matches the /sl_bots list output
			-- (see botmatch.display_name).
			if botmatch.display_name then
				self.object:set_nametag_attributes({
					color = { a = 255, r = 255, g = 220, b = 80 },
				})
				self.object:set_properties({
					nametag = botmatch.display_name(self.bot_name),
				})
			end
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

-- ================================================================
-- Mob spawn position: thin wrapper around game_mode.find_spawn_pos.
--
-- The real air-pocket search lives in sl_modebase/spawn.lua
-- (game_mode.find_spawn_pos) so that both real players AND bot
-- mob bodies use the same claim table. Real players
-- (game_mode.spawn_player) and bot bodies (this file's
-- spawn_mob_body) both walk the same spiral and add claims to
-- the same game_mode.spawn_claims map, so a real player landing
-- on beacon_a's bastion can't have a bot body later snap on top
-- of them, and vice versa.
--
-- If game_mode.find_spawn_pos is missing (e.g. a test that loads
-- mob_player.lua without sl_modebase), the wrapper falls back
-- to the team spawn's static position. The fallback is the same
-- one the previous local find_spawn_pos used, so a missing
-- dependency surfaces as "spawned on the beacon" rather than
-- "crashed in setup".
-- ================================================================
local function find_spawn_pos(team, name)
	if rawget(_G, "game_mode") and game_mode.find_spawn_pos then
		return game_mode.find_spawn_pos(team, name)
	end
	-- Fallback path: best-effort team spawn. (Used only when
	-- mob_player.lua is loaded in isolation by a headless test
	-- that does not initialize game_mode.)
	local st = (rawget(_G, "game_mode") and game_mode.state) or {}
	local ts
	if st.teams and st.teams[team or ""] then
		ts = st.teams[team].spawn
	end
	ts = ts or st.lobby_spawn or { x = 0, y = 1, z = 0 }
	return { x = ts.x, y = ts.y, z = ts.z }
end

-- Spawn (or reuse) the body for a bot and wire the teleport hook.
function botmatch.spawn_mob_body(name, bot)
	local pos = find_spawn_pos(bot and bot.team, name)
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
	minetest.log("action", "[botmatch] mob body spawned for " .. name
		.. " at (" .. string.format("%d,%d,%d", pos.x, pos.y, pos.z) .. ")")
end

-- Backward-compat shim for callers (and the old end_match
-- wrapper in init.lua) that still call clear_mob_spawn_claims.
-- The real claim table is game_mode.spawn_claims; this just
-- forwards.
function botmatch.clear_mob_spawn_claims()
	if rawget(_G, "game_mode") and game_mode.clear_spawn_claims then
		game_mode.clear_spawn_claims()
	end
end
