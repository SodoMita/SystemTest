-- ================================================================
-- aaa_botmatch/behavior.lua
-- Scripted AI behavior + deterministic arena construction.
-- Determinism over intelligence: bots follow fixed policies seeded
-- by math.randomseed(sl_botmatch.seed), so a failing run can be
-- replayed with the same seed.
--
-- Loaded by init.lua AFTER botmatch table exists; all functions
-- attach to botmatch.
-- ================================================================

local function now_s()
	return minetest.get_us_time() / 1000000
end

local function dist2d(a, b)
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- Move one tick toward target, ground-locked to the arena plane.
-- Mob mode: sets the nav target; the entity body walks it with engine
-- pathfinding and syncs its position back into the logical player.
local function step_toward(bot, target, dt, speed_mult)
	if botmatch.config.mob_mode then
		bot.bm.nav_target = { x = target.x, y = target.y or bot:get_pos().y, z = target.z }
		return false
	end
	local pos = bot:get_pos()
	local dx, dz = target.x - pos.x, target.z - pos.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 0.15 then return true end
	local speed = botmatch.config.bot_speed * (speed_mult or 1) * dt
	-- slight deterministic weave so bots do not perfectly overlap
	local weave = math.sin(now_s() * 1.7 + #bot:get_player_name() * 2.3) * 0.35
	local nx, nz = dx / d, dz / d
	local move = math.min(speed, d)
	bot:set_pos({
		x = pos.x + nx * move + (-nz) * weave * move,
		y = pos.y,
		z = pos.z + nz * move + nx * weave * move,
	})
	return false
end

-- ================================================================
-- Arena: deterministic, hand-placed, matching the spec's
-- "fixed starting equipment + hand-placed pickups" milestone.
-- ================================================================
function botmatch.build_arena()
	local gm = game_mode
	local state = gm.state

	-- Geometry scales with beacon spacing. Turbo (spacing ~4) puts the
	-- bases next to each other so a match resolves in seconds; the default
	-- 24 keeps a midfield for brawls.
	local half = math.max(4, math.floor(botmatch.config.beacon_spacing / 2))
	local bx = math.max(2, math.floor(botmatch.config.beacon_spacing / 2))
	local floor_half = bx + 6

	-- EMERGE FIRST, THEN BUILD: set_node silently no-ops on blocks that
	-- were never generated, and headless servers have no players to
	-- trigger mapgen. load_area synchronously emerges each block; once
	-- emerged and saved, contents persist via map.sqlite across reloads.
	-- (forceload_block additionally pins them, where the engine allows.)
	local gs = state.ghost_spawn
	for x = -floor_half, floor_half, 16 do
		for z = -floor_half, floor_half, 16 do
			for _, y in ipairs({ 0, 16 }) do
				local p = { x = x, y = y, z = z }
				if minetest.load_area then minetest.load_area(p) end
				if minetest.forceload_block then minetest.forceload_block(p, true) end
			end
		end
	end
	if minetest.load_area then minetest.load_area(gs) end
	if minetest.forceload_block then minetest.forceload_block(gs, true) end

	-- Arena floor at y = 0
	for x = -floor_half, floor_half do
		for z = -floor_half, floor_half do
			minetest.set_node({ x = x, y = 0, z = z }, { name = "default:stone" })
		end
	end

	-- Symmetric cover blocks only when there is a midfield to hide in.
	if bx >= 6 then
		for _, c in ipairs({ { -6, -4 }, { -6, 4 }, { -9, 0 }, { 6, -4 }, { 6, 4 }, { 9, 0 } }) do
			for y = 1, 2 do
				minetest.set_node({ x = c[1], y = y, z = c[2] }, { name = "default:cobble" })
			end
		end
	end

	-- Beacons: symmetric at x = -bx / +bx. set_node does not run
	-- after_place_node, so spawn anchors are registered explicitly.
	minetest.set_node({ x = -bx, y = 1, z = 0 }, { name = "sl_modebase:beacon_a" })
	minetest.set_node({ x = bx, y = 1, z = 0 }, { name = "sl_modebase:beacon_b" })
	state.teams.beacon_a.spawn = { x = -bx, y = 2, z = 0 }
	state.teams.beacon_b.spawn = { x = bx, y = 2, z = 0 }
	gm.save_spawns()

	-- Ghost altar at midfield + one loot crate (sabotage/possession target)
	minetest.set_node({ x = 0, y = 1, z = 0 }, { name = "sl_modebase:ghost_altar" })
	local cx = math.min(botmatch.config.turbo and 3 or 5, floor_half - 2)
	minetest.set_node({ x = cx, y = 1, z = cx }, { name = "sl_modebase:loot_crate" })
	botmatch.crate_pos = { x = cx, y = 1, z = cx }

	-- Lobby platform under lobby_spawn
	local l = state.lobby_spawn
	for x = -3, 3 do
		for z = -3, 3 do
			minetest.set_node({ x = l.x + x, y = l.y - 1, z = l.z + z }, { name = "default:stone" })
		end
	end

	-- Cloud cage containment at ghost spawn
	if minetest.load_area then minetest.load_area(vector.round(state.ghost_spawn)) end
	if gm.build_cloud_cage then gm.build_cloud_cage() end

	-- Register the arena with the map system: matches played here still
	-- get the initial-state reset contract (journal restore of out-of-
	-- volume node edits, mob purge at match end, mob respawn at match
	-- start), but botmatch owns the build — the map system never
	-- rebuilds this arena itself.
	if gm.map and gm.map.adopt then
		local l = state.lobby_spawn
		local mm = state.monster_master.base_spawn
		gm.map.adopt({
			name = "botmatch arena",
			minp = { x = -floor_half - 2, y = -1, z = -floor_half - 2 },
			maxp = { x = floor_half + 2, y = math.max(25, gs.y + 5), z = floor_half + 2 },
			anchor = {
				beacon_a = { x = -bx, y = 1, z = 0 },
				beacon_b = { x = bx, y = 1, z = 0 },
				altar = { x = 0, y = 1, z = 0 },
				mm_pad = { x = mm.x, y = mm.y - 1, z = mm.z },
				lobby = { x = l.x, y = l.y, z = l.z },
				ghost = { x = gs.x, y = gs.y, z = gs.z },
			},
			mobs = {},
		})
	end

	minetest.log("action", "[botmatch] deterministic arena materialized")
end

-- ================================================================
-- Match insertion hook: hand out the fixed starting kit.
-- ================================================================
function botmatch.on_match_inserted()
	local state = game_mode.state
	if not state.match_active then
		table.insert(botmatch.bugs, { context = "insertion", error = "match did not start after countdown" })
		minetest.log("error", "[botmatch][BUG] insertion: match did not start after countdown")
		return
	end

	-- Deterministic roles: the first bot of each team is the objective
	-- runner (beacon pressure guaranteed); the rest brawl in the midfield.
	local runner_taken = {}
	for _, name in ipairs(botmatch.bot_order) do
		local bot = botmatch.bots[name]
		local team = game_mode.get_player_state(name).team
		bot.bm.runner = false
		if team and not runner_taken[team] then
			runner_taken[team] = name
			bot.bm.runner = true
		end
	end

	-- One random living non-runner receives the ritual kit (altar coverage).
	local living = {}
	for _, name in ipairs(botmatch.connected) do
		if game_mode.get_player_state(name).phase == "alive"
				and not botmatch.bots[name].bm.runner then
			table.insert(living, name)
		end
	end
	if #living == 0 then
		for _, name in ipairs(botmatch.connected) do
			table.insert(living, name)
		end
	end
	if #living > 0 then
		local carrier = living[math.random(1, #living)]
		local inv = botmatch.bots[carrier]:get_inventory()
		inv:add_item("main", ItemStack("sl_modebase:ritual_ashen_relic"))
		inv:add_item("main", ItemStack("sl_modebase:ritual_soul_shard"))
		inv:add_item("main", ItemStack("sl_modebase:ritual_signal_ink"))
		botmatch.bots[carrier].bm.kit = true
		botmatch.bots[carrier].bm.carrier = true
		minetest.log("action", "[botmatch] ritual kit issued to " .. carrier)
	end

	-- Per-bot match bookkeeping
	for _, name in ipairs(botmatch.bot_order) do
		local bot = botmatch.bots[name]
		bot.dead = false -- clean reset returned everyone to the lobby
		bot.bm.next_attack = 0
		bot.bm.next_act = now_s() + 8 + math.random(0, 12)
		bot.bm.offered = false
		bot.bm.revived_at = 0
		bot.bm.possessed_done = false
		bot.bm.sabotage_target = nil
	end

	-- Disconnect/reconnect scenario: one random bot, mid-match.
	if botmatch.config.disconnect_test then
		local delay = (botmatch.config.match_duration or 120) * (0.3 + math.random() * 0.3)
		minetest.after(delay, function()
			if game_mode.state.match_active and #botmatch.connected > 2 then
				local victim = botmatch.connected[math.random(1, #botmatch.connected)]
				botmatch.disconnect_bot(victim)
			end
		end)
	end
end

function botmatch.disconnect_bot(name)
	local bot = botmatch.bots[name]
	if not bot then return end
	for i, n in ipairs(botmatch.connected) do
		if n == name then table.remove(botmatch.connected, i) break end
	end
	botmatch.record_event("disconnects", 1)
	botmatch.fire("leaveplayer", bot)
	minetest.log("action", "[botmatch] " .. name .. " disconnected (scenario)")
	minetest.after(8, function()
		if not botmatch.is_connected(name) then
			table.insert(botmatch.connected, name)
			botmatch.fire("joinplayer", bot)
			minetest.log("action", "[botmatch] " .. name .. " reconnected (scenario)")
		end
	end)
end

-- ================================================================
-- Behavior dispatcher (called every 0.5 s per connected bot)
-- ================================================================
function botmatch.behave(name, dt)
	local bot = botmatch.bots[name]
	local pl = game_mode.get_player_state(name)

	if pl.phase == "alive" then
		botmatch.behave_alive(bot, pl, dt)
	elseif pl.phase == "ghost" then
		botmatch.behave_ghost(bot, pl, dt)
	elseif pl.phase == "evil_ghost" then
		botmatch.behave_evil(bot, pl, dt)
	end
end

-- Enemy beacon for a team id.
local function enemy_team(team)
	return (team == "beacon_a") and "beacon_b" or "beacon_a"
end

function botmatch.behave_alive(bot, pl, dt)
	local state = game_mode.state
	local now = now_s()
	local pos = bot:get_pos()
	local foe_id = enemy_team(pl.team)
	local foe = state.teams[foe_id]

	-- 0) Runners hit the objective first, even under pressure — guarantees
	-- every match exercises the beacon damage path.
	if bot.bm.runner and foe and foe.spawn then
		local bpos = { x = foe.spawn.x, y = foe.spawn.y - 1, z = foe.spawn.z }
		if dist2d(pos, bpos) < 3 and now >= bot.bm.next_attack then
			bot.bm.next_attack = now + botmatch.config.attack_interval
			botmatch.punch_beacon(bot, foe_id, bpos)
			return
		end
	end

	-- 1) Purge nearby evil ghosts (counterplay policy)
	for _, other_name in ipairs(botmatch.bot_order) do
		if other_name ~= bot:get_player_name() and botmatch.is_connected(other_name)
				and not botmatch.bots[other_name].dead then
			local opl = game_mode.get_player_state(other_name)
			local other = botmatch.bots[other_name]
			if opl.phase == "evil_ghost" and dist2d(pos, other:get_pos()) < 3 then
				if now >= bot.bm.next_attack then
					bot.bm.next_attack = now + botmatch.config.attack_interval
					botmatch.punch_player(bot, other)
				end
				return
			end
		end
	end

	-- 1.2) Ritual: a kit carrier heads for the altar unless in melee range
	-- (moved ahead of general engagement; otherwise the midfield brawl
	-- starves the altar path entirely).
	local altar_chance = botmatch.config.turbo and 0.9 or 0.5
	if bot.bm.kit and not bot.bm.runner and not botmatch.summon_in_progress
			and math.random() < altar_chance then
		local altar_pos = { x = 0, y = 1, z = 0 }
		local threatened = false
		for _, other_name in ipairs(botmatch.bot_order) do
			if other_name ~= bot:get_player_name() and botmatch.is_connected(other_name) then
				local opl = game_mode.get_player_state(other_name)
				if opl.team ~= pl.team and opl.phase == "alive"
						and dist2d(pos, botmatch.bots[other_name]:get_pos()) < 3 then
					threatened = true
					break
				end
			end
		end
		if not threatened then
			if dist2d(pos, altar_pos) < 2.5 then
				botmatch.try_altar_summon(bot)
				return
			else
				step_toward(bot, altar_pos, dt)
				return
			end
		end
	end

	-- 1.5) Engage nearby enemy players. Mutual attrition sends players
	-- creating the ghost / altar / revival / sabotage windows this soak
	-- exists to exercise.
	local enemy = botmatch.find_enemy_target(bot, pl)
	if enemy then
		local ed = dist2d(pos, enemy:get_pos())
		-- Runners only fight at melee range; pushing the beacon wins the match.
		local engage_range = bot.bm.runner and 1.8 or 6
		if ed < engage_range then
			if now >= bot.bm.next_attack then
				bot.bm.next_attack = now + botmatch.config.attack_interval
				botmatch.punch_player(bot, enemy)
			end
			return
		elseif ed < 8 and not bot.bm.runner and math.random() < 0.25 then
			-- Brawlers sometimes chase; runners always push the objective,
			-- so beacon pressure and midfield attrition coexist.
			step_toward(bot, enemy:get_pos(), dt)
			return
		end
	end

	-- 2) Counterplay: repair corrupted beacons and exorcise possessed
	-- vessels nearby (visible cause -> living response).
	local foe_id = enemy_team(pl.team)
	local counter_points = {}
	for _, team_id in ipairs({ pl.team, foe_id }) do
		local spawn = state.teams[team_id] and state.teams[team_id].spawn
		if spawn then
			table.insert(counter_points, { x = spawn.x, y = spawn.y - 1, z = spawn.z })
		end
	end
	table.insert(counter_points, { x = 0, y = 1, z = 0 })   -- altar
	if botmatch.crate_pos then
		table.insert(counter_points, botmatch.crate_pos)     -- loot crate
	end
	for _, cpos in ipairs(counter_points) do
		if game_mode.is_sabotaged(cpos) and dist2d(pos, cpos) < 4 then
			botmatch.repair_node(bot, cpos)
			return
		end
	end

	-- 2b) Exorcism duty: the living bot closest to a possessed vessel is
	-- designated to punch it out (deterministic counterplay, not luck).
	for _, cpos in ipairs(counter_points) do
		if game_mode.is_possessed(cpos) then
			local nearest, nd = nil, 999
			for _, other_name in ipairs(botmatch.bot_order) do
				if botmatch.is_connected(other_name) and not botmatch.bots[other_name].dead then
					local opl = game_mode.get_player_state(other_name)
					if opl.phase == "alive" then
						local d = dist2d(botmatch.bots[other_name]:get_pos(), cpos)
						if d < nd then nearest, nd = other_name, d end
					end
				end
			end
			if nearest == bot:get_player_name() then
				if dist2d(pos, cpos) < 4 then
					botmatch.repair_node(bot, cpos)
				else
					step_toward(bot, cpos, dt)
				end
				return
			end
		end
	end

	-- 3) Objective push: pressure the enemy beacon
	if not foe.spawn then
		-- Enemy beacon destroyed: hunt surviving enemy players instead.
		local target = botmatch.find_enemy_target(bot, pl)
		if target then
			if dist2d(pos, target:get_pos()) < 5 then
				if now >= bot.bm.next_attack then
					bot.bm.next_attack = now + botmatch.config.attack_interval
					botmatch.punch_player(bot, target)
				end
			else
				step_toward(bot, target:get_pos(), dt)
			end
		end
		return
	end

	local bpos = { x = foe.spawn.x, y = foe.spawn.y - 1, z = foe.spawn.z }
	if dist2d(pos, bpos) < 3 then
		if now >= bot.bm.next_attack then
			bot.bm.next_attack = now + botmatch.config.attack_interval
			botmatch.punch_beacon(bot, foe_id, bpos)
		end
	else
		step_toward(bot, { x = foe.spawn.x, z = foe.spawn.z }, dt)
	end
