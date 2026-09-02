local S = game_mode.S
local state = game_mode.state

-- ================================================================
-- Air-pocket spawn search.
--
-- WHY THIS IS HERE: state.teams[team].spawn is the team spawn point
-- that gameplay code uses as a "near the beacon" anchor (range
-- checks, target acquisition, mob AI nav targets), but it is NOT
-- a safe place to physically stand:
--
--   * the procedural map raises a 5x5 bastion pad at y = fy + 1
--     around each beacon, and the beacon itself sits on the pad at
--     y = fy + 1 / fy + 2, so the spawn point is INSIDE the
--     bastion pad node (mob bodies land "in a node below beacon");
--   * the altar pad at the arena origin and the MM redoubt at
--     +Z each cover a 3x3 / 7x7 footprint, so any fixed (x, z)
--     round-robin around the team spawn can drop a body on a pad;
--   * the 2-vertical-air-node requirement (foot + head clear,
--     floor solid) is not validated at the static spawn point.
--
-- Without this search, every player on beacon_a spawns at the same
-- coordinate ON the beacon, and any bot body whose spawn was
-- resolved to a real air pocket is snapped BACK onto the beacon
-- when game_mode.spawn_player runs the static spawn via set_pos
-- (the fake_player.lua _pos_hook forwards that set_pos into the
-- mob body's set_pos, defeating the bot's own air-pocket search).
--
-- The search walks a spiral of candidates around the team spawn
-- and claims the first one that is:
--   * clear of every structural anchor (each anchor has its own
--     chebyshev half-extent: 3 for 5x5 bastions, 2 for the 3x3
--     altar, 4 for the 7x7 MM redoubt, plus a 1-node clearance
--     band),
--   * foot+head passable (air or registered as walkable=false /
--     pointable=false),
--   * floor solid AND a known arena-floor node (NOT
--     ground:square_neon_opaque, which marks pads and walls),
--   * not already claimed by another spawn this match.
--
-- Claims are released on every match end (see end_match below) so
-- the next match's bots find empty air again. The same function
-- is used by both real players (game_mode.spawn_player) and bot
-- mob bodies (mods/game/aaa_botmatch/mob_player.lua), so the two
-- spawn paths can never disagree on where the air is.
-- ================================================================
local SPAWN_SEARCH_RADIUS = 20
local MIN_INTER_BODY_DIST = 2  -- not on top of another body
local MIN_CLEARANCE       = 1

-- Per-anchor chebyshev half-extent (the actual structural
-- footprint plus MIN_CLEARANCE).
local ANCHOR_FOOTPRINTS = {
	beacon_a = 3,  -- 5x5 bastion (half = 2) + 1 buffer
	beacon_b = 3,
	altar    = 2,  -- 3x3 altar pad (half = 1) + 1 buffer
	mm_pad   = 4,  -- 7x7 MM redoubt (half = 3) + 1 buffer
}

local function is_passable(name)
	if name == "air" or name == "ignore" then return true end
	local def = minetest.registered_nodes[name]
	if not def then return false end
	if def.pointable == false then return true end
	if def.walkable == false then return true end
	return false
end

-- Floor under the body must be the arena's actual ground plane,
-- not a bastion pad / altar pad / MM pad / wall. The procedural
-- map (mods/game/sl_modebase/map.lua) writes
--   * ground:square_neon       on the open arena floor (y = fy)
--   * ground:square_neon_opaque on every structural pad and the
--     wall ring
-- We accept ground:square_neon as "the floor", but NOT the opaque
-- variant — a mob standing on the opaque pad would be inside the
-- pad. For maps that don't ship the ground mod, fall back to
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

-- Shared claim table: {["x,y,z"] = true} per claimed air node.
-- One process-wide table so a real player on beacon_a and a bot
-- body on beacon_a see the same claims; otherwise the second
-- spawn would land on top of the first.
game_mode.spawn_claims = game_mode.spawn_claims or {}

local function claim_key(x, y, z)
	return string.format("%d,%d,%d", math.floor(x + 0.5),
		math.floor(y + 0.5), math.floor(z + 0.5))
end

local function is_claimed(x, y, z)
	return game_mode.spawn_claims[claim_key(x, y, z)] == true
end

local function mark_claimed(x, y, z)
	game_mode.spawn_claims[claim_key(x, y, z)] = true
end

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

local function resolve_floor_y(anchors)
	local m = game_mode and game_mode.mmap and game_mode.mmap.current
	if m and m.origin and m.origin.y ~= nil then
		return m.origin.y
	end
	local sx, sz = 0, 0
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

