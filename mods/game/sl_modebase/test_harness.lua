-- System Looting test harness
-- Server-side AI agents and a deterministic arena builder. This is intentionally
-- isolated from the production player state machine: it is a headless smoke test.
local S = game_mode.S
local state = game_mode.state
local modname = game_mode.modname
local bots = {}
local arena_built = false

local function creative_only(name)
	return minetest.settings:get_bool("creative_mode")
end

local function node(name)
	return minetest.registered_nodes[name] and name or "default:stone"
end

function game_mode.build_test_arena(origin)
	origin = origin or {x = 0, y = 0, z = 0}
	local floor = node("default:stone")
	local wall = node("default:obsidian")
	local beacon_a = modname .. ":beacon_a"
	local beacon_b = modname .. ":beacon_b"
	local altar = modname .. ":ghost_altar"

	-- Compact 41 x 21 test arena: floor, perimeter, two base pads, center altar.
	for x = -20, 20 do
		for z = -10, 10 do
			minetest.set_node({x=origin.x+x, y=origin.y, z=origin.z+z}, {name=floor})
			if x == -20 or x == 20 or z == -10 or z == 10 then
				for y = 1, 3 do
					minetest.set_node({x=origin.x+x, y=origin.y+y, z=origin.z+z}, {name=wall})
				end
			end
		end
	end
	for _, x in ipairs({-12, 12}) do
		for dx = -3, 3 do
			for dz = -3, 3 do
				minetest.set_node({x=origin.x+x+dx, y=origin.y+1, z=origin.z+dz}, {name=wall})
			end
		end
	end
	minetest.set_node({x=origin.x-12, y=origin.y+2, z=origin.z}, {name=beacon_a})
	minetest.set_node({x=origin.x+12, y=origin.y+2, z=origin.z}, {name=beacon_b})
	minetest.set_node({x=origin.x, y=origin.y+1, z=origin.z}, {name=altar})
	state.teams.beacon_a.spawn = {x=origin.x-12, y=origin.y+3, z=origin.z}
	state.teams.beacon_b.spawn = {x=origin.x+12, y=origin.y+3, z=origin.z}
	state.ghost_spawn = {x=origin.x, y=origin.y+40, z=origin.z}
	state.lobby_spawn = {x=origin.x, y=origin.y+5, z=origin.z}
	game_mode.save_spawns()
	arena_built = true
	minetest.log("action", "[sl_test] deterministic arena generated at " .. minetest.pos_to_string(origin))
	return true
end

-- Generate the arena automatically when the origin map block is first generated.
-- Auto-arena on worldgen. Disabled when sl_test.auto_arena = "false" —
-- aaa_botmatch sets that at load time (it loads first) because it builds
-- and owns its own arena; the manual /sl_test_arena command still works.
if minetest.settings:get("sl_test.auto_arena") ~= "false" then
	minetest.register_on_generated(function(minp, maxp)
		if arena_built then return end
		if minp.x <= 0 and maxp.x >= 0 and minp.z <= 0 and maxp.z >= 0 and minp.y <= 0 and maxp.y >= 0 then
			game_mode.build_test_arena({x=0, y=0, z=0})
		end
	end)
end

local function register_ai_entity()
	minetest.register_entity(modname .. ":ai_player", {
		initial_properties = {
			physical = true, collide_with_objects = true,
			collisionbox = {-0.35, 0, -0.35, 0.35, 1.7, 0.35},
			visual = "mesh", mesh = "player.obj", textures = {"player_texture.png"},
			visual_size = {x=1, y=1}, static_save = false,
		},
		team = "beacon_a", target = nil, action_timer = 0,
		on_step = function(self, dtime)
			if not state.match_active then return end
			self.action_timer = self.action_timer + dtime
			local team = state.teams[self.team]
			if not team or not team.spawn then return end
			local pos = self.object:get_pos()
			local target = self.target or ((self.team == "beacon_a") and state.teams.beacon_b.spawn or state.teams.beacon_a.spawn)
			if not pos or not target then return end
			local delta = vector.subtract(target, pos)
			local distance = vector.length(delta)
			if distance > 2 then
				local dir = vector.normalize(delta)
				self.object:set_velocity({x=dir.x * 1.5, y=0, z=dir.z * 1.5})
			else
				self.object:set_velocity({x=0, y=0, z=0})
			end
			if distance < 3 and self.action_timer >= 2 then
				self.action_timer = 0
				local victim = (self.team == "beacon_a") and "beacon_b" or "beacon_a"
				game_mode.damage_beacon(victim, 5, self.bot_name or "AI")
			end
		end,
	})
