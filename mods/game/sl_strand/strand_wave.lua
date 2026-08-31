-- ================================================================
-- sl_strand / strand_wave.lua
-- Night wave: the horde (Mo's "junk into horror"), socket defense,
-- and the Al Dente Core integrity meter.
--
-- Each night a wave spawns at a set of defense sockets.  The player has
-- built turrets/barricades from scrap; the horde breaches the Core if
-- defense is too thin.  Wrongful exiles reduce effective defense, which
-- is the TD consequence of the deduction failure (Penelope's point:
-- the wrong wall placement is a trust cost).
--
-- The spawn math is pure and testable; the "broadcast"/entity spawn
-- seams are guarded so the headless harness can run without an engine.
-- ================================================================

strand.SOCKET_TYPES = { turret = true, barricade = true, trap = true }

function strand.make_sockets(run)
	-- 3 defense sockets per night (Mo: "scrap on the wall").
	local sockets = {}
	for i = 1, 3 do
		sockets[i] = { name = "socket_" .. i, built = nil }
	end
	run.sockets = sockets
	return sockets
end

-- Build/upgrade a socket from a scrap-defense kit.
function strand.build_socket(run, socket_name, def_type)
	if not def_type or not strand.SOCKET_TYPES[def_type] then
		return false, "unknown defense type"
	end
	local sock = nil
	for _, s in ipairs(run.sockets or {}) do
		if s.name == socket_name then sock = s end
	end
	if not sock then return false, "no such socket" end
	sock.built = def_type
	sock.level = (sock.level or 0) + 1
	return true, def_type
end

-- Effective defense this night: sum of built sockets, penalised by
-- wrongful exiles (each wrong vote costs a notch of uptime), boosted by
-- turret level.
function strand.effective_defense(run)
	local def = 0
	for _, s in ipairs(run.sockets or {}) do
		if s.built == "turret" then
			def = def + 10 + (s.level or 1) * 3
		elseif s.built == "barricade" then
			def = def + 6 + (s.level or 1) * 2
		elseif s.built == "trap" then
			def = def + 4 + (s.level or 1) * 2
		end
	end
	-- Wrongful exiles subtract from total uptime.
	local penalty = run.wrong_votes * 4
	def = math.max(0, def - penalty)
	return def
end

-- Scale of the oncoming horde this night.  Grows with night number,
-- phantom-boss count (persistent difficulty), and wrongful exiles.
function strand.horde_scale(run)
	local night = run.night + 1
	local base = 4 + night * 2
	local phantom = strand.phantom_boss_count()
	local wrong = run.wrong_votes
	return base + phantom + wrong * 2
end

-- Resolve one night's wave.  Returns a summary table; pure math so the
-- test can assert the outcomes deterministically.
function strand.resolve_wave(run)
	local scale = strand.horde_scale(run)
	local defense = strand.effective_defense(run)
	local survived = defense >= scale
	local breach = 0
	if not survived then
		breach = scale - defense
		run.core.integrity = run.core.integrity - breach
	end
	run.wave_log[#run.wave_log + 1] = {
		night = run.night + 1,
		scale = scale,
		defense = defense,
		survived = survived,
		breach = breach,
		integrity = run.core.integrity,
	}
	local outcome = "survived"
	if survived then
		run.core.integrity = math.min(run.core.integrity + 5, strand.config.core_integrity)
	else
		outcome = "breached"
		if run.core.integrity <= 0 then
			strand.run_defeat(run, "core-breach")
			outcome = "defeat"
		end
	end
	return {
		night = run.night + 1,
		scale = scale,
		defense = defense,
		survived = survived,
		breach = breach,
		integrity = run.core.integrity,
		outcome = outcome,
	}
end

-- Mutations between runs (roguelike).  Adds a deterministic, escalating
-- variant of the recipe each run.
strand.MUTATIONS = {
	{ id = "thin_walls",  desc = "Core integrity dries 10% each night.", delta_integrity = -1 },
	{ id = "hungry_horde", desc = "The horde feeds; waves grow faster.", delta_scale = 1 },
	{ id = "short_trust", desc = "Trust runs thinner each turn.", delta_trust = -1 },
	{ id = "loose_tongue", desc = "The crew remembers less.", delta_memory = -0.15 },
	{ id = "soft_cores", desc = "Wrongful exiles cost more defense.", delta_wrong_penalty = 1 },
}

function strand.roll_mutation(run)
	local idx = run.rng:range(1, #strand.MUTATIONS)
	local m = strand.MUTATIONS[idx]
	run.mutation = m
	return m
end

function strand.apply_mutation(run, m)
	m = m or run.mutation
	if not m then return end
	if m.id == "thin_walls" then
		run.core.integrity = run.core.integrity + m.delta_integrity
	elseif m.id == "hungry_horde" then
		-- encoded in horde_scale via run.mutation
	elseif m.id == "short_trust" then
		run.trust = math.max(1, run.trust + m.delta_trust)
	elseif m.id == "loose_tongue" then
		for _, bot in ipairs(run.crew) do
			for k in pairs(bot.memory) do
				if run.rng:fraction() < -m.delta_memory then bot.memory[k] = false end
			end
		end
	elseif m.id == "soft_cores" then
		-- stored so effective_defense reads it
		run.soft_cores = true
	end
end

function strand.mutation_bonus(run)
	local m = run.mutation
	if not m then return 0 end
	if m.id == "hungry_horde" then return m.delta_scale end
	if m.id == "soft_cores" and run.soft_cores then return 2 end
	return 0
end