end

function botmatch.find_enemy_target(bot, pl)
	local best, best_d = nil, 999
	for _, other_name in ipairs(botmatch.bot_order) do
		if other_name ~= bot:get_player_name() and botmatch.is_connected(other_name)
				and not botmatch.bots[other_name].dead then
			local opl = game_mode.get_player_state(other_name)
			if opl.team ~= pl.team and opl.phase == "alive" then
				local d = dist2d(bot:get_pos(), botmatch.bots[other_name]:get_pos())
				if d < best_d then best, best_d = botmatch.bots[other_name], d end
			end
		end
	end
	return best
end

function botmatch.behave_ghost(bot, pl, dt)
	local state = game_mode.state
	local now = now_s()

	-- If summoned, transmit one information packet through the real command.
	if pl.ghost_summoned_by and not bot.bm.offered then
		bot.bm.offered = true
		botmatch.try_ghost_offer(bot, pl)
	end

	-- Voluntary revival after a bounded reflection period (~10 s as ghost;
	-- ~1-3 s under turbo, or the altar economy consumes the whole window
	-- before revival matures in 5-second matches).
	if pl.ghost_summoned_by == nil and bot.bm.revived_at == 0 then
		if botmatch.config.turbo then
			bot.bm.revived_at = now + 1 + math.random(0, 2)
		else
			bot.bm.revived_at = now + 10 + math.random(0, 8)
		end
	end
	if bot.bm.revived_at > 0 and now >= bot.bm.revived_at and bot.bm.revived_at ~= -1 then
		bot.bm.revived_at = -1
		botmatch.try_revive(bot)
		return
	end

	-- Otherwise hover in the cage (contained observation state).
	local g = state.ghost_spawn
	local pos = bot:get_pos()
	if dist2d(pos, g) > 4 then
		step_toward(bot, g, dt)
	else
		bot:set_pos({
			x = g.x + math.sin(now * 0.7) * 2,
			y = g.y + 0.5,
			z = g.z + math.cos(now * 0.7) * 2,
		})
	end
