-- ================================================================
-- sl_strand / strand_ledger.lua
-- THE CHAIN LEDGER — the singleplayer economy layer.
--
-- The council's open questions (TOPICS_QUESTIONS.txt items 3-5):
--   * points had state and display but no EARN RULE;
--   * the debt economy ("debt from burned scores") had no shape;
--   * endings had no named identities or flag combos.
--
-- This file is that shape. One run settles exactly once:
--
--   score_run(run)   -> pure scoring of a finished (or finishing) run
--   ending_for(run)  -> deterministic named ending + flags
--   settle_run(run)  -> ledger update (score, debt, endings) + persist
--   apply_debt(run)  -> start-of-run penalty curve from carried debt
--   ledger_summary() -> HUD/result view of the persistent chain
--
-- All math is integer and deterministic; the headless test drives it.
-- ================================================================

strand = rawget(_G, "strand") or {}
_G.strand = strand

-- ---------------------------------------------------------------
-- Named endings.  One per terminal state; flags layer on top.
-- ---------------------------------------------------------------
strand.ENDINGS = {
	ascent = {
		id = "ascent", title = "AL DENTE ASCENT",
		desc = "The Core completed. The crew was right enough, often enough.",
	},
	hollow_crown = {
		id = "hollow_crown", title = "HOLLOW CROWN",
		desc = "You were the Echo all along, and the Core fell with you inside it.",
	},
	clean_cut = {
		id = "clean_cut", title = "CLEAN CUT",
		desc = "You turned yourself in. No phantom was born; the chain is halved.",
	},
	deleted = {
		id = "deleted", title = "DELETED",
		desc = "You were the Echo, and the room finally saw you.",
	},
	witch_trial = {
		id = "witch_trial", title = "WITCH TRIAL",
		desc = "They burned the wrong soul. It was you, and you were innocent.",
	},
	static = {
		id = "static", title = "STATIC",
		desc = "The Core breached. The horde is in the walls now.",
	},
	overrun = {
		id = "overrun", title = "OVERRUN",
		desc = "Too many wrong votes. The room could no longer defend itself.",
	},
}

-- defeat_reason -> ending id (victory endings come from victory_reason)
local DEFEAT_ENDING = {
	["self-surrender"]     = "clean_cut",
	["echo-exiled"]        = "deleted",
	["wrongfully-exiled"]  = "witch_trial",
	["core-breach"]        = "static",
	["overrun"]            = "overrun",
}

