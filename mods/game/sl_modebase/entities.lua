local state = game_mode.state

-- Monster entity (very simple placeholder)
local MONSTER_NAME = game_mode.modname .. ":basic_monster"

game_mode.MONSTER_NAME = MONSTER_NAME

minetest.register_entity(MONSTER_NAME, {
	initial_properties = {
		hp_max = 20,
		physical = true,
		collide_with_objects = true,
		collisionbox = { -0.4, 0.0, -0.4, 0.4, 1.8, 0.4 },
		visual = "cube",
		visual_size = { x = 0.8, y = 1.8 },
		textures = {
			"default_steel_block.png",
			"default_steel_block.png",
			"default_steel_block.png",
			"default_steel_block.png",
			"default_steel_block.png",
			"default_steel_block.png",
		},
	},

	monster_owner = nil,
	timer = 0,

	on_step = function(self, dtime)
		self.timer = self.timer + dtime
		if self.timer < 0.5 then
			return
		end
		self.timer = 0

		local pos = self.object:get_pos()
		if not pos then
			return
		end

		-- Find nearest player on beacon teams
		local nearest
		local nearest_dist_sq

		for _, player in ipairs(minetest.get_connected_players()) do
			local name = player:get_player_name()
			local pl = state.players[name]
			if pl and pl.team and game_mode.is_beacon_team(pl.team) then
				local ppos = player:get_pos()
				if ppos then
					local dx = ppos.x - pos.x
					local dy = ppos.y - pos.y
					local dz = ppos.z - pos.z
					local dist_sq = dx * dx + dy * dy + dz * dz
					if not nearest or dist_sq < nearest_dist_sq then
						nearest = player
						nearest_dist_sq = dist_sq
					end
				end
			end
		end

		if nearest and nearest_dist_sq then
			local ppos = nearest:get_pos()
			if not ppos then
				return
			end

			local dir = vector.normalize(vector.subtract(ppos, pos))
			self.object:set_velocity({
				x = dir.x * 2,
				y = dir.y * 2,
				z = dir.z * 2,
			})

			if nearest_dist_sq < 1.2 * 1.2 then
				nearest:punch(self.object, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = { fleshy = 2 },
				}, nil)
			end
		else
			-- Slow down when there is no target
			self.object:set_velocity({ x = 0, y = 0, z = 0 })
		end
	end,
})