end

function botmatch.behave_evil(bot, pl, dt)
	local state = game_mode.state
	local now = now_s()

	-- Objective blocks. Order alternates per revival (bot.bm.sab_first)
	-- so BOTH mechanics get a window regardless of purge timing — a fixed
	-- order starves whichever runs second.
	local function possess_objective()
		if bot.bm.possessed_done then return false end
		if not bot:get_inventory():contains_item("main",
				ItemStack("sl_modebase:possession_focus")) then
			return false
		end
		local vessel = botmatch.crate_pos or { x = 0, y = 1, z = 0 }
		if dist2d(bot:get_pos(), vessel) < 3 then
			if now >= bot.bm.next_act then
				bot.bm.next_act = now + 2
				if botmatch.try_possess(bot, vessel) then
					bot.bm.possessed_done = true
				end
			end
		else
			step_toward(bot, vessel, dt, 2.2) -- evil ghosts fly fast
			return true
		end
		return false
	end

	local function sabotage_objective()
		if bot.bm.sabotage_target == nil then
			local target_team = math.random() < 0.5 and "beacon_a" or "beacon_b"
			local spawn = state.teams[target_team] and state.teams[target_team].spawn
			bot.bm.sabotage_target = spawn
				and { x = spawn.x, y = spawn.y - 1, z = spawn.z } or false
		end
		if not bot.bm.sabotage_target then return false end
		local t = bot.bm.sabotage_target
		if dist2d(bot:get_pos(), t) < 3 then
			if now >= bot.bm.next_act then
				bot.bm.next_act = now + 2
				botmatch.try_sabotage(bot, t)
				bot.bm.sabotage_target = false
			end
			return false
		else
			step_toward(bot, t, dt, 2.2)
			return true
		end
	end

	if bot.bm.sab_first then
		if sabotage_objective() then return end
		if possess_objective() then return end
	else
		if possess_objective() then return end
		if sabotage_objective() then return end
	end

	-- Objectives done: kite away from living hunters (trickster survival —
	-- faster than them, so kiting must never precede objectives or the
	-- ghost stalemates into match end without ever acting), otherwise
	-- drift ominously over the arena (taunting presence, no attacks).
	local threat, td = nil, 99
	for _, other_name in ipairs(botmatch.bot_order) do
		if other_name ~= bot:get_player_name() and botmatch.is_connected(other_name)
				and not botmatch.bots[other_name].dead then
			local opl = game_mode.get_player_state(other_name)
			if opl.phase == "alive" then
				local d = dist2d(bot:get_pos(), botmatch.bots[other_name]:get_pos())
				if d < td then threat, td = botmatch.bots[other_name], d end
			end
		end
	end
	local pos = bot:get_pos()
	if threat and td < 6 then
		local away = vector.subtract(pos, threat:get_pos())
		step_toward(bot, { x = pos.x + away.x * 2, y = pos.y, z = pos.z + away.z * 2 }, dt, 2.2)
		return
	end
	bot:set_pos({
		x = math.sin(now * 0.4 + 1.3) * 10,
		y = 4 + math.sin(now * 0.9) * 1.5,
		z = math.cos(now * 0.4 + 1.3) * 10,
	})
	if dist2d(pos, { x = 0, z = 0 }) > 40 then
		bot:set_pos({ x = 0, y = 4, z = 0 })
	end