-- ---------------------------------------------------------------
-- Ending resolution.  Deterministic given final run state; NEVER
-- called mid-run (only from settle paths).
-- ---------------------------------------------------------------
function strand.ending_for(run)
	local e
	if run.phase == "victory" then
		e = (run.victory_reason == "corruption")
			and strand.ENDINGS.hollow_crown
			or strand.ENDINGS.ascent
	else
		e = strand.ENDINGS[DEFEAT_ENDING[run.defeat_reason] or "static"]
	end
	local flags = {}
	if run.player_is_echo then
		flags[#flags + 1] = "hollow"          -- the run was a lie about you
	end
	if run.wrong_votes == 0 then
		flags[#flags + 1] = "flawless"        -- nobody innocent was burned
	end
	if #(run.phantom_bosses_this_run or {}) > 0 then
		flags[#flags + 1] = "phantom_seeded"  -- the chain grew a hunter
	end
	return e, flags
end

-- ---------------------------------------------------------------
-- The earn rule.  Pure: reads the run, returns an integer total and
-- a breakdown every line of which is explainable on the result screen.
--   nights    : 10 each survived
--   purges    : 40 each correct Echo purge
--   wrong     : -25 each wrongful exile
--   trust     : 2 per banked Trust point at settlement
--   integrity : 1 per 2 remaining Core points (victories only)
--   flawless  : +30 victory with zero wrongful exiles
--   deception : +50 the HOLLOW CROWN (played the lie to the end)
-- ---------------------------------------------------------------
function strand.score_run(run)
	local w = strand.config
	local breakdown = {
		nights    = (run.night or 0) * w.ledger_score_per_night,
		purges    = (run.correct_purges or 0) * w.ledger_purge_bonus,
		wrong     = -(run.wrong_votes or 0) * w.ledger_wrong_penalty,
		trust     = math.floor(math.max(0, run.trust or 0)) * w.ledger_trust_point,
		integrity = 0,
		flawless  = 0,
		deception = 0,
	}
	if run.phase == "victory" then
		breakdown.integrity = math.floor(math.max(0, run.core.integrity or 0)
			* w.ledger_integrity_point)
		if (run.wrong_votes or 0) == 0 then
			breakdown.flawless = w.ledger_flawless_bonus
		end
		if run.victory_reason == "corruption" then
			breakdown.deception = w.ledger_deception_bonus
		end
	end
	local total = 0
	for _, v in pairs(breakdown) do total = total + v end
	breakdown.total = math.max(0, math.floor(total))
	return breakdown
end

-- ---------------------------------------------------------------
-- Ledger default + accessors
-- ---------------------------------------------------------------
function strand.default_ledger()
	return {
		score = 0,        -- banked across all runs
		debt = 0,         -- burned potential, punishes later runs
		runs = 0,
		wins = 0,
		best_nights = 0,
		endings = {},     -- [ending_id] = times seen
		flags = {},       -- [flag] = times seen
	}
end

function strand.ledger()
	local p = strand.persisted
	if not p.ledger then p.ledger = strand.default_ledger() end
	return p.ledger
end

function strand.ledger_summary()
	local l = strand.ledger()
	-- Snapshot: never hand out live references — callers must not be able
	-- to mutate the persistent ledger through a summary view.
	local endings, flags = {}, {}
	for k, v in pairs(l.endings or {}) do endings[k] = v end
	for k, v in pairs(l.flags or {}) do flags[k] = v end
	return {
		score = l.score,
		debt = l.debt,
		runs = l.runs,
		wins = l.wins,
		best_nights = l.best_nights,
		endings = endings,
		flags = flags,
		phantom_bosses = strand.phantom_boss_count(),
	}
end

-- ---------------------------------------------------------------
-- Settlement.  Idempotent; wired into run_victory / run_defeat /
-- the advance_phase victory edge so every terminal path settles
-- exactly once.
--
-- Debt rule ("debt from burned scores"):
--   * a LOSS burns the run's unearned potential into debt —
--       remaining_nights * 10 * 0.5  +  wrong_votes * 5
--   * a VICTORY banks its score and pays half of it against debt;
--   * the CLEAN CUT (self-surrender) burns at half rate: the one
--     strategic mercy in the chain.
--   * debt is capped; it decays only through victory.
-- ---------------------------------------------------------------
function strand.settle_run(run)
	if run._settled then return run.ledger_result end
	run._settled = true

	local ending, flags = strand.ending_for(run)
	local sc = strand.score_run(run)
	local l = strand.ledger()
	local cfg = strand.config

	l.runs = l.runs + 1
	if run.night > (l.best_nights or 0) then l.best_nights = run.night end
	l.endings[ending.id] = (l.endings[ending.id] or 0) + 1
	for _, f in ipairs(flags) do
		l.flags[f] = (l.flags[f] or 0) + 1
	end

	local victory = (run.phase == "victory")
	if victory then
		l.wins = l.wins + 1
		l.score = l.score + sc.total
		l.debt = math.max(0, l.debt - math.floor(sc.total * cfg.ledger_paydown))
	else
		local remaining = math.max(0, (run.core.target or 0) - (run.night or 0))
		local burned = math.floor(remaining * cfg.ledger_score_per_night
			* cfg.ledger_debt_ratio)
			+ (run.wrong_votes or 0) * cfg.ledger_debt_wrong
		if ending.id == "clean_cut" then
			burned = math.floor(burned * 0.5) -- the clean cut halves the chain
		end
		l.debt = math.min(cfg.ledger_debt_cap, l.debt + burned)
	end

	run.ledger_result = {
		ending = ending,
		flags = flags,
		score = sc,
	}
	strand.save_persisted(strand.persisted)
	return run.ledger_result
end

-- ---------------------------------------------------------------
-- Start-of-run debt pressure.  Called from start_run after the
-- mutation is applied, so every later run feels every earlier loss:
--   * horde grows by debt * 0.2   (debt 50 -> +10 scale)
--   * starting Trust thins by 1 per 10 debt, capped at 3
-- ---------------------------------------------------------------
function strand.apply_debt(run)
	local d = strand.ledger().debt
	run.debt = d
	run.debt_horde = 0
	run.debt_trust = 0
	if d <= 0 then return run.debt end
	run.debt_horde = math.floor(d * strand.config.ledger_debt_horde)
	run.debt_trust = math.min(3, math.floor(d / 10))
	if run.debt_trust > 0 then
		run.trust = math.max(1, run.trust - run.debt_trust)
	end
	return run.debt
end

-- ---------------------------------------------------------------
-- Human-readable settlement for the result screen / console.
-- ---------------------------------------------------------------
function strand.describe_settlement(res)
	if not res then return "" end
	local lines = {
		res.ending.title .. " — " .. res.ending.desc,
	}
	if #res.flags > 0 then
		lines[1] = lines[1] .. "  [" .. table.concat(res.flags, ", ") .. "]"
	end
	local b = res.score
	lines[#lines + 1] = string.format(
		"Score %d  (nights %d · purges %d · trust %d · integrity %d · wrong %d%s%s)",
		b.total, b.nights, b.purges, b.trust, b.integrity, b.wrong,
		b.flawless > 0 and (" · flawless +" .. b.flawless) or "",
		b.deception > 0 and (" · deception +" .. b.deception) or "")
	local l = strand.ledger_summary()
	lines[#lines + 1] = string.format(
		"Chain: %d pts · debt %d · %d runs (%d wins) · %d phantoms",
		l.score, l.debt, l.runs, l.wins, l.phantom_bosses)
	return table.concat(lines, "\n")
end
