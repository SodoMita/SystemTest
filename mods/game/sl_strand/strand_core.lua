-- ================================================================
-- sl_strand / strand_core.lua
-- High-level run driver.  Ties state+trust+vote+wave into a single
-- turn-by-turn entry point so the headless test can play a whole run
-- exactly as a human would, and so the runtime can drive the same
-- code.
--
--   run = strand.start_run(seed)
--   strand.turn(run, { type = "read_tell", bot = "Crew-3", target = "Crew-4" })
--   strand.turn(run, { type = "build", socket = "socket_1", kind = "turret" })
--   strand.turn(run, { type = "vote", accused = "Crew-3" })
-- ================================================================

-- Start a fresh run.  Builds the roster, rolls the Echo (possibly the
-- player), socialises the suspicion graph, lays sockets, and rolls the
-- mutation.
function strand.start_run(seed)
	seed = seed or (os.time() * 1000)
	local run = strand.new_run_state(seed)
	strand.make_crew(run, seed)
	strand.socialise_crew(run)
	strand.roll_echo(run)
	strand.make_sockets(run)
	strand.roll_mutation(run)
	strand.apply_mutation(run)
	return run
end

local TURN_ACTIONS = {
	["read_tell"] = function(run, a) return strand.read_tell(run, strand.find_bot(run, a.bot), a.target) end,
	["confide"]   = function(run, a) return strand.confide(run, strand.find_bot(run, a.bot)) end,
	["observe"]   = function(run, a) return strand.observe(run, strand.find_bot(run, a.bot), a.target) end,
	["build"]     = function(run, a) return strand.build_socket(run, a.socket, a.kind) end,
	["reveal"]    = function(run, a) return strand.reveal_player_is_echo(run) end,
	["choose"]    = function(run, a) run.player_choice = a.choice; return run.player_choice end,
	["vote"]      = function(run, a) return strand.resolve_vote(run, a.accused, a.player_vote) end,
}

function strand.find_bot(run, name)
	for _, bot in ipairs(run.crew) do
		if bot.name == name then return bot end
	end
	return nil
end

-- Execute one player action for the current phase, then advance the
-- phase machine if the action was terminal for that phase.
function strand.turn(run, action)
	if not run or not run.active then
		return nil, "run is not active"
	end
	local fx = TURN_ACTIONS[action and action.type]
	if not fx then
		return nil, "unknown action: " .. tostring(action and action.type)
	end
	local result, extra = fx(run, action)

	-- After a vote or a wave the phase machine advances automatically.
	if action.type == "vote" and run.active then
		if run.phase == "vote" then
			strand.advance_phase(run) -- vote -> wave
			local wave = strand.resolve_wave(run)
			strand.advance_phase(run) -- wave -> resolving
			strand.advance_phase(run) -- resolving -> build/victory/defeat
			if run.active then
				strand.make_sockets(run) -- re-arm sockets for the next night
				strand.apply_mutation(run) -- re-apply persistent mutation
			end
			return { result = result, wave = wave }, extra
		end
	end
	return result, extra
end

-- Describe the current run to the player/HUD.  Identity-safe: never
-- reveals who the Echo is.
function strand.describe_run(run)
	local core = run.core
	local status = "Core " .. math.floor(core.integrity) .. "/" .. core.target .. " · Night " ..
		run.night .. "/" .. core.target
	if run.player_is_echo and run.player_has_learned then
		status = status .. " · YOU ARE THE ECHO (" .. tostring(run.player_choice or "?") .. ")"
	end
	return status
end

-- Survival summary for the result screen.
function strand.run_summary(run)
	return {
		seed = run.seed,
		nights = run.night,
		outcome = run.phase,
		reason = run.defeat_reason or "core-complete",
		wrong_votes = run.wrong_votes,
		phantom_bosses = strand.phantom_boss_count(),
		mutation = run.mutation and run.mutation.id,
	}
end