end

-- ================================================================
-- Actions: each one drives REAL registered definitions/handlers.
-- ================================================================

function botmatch.punch_player(attacker, victim)
	if victim.dead then return end -- never corpse-camp: one lethal, one kill
	local damage = botmatch.config.combat_damage
	local dir = vector.subtract(victim:get_pos(), attacker:get_pos())
	-- Real registered_on_punchplayer chain (guards: ghosts cannot attack,
	-- lobby damage blocked, creative no-damage, ...).
	local canceled = botmatch.fire("punchplayer", victim, attacker, 1.0,
		{ full_punch_interval = 1.0, damage_groups = { fleshy = damage } }, dir, damage)
	if not canceled then
		victim:set_hp(victim:get_hp() - damage)
		if victim:get_hp() <= 0 then
			botmatch.attribute_kill(attacker:get_player_name(), victim:get_player_name())
		end
	end
end

function botmatch.punch_beacon(bot, team_id, bpos)
	local def = minetest.registered_nodes["sl_modebase:beacon_" .. (team_id == "beacon_a" and "a" or "b")]
	if def and def.on_punch then
		botmatch.safe("beacon_punch", def.on_punch, bpos, minetest.get_node(bpos), bot, { type = "node", under = bpos })
	end
end

function botmatch.repair_node(bot, pos)
	local was_sabotaged = game_mode.is_sabotaged(pos)
	local was_possessed = game_mode.is_possessed(pos)
	-- Exorcism needs two punches (WP3 rule); repairs need one.
	local punches = was_possessed and 2 or 1
	for _ = 1, punches do
		botmatch.fire("punchnode", pos, minetest.get_node(pos), bot, { type = "node", under = pos })
	end
	if was_sabotaged and not game_mode.is_sabotaged(pos) then
		botmatch.record_event("repairs", 1)
	end
	if was_possessed and not game_mode.is_possessed(pos) then
		botmatch.record_event("exorcisms", 1)
	end
