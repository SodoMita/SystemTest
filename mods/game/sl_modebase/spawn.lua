local S = game_mode.S
local state = game_mode.state

-- Respawn / spawn handling
function game_mode.spawn_player(player)
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)

	local pos

	if pl.role == "monster_master" then
		pos = table.copy(state.monster_master.base_spawn)
	elseif pl.team and state.teams[pl.team] then
		pos = table.copy(state.teams[pl.team].spawn)
	end

	if not pos then
		return false
	end

	player:set_pos(pos)

	-- Default Boxman properties
	local boxman_tex = "sl_boxman_neon.png"
	local boxman_textures = {boxman_tex, boxman_tex, boxman_tex, boxman_tex, boxman_tex}

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
	elseif pl.phase == "ghost" then
		player_api.set_model(player, "SimpleOutlinedBoxman.glb")
		player:set_physics_override({
			speed = 1.2,
			jump = 0.0,
			gravity = 0.0,
		})
		local ghost_tex = boxman_tex .. "^[opacity:120"
		player:set_properties({
			textures = {ghost_tex, ghost_tex, ghost_tex, ghost_tex, ghost_tex},
			visual_size = {x=10, y=10},
		})
	elseif pl.phase == "monster" or pl.phase == "master_monster" then
		player:set_properties({
			mesh = "monster.obj",
			visual = "mesh",
			textures = { pl.phase == "monster" and "monster_texture.png" or "monster_texture.png^[colorize:#ff0000:80" },
			visual_size = {x=1, y=1},
		})
		player:set_physics_override({
			speed = 1.5,
			jump = 1.1,
			gravity = 1.0,
		})
	else
		-- Normal "alive" phase
		if sl_characters and sl_characters.apply_default_model then
			sl_characters.apply_default_model(player)
		else
			player_api.set_model(player, "SimpleOutlinedBoxman.glb")
			player:set_properties({
				textures = boxman_textures,
				visual_size = {x=10, y=10},
			})
		end
		player:set_physics_override({
			speed = 1.0,
			jump = 1.0,
			gravity = 1.0,
		})
	end

	return true
end

-- Hooks for join / respawn
minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local pl = game_mode.get_player_state(name)

	if not pl.team and pl.role ~= "monster_master" then
		local team_id = game_mode.assign_beacon_team(name)
		local color = game_mode.get_team_color(team_id)
		minetest.chat_send_player(name, minetest.colorize(color,
			S("You were assigned to @1.", game_mode.get_team_label(team_id))))
	end

	-- Initial spawn
	minetest.after(0.1, function()
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

