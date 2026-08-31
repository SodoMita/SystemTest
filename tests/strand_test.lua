-- ================================================================
-- tests/strand_test.lua
-- Headless smoke test for the Simulacrum Strand singleplayer mode
-- (mods/game/sl_strand).  Exercises the deduction Core that the council
-- agreed must be a real, provable machine:
--   * mod load path
--   * seeded Echo roll (crew + the PLAYER-as-Echo systemic lie)
--   * Trust Meter spend (read_tell / confide / observe)
--   * suspicion graph + tell readout
--   * vote resolution (correct purge, wrongful exile, partial truth)
--   * permadeath -> phantom-boss ledger persistence
--   * night wave / socket defense / Al Dente Core breach
--   * full scripted victory and defeat loops
--   * Chain Ledger: score earn rule, debt burn/paydown, named endings,
--     flag combos, and the HOLLOW CROWN corruption win
--
-- Run from the repo root:  luajit tests/strand_test.lua
-- (LuaJIT 2.1, as CI uses.  Also runs under lua5.1.)
-- ================================================================

local H = dofile("tests/minetest_stub.lua")

local pass_count, fail_count = 0, 0
local function check(cond, label)
	if cond then
		pass_count = pass_count + 1
		print("  [PASS] " .. label)
	else
		fail_count = fail_count + 1
		print("  [FAIL] " .. label)
	end
end

local function section(title)
	print("== " .. title)
end

