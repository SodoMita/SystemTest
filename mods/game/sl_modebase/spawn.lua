local S = game_mode.S
local state = game_mode.state

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
		pos = table.copy(state.teams[pl.team].spawn)
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

	-- Initial spawn at lobby (or beacon if match is active)
	minetest.after(0.2, function()
		local p = minetest.get_player_by_name(name)
		if p then
			game_mode.spawn_player(p)
		end
	end)
end)

minetest.register_on_leaveplayer(function(player)
	-- nothing special yet; state is kept so reconnecting keeps team/lives
end)

minetest.register_on_respawnplayer(function(player)
	if game_mode.spawn_player(player) then
		return true
	end
	return false
end)
