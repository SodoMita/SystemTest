-- ================================================================
-- sl_strand / strand_vote.lua
-- The Meeting / Vote resolution (the witch-trial, Melody's mandate).
--
-- The player accuses one crew-bot (or, once revealed, defends self /
-- accuses self).  The crew "argue" via their leans and the dialogue
-- layer; here we resolve the *rules*: what information is exposed
-- (partial, never certain), whether the exile is right or wrong, and
-- the permadeath -> phantom-boss consequence.
-- ================================================================

-- The amount of the crew's verdict revealed to the player.  We NEVER
-- reveal who is the Echo - only a bounded count of "certain" claims and
-- whether the accused is *more* or *less* suspected than the average,
-- which is the partial-truth contract.
function strand.vote_evaluation(run, accused)
	local verdict = strand.crew_verdict(run, accused)
	local is_echo = (accused == run.echo_identity)
	-- A "confident" block: the bots that voted accuse at full weight.
	local certain = verdict.accuse
	local total = verdict.total or 1
	local suspicion_ratio = (verdict.accuse + verdict.lean_accuse) / total
	-- Compare against a neutral baseline (40%) so partial info reads as
	-- a lean, not a verdict.
	local rel = suspicion_ratio - 0.40
	return {
		accused = accused,
		is_echo = is_echo,
		certain = certain,
		total = total,
		suspicion_ratio = suspicion_ratio,
		lean = rel > 0.15 and "suspected" or (rel < -0.15 and "cleared" or "mixed"),
	}
end

function strand.describe_evaluation(ev)
	return string.format(
		"%d of %d crew are certain. The room leans %s.",
		ev.certain, ev.total, ev.lean)
end

-- Force the player to LEARN they are the Echo (the systemic lie, made
-- explicit only when the moment arrives).  Melody's reveal; Barnaby's
-- fork.  Returns the two choices.
function strand.reveal_player_is_echo(run)
	if not run.player_is_echo then return false, "you are not the echo" end
	run.player_has_learned = true
	run.player_choice = nil
	return true, {
		-- PLAY ALONG = survive as the Echo, keep the Core from completing,
		--           and win by corrupting it (the Echo win).
		-- GIVE UP    = turn yourself in; a clean end that still counts as
		--           a run but surrenders the Echo win (Barnaby's dread).
		survive = "survive",
		give_up = "give_up",
	}
end

-- Resolve a vote.  `accused` is a crew-bot name OR strand.ECHO_PLAYER_NAME.
-- `player_vote` is the player's explicit action (optional; when the
-- player is the Echo and has chosen, it overrides the machinery).
function strand.resolve_vote(run, accused, player_vote)
	if accused == nil then
		return { outcome = "no_vote", message = "The crew looks at the floor." }
	end

	-- Self-aware Echo paths.
	if run.player_is_echo and run.player_has_learned then
		if run.player_choice == "give_up" then
			-- A clean surrender: the run ends as a non-win (no phantom
			-- boss is recorded; the player actively severed the chain).
			run._surrender = true
			strand.run_defeat(run, "self-surrender")
			return { outcome = "surrender", message = "You turn yourself in. The water stills." }
		end
		-- "survive": the player plays along; a vote resolved against the
		-- player would exile the Echo (crew win) unless defended.
		if accused == strand.ECHO_PLAYER_NAME then
			run.wrong_votes = run.wrong_votes + 1
			local drowned = (run.wrong_votes >= run.vote_limit)
			if drowned then
				strand.run_defeat(run, "overrun")
				return { outcome = "defeat", message = "The Echo is cornered and the room turns." }
			end
			return { outcome = "survived_vote", message = "The room cannot agree. You slip the rope." }
		end
	end

	local ev = strand.vote_evaluation(run, accused)

	-- Resolve the exile itself.
	if ev.is_echo then
		-- CORRECT exile: the Echo is purged.  If it was a crew-bot, its
		-- data becomes a phantom boss in the chain (persistent difficulty).
		if accused == strand.ECHO_PLAYER_NAME then
			strand.run_defeat(run, "echo-exiled")
			return { outcome = "defeat", message = "You were the Echo. You are deleted." }
		end
	-- remove the exiled crew-bot
	for _, bot in ipairs(run.crew) do
		if bot.name == accused then
			bot.alive = false
			bot.voted_out = true
		end
	end
	run.echo_identity = nil -- the Echo is gone this run
	run.correct_purges = (run.correct_purges or 0) + 1
	table.insert(run.exiled, accused)
	table.insert(run.phantom_bosses_this_run, accused)
	strand.record_phantom_boss({
			name = accused,
			seed = run.seed,
			night = run.night,
			score = ev.certain,
		})
		run.phase = "wave"
		run.voice_note = "The station exhales. One less liar, one more phantom."
		return { outcome = "correct", evaluation = ev, message = "The Echo is purged." }
	end

	-- WRONGFUL exile: a crew-bot (or the player, who was not the Echo)
	-- is burned.  Defense uptime suffers; the horde grows.
	run.wrong_votes = run.wrong_votes + 1
	if accused == strand.ECHO_PLAYER_NAME then
		-- The player, not the Echo, gets exiled by their own peers.
		-- This is a deep suspicion failure but NOT an Echo deletion.
		run.player_exiled = true
		strand.run_defeat(run, "wrongfully-exiled")
		return { outcome = "defeat", message = "They vote the wrong one out. It was you." }
	end
	for _, bot in ipairs(run.crew) do
		if bot.name == accused then
			bot.alive = false
			bot.voted_out = true
		end
	end
	table.insert(run.exiled, accused)
	table.insert(run.phantom_bosses_this_run, accused)
	-- The wronged bot's data still seeds a phantom: they were innocent,
	-- so the phantom is an *unwilling* horror (Barnaby's dread).
	strand.record_phantom_boss({
		name = accused,
		seed = run.seed,
		night = run.night,
		score = -ev.certain, -- negative = wronged
	})
	run.phase = "wave"
	run.voice_note = "You burned the wrong soul. The walls lean in."
	return { outcome = "wrong", evaluation = ev, message = "The wrong one is gone." }
end

-- Post-vote "did we survive?" — the night wave result feeds back here.
function strand.apply_wave_after_vote(run, wave)
	-- handled by strand_wave; kept as a seam
end
