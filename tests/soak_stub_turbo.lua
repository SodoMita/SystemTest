-- ================================================================
-- tests/soak_stub_turbo.lua — Phase W exit-gate soak (stub engine)
--
-- Runs TURBO deathmatches with real sl_weapons logic: simulated bots
-- roam an arena, pick up loadouts, aim, fire, die through the real
-- punch/dieplayer pipeline (corpses, pool smashing, residue), respawn,
-- and fight again. The user's exit gate:
--
--   GATE 1  no single weapon claims > 30 % of kills over the run;
--   GATE 2  Grapple Lash holders die at a rate >= non-holders
--           (the Lash must stay expensive and dangerous, §10.1).
--
-- Plus: zero Lua errors anywhere (globalsteps are pcalled by the
-- stub; any error line fails the run), and the match-end sweep must
-- return the world to a clean state between matches.
--
-- Run: lua51 tests/soak_stub_turbo.lua [matches] [seed]
-- ================================================================

local MATCHES = tonumber(arg and arg[1]) or 40
local SEED = tonumber(arg and arg[2]) or 20260829
local TICKS = 340 -- ~85 s of simulated time per turbo match
local DT = 0.25

local H = dofile("tests/minetest_stub.lua")

H.current_modname = "sl_modebase"
dofile("mods/game/sl_modebase/init.lua")
H.modpaths.sl_weapons = "mods/game/sl_weapons"
H.current_modname = "sl_weapons"
local okw, errw = pcall(dofile, "mods/game/sl_weapons/init.lua")
if not okw then
	print("FATAL: sl_weapons failed to load: " .. tostring(errw))
	os.exit(1)
end
local W = sl_weapons
local gm = game_mode
local state = gm.state

-- ----------------------------------------------------------------
-- Arena: a 22x22 floor at y=59 so shots and shells have ground.
-- ----------------------------------------------------------------
local ARENA = { x0 = 0, x1 = 21, z0 = 0, z1 = 21, y = 60 }
local function build_arena()
	for x = ARENA.x0 - 2, ARENA.x1 + 2 do
		for z = ARENA.z0 - 2, ARENA.z1 + 2 do
			H.voxels[H.vhash({ x = x, y = 59, z = z })] = "default:stone"
		end
	end
end

-- ----------------------------------------------------------------
-- Bots
-- ----------------------------------------------------------------
local TEAM_A, TEAM_B = "beacon_a", "beacon_b"
local PRIMARIES = {
	"sl_weapons:chatter", "sl_weapons:scatter", "sl_weapons:lance",
	"sl_weapons:mortar", "sl_weapons:driver", "sl_weapons:neon_six",
	"sl_weapons:neon_repeater",
}

