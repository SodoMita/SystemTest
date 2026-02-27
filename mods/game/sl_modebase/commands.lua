local S = game_mode.S
local state = game_mode.state

-- Monster master helpers
function game_mode.is_monster_master(name)
	return state.monster_master.player == name
end

function game_mode.set_monster_master(name)
	if name == nil or name == "" then
		state.monster_master.player = nil
		return
	end

	state.monster_master.player = name

	local pl = game_mode.get_player_state(name)
	pl.role = "monster_master"
	pl.team = nil
	pl.lives = game_mode.LIVES_PER_PLAYER
	pl.eliminated = false

	local player = minetest.get_player_by_name(name)
	if player then
		game_mode.spawn_player(player)
	end
end

-- Privilege for admin control over roles/teams
minetest.register_privilege("sl_admin", {
	description = S("System Looting game admin (assign teams, roles)"),
	give_to_singleplayer = true,
})

-- Chat commands
minetest.register_chatcommand("sl_state", {
	description = S("Show your System Looting team / role state"),
	func = function(name)
		local pl = game_mode.get_player_state(name)
		local parts = {}

		if pl.role == "monster_master" then
			table.insert(parts, S("Role: Monster Master"))
		else
			table.insert(parts, S("Role: Player"))
		end

		if pl.team then
			table.insert(parts, S("Team: @1", game_mode.get_team_label(pl.team)))
		else
			table.insert(parts, S("Team: None"))
		end

		table.insert(parts, S("Lives: @1", tostring(pl.lives)))
		if pl.eliminated then
			table.insert(parts, S("(Eliminated)"))
		end

		minetest.chat_send_player(name, "[System Looting] " .. table.concat(parts, " | "))
		if state.match_active then
			minetest.chat_send_player(name, S("A match is currently running (Match #@1).", tostring(state.match_count)))
		else
			minetest.chat_send_player(name, S("No active match."))
		end
	end,
})

minetest.register_chatcommand("sl_be_monster_master", {
	description = S("Become the monster master (if none exists yet)"),
	func = function(name)
		if state.monster_master.player and state.monster_master.player ~= name then
			return false, S("Monster master is already @1", state.monster_master.player)
		end

		game_mode.set_monster_master(name)
		game_mode.broadcast(S("@1 is now the Monster Master!", name))
		return true
	end,
})

minetest.register_chatcommand("sl_mm_return", {
	description = S("Monster master: instantly return to base spawn"),
	func = function(name)
		if not game_mode.is_monster_master(name) then
			return false, S("You are not the monster master.")
		end

		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("Player not found.")
		end

		player:set_pos(table.copy(state.monster_master.base_spawn))
		return true, S("Returned to monster master base.")
	end,
})

minetest.register_chatcommand("sl_mm_spawn", {
	params = "[count]",
	description = S("Monster master: spawn basic monsters near you"),
	func = function(name, param)
		if not game_mode.is_monster_master(name) then
			return false, S("You are not the monster master.")
		end

		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("Player not found.")
		end

		local count = tonumber(param) or 1
		count = math.max(1, math.min(count, 5))

		local pos = player:get_pos()
		if not pos then
			return false, S("No position.")
		end

		for i = 1, count do
			local offset = {
				x = math.random(-3, 3),
				y = 0,
				z = math.random(-3, 3),
			}
			local spawn_pos = vector.add(pos, offset)
			local obj = minetest.add_entity(spawn_pos, game_mode.MONSTER_NAME)
			if obj then
				local lua = obj:get_luaentity()
				if lua then
					lua.monster_owner = name
				end
			end
		end

		return true, S("Spawned @1 monster(s).", tostring(count))
	end,
})

-- Admin command: force-assign player to beacon or monster master
minetest.register_chatcommand("sl_assign", {
	params = "<player> <beacon_a|beacon_b|monster_master>",
	description = S("Assign a player to a beacon team or as monster master"),
	privs = { sl_admin = true },
	func = function(name, param)
		local target_name, role = param:match("^(%S+)%s+(%S+)$")
		if not target_name or not role then
			return false, S("Usage: /sl_assign <player> <beacon_a|beacon_b|monster_master>")
		end

		local pl = game_mode.get_player_state(target_name)

		if role == "monster_master" then
			game_mode.set_monster_master(target_name)
			game_mode.broadcast(S("@1 has been assigned as Monster Master.", target_name))
			return true
		elseif role == "beacon_a" or role == "beacon_b" then
			pl.team = role
			pl.role = nil
			pl.lives = game_mode.LIVES_PER_PLAYER
			pl.eliminated = false

			local player = minetest.get_player_by_name(target_name)
			if player then
				game_mode.spawn_player(player)
			end

			game_mode.broadcast(S("@1 has been assigned to @2.", target_name, game_mode.get_team_label(role)))
			return true
		else
			return false, S("Unknown role/team: @1", role)
		end
	end,
})

-- Match control commands
minetest.register_chatcommand("sl_match_start", {
	description = S("Start a new match (resets lives, keeps roles/teams)"),
	privs = { sl_admin = true },
	func = function(name)
		local ok, msg = game_mode.start_new_match(name)
		if ok == false and msg then
			return false, msg
		end
		return true
	end,
})

minetest.register_chatcommand("sl_match_stop", {
	description = S("Force-stop the current match without a winner"),
	privs = { sl_admin = true },
	func = function(name)
		if not state.match_active then
			return false, S("No active match.")
		end

		game_mode.end_match(nil, S("Stopped by @1", name))
		return true, S("Match stopped.")
	end,
})

minetest.register_chatcommand("sl_match_status", {
	description = S("Show basic match status"),
	func = function(name)
		if not state.match_active then
			return true, S("No active match.")
		end

		return true, S("Match #@1 is running.", tostring(state.match_count))
	end,
})