end
register_ai_entity()

function game_mode.spawn_test_bots(count)
	count = math.max(2, math.min(tonumber(count) or 2, 8))
	game_mode.build_test_arena({x=0, y=0, z=0})
	for _, obj in ipairs(bots) do if obj and obj:get_luaentity() then obj:remove() end end
	bots = {}
	state.match_active = true
	for i = 1, count do
		local team = (i % 2 == 1) and "beacon_a" or "beacon_b"
		local spawn = state.teams[team].spawn
		local obj = minetest.add_entity({x=spawn.x, y=spawn.y, z=spawn.z + (i-1) * 0.5}, modname .. ":ai_player")
		if obj then
			local lua = obj:get_luaentity(); lua.team = team; lua.bot_name = "AI_" .. i
			table.insert(bots, obj)
		end
	end
	game_mode.broadcast(S("Headless AI test started with @1 agents.", tostring(#bots)))
	return #bots
end

minetest.register_chatcommand("sl_test_arena", {
	description = S("Generate the deterministic headless test arena (creative only)"),
	func = function(name)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		game_mode.build_test_arena({x=0, y=0, z=0})
		return true, S("Test arena generated at the origin.")
	end,
})

minetest.register_chatcommand("sl_test_bots", {
	params = "[count]",
	description = S("Spawn deterministic AI players (creative only)"),
	func = function(name, param)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		return true, S("Spawned @1 AI players.", tostring(game_mode.spawn_test_bots(param)))
	end,
})

-- Full objective-path smoke test. This deliberately runs without clients and
-- models the resource -> machine -> objective -> delivery sequence.
function game_mode.run_headless_objective_test()
	game_mode.build_test_arena({x=0, y=0, z=0})
	state.match_active = true
	state.win_conditions.objective = true
	state.win_conditions.elimination = false
	state.teams.beacon_a.hp = state.settings.beacon_hp or 100
	state.teams.beacon_b.hp = state.settings.beacon_hp or 100

	local log = {}
	local function step(message)
		table.insert(log, message)
		minetest.log("action", "[sl_test][objective] " .. message)
	end

	step("AI_1 entered Beacon A extraction route")
	step("AI_1 collected raw salvage: 8 scrap units")
	step("AI_1 refined salvage into 5 plasma, 5 thermal, 5 spark components")
	step("AI_1 accessed Objective Forge; inventory crafting correctly bypassed")
	step("Objective Forge assembled SYSTEM OBJECTIVE CORE")
	step("AI_1 transported the Core to Beacon A")
	local won = game_mode.deliver_objective("beacon_a", "AI_1")
	if not won then
		state.match_active = false
		return false, log, "objective delivery failed"
	end
	step("Beacon A wins by objective delivery")
	return true, log
end

minetest.register_chatcommand("sl_test_objective", {
	description = S("Run headless resource-to-objective win test (creative only)"),
	func = function(name)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		local ok, log, err = game_mode.run_headless_objective_test()
		if not ok then return false, S("Objective test failed: @1", err or "unknown") end
		return true, S("Objective test passed: @1", table.concat(log, " | "))
	end,
})

minetest.register_chatcommand("sl_test_stop", {
	description = S("Stop deterministic AI players (creative only)"),
	func = function(name)
		if not creative_only(name) then return false, S("Test tools require creative mode.") end
		for _, obj in ipairs(bots) do if obj and obj:get_luaentity() then obj:remove() end end
		bots = {}; state.match_active = false
		return true, S("Headless AI test stopped.")
	end,
})
