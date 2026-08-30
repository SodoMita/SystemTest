-- ================================================================
-- sl_solo/traitor.lua — THE ECHO (hidden traitor)
-- ================================================================
-- One crew bot on the operator's beacon team serves the Simulation.
-- It is never announced; it is only observable:
--
--   TELLS (the deduction surface, documented in SINGLEPLAYER.md):
--   * Corruption on CORE A is ALWAYS the Echo while it lives — the
--     solo doctrine suppresses rival evil-ghost revivals entirely.
--   * The Echo never engages the rival crew (it will not brawl).
--   * It loiters at midfield / the loot crate instead of pushing the
--     objective or holding the core.
--   * It flees hostile waves far earlier than loyal units (which stand
--     and punch at 2.5 m).
--   * It deflects in crew chatter; loyal units sometimes witness a
--     sabotage and name what they saw.
--   * Late match (difficulty-gated) it stops pretending and HUNTS.
--
-- Sabotage calls game_mode.register_sabotage directly: the Echo is a
-- native corruption of the simulation, not an evil ghost with a
-- charge item, so the same visible corruption marker / repair rules /
-- beacon corrosion apply through the real WP3 systems.
-- ================================================================

local function now_s() return game_mode.now() end

local function dist2d(a, b)
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- Select the Echo from the operator's crew (never the operator).
function sl_solo.select_traitor()
	local st = sl_solo.state
	local pool = {}
	local b = rawget(_G, "botmatch")
	if b then
		for _, botname in ipairs(b.bot_order) do
			if st.crew[botname] then table.insert(pool, botname) end
		end
	end
	if #pool == 0 then return nil end
	local idx = math.random(1, #pool)
	if sl_solo.cfg.traitor_index > 0 then
		idx = ((sl_solo.cfg.traitor_index - 1) % #pool) + 1
	end
	return pool[idx]
end

-- The Echo's entire living behavior. Returns true when handled (the
-- harness default behavior is skipped so it never fights the rival
-- crew by accident).
function sl_solo.traitor_tick(name, dt)
	local st = sl_solo.state
	local b = rawget(_G, "botmatch")
	local bot = b and b.bots[name]
	if not bot then return true end

	local pl = game_mode.get_player_state(name)
	if pl.phase ~= "alive" or pl.eliminated or bot.dead then
		return false -- ghost/evil handling falls through to the harness
	end

	local preset = st.preset or sl_solo.difficulties.standard
	local now = now_s()
	local pos = bot:get_pos()
	local team_id = pl.team or st.human_team
	local tdef = game_mode.state.teams[team_id]

	-- 0) HUNT: past the difficulty gate the mask comes off — attack the
	-- nearest living player (crew OR operator; frame the chaos).
	if st.hunt_at and now >= st.hunt_at then
		local target, td = nil, 5
		local function consider(pname)
			local opl = game_mode.get_player_state(pname)
			local p = minetest.get_player_by_name(pname)
			if opl and opl.phase == "alive" and not opl.eliminated and p and not (b.bots[pname] and b.bots[pname].dead) then
				local d = dist2d(pos, p:get_pos())
				if d < td then target, td = p, d end
			end
		end
		consider(st.human)
		for botname in pairs(st.crew) do
			if botname ~= name then consider(botname) end
		end
		if target then
			if td < 2 then
				if now >= (bot.bm.next_hunt or 0) then
					bot.bm.next_hunt = now + 6
					b.punch_player(bot, target)
				end
			else
				bot.bm.nav_target = target:get_pos()
			end
			return true
		end
	end

	-- 1) Cowardice tell: flee hostiles at 7 m (loyal units brawl at 2.5).
	local monster, md = sl_solo.nearest_monster(pos, 7)
	if monster and md < 7 then
		local away = vector.subtract(pos, monster:get_pos())
		bot.bm.nav_target = {
			x = pos.x + away.x * 2,
			y = pos.y,
			z = pos.z + away.z * 2,
		}
		return true
	end

	-- 2) Sabotage window: creep toward CORE A, corrupt, slip away.
	if now >= (st.traitor_next_sabotage or 0) and tdef and tdef.spawn then
		local bpos = { x = tdef.spawn.x, y = tdef.spawn.y - 1, z = tdef.spawn.z }
		local d = dist2d(pos, bpos)
		if d < 3 then
			-- Stealth roll: if someone is watching, half the time the Echo
			-- bottles it and waits (a near-miss is a tell too).
			local watcher = sl_solo.find_watcher(bpos, 9, name)
			if watcher and math.random() < 0.5 then
				st.traitor_next_sabotage = now + 12
				return true
			end
			game_mode.register_sabotage(bpos, "beacon", team_id)
			st.traitor_sabotages = st.traitor_sabotages + 1
			st.traitor_next_sabotage = now + preset.sabotage_min
				+ math.random(0, math.max(0, preset.sabotage_max - preset.sabotage_min))
			minetest.sound_play("alert", { pos = bpos, gain = 0.7, max_hear_distance = 12 })
			sl_solo.traitor_sabotaged(name, bpos)
			-- slip away from the scene
			bot.bm.nav_target = { x = bpos.x + (math.random() - 0.5) * 16, y = pos.y, z = bpos.z + (math.random() - 0.5) * 16 }
			return true
		end
		-- Lurk on a 6 m ring around the core: close enough to look busy,
		-- far enough to look wrong once you know what busy looks like.
		if d > 6 then
			bot.bm.nav_target = { x = bpos.x, y = tdef.spawn.y, z = bpos.z }
		else
			bot.bm.nav_target = nil -- hold position
		end
		return true
	end

	-- 3) Loiter: midfield / loot crate. Never engage rivals: if one is
	-- close, drift away (that refusal to brawl is a visible tell).
	local enemy = nil
	local ed = 6
	for botname in pairs(st.rivals) do
		local rbot = b.bots[botname]
		local opl = game_mode.get_player_state(botname)
		if rbot and not rbot.dead and opl.phase == "alive" and not opl.eliminated then
			local d = dist2d(pos, rbot:get_pos())
			if d < ed then enemy, ed = rbot, d end
		end
	end
	if enemy then
		local away = vector.subtract(pos, enemy:get_pos())
		bot.bm.nav_target = { x = pos.x + away.x * 2, y = pos.y, z = pos.z + away.z * 2 }
		return true
	end

	-- Idle drift between the crate and the altar.
	local lurk = b.crate_pos or { x = 0, y = 1, z = 0 }
	if dist2d(pos, lurk) > 4 then
		bot.bm.nav_target = { x = lurk.x, y = lurk.y, z = lurk.z }
	else
		bot.bm.nav_target = nil
	end
	return true