end

function botmatch.try_altar_summon(bot)
	local pos = { x = 0, y = 1, z = 0 }
	local def = minetest.registered_nodes["sl_modebase:ghost_altar"]
	if not def or not def.on_rightclick then return end
	botmatch.summon_in_progress = true
	def.on_rightclick(pos, minetest.get_node(pos), bot, ItemStack(""), { type = "node", under = pos })
	-- Did the ritual bind a ghost?
	local summoned = nil
	for _, name in ipairs(botmatch.bot_order) do
		local pl = game_mode.get_player_state(name)
		if pl.phase == "ghost" and pl.ghost_summoned_by == bot:get_player_name() then
			summoned = name
		end
	end
	if summoned then
		botmatch.record_event("ghost_summons", 1)
		minetest.log("action", "[botmatch] altar ritual bound ghost " .. summoned)
		-- Channel collapses after 30 s (sl_modebase timer); allow re-summons later.
		minetest.after(31, function()
			botmatch.summon_in_progress = false
			bot.bm.kit = false
		end)
	else
		botmatch.summon_in_progress = false
		bot.bm.kit = false
	end
end

function botmatch.try_ghost_offer(bot, pl)
	local cmd = minetest.registered_chatcommands["sl_ghost_offer"]
	if not cmd then return end
	-- The offer command is a creative-mode developer control; toggle the
	-- engine setting for the duration of the call, exactly like a dev would.
	local was_creative = minetest.settings:get_bool("creative_mode")
	minetest.settings:set_bool("creative_mode", true)
	local ok = cmd.func(bot:get_player_name(), pl.ghost_summoned_by .. " security")
	minetest.settings:set_bool("creative_mode", was_creative)
	if ok then
		botmatch.record_event("offers", 1)
	end
