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
		-- — there is nothing to animate.
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

-- ================================================================
-- Mob spawn position search.
--
-- Bug fixed in this revision: an earlier version of the mob spawn
-- path used a hard-coded {x, z} round-robin table with a fixed
-- y = 1.0. That collided with the procedural arena in two ways:
--   * the procedural map raises a 5x5 bastion pad at y = fy + 1
--     around each beacon, so y = 1.0 put the mob body ON the pad
--     directly under the beacon node ("spawning in a node below
--     beacon"), and
--   * the altar pad at the arena origin occupied some of the
--     round-robin x,z slots, so a bot could land on the altar.
--
-- The search below walks a candidate grid around the team's
-- beacon spawn and finds the first position where:
--   * the foot node AND the head node are both air (or ignore),
--   * the node directly below the foot is solid (so the mob won't
--     fall through the world),
--   * the candidate is not already claimed by another mob body,
--   * the candidate clears the chebyshev extent of every
--     structural anchor (each anchor has its own half-extent:
--     5x5 for the beacon bastions, 3x3 for the altar, 7x7 for
--     the MM pad), plus a small clearance band.
--
-- Spawned mobs claim their two air nodes so the next bot finds
-- the next free air pocket. Claims are released at every match
-- end (see botmatch.clear_mob_spawn_claims, called from the
-- end_match hook in init.lua).
-- ================================================================
local SPAWN_SEARCH_RADIUS = 20        -- search this far from the team spawn
local MIN_INTER_BOT_DIST  = 2         -- don't land right on top of another bot
local MIN_CLEARANCE       = 1         -- extra nodes outside any anchor footprint

-- Per-anchor footprint (chebyshev radius). The bastion pads are
-- 5x5, the altar pad is 3x3, the MM pad is 7x7. Anything inside
-- the anchor's footprint + MIN_CLEARANCE is treated as "on the
-- structure" and rejected.
local ANCHOR_FOOTPRINTS = {
	beacon_a = 3,  -- 5x5 bastion (half = 2) + 1 node buffer = 3
	beacon_b = 3,
	altar    = 2,  -- 3x3 altar pad (half = 1) + 1 buffer
	mm_pad   = 4,  -- 7x7 MM redoubt (half = 3) + 1 buffer
}

-- A node name is "passable" for the spawn probe if the mob can
-- stand in it. air and ignore are always passable. Anything else
-- must be checked against the registered node def for walkable /
-- pointable. We never use this to decide ground (the floor has to
-- be a known structural name), only to decide "is the foot/head
-- empty?".
local function is_passable(name)
	if name == "air" or name == "ignore" then return true end
	local def = minetest.registered_nodes[name]
	if not def then return false end
	if def.pointable == false then return true end
	if def.walkable == false then return true end
	return false
end

-- The floor under the mob must be the arena's actual ground
-- plane, not a bastion pad / altar pad / MM pad / wall. The
-- procedural map (mods/game/sl_modebase/map.lua) writes
--   * ground:square_neon       on the open arena floor (y = fy)
--   * ground:square_neon_opaque on every structural pad (5x5
--     bastion, 3x3 altar, 7x7 MM redoubt) and on the wall ring
-- We accept ground:square_neon as "the floor", but NOT the
-- opaque variant — a mob standing on the opaque pad would be
-- inside the pad (the bastion pad is at the same y as the mob's
-- foot). For maps that don't ship the ground mod, fall back to
-- default:stone / default:cobble / default:dirt as a last resort.
local GROUND_NAMES = {
	["ground:square_neon"]   = true,
	["default:stone"]        = true,
	["default:cobble"]       = true,
	["default:dirt"]         = true,
	["default:desert_stone"] = true,
}
local function is_ground(name)
	return name and GROUND_NAMES[name] == true
end

-- Claim bookkeeping: {["x,y,z"] = true} for each air node a
-- spawned mob body occupies. Two bot bodies must not be assigned
-- overlapping air nodes.
botmatch.mob_spawn_claims = botmatch.mob_spawn_claims or {}

local function claim_key(x, y, z)
	return string.format("%d,%d,%d", math.floor(x + 0.5),
		math.floor(y + 0.5), math.floor(z + 0.5))
end

local function is_claimed(x, y, z)
	return botmatch.mob_spawn_claims[claim_key(x, y, z)] == true
end

local function mark_claimed(x, y, z)
	botmatch.mob_spawn_claims[claim_key(x, y, z)] = true
end

-- Resolve the structural anchors and per-anchor half-extents.
-- Returns a list of {x, z, half} tuples for clearance checks.
local function anchors_with_extents()
	local out = {}
	local m = game_mode and game_mode.mmap and game_mode.mmap.current
	local a = m and m.anchor
	if not a and game_mode and game_mode.state and game_mode.state.map
		and game_mode.state.map.current then
		a = game_mode.state.map.current.anchor
	end
	if not a then return out end
	local function add(name, key)
		if a[key] then
			out[#out + 1] = {
				x = a[key].x,
				z = a[key].z,
				half = ANCHOR_FOOTPRINTS[name] or 3,
			}
		end
	end
	add("beacon_a", "beacon_a")
	add("beacon_b", "beacon_b")
	add("altar",    "altar")
	add("mm_pad",   "mm_pad")
	return out
end

-- Find the real arena floor y. We don't trust the team spawn's
-- vertical because beacons sit on a bastion pad (the team spawn
-- is 1 above the beacon, which is 1 above the pad, which is 1
-- above the actual ground). Scan from a position well outside
-- every pad to find the true floor. If a map origin is exposed,
-- prefer that.
local function resolve_floor_y(anchors)
	local m = game_mode and game_mode.mmap and game_mode.mmap.current
	if m and m.origin and m.origin.y ~= nil then
		-- The map's origin y is the floor y for the procedural
		-- layout — it's the y of the arena's ground plane.
		return m.origin.y
	end
	-- Fallback: scan downward from y=50 at an off-pad position
	-- (e.g. far from every anchor) until we find a walkable node.
	-- Use the lobby spawn or (0, 0) as the off-pad sample point.
	local sx, sz = 0, 0
	for _, a in ipairs(anchors) do
		-- Pick a corner of the arena far from every anchor.
		-- The simplest approach: use the lobby spawn.
	end
	if game_mode and game_mode.state and game_mode.state.lobby_spawn then
		sx = math.floor(game_mode.state.lobby_spawn.x)
		sz = math.floor(game_mode.state.lobby_spawn.z)
	end
	for y = 50, -10, -1 do
		local n = minetest.get_node({ x = sx, y = y, z = sz }).name
		if is_ground(n) then
			return y
		end
	end
	return 0
end

-- Single-candidate validator. Lua 5.1 has no goto/continue, so the
-- spiral search above delegates each ring cell to this function
-- and the function returns true on a clean match.
local function candidate_ok(x, z, y_foot, y_head, y_floor, anchors)
	-- Clearance band against every structural anchor. Each
	-- anchor's chebyshev half-extent + MIN_CLEARANCE defines
	-- its "do not spawn here" footprint.
	for _, a in ipairs(anchors) do
		if math.abs(x - a.x) <= a.half and math.abs(z - a.z) <= a.half then
			return false
		end
	end
	-- Foot and head must both be passable.
	local nf = minetest.get_node({ x = x, y = y_foot, z = z }).name
	local nh = minetest.get_node({ x = x, y = y_head, z = z }).name
	if not is_passable(nf) or not is_passable(nh) then
		return false
	end
	-- Solid ground directly below the foot.
	if not is_ground(minetest.get_node({ x = x, y = y_floor, z = z }).name) then
		return false
	end
	-- Not already claimed by another mob body.
	if is_claimed(x, y_foot, z) or is_claimed(x, y_head, z) then
		return false
	end
	-- Not on top of an existing mob body.
	for _, obj in pairs(botmatch.mobs or {}) do
		if obj and obj.get_pos then
			local p = obj:get_pos()
			if p and math.abs(p.x - x) < MIN_INTER_BOT_DIST
				and math.abs(p.z - z) < MIN_INTER_BOT_DIST
				and math.abs(p.y - y_foot) < 2 then
				return false
			end
		end
	end
	return true
end

-- Find the first valid mob spawn position for `team` near the
-- team's beacon. Returns a candidate {x, y, z} on success, or a
-- fallback (the team spawn itself) if every candidate was
-- rejected. Better a solid-footed spawn at a known anchor than
-- a body in the void.
local function find_spawn_pos(team)
	local state = (game_mode and game_mode.state) or {}
	local team_spawn
	if state.teams and state.teams[team or ""] then
		team_spawn = state.teams[team].spawn
	end
	if not team_spawn then
		team_spawn = state.lobby_spawn or { x = 0, y = 1, z = 0 }
	end

	local anchors = anchors_with_extents()
	local floor_y = resolve_floor_y(anchors)
	local y_foot = floor_y + 1
	local y_head = y_foot + 1
	local cx = math.floor(team_spawn.x)
	local cz = math.floor(team_spawn.z)

	-- Spiral search outward from the team spawn (chebyshev rings).
	for ring = 0, SPAWN_SEARCH_RADIUS do
		for dx = -ring, ring do
			for dz = -ring, ring do
				if math.max(math.abs(dx), math.abs(dz)) == ring then
					local x = cx + dx
					local z = cz + dz
					if candidate_ok(x, z, y_foot, y_head, floor_y, anchors) then
						mark_claimed(x, y_foot, z)
						mark_claimed(x, y_head, z)
						return { x = x, y = y_foot, z = z }
					end
				end
			end
		end
	end

	-- Fallback: return the team spawn itself. The caller will at
	-- least drop the body at a known position, even if it's on
	-- the bastion pad.
	return { x = cx, y = y_foot, z = cz }
end

-- Spawn (or reuse) the body for a bot and wire the teleport hook.
function botmatch.spawn_mob_body(name, bot)
	local pos = find_spawn_pos(bot and bot.team)
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

-- Release every spawn claim. Called from the match-end clean reset
-- so the next match's bots find empty air again.
function botmatch.clear_mob_spawn_claims()
	botmatch.mob_spawn_claims = {}
end