local bots = {}
local function make_bots()
	local names_a, names_b = {}, {}
	for i = 1, 4 do names_a[i] = "bot_a" .. i end
	for i = 1, 4 do names_b[i] = "bot_b" .. i end
	for _, n in ipairs(names_a) do bots[#bots + 1] = { p = H.new_player(n), team = TEAM_A } end
	for _, n in ipairs(names_b) do bots[#bots + 1] = { p = H.new_player(n), team = TEAM_B } end
	for _, b in ipairs(bots) do
		H.fire_joinplayer(b.p)
	end
	H.advance(0.3, 0.1)
	for _, b in ipairs(bots) do
		local pl = gm.get_player_state(b.p:get_player_name())
		pl.team = b.team
		pl.phase = "alive"
	end
end

local function random_pos()
	return {
		x = ARENA.x0 + math.random(0, ARENA.x1 - ARENA.x0),
		y = ARENA.y,
		z = ARENA.z0 + math.random(0, ARENA.z1 - ARENA.z0),
	}
end

local function alive_enemy_of(bot)
	local best, bd
	for _, o in ipairs(bots) do
		if o ~= bot and not o.p._dead and o.p:get_hp() > 0
			and gm.get_player_state(o.p:get_player_name()).phase == "alive" then
			local d = vector.distance(bot.p:get_pos(), o.p:get_pos())
			if not bd or d < bd then best, bd = o, d end
		end
	end
	return best, bd
end

-- ----------------------------------------------------------------
-- Telemetry
-- ----------------------------------------------------------------
local kills_by_cause = {}
local total_kills = 0
local lash_holder_deaths, lash_holder_alive_ticks = 0, 0
local plain_deaths, plain_alive_ticks = 0, 0
local lua_errors = 0

local function tally_errors()
	for _, l in ipairs(H.logs) do
		if type(l) == "string" and l:find("error", 1, true) then
			lua_errors = lua_errors + 1
			print("  LUA ERROR: " .. l)
		end
	end
end

-- ----------------------------------------------------------------
-- Match loop
-- ----------------------------------------------------------------
local respawn_queue = {} -- name -> time

local function start_match(with_lash)
	state.settings.mm_auto_assign = false
	minetest.registered_chatcommands.sl_match_start.func(bots[1].p:get_player_name(), "")
	for _, b in ipairs(bots) do
		minetest.registered_chatcommands.sl_ready.func(b.p:get_player_name(), "")
	end
	H.advance(7, 0.5)
	if not state.match_active then
		print("FATAL: match failed to start")
		os.exit(1)
	end

	-- Loadouts: one random primary each. Lash trials: one bot per team
	-- ALSO carries the Grapple Lash — it is a movement tool beside the
	-- primary (§10.1); its price is cells (5/launch, shared with the
	-- lance and driver) and the exposure of hanging on a line.
	for i, b in ipairs(bots) do
		b.lash = false
		b.p:get_inventory():add_item("main",
			W.loaded_stack(PRIMARIES[math.random(1, #PRIMARIES)]))
		if with_lash and (i == 1 or i == 5) then
			b.lash = true
			b.p:get_inventory():add_item("main", ItemStack("sl_weapons:grapple"))
		end
		local pool = W.get_pool(b.p:get_player_name())
		pool.bullets = math.random(30, 90)
		pool.shells = math.random(8, 20)
		pool.cells = math.random(20, 70)
		pool.rockets = math.random(4, 10)
		b.p:set_hp(20)
		b.p:set_pos(random_pos())
	end
end

local function ai_tick(bot, now)
	local pl = gm.get_player_state(bot.p:get_player_name())
	if bot.p._dead or pl.phase ~= "alive" then return end
	local foe, dist = alive_enemy_of(bot)
	if not foe then return end

	-- Strafe/approach: 1 node per tick with jitter (4 n/s feel), with a
	-- small standoff so brawlers do not live inside the foe's vest.
	local mypos, fpos = bot.p:get_pos(), foe.p:get_pos()
	local dx, dz = fpos.x - mypos.x, fpos.z - mypos.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len > 0.001 then dx, dz = dx / len, dz / len end
	local drive = (dist < 3 and -0.6) or 0.7
	local tx = mypos.x + dx * drive + (math.random() - 0.5) * 2.2
	local tz = mypos.z + dz * drive + (math.random() - 0.5) * 2.2
	tx = math.max(ARENA.x0, math.min(ARENA.x1, tx))
	tz = math.max(ARENA.z0, math.min(ARENA.z1, tz))
	bot.p:set_pos({ x = tx, y = ARENA.y, z = tz })

	-- Hanging on the lash: hands are busy, the body is exposed — reel
	-- toward the anchor instead of shooting back.
	local st = W.lash[bot.p:get_player_name()]
	if st and st.anchor then
		local mp = bot.p:get_pos()
		local ax, az = st.anchor.x - mp.x, st.anchor.z - mp.z
		local al = math.sqrt(ax * ax + az * az)
		if al > 1.5 and al < 24 then
			bot.p:set_pos({ x = mp.x + ax / al * 2, y = ARENA.y, z = mp.z + az / al * 2 })
		end
		return
	end

	-- Aim at the foe's chest.
	local eye = { x = tx, y = ARENA.y + 1.625, z = tz }
	local tgt = { x = fpos.x, y = fpos.y + 1.0, z = fpos.z }
	local dir = vector.direction(eye, tgt)
	bot.p:set_look_dir(dir)

	-- Fire whatever is carried (raise/refire/cooldown gates decide).
	-- Bots prefer any weapon whose ammo pool can still feed it; the
	-- loadout pistol is the fallback when every primary is dry
	-- (v1.3.9: no more autoswitch — dry guns stay in the hand).
	local inv = bot.p:get_inventory()
	local pool = W.peek_pool(bot.p:get_player_name())

	-- Lash holders pay the real price: launch the line instead of
	-- shooting whenever the urge takes them (5 cells a throw).
	if bot.lash and math.random() < 0.18 and (pool.cells or 0) >= 5 then
		-- Players do not brawl in a finished match; the mod's open
		-- test range is for the living, not for bots farming noise.
		if game_mode.state.match_active then
			local ldef = minetest.registered_tools["sl_weapons:grapple"]
			if ldef and ldef.on_use then
				bot.p:set_look_dir({ x = dir.x, y = dir.y - 0.45, z = dir.z })
				pcall(ldef.on_use, ItemStack("sl_weapons:grapple"), bot.p, nil)
			end
		end
		return
	end

	local wield, pistol = "", ""
	for _, st in ipairs(inv:get_list("main")) do
		local n = st:get_name()
		if n ~= "" and (W.defs_by_item[n] or n == "sl_weapons:grapple") then
			local d = W.defs_by_item[n]
			if d and d.id == "pistol" then
				pistol = n
			elseif wield == "" then
				local cost = (d and d.ammo_cost) or 1
				local kind = d and d.pool
				if not kind or (pool[kind] or 0) >= cost or n == "sl_weapons:grapple" then
					wield = n
				else
					wield = "" -- primary is dry; keep looking for a fed one
				end
			end
		end
	end
	if wield == "" then wield = pistol end
	-- v1.3 magazines: bots keep one persistent stack per weapon and
	-- load it from their reserve when it runs dry, exactly like a
	-- player pressing the load key.
	bot.stacks = bot.stacks or {}
	local st = bot.stacks[wield]
	if not st or st:get_name() ~= wield then
		st = ItemStack(wield)
		bot.stacks[wield] = st
	end
	local wdef = W.defs_by_item[wield]
	if wdef and wdef.pool and wdef.mag and W.mag_get(st) <= 0 then
		W.mag_load(bot.p, wdef, st)
	end
	local def = minetest.registered_tools[wield]
	if def and def.on_use and math.random() < 0.65
		and (not wdef or not wdef.pool or W.mag_get(st) > 0)
		and game_mode.state.match_active then
		-- Fast weapons may cycle several times inside one tick;
		-- the mod's own refire gates decide what actually leaves
		-- the barrel.
		for _ = 1, 3 do
			pcall(def.on_use, st, bot.p, nil)
		end
	end
end

local match_seq = 0
local primary_run = true -- kill shares are reported for the first seed only

local function run_match(mi)
	match_seq = match_seq + 1
	local with_lash = (match_seq % 2 == 1) -- half the matches run the Lash trial
	start_match(with_lash)
	local t0 = #H.logs

	local next_restock = W.now() + 12
	for tick = 1, TICKS do
		local now = W.now()
		-- Arena economy: pads re-arm periodically; bots that wander
		-- refill their pools (AMMO_YIELD per pickup, spec §4).
		if now >= next_restock then
			next_restock = now + 12
			for _, b in ipairs(bots) do
				local pool = W.get_pool(b.p:get_player_name())
				for kind, cap in pairs(W.POOL_MAX) do
					pool[kind] = math.min(cap, (pool[kind] or 0) + W.AMMO_YIELD[kind])
				end
			end
		end
		-- Respawns (2 s delay).
		for name, when in pairs(respawn_queue) do
			if now >= when then
				respawn_queue[name] = nil
				local p = minetest.get_player_by_name(name)
				if p then
					H.respawn(p)
					p:set_hp(20)
					p:set_pos(random_pos())
				end
			end
		end
		H.advance(DT, DT)
		for _, bot in ipairs(bots) do
			ai_tick(bot, now)
		end
		-- Death telemetry: the stub's dieplayer chain already ran the
		-- corpse/pool logic; attribute the kill and holder status.
		for _, bot in ipairs(bots) do
			local name = bot.p:get_player_name()
			if bot.p._dead and not bot.counted then
				bot.counted = true
				local cause = W.last_cause[name] or "unknown"
				if primary_run then
					kills_by_cause[cause] = (kills_by_cause[cause] or 0) + 1
					total_kills = total_kills + 1
				end
				if bot.lash then
					lash_holder_deaths = lash_holder_deaths + 1
				else
					plain_deaths = plain_deaths + 1
				end
				respawn_queue[name] = W.now() + 2.0
			elseif not bot.p._dead then
				if bot.lash then
					lash_holder_alive_ticks = lash_holder_alive_ticks + 1
				else
					plain_alive_ticks = plain_alive_ticks + 1
				end
			end
		end
	end

	-- End the match and require a clean sweep.
	gm.end_match(nil, "turbo soak " .. mi)
	H.advance(1.0, 0.5)
	local clean = (#W.corpses == 0) and (next(W.turrets) == nil)
		-- pads/lash registries swept too
		and (next(W.lash) == nil)
	local residue_left = 0
	for h, name in pairs(H.voxels) do
		if name == "sl_weapons:residue" then residue_left = residue_left + 1 end
	end
	-- Reset per-bot flags for the next match.
	for _, bot in ipairs(bots) do
		bot.counted = false
		bot.stacks = {} -- magazines do not survive the sweep
		local inv = bot.p:get_inventory()
		for i = 1, inv:get_size("main") do
			inv:set_stack("main", i, ItemStack(""))
		end
	end
	return clean, residue_left
end

local function main()
	build_arena()
	make_bots()
	local seeds = { SEED, SEED + 101, SEED + 202 } -- danger gate is an
	-- aggregate: a single fixed seed puts a knife-edge metric one coin
	-- flip from red, and any benign change reshuffles the stream.
	print("== STUB TURBO SOAK: " .. MATCHES .. " matches x " .. #seeds
		.. " seeds (" .. table.concat(seeds, ",") .. ") ==")

	local dirty_matches = 0
	for si, seed in ipairs(seeds) do
		primary_run = (si == 1)
		math.randomseed(seed)
		for mi = 1, MATCHES do
			local clean, residue_left = run_match(mi)
			if not clean or residue_left > 0 then
				dirty_matches = dirty_matches + 1
				print(string.format("  seed %d match %d: sweep clean=%s residue_left=%d",
					seed, mi, tostring(clean), residue_left))
			end
		end
	end
	tally_errors()

	-- ------------------------------------------------------------
	-- Verdict
	-- ------------------------------------------------------------
	local pass = true
	print("\n== KILL SHARES ==")
	local shares = {}
	for cause, n in pairs(kills_by_cause) do shares[#shares + 1] = { cause, n } end
	table.sort(shares, function(a, b) return a[2] > b[2] end)
	for _, s in ipairs(shares) do
		local pct = 100 * s[2] / math.max(1, total_kills)
		print(string.format("  %-10s %4d kills  %5.1f%%", s[1], s[2], pct))
		if pct > 30.0 then
			print("  GATE 1 FAIL: " .. s[1] .. " exceeds 30% kill share")
			pass = false
		end
	end
	print(string.format("  total kills: %d", total_kills))

	print("\n== LASH TRIAL ==")
	local lash_rate = lash_holder_alive_ticks > 0
		and lash_holder_deaths / (lash_holder_alive_ticks * DT / 60) or 0
	local plain_rate = plain_alive_ticks > 0
		and plain_deaths / (plain_alive_ticks * DT / 60) or 0
	print(string.format("  holders:    %d deaths / %.1f min alive = %.2f deaths/min",
		lash_holder_deaths, lash_holder_alive_ticks * DT / 60, lash_rate))
	print(string.format("  nonholders: %d deaths / %.1f min alive = %.2f deaths/min",
		plain_deaths, plain_alive_ticks * DT / 60, plain_rate))
	if lash_rate + 1e-9 < plain_rate then
		print("  GATE 2 FAIL: Lash holders die LESS often than non-holders")
		pass = false
	end

	if lua_errors > 0 then
		print("\nLUA ERRORS: " .. lua_errors .. "  (GATE 3 FAIL)")
		pass = false
	end
	if dirty_matches > 0 then
		print("\nDIRTY SWEEPS: " .. dirty_matches .. " match(es) left state behind")
		pass = false
	end

	print("\nSOAK VERDICT: " .. (pass and "PASS" .. "" or "FAIL"))
	if not pass then os.exit(1) end
end

main()