end

function botmatch.try_revive(bot)
	local def = minetest.registered_craftitems["sl_modebase:reincarnate"]
	if not def or not def.on_use then return end
	local before = game_mode.get_player_state(bot:get_player_name()).phase
	def.on_use(ItemStack("sl_modebase:reincarnate"), bot, nil)
	if game_mode.get_player_state(bot:get_player_name()).phase == "evil_ghost" and before == "ghost" then
		botmatch.record_event("revivals", 1)
		botmatch.record_bot_flag(bot:get_player_name(), "revived_evil")
		bot.bm.next_act = 0          -- act as soon as in range
		bot.bm.sabotage_target = nil -- re-pick a beacon target
		bot.bm.sab_first = math.random() < 0.5 -- alternate objective order
		-- Phase in at a random arena edge: ghosts die in melee, so reviving
		-- at the death spot puts them instantly back inside hunter range
		-- (purged before any objective). The trickster re-entries elsewhere.
		local ang = math.random() * 2 * math.pi
		bot:set_pos({ x = math.cos(ang) * 8, y = 3, z = math.sin(ang) * 8 })
	end
end

function botmatch.try_sabotage(bot, pos)
	local def = minetest.registered_tools["sl_modebase:sabotage_charge"]
	if not def or not def.on_use then return end
	local result = def.on_use(ItemStack("sl_modebase:sabotage_charge"), bot, { type = "node", under = pos })
	local used = result and result.to_string and result:to_string() == "" or result == nil
	if game_mode.is_sabotaged(pos) and used then
		botmatch.record_event("sabotages", 1)
	end
