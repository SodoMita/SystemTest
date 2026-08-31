-- ================================================================
-- sl_strand / strand_trust.lua
-- Trust Meter + crew-bot suspicion model.
--
-- The spine of the singleplayer run (Penelope's mandate): the player
-- only has a finite **Trust** to spend each turn, and the Echo has the
-- same budget hidden.  Suspicion is a *machine*, not a vibe: each
-- crew-bot privately scores every other agent and the player, but
-- publicly *claims* something different.  The player reads the gap.
--
-- All scoped to strand / minetest basics so the headless test can
-- drive it without the full game loaded.
-- ================================================================

-- Initialise one crew-bot's social state against a full roster.
-- Public persona deliberately differs from private belief (the "tell").
function strand.init_crew_social(run, bot, names)
	bot.trust = {}
	bot.persona = {}
	bot.memory = {}
	for _, other in ipairs(names) do
		if other ~= bot.name then
			-- Private belief: a base closeness jittered by leadership bias.
			local base = 40 + run.rng:range(-20, 20)
			-- The Echo is subtly "too helpful / too agreeable"; the seed
			-- nudges openness toward the Echo without broadcasting it.
			local is_echo = (other == run.echo_identity)
			bot.trust[other] = math.max(0, math.min(100, base + (is_echo and run.rng:range(-8, 8) or 0)))
			-- Public claim: a performative stance, often warmer than the
			-- private score to masquerade suspicion.
			local persona = bot.trust[other] + run.rng:range(-15, 25)
			bot.persona[other] = math.max(0, math.min(100, persona))
			-- Memory: only ~60% of observations are actually recorded.
			bot.memory[other] = (run.rng:fraction() < 0.6)
		end
	end
end

-- Rebuild all bots' social graph for a freshly initialised run.
function strand.socialise_crew(run)
	local names = run.crew_names or {}
	for _, bot in ipairs(run.crew) do
		strand.init_crew_social(run, bot, names)
	end
end

-- How sure a bot secretly is that `target` is the Echo.  Lower score =
-- more suspicious.  Returns 0..100.
function strand.private_suspicion(run, bot, target)
	local trust = bot.trust[target]
	if trust == nil then return 50 end
	return 100 - trust
end

-- The public stance a bot PROJECTS about `target`.  The player uses
-- this to spend Trust and infer the gap (Penelope's "the tell").
function strand.public_persona(run, bot, target)
	return bot.persona[target] or 50
end

-- Read the TELL: compare the bot's public persona against its private
-- belief.  A wide gap means the bot is performing - which is *not* the
-- same as lying, but it is information.  Costs 1 Trust.
function strand.read_tell(run, bot, target)
	if run.trust < 1 then return nil, "no trust" end
	run.trust = run.trust - 1
	run.presence_spent = run.presence_spent + 1
	local pub = strand.public_persona(run, bot, target)
	local priv = bot.trust[target] or 50
	local gap = pub - priv
	-- Classify the tell into a human-readable readout.
	local read
	if gap >= 20 then
		read = "performing warm — hiding something"
	elseif gap <= -20 then
		read = "publicly cold but privately soft"
	else
		read = "roughly consistent"
	end
	-- If the bot actually has this in memory, it also reports what it
	-- observed (the honest signal within the performance).
	if bot.memory[target] then
		read = read .. "; remembers an action"
	else
		read = read .. "; no memory of action"
	end
	return read, bot.trust[target]
end

-- CONFIDE: spend 1 Trust to raise a bot's trust in the player (they may
-- still betray it later).  Returns the new trust value.
function strand.confide(run, bot)
	if run.trust < 1 then return nil, "no trust" end
	run.trust = run.trust - 1
	run.presence_spent = run.presence_spent + 1
	local current = bot.trust[strand.ECHO_PLAYER_NAME] or 50
	current = math.min(100, current + 15)
	bot.trust[strand.ECHO_PLAYER_NAME] = current
	return current
end

-- OBSERVE: spend 1 Trust to force a bot to (re)record an observation
-- this turn, future-proofing the read against its broken memory.
function strand.observe(run, bot, target)
	if run.trust < 1 then return nil, "no trust" end
	run.trust = run.trust - 1
	run.presence_spent = run.presence_spent + 1
	bot.memory[target] = true
	return true
end

-- A single bot's LEAN during a vote: how strongly it will push to
-- exile `accused` given its private belief and its persona toward the
-- accuser.  Pure and deterministic given state.
function strand.bot_lean(run, bot, accused)
	if not bot.alive then return nil end
	if accused == bot.name then return { vote = "defend", weight = 100 } end
	local suspicion = strand.private_suspicion(run, bot, accused)
	local persona = strand.public_persona(run, bot, accused)
	-- A bot's willingness to accuse scales with its suspicion and its
	-- independence from the accuser's influence.
	local voice = suspicion
	-- Defensive/aggressive personality skews the lean.
	voice = voice + (bot.leadership - 50) * 0.2
	local lean
	if voice >= 70 then
		lean = "accuse"
	elseif voice >= 55 then
		lean = "lean_accuse"
	elseif voice <= 30 then
		lean = "defend"
	else
		lean = "uncertain"
	end
	return { vote = lean, weight = voice, persona = persona }
end

-- Aggregate the crew's public verdict on `accused`.  Returns counts.
function strand.crew_verdict(run, accused)
	local counts = { accuse = 0, lean_accuse = 0, uncertain = 0, defend = 0 }
	local total = 0
	for _, bot in ipairs(run.crew) do
		local l = strand.bot_lean(run, bot, accused)
		if l then
			counts[l.vote] = counts[l.vote] + 1
			total = total + 1
		end
	end
	counts.total = total
	counts.certain = counts.accuse -- the "certain enough" block for partial reveal
	return counts
end