section("PHASE 1 — mod load path")
H.current_modname = "sl_strand"
local ok, err = pcall(dofile, "mods/game/sl_strand/strand_state.lua")
check(ok, "strand_state.lua loads" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then print("FATAL: strand_state failed to load; aborting."); os.exit(1) end

local load_ok = true
for _, f in ipairs({ "strand_trust", "strand_vote", "strand_wave", "strand_core", "strand_ledger" }) do
	local o, e = pcall(dofile, "mods/game/sl_strand/" .. f .. ".lua")
	if not o then load_ok = false; print("  [FAIL] " .. f .. ".lua -> " .. tostring(e)) end
end
check(load_ok, "strand_trust/vote/wave/core load")

-- Config sanity
check(type(strand.config) == "table", "strand.config exists")
check(strand.config.crew_size == 5, "default crew size is 5")

section("PHASE 2 — seeded run + Echo roll")
local seed = 12345
local run = strand.start_run(seed)
check(type(run) == "table" and run.active, "start_run returns an active run")
check(#run.crew_names == 5, "crew has 5 names")
check(run.core.target >= 1, "core target set")
check(run.echo_identity ~= nil, "an Echo was rolled")
local is_crew_echo = false
for _, n in ipairs(run.crew_names) do if n == run.echo_identity then is_crew_echo = true end end
check(is_crew_echo or run.echo_identity == strand.ECHO_PLAYER_NAME,
	"Echo is a crew-bot OR the player")

-- Determinism: the same seed reproduces the same Echo.
local run2 = strand.start_run(seed)
check(run2.echo_identity == run.echo_identity and run2.player_is_echo == run.player_is_echo,
	"same seed -> same Echo (deterministic)")
check(run.mutation ~= nil and run.mutation.id ~= nil, "a mutation was rolled")

section("PHASE 3 — PLAYER-is-Echo systemic lie")
-- Scan seeds to find a run where the player is secretly the Echo.
local player_echo_seed, player_echo_run
for s = 1, 400 do
	local r = strand.start_run(s)
	if r.player_is_echo then
		player_echo_seed = s
		player_echo_run = r
		break
	end
end
check(player_echo_seed ~= nil, "found a seed that casts the player as the Echo")
if player_echo_run then
	check(player_echo_run.echo_identity == strand.ECHO_PLAYER_NAME,
		"player-Echo run: identity is the player sentinel")
	local ok_reveal, choices = strand.reveal_player_is_echo(player_echo_run)
	check(ok_reveal == true and player_echo_run.player_has_learned, "player reveals the systemic lie")
	check(type(choices) == "table" and choices.survive and choices.give_up, "reveal surfaces the two forks")
	-- Barnaby fork: give up ends the run as a non-win, no new phantom.
	local g_before = strand.phantom_boss_count()
	player_echo_run.player_choice = "give_up"
	local res = strand.resolve_vote(player_echo_run, strand.ECHO_PLAYER_NAME)
	check(res.outcome == "surrender", "give_up -> surrender ending")
	check(strand.phantom_boss_count() == g_before, "surrender records no phantom boss")
end

section("PHASE 4 — Trust Meter spend")
local t = strand.start_run(757)
local crew_bot = t.crew[1]
local start_trust = t.trust
local read, secret = strand.turn(t, { type = "read_tell", bot = crew_bot.name, target = t.crew[2].name })
check(type(read) == "string", "read_tell returns a readout")
check(t.trust == start_trust - 1, "read_tell spends 1 trust")

local st2 = t.trust
local okc, rc = strand.turn(t, { type = "confide", bot = crew_bot.name })
check(type(okc) == "number", "confide returns the new trust (a number)")
check(t.trust == st2 - 1, "confide spends 1 trust")

local okb, _ = strand.turn(t, { type = "observe", bot = crew_bot.name, target = t.crew[3].name })
check(okb == true, "observe records observation")

section("PHASE 5 — socket defense + horde scale")
local w = strand.start_run(999)
strand.turn(w, { type = "build", socket = "socket_1", kind = "turret" })
strand.turn(w, { type = "build", socket = "socket_2", kind = "turret" })
strand.turn(w, { type = "build", socket = "socket_3", kind = "barricade" })
local def = strand.effective_defense(w)
check(def >= 26, "three built sockets yield substantial defense (" .. def .. ")")

locper = nil
local bad, bmsg = strand.build_socket(w, "socket_1", "mystery")
check(bad == false, "unknown defense type rejected")

-- Wrongful exiles cost defense.
w.wrong_votes = 3
check(strand.effective_defense(w) == math.max(0, def - 12), "wrongful exiles subtract defense uptime")

check(strand.horde_scale(w) >= 4, "horde scale is at least the base")

section("PHASE 6 — vote resolution (correct purge)")
local v_run
for s = 1, 400 do
	local r = strand.start_run(s)
	if not r.player_is_echo then v_run = r; break end
end
check(v_run ~= nil, "found a run where the player is not the Echo")
if v_run then
	local echo_name = v_run.echo_identity
	check(echo_name ~= strand.ECHO_PLAYER_NAME, "Echo is a crew-bot")
	local pb_before = strand.phantom_boss_count()
	local res = strand.resolve_vote(v_run, echo_name)
	check(res.outcome == "correct", "correct exile resolves as 'correct'")
	check(v_run.echo_identity == nil, "correct exile purges the Echo")
	check(strand.phantom_boss_count() == pb_before + 1, "exiled Echo becomes a phantom boss")
	local exiled = false
	for _, b in ipairs(v_run.crew) do if b.name == echo_name and not b.alive then exiled = true end end
	check(exiled, "exiled crew-bot is marked dead")
end

section("PHASE 7 — vote resolution (wrongful exile)")
local wrong_run
for s = 1, 400 do
	local r = strand.start_run(s)
	if not r.player_is_echo then wrong_run = r; break end
end
if wrong_run then
	local innocent = nil
	for _, b in ipairs(wrong_run.crew) do
		if b.name ~= wrong_run.echo_identity then innocent = b.name; break end
	end
	local pb_before = strand.phantom_boss_count()
	local before_votes = wrong_run.wrong_votes
	local res = strand.resolve_vote(wrong_run, innocent)
	check(res.outcome == "wrong", "wrongful exile resolves as 'wrong'")
	check(wrong_run.wrong_votes == before_votes + 1, "wrongful exile increments wrong_votes")
	check(strand.phantom_boss_count() == pb_before + 1, "wronged crew also seeds a phantom")
	check(wrong_run.voice_note ~= nil, "a dread note is set on wrong exile")
end

section("PHASE 8 — partial truth is never certainty")
local pr = strand.start_run(4242)
local eval = strand.vote_evaluation(pr, pr.echo_identity)
check(eval.certain <= eval.total, "partial truth caps the 'certain' block below a verdict")
check(type(eval.lean) == "string", "evaluation carries a lean (suspected/mixed/cleared)")
check(strand.describe_evaluation(eval):find("of %d crew") ~= nil, "evaluation is human-readable")

section("PHASE 9 — night wave / core breach")
local nw = strand.start_run(31337)
-- No defense built -> a large wave breaches the Core.
nw.core.integrity = 10
local wave = strand.resolve_wave(nw)
check(wave.scale > 0, "horde is non-empty")
check(wave.survived == false or wave.defense >= wave.scale, "wave resolves to survived or breach")
-- A breach with low integrity should eventually defeat.
local doomed = strand.start_run(31337)
doomed.core.integrity = 1
doomed.sockets = { { name = "socket_1", built = nil }, { name = "socket_2", built = nil }, { name = "socket_3", built = nil } }
local dw = strand.resolve_wave(doomed)
check(dw.integrity <= 0 or doomed.phase == "defeat", "core breach leads toward defeat")

section("PHASE 10 — scripted VICTORY loop")
local v = strand.start_run(8888)
local target = v.core.target
local vwins = false
for i = 1, target do
	-- build full turret suite
	for s = 1, 3 do
		strand.build_socket(v, "socket_" .. s, "turret")
	end
	-- advance build -> watch -> vote without an exile (skip vote)
	local ph = strand.advance_phase(v) -- build->watch
	ph = strand.advance_phase(v)       -- watch->vote
	-- hold the vote / cast on the Echo if it is a crew-bot (we can know
	-- because in this loop we are testing a clean crew victory)
	local res = strand.resolve_vote(v, v.echo_identity)
	-- resolve_vote sets phase to wave; run the wave and advance
	local rw = strand.resolve_wave(v)
	v.night = v.night + 1
	if v.core.integrity <= 0 then vwins = false; break end
	ph = strand.advance_phase(v)       -- resolving->build (or victory)
	if v.phase == "victory" then vwins = true; break end
	-- survive to next night edge case: ensure integrity is positive
end
check(vwins and v.phase == "victory", "cleaned run reaches victory after surviving the nights")

section("PHASE 11 — persistence round-trip")
local pb0 = strand.phantom_boss_count()
strand.record_phantom_boss({ name = "Test-Phantom", seed = 1, night = 2, score = 3 })
check(strand.phantom_boss_count() == pb0 + 1, "phantom-boss count increments")
-- reload from storage (module-level reload path)
strand.persisted = nil
strand._storage = nil
strand.persisted = strand.load_persisted()
check(strand.phantom_boss_count() == pb0 + 1, "phantom boss persists across a storage reload")

section("PHASE 12 — Chain Ledger (score, debt, endings)")

-- 12.1  The earn rule, pure and deterministic.
local lr = strand.start_run(777)
lr.night = 3; lr.correct_purges = 1; lr.wrong_votes = 0; lr.trust = 5
lr.phase = "victory"; lr.victory_reason = "core-complete"; lr.core.integrity = 60
local sc = strand.score_run(lr)
check(sc.nights == 30 and sc.purges == 40 and sc.trust == 10 and sc.wrong == 0,
	"score_run: nights/purges/trust earn rule")
check(sc.integrity == 30, "score_run: integrity banks on victory (60 * 0.5)")
check(sc.flawless == 30, "score_run: flawless bonus for zero wrongful exiles")
check(sc.deception == 0, "score_run: no deception bonus on an honest victory")
check(sc.total == 30 + 40 + 10 + 30 + 30, "score_run: total is the sum of the breakdown")

-- 12.2  The deception bonus belongs to the HOLLOW CROWN only.
lr.victory_reason = "corruption"
local sc2 = strand.score_run(lr)
check(sc2.deception == 50 and sc2.total == sc.total + 50,
	"score_run: HOLLOW CROWN banks the deception bonus")

-- 12.3  Ending mapping is deterministic per terminal state.
local function ending_id_of(r)
	local e = strand.ending_for(r)
	return e.id
end
local dr = { phase = "defeat", wrong_votes = 1, player_is_echo = false,
	phantom_bosses_this_run = {}, core = { target = 7 } }
dr.defeat_reason = "core-breach";       check(ending_id_of(dr) == "static",      "ending: core-breach -> STATIC")
dr.defeat_reason = "overrun";           check(ending_id_of(dr) == "overrun",     "ending: overrun -> OVERRUN")
dr.defeat_reason = "echo-exiled";       check(ending_id_of(dr) == "deleted",     "ending: echo-exiled -> DELETED")
dr.defeat_reason = "wrongfully-exiled"; check(ending_id_of(dr) == "witch_trial", "ending: wrongfully-exiled -> WITCH TRIAL")
dr.defeat_reason = "self-surrender";    check(ending_id_of(dr) == "clean_cut",   "ending: self-surrender -> CLEAN CUT")
local vr = { phase = "victory", victory_reason = "core-complete", wrong_votes = 0,
	player_is_echo = false, phantom_bosses_this_run = {} }
check(ending_id_of(vr) == "ascent", "ending: crew victory -> AL DENTE ASCENT")
vr.victory_reason = "corruption"; vr.player_is_echo = true
check(ending_id_of(vr) == "hollow_crown", "ending: corruption win -> HOLLOW CROWN")
local e_vr, f_vr = strand.ending_for(vr)
local has_flawless = false
for _, f in ipairs(f_vr) do if f == "flawless" then has_flawless = true end end
check(has_flawless and #f_vr == 2, "ending: flags layer on (flawless + hollow)")

-- 12.4  A victory settles: score banks, debt is paid down.
local L1 = strand.ledger_summary()
local sv = strand.start_run(7001)
sv.night = 7; sv.correct_purges = 1; sv.wrong_votes = 0; sv.trust = 6
sv.core.integrity = 80
strand.run_victory(sv, "core-complete")
local L2 = strand.ledger_summary()
check(sv.ledger_result.score.total == 192, "settle: victory score is the earn rule (192)")
check(L2.score == L1.score + 192, "settle: victory banks its score in the ledger")
check(L2.runs == L1.runs + 1 and L2.wins == L1.wins + 1, "settle: victory counts a run and a win")
check(L2.debt == math.max(0, L1.debt - math.floor(192 * 0.5)),
	"settle: victory pays half its score against debt")
check(L2.endings["ascent"] == (L1.endings["ascent"] or 0) + 1, "settle: ASCENT ending recorded")

-- 12.5  A defeat burns unearned potential into debt.
local L3 = strand.ledger_summary()
local sd = strand.start_run(7002)
sd.core.target = 7; sd.night = 2; sd.wrong_votes = 1
strand.run_defeat(sd, "core-breach")
local L4 = strand.ledger_summary()
check(L4.debt == math.min(60, L3.debt + 30),
	"settle: defeat burns remaining potential + wrongful exiles into debt")
check(L4.endings["static"] == (L3.endings["static"] or 0) + 1, "settle: STATIC ending recorded")

-- 12.6  The clean cut halves the burn.
local L5 = strand.ledger_summary()
local ss = strand.start_run(7003)
ss.player_is_echo = true; ss.player_has_learned = true
ss.player_choice = "give_up"; ss._surrender = true
strand.run_defeat(ss, "self-surrender")
local L6 = strand.ledger_summary()
check(L6.debt == math.min(60, L5.debt + 17), "settle: CLEAN CUT burns at half rate (17, not 35)")

-- 12.7  Debt presses on the next run: horde and trust.
strand.ledger().debt = 40 -- deterministic dial-in
local dn = strand.start_run(7004)
check(dn.debt == 40, "debt carries into the next run")
check(dn.debt_horde == 8, "debt thickens the horde (40 * 0.2)")
check(dn.debt_trust == 3, "debt thins starting trust (1 per 10, capped at 3)")
check(dn.trust == 1, "starting trust after debt pressure is 1")
check(strand.horde_scale(dn) >= 4 + 8, "horde scale includes debt pressure")

-- 12.8  The corruption win, end to end: a surviving Echo fells the Core.
local ce
for s = 5000, 5400 do
	local r = strand.start_run(s)
	if r.player_is_echo then ce = r; break end
end
check(ce ~= nil, "corruption test: found a player-Echo seed")
if ce then
	strand.reveal_player_is_echo(ce)
	ce.player_choice = "survive"
	ce.core.integrity = 1
	ce.sockets = { { name = "socket_1", built = nil },
		{ name = "socket_2", built = nil },
		{ name = "socket_3", built = nil } }
	local wv = strand.resolve_wave(ce)
	check(wv.outcome == "corruption", "corruption win: breach with a surviving Echo resolves as corruption")
	check(ce.phase == "victory" and ce.victory_reason == "corruption",
		"corruption win: run closes as a corruption victory")
	check(strand.ending_for(ce).id == "hollow_crown", "corruption win: ending is HOLLOW CROWN")
	check(ce.ledger_result ~= nil and ce.ledger_result.score.deception == 50,
		"corruption win: deception bonus banked")
end

-- 12.9  The ledger survives a storage reload (the chain is the save file).
local before = strand.ledger_summary()
strand.persisted = nil
strand._storage = nil
strand.persisted = strand.load_persisted()
local after = strand.ledger_summary()
check(after.score == before.score and after.debt == before.debt,
	"ledger survives a storage reload")
check(after.runs == before.runs and (after.endings["ascent"] or 0) == (before.endings["ascent"] or 0),
	"ledger endings survive a storage reload")

-- 12.10  run_summary and describe_settlement surface the economy.
local sum = strand.run_summary(sv)
check(sum.ending == "ascent" and sum.ending_title == "AL DENTE ASCENT",
	"run_summary names the ending")
check(sum.score == 192 and sum.ledger ~= nil, "run_summary carries score and ledger")
local ds = strand.describe_settlement(sv.ledger_result)
check(type(ds) == "string" and ds:find("AL DENTE ASCENT") ~= nil and ds:find("Chain:") ~= nil,
	"describe_settlement is human-readable")
check(strand.run_victory(sv) == true and sv._settled == true,
	"settlement is idempotent (a second settle does not double-count)")
local L7 = strand.ledger_summary()
check(L7.score == before.score and L7.runs == before.runs and L7.debt == before.debt,
	"re-settle left the ledger untouched")

print("== RESULT: " .. pass_count .. " passed, " .. fail_count .. " failed")
if fail_count > 0 then os.exit(1) end
os.exit(0)