end

function botmatch.try_possess(bot, pos)
	-- Fused WP3 system: reusable possession_focus tool, cooldown-bounded.
	local def = minetest.registered_tools["sl_modebase:possession_focus"]
	if not def or not def.on_use then return false end
	local name = bot:get_player_name()
	local pl = game_mode.get_player_state(name)
	local had_focus = bot:get_inventory():contains_item("main",
		ItemStack("sl_modebase:possession_focus"))
	def.on_use(ItemStack("sl_modebase:possession_focus"), bot, { type = "node", under = pos })
	if game_mode.is_possessed(pos) then
		botmatch.record_event("possessions", 1)
		return true
	end
	local node = minetest.get_node_or_nil(pos)
	minetest.log("action", string.format(
		"[botmatch][possess-debug] %s refused at %s: phase=%s focus=%s match_active=%s cd_left=%.1f node=%s possessable=%s possessed=%s sabotaged=%s crate_pos=%s",
		name, minetest.pos_to_string(pos), tostring(pl.phase), tostring(had_focus),
		tostring(game_mode.state.match_active),
		math.max(0, (pl.possession_ready_at or 0) - game_mode.now()),
		node and node.name or "nil",
		tostring(node and game_mode.is_possessable(node.name)),
		tostring(game_mode.is_possessed(pos)),
		tostring(game_mode.is_sabotaged(pos)),
		botmatch.crate_pos and minetest.pos_to_string(botmatch.crate_pos) or "nil"))
	return false
end