-- Single-candidate validator. Lua 5.1 has no goto/continue, so
-- the spiral search above delegates each ring cell to this
-- function and the function returns true on a clean match.
local function candidate_ok(x, z, y_foot, y_head, y_floor, anchors)
	for _, a in ipairs(anchors) do
		if math.abs(x - a.x) <= a.half and math.abs(z - a.z) <= a.half then
			return false
		end
	end
	local nf = minetest.get_node({ x = x, y = y_foot, z = z }).name
	local nh = minetest.get_node({ x = x, y = y_head, z = z }).name
	if not is_passable(nf) or not is_passable(nh) then
		return false
	end
	if not is_ground(minetest.get_node({ x = x, y = y_floor, z = z }).name) then
		return false
	end
	if is_claimed(x, y_foot, z) or is_claimed(x, y_head, z) then
		return false
	end
	-- Not on top of an existing body (real player or mob).
	for _, ref in pairs(minetest.get_connected_players()) do
		if ref and ref.get_pos then
			local p = ref:get_pos()
			if p and math.abs(p.x - x) < MIN_INTER_BODY_DIST
				and math.abs(p.z - z) < MIN_INTER_BODY_DIST
				and math.abs(p.y - y_foot) < 2 then
				return false
			end
		end
	end
	return true
end

-- Find a free air pocket near `team`'s beacon. The first
-- candidate that passes candidate_ok gets its two air nodes
-- claimed. If no candidate in the search radius passes, returns
-- the team spawn's y-foot fallback so the body is at least on
-- solid ground (better than the void).
--
-- `name` is reserved for future per-name claim hints (so e.g.
-- re-spawning the same player mid-match could prefer a
-- remembered position). The current implementation ignores it;
-- it is in the signature so callers don't need to change when
-- the hint logic lands.
function game_mode.find_spawn_pos(team, name)
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

	return { x = cx, y = y_foot, z = cz }
end

-- Release every spawn claim. Called by end_match's clean reset
-- so the next match's spawns find empty air again.
function game_mode.clear_spawn_claims()
	game_mode.spawn_claims = {}
end

