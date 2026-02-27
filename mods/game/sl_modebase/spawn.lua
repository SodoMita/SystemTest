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

	-- Basic monster master movement: ghost-like (low gravity, slightly faster)
	if pl.role == "monster_master" then
		player:set_physics_override({
			speed = 1.3,
			jump = 1.0,
			gravity = 0.1,
		})
		player:set_armor_groups({ immortal = 0, fleshy = 100 })
	else
		-- Normal physics
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