end

-- Nearest LIVING player (other than `exclude`) within range of pos.
-- Returns name or nil. Used for stealth rolls and witness lines.
function sl_solo.find_watcher(pos, range, exclude)
	local best, bd = nil, range
	local function consider(pname)
		if pname == exclude then return end
		local b = rawget(_G, "botmatch")
		if b and b.bots[pname] and b.bots[pname].dead then return end
		local pl = game_mode.get_player_state(pname)
		if not pl or pl.phase ~= "alive" or pl.eliminated then return end
		local p = minetest.get_player_by_name(pname)
		if not p then return end
		local d = vector.distance(pos, p:get_pos())
		if d < bd then best, bd = pname, d end
	end
	local st = sl_solo.state
	consider(st.human)
	for botname in pairs(st.crew) do consider(botname) end
	for botname in pairs(st.rivals) do consider(botname) end
	return best
end

-- The corruption just landed. Publish the observable consequences:
-- a public broadcast (already fired by the real systems for items; we
-- add the Simulation's voice), a private sighting hint when the
-- operator is close enough to have "seen" it, and maybe a loyal unit
-- witness line naming the lurker they spotted.
function sl_solo.traitor_sabotaged(traitor_name, bpos)
	local st = sl_solo.state
	local traitor_desig = st.designations[traitor_name] or "a crew unit"
	game_mode.broadcast(minetest.colorize("#ff5555", "CORE A INTEGRITY COMPROMISED — internal corruption."))

	-- Operator sighting: within 18 m the operator sees the designation.
	local hp = st.human and minetest.get_player_by_name(st.human) or nil
	if hp then
		local pl = game_mode.get_player_state(st.human)
		if pl.phase == "alive" and vector.distance(hp:get_pos(), bpos) < 18 then
			minetest.chat_send_player(st.human, minetest.colorize("#ffaa00",
				"You glimpse " .. traitor_desig .. " slipping away from the core housing."))
		end
	end

	-- Loyal witness (50%): the nearest living crew unit names a lurker.
	if math.random() < 0.5 then
		local b = rawget(_G, "botmatch")
		local witness, wd = nil, 26
		for botname in pairs(st.crew) do
			if botname ~= traitor_name and b and b.bots[botname] and not b.bots[botname].dead then
				local opl = game_mode.get_player_state(botname)
				if opl.phase == "alive" and not opl.eliminated then
					local d = vector.distance(b.bots[botname]:get_pos(), bpos)
					if d < wd then witness, wd = botname, d end
				end
			end
		end
		if witness then
			sl_solo.say(witness, "corruption spike at CORE A — I have " .. traitor_desig .. " on my proximity log.")
		end
	end
end

-- The Echo died. The mask comes off either way.
function sl_solo.reveal_traitor_death(name)
	local st = sl_solo.state
	if st.traitor_purged then return end
	st.traitor_purged = true
	local desig = st.designations[name] or name
	local killer = st.killer_of[name]
	local line
	if killer == st.human then
		line = "You purged it yourself. Good."
	elseif killer then
		line = "Another salvager's blade found it first — the credit is shared."
	else
		line = "The Simulation consumed its own echo."
	end
	sl_solo.announce("== ECHO EXPOSED: " .. desig .. " was the corruption. " .. line .. " ==")
	sl_solo.log("echo " .. tostring(name) .. " purged (" .. tostring(killer or "simulation") ..
		"); sabotages=" .. st.traitor_sabotages .. " operator innocent kills=" .. st.innocent_kills)

	minetest.after(4, function()
		if st.active and game_mode.state.match_active then
			game_mode.end_match("beacon_a", "SOLO PROTOCOL COMPLETE — the Echo was purged")
		end
	end)
end