-- Respawn / spawn handling
function game_mode.spawn_player(player)
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)

	local pos

	if not state.match_active then
		pos = table.copy(state.lobby_spawn)
	elseif pl.role == "monster_master" then
		pos = table.copy(state.monster_master.base_spawn)
	elseif pl.phase == "ghost" then
		pos = table.copy(state.ghost_spawn)
	elseif pl.phase == "evil_ghost" then
		pos = table.copy(pl.last_death_pos or state.ghost_spawn)
	elseif pl.phase == "monster" or pl.phase == "master_monster" then
		pos = table.copy(pl.last_death_pos or state.ghost_spawn)
	elseif pl.team and state.teams[pl.team] then
		if state.teams[pl.team].spawn then
			-- Walk the air-pocket search instead of trusting the
			-- static beacon-top coordinate: the bastion pad sits
			-- on top of the beacon and the static spawn lands the
			-- body inside a node. find_spawn_pos finds a free
			-- 2-vertical-air pocket that is on solid arena
			-- ground and clear of every structural anchor. It
			-- also claims the pocket so the next spawn on the
			-- same team lands somewhere else.
			pos = game_mode.find_spawn_pos(pl.team, name)
		elseif pl.phase == "alive" then
			-- Beacon destroyed while this player was disconnected: the team
			-- is out, so the returning player enters the cloud cage instead
			-- of crashing on a nil spawn (found by the turbo soak sweep).
			pl.phase = "ghost"
			pos = table.copy(state.ghost_spawn)
		end
	end

	if not pos then
		return false
	end

	minetest.log("action", string.format("[game_mode] Spawning %s at %s (match_active: %s)",
		name, minetest.pos_to_string(pos), tostring(state.match_active)))
	player:set_pos(pos)
	player:set_hp(player:get_properties().hp_max or 20)

	-- Default Boxman properties
	local boxman_tex = "sl_boxman_neon.png"
	local boxman_textures = {boxman_tex, boxman_tex, boxman_tex, boxman_tex, boxman_tex, boxman_tex, boxman_tex, boxman_tex}

	-- Globally hide nametags
	player:set_nametag_attributes({color = {a = 0, r = 255, g = 255, b = 255}})

	if pl.role == "monster_master" then
		player_api.set_model(player, "SimpleOutlinedBoxman.glb")
		player:set_physics_override({
			speed = 1.3,
			jump = 1.0,
			gravity = 0.1,
		})
		player:set_properties({
			textures = boxman_textures,
			visual_size = {x=10, y=10},
		})
		player:set_armor_groups({ fleshy = 100 })
	elseif not state.match_active then
		-- Lobby state: immortal, neutral, and empty inventory
		player_api.set_model(player, "SimpleOutlinedBoxman.glb")
		player:set_properties({
			textures = boxman_textures,
			visual_size = {x=10, y=10},
			-- Restore standard boxes in case this player was a ghost last match.
			collisionbox = { -0.3, 0.0, -0.3, 0.3, 1.75, 0.3 },
			selectionbox = { -0.3, 0.0, -0.3, 0.3, 1.75, 0.3 },
		})
		player:set_armor_groups({ immortal = 1 })
		player:set_physics_override({
			speed = 1.0,
			jump = 1.0,
			gravity = 1.0,
		})

		-- Former ghosts must not keep flight/noclip in the lobby.
		local privs = minetest.get_player_privs(name)
		if not minetest.settings:get_bool("creative_mode") then
			privs.fly = nil
			privs.noclip = nil
			minetest.set_player_privs(name, privs)
		end
		
		-- Clear inventory for lobby
		local inv = player:get_inventory()
		if not minetest.settings:get_bool("creative_mode") then
			inv:set_list("main", {})
		end
	elseif pl.phase == "ghost" or pl.phase == "evil_ghost" then
		player_api.set_model(player, "SimpleOutlinedBoxman.glb")
		player:set_physics_override({
			speed = 1.5,
			jump = 0.0,
			gravity = 0.0,
		})
		-- Give Ghost flight and noclip privs
		local privs = minetest.get_player_privs(name)
		privs.fly = true
		privs.noclip = true
		minetest.set_player_privs(name, privs)

		local is_evil = pl.phase == "evil_ghost"
		player:set_properties({
			visual_size = is_evil and {x=1.2, y=1.2} or {x=0, y=0},
			textures = is_evil and {"sl_boxman_neon.png^[colorize:#ff00ff:120"} or boxman_textures,
			collisionbox = {0,0,0,0,0,0},
			-- Evil ghosts stay selectable so the living can purge them;
			-- contained ghosts remain untargetable.
			selectionbox = is_evil and {-0.3, 0.0, -0.3, 0.3, 1.75, 0.3} or {0,0,0,0,0,0},
		})
		
		-- Ghosts receive only a revival option; evil ghosts receive the
		-- bounded sabotage charge (WP2) plus the possession focus (WP3 kit).
		local inv = player:get_inventory()
		inv:set_list("main", {})
		if is_evil then
			inv:add_item("main", game_mode.modname .. ":sabotage_charge")
			if game_mode.grant_evil_ghost_kit then
				game_mode.grant_evil_ghost_kit(player)
			end
		else
			inv:add_item("main", game_mode.modname .. ":reincarnate")
		end
	elseif pl.phase == "monster" or pl.phase == "master_monster" then
		-- Remove flight/noclip when mutating
		local privs = minetest.get_player_privs(name)
		privs.fly = nil
		privs.noclip = nil
		minetest.set_player_privs(name, privs)

		player:set_properties({
			mesh = "monster.obj",
			visual = "mesh",
			textures = { pl.phase == "monster" and "monster_texture.png" or "monster_texture.png^[colorize:#ff0000:80" },
			visual_size = {x=1, y=1},
			collisionbox = { -0.4, 0.0, -0.4, 0.4, 1.8, 0.4 },
		})
		player:set_physics_override({
			speed = 1.5,
			jump = 1.1,
			gravity = 1.0,
		})
	else
		-- Normal "alive" phase
		-- Remove flight/noclip
		local privs = minetest.get_player_privs(name)
		if not minetest.settings:get_bool("creative_mode") then
			privs.fly = nil
			privs.noclip = nil
			minetest.set_player_privs(name, privs)
		end

		if sl_characters and sl_characters.apply_default_model then
			sl_characters.apply_default_model(player)
		else
			player_api.set_model(player, "SimpleOutlinedBoxman.glb")
			player:set_properties({
				textures = boxman_textures,
				visual_size = {x=10, y=10},
			})
		end
		-- Guarantee targetability even after a ghost phase zeroed the boxes.
		player:set_properties({
			collisionbox = { -0.3, 0.0, -0.3, 0.3, 1.75, 0.3 },
			selectionbox = { -0.3, 0.0, -0.3, 0.3, 1.75, 0.3 },
		})
		player:set_physics_override({
			speed = 1.0,
			jump = 1.0,
			gravity = 1.0,
		})
		player:set_armor_groups({ fleshy = 100 })
	end

	return true
end

-- Hooks for join / respawn
minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)

	-- Tournament seasons lock their roster at start (v1.3.5): anyone
	-- arriving mid-season watches from the rail. The flag clears itself
	-- when the season (or /sl_tournament stop) runs its clean reset.
	if state.tournament and not state.tournament_roster[name] then
		pl.tournament_spectator = true
		minetest.chat_send_player(name, S("A tournament is running — you join as a spectator until it ends."))
	else
		pl.tournament_spectator = nil
	end

	-- Initial spawn at lobby (or beacon if match is active)
	minetest.after(0.2, function()
		local p = minetest.get_player_by_name(name)
		if p then
			game_mode.spawn_player(p)
		end
	end)
end)

minetest.register_on_leaveplayer(function(player)
	-- nothing special yet; state is kept so reconnecting keeps team/phase
end)

minetest.register_on_respawnplayer(function(player)
	if game_mode.spawn_player(player) then
		return true
	end
	return false
end)
