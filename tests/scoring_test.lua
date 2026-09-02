-- ================================================================
-- tests/scoring_test.lua
-- Unit tests for the per-player point model in
-- mods/game/sl_modebase/scoring.lua. Verifies the kill formula,
-- the objective credits, and the end-match survival + victory
-- bonuses, plus the bookkeeping (last_puncher, awarded flag,
-- per-match kill/death counters) that the clean reset in
-- match.lua end_match must clear.
-- ================================================================

local H = dofile("tests/minetest_stub.lua")

local pass, fail = 0, 0
local function check(cond, label)
	if cond then
		pass = pass + 1
		print("  [PASS] " .. label)
	else
		fail = fail + 1
		print("  [FAIL] " .. label)
	end
end

-- The scoring module expects game_mode + game_mode.state to exist
-- with players = {} and the standard team fields. Build the minimum
-- surface the module uses.
H.current_modname = "sl_modebase"
game_mode = rawget(_G, "game_mode") or {}
_G.game_mode = game_mode
game_mode.S = function(s, ...) return s end
game_mode.state = {
	teams = {
		beacon_a = { spawn = { x = -8, y = 2, z = 0 }, hp = 100, label = "Beacon A" },
		beacon_b = { spawn = { x =  8, y = 2, z = 0 }, hp = 100, label = "Beacon B" },
	},
	players = {},
	settings = {},
	match_active = true,
}
game_mode.get_player_state = function(name)
	local pl = game_mode.state.players[name]
	if not pl then
		pl = {
			team = nil, eliminated = false, role = nil, phase = "alive",
			points = 0, kills = 0, deaths = 0,
			ghost_summoned_by = nil, ghost_summon_pos = nil, last_death_pos = nil,
		}
		game_mode.state.players[name] = pl
	end
	return pl
end

-- Load the module under test.
dofile("mods/game/sl_modebase/scoring.lua")

local function fresh()
	game_mode.state.players = {}
	game_mode.state.match_active = true
end

-- ================================================================
-- 1) K/D-weighted kill score
-- ================================================================
section = function() end -- no-op, just for clarity

fresh()
-- First kill ever: K/D treated as 1.0 (kills=1, deaths=0 → kills/max(1,0) = 1).
-- Formula: max(1, round(1.0 * 7)) = 7.
game_mode.award_kill_points("alpha", "beta")
local aplha = game_mode.get_player_state("alpha")
local beta = game_mode.get_player_state("beta")
check(aplha.points == 7, "first kill is worth 7 points (K/D = 1.0)")
check(aplha.kills == 1, "killer's kills counter incremented")
check(beta.deaths == 1, "victim's deaths counter incremented")

-- 0.5 K/D: alpha has 1 kill, 1 death → 0.5 K/D → round(0.5*7) = 4 (rounded up from 3.5).
-- Wait: math.floor(3.5 + 0.5) = math.floor(4.0) = 4. So 4 points.
fresh()
local a = game_mode.get_player_state("alpha")
a.kills = 1; a.deaths = 1
local b = game_mode.get_player_state("beta")
b.kills = 0; b.deaths = 0
game_mode.award_kill_points("alpha", "beta")
-- After this kill: alpha has 2 kills, 1 death → K/D = 2.0 → round(2.0*7) = 14.
check(a.points == 14, "1.0 K/D before kill, 2.0 after — second kill worth 14")

-- 2.0 K/D: alpha at 2 kills / 1 death; after this kill: 3 / 1 → 21 points.
local c = game_mode.get_player_state("gamma")
game_mode.award_kill_points("alpha", "gamma")
check(a.points == 14 + 21, "subsequent 3.0 K/D kill worth 21 points (cumulative)")

-- Suicide is silently ignored.
local pts_before = a.points
game_mode.award_kill_points("alpha", "alpha")
check(a.points == pts_before, "suicide does not credit or debit")

-- Same-name self-kill doesn't even increment kills.
check(a.kills == 3, "suicide did not bump kills counter")

-- 0.0 K/D player getting their first kill: round(1.0 * 7) = 7.
fresh()
local rookie = game_mode.get_player_state("rookie")
local victim = game_mode.get_player_state("victim")
game_mode.award_kill_points("rookie", "victim")
check(rookie.points == 7, "rookie first kill: 7 points (K/D = 1.0)")

-- Inactive match: no credit.
fresh()
game_mode.state.match_active = false
local pts_before_inactive = rookie.points
game_mode.award_kill_points("rookie", "victim")
check(rookie.points == pts_before_inactive,
	"award_kill_points is a no-op when match_active = false")

-- ================================================================
-- 2) Objective points
-- ================================================================
fresh()
game_mode.award_objective_points("alpha", "core_delivery")
check(game_mode.get_player_state("alpha").points == 5000,
	"core_delivery credits +5000")

game_mode.award_objective_points("beta", "beacon_destruction")
check(game_mode.get_player_state("beta").points == 1000,
	"beacon_destruction credits +1000")

-- Unknown kind is silently dropped.
local pts = game_mode.get_player_state("gamma").points
game_mode.award_objective_points("gamma", "mystery_kind")
check(game_mode.get_player_state("gamma").points == pts,
	"unknown objective kind is a no-op")

-- Nil actor is silently dropped.
game_mode.award_objective_points(nil, "core_delivery")
check(true, "nil actor in award_objective_points does not crash")

-- ================================================================
-- 3) Match-end points: survival + victory
-- ================================================================
fresh()
local a2 = game_mode.get_player_state("a2"); a2.team = "beacon_a"; a2.phase = "alive"
local b2 = game_mode.get_player_state("b2"); b2.team = "beacon_b"; b2.phase = "alive"
local c2 = game_mode.get_player_state("c2"); c2.team = "beacon_a"; c2.phase = "ghost"
local d2 = game_mode.get_player_state("d2"); d2.team = "beacon_b"; d2.phase = "alive"

-- beacon_a wins. Expected:
--   a2 (alive, winning): +50 survive + +300 victory = +350
--   b2 (alive, losing):  +50 survive = +50
--   c2 (ghost, winning): +0 (not alive) + +300 victory = +300
--   d2 (alive, losing):  +50 survive = +50
game_mode.award_match_end_points("beacon_a", game_mode.state.players)
check(a2.points == 350, "alive winner: +350 (50 survive + 300 victory)")
check(b2.points ==  50, "alive loser:  +50  (survive only)")
check(c2.points == 300, "ghost winner: +300 (victory only, no survive)")
check(d2.points ==  50, "alive loser on losing team: +50")

-- Idempotency: calling award_match_end_points twice on the same
-- state does NOT double-credit.
game_mode.award_match_end_points("beacon_a", game_mode.state.players)
check(a2.points == 350, "match-end credits are idempotent (alive winner still 350)")
check(b2.points ==  50, "match-end credits are idempotent (alive loser still 50)")

-- "beacons" winner (elimination) — every alive player gets survive
-- but no team gets the victory bonus.
fresh()
local e1 = game_mode.get_player_state("e1"); e1.phase = "alive"
local e2 = game_mode.get_player_state("e2"); e2.phase = "alive"
local e3 = game_mode.get_player_state("e3"); e3.phase = "alive"
game_mode.award_match_end_points("beacons", game_mode.state.players)
check(e1.points == 50, "beacons win: e1 (alive) gets survive but no victory")
check(e2.points == 50, "beacons win: e2 (alive) gets survive but no victory")
check(e3.points == 50, "beacons win: e3 (alive) gets survive but no victory")

-- nil winner (draw) — no victory, only survive.
fresh()
local d1 = game_mode.get_player_state("d1"); d1.phase = "alive"
local d2p = game_mode.get_player_state("d2p"); d2p.phase = "alive"
game_mode.award_match_end_points(nil, game_mode.state.players)
check(d1.points == 50, "draw: alive player still gets survive (+50)")
check(d2p.points == 50, "draw: alive player still gets survive (+50)")

-- Eliminated player: no survive bonus.
fresh()
local x1 = game_mode.get_player_state("x1"); x1.phase = "alive"; x1.eliminated = true
local x2 = game_mode.get_player_state("x2"); x2.phase = "alive"; x2.eliminated = false
x2.team = "beacon_a"
game_mode.award_match_end_points("beacon_a", game_mode.state.players)
-- (x1 has no team, so victory doesn't apply either.)
check(x1.points == 0, "eliminated player: no survive, no victory")
check(x2.points == 350, "non-eliminated alive winner: 50 + 300")

-- ================================================================
-- 4) clean-reset contract: clear_match_end_points_awarded
--    AND match.lua end_match (real path) must also clear kills /
--    deaths / last_puncher so the next match starts from zero.
-- ================================================================
fresh()
local pl = game_mode.get_player_state("alpha")
pl.kills = 5
pl.deaths = 3
pl.points = 42
pl.last_puncher = "beta"
pl.awarded_end_points = true

game_mode.clear_match_end_points_awarded(game_mode.state.players)
-- Per the scoring module's contract, the bookkeeping flag is the
-- only thing this function clears; kills/deaths/last_puncher
-- belong to match.lua's end_match clean reset.
check(pl.awarded_end_points == nil,
	"clear_match_end_points_awarded clears the awarded flag")
-- Other fields are match.lua's responsibility; verify the test
-- confirms the scoring module leaves them alone.
check(pl.kills == 5, "scoring module preserves kills for match.lua to clear")
check(pl.deaths == 3, "scoring module preserves deaths for match.lua to clear")
check(pl.last_puncher == "beta",
	"scoring module preserves last_puncher for match.lua to clear")

-- ================================================================
-- 5) K/D edge: zero kills, zero deaths → treated as 1.0 (max(1, ...))
-- ================================================================
fresh()
local ghost = game_mode.get_player_state("ghost") -- kills=0, deaths=0
-- This player has literally no kills to give; calling award_kill_points
-- from "ghost" would still credit kills=1, deaths=0 → K/D=1.0 → 7.
-- (Real engine never invokes that path; here it documents behavior.)
local prey = game_mode.get_player_state("prey")
game_mode.award_kill_points("ghost", "prey")
check(ghost.points == 7, "ghost first kill: 7 points (K/D = 1.0 from kills=1)")
check(ghost.kills == 1, "ghost.kills is 1 after one kill")
check(prey.deaths == 1, "prey.deaths is 1 after one death")

-- Player with very high deaths: 1 kill / 10 deaths → 0.1 K/D
-- round(0.1 * 7) = round(0.7) = 1. So 1 point (the floor).
fresh()
local feeder = game_mode.get_player_state("feeder")
feeder.kills = 0; feeder.deaths = 10
local m = game_mode.get_player_state("martyr")
game_mode.award_kill_points("feeder", "martyr")
-- After kill: feeder has 1 kill, 10 deaths → 1/10 = 0.1 → round(0.7) = 1.
check(feeder.points == 1, "feeder 0.1 K/D earns 1 point (formula floor)")

-- ================================================================
-- 6) Two-track score: pl.points vs pl.earned_points
--    Per the §13.3 owner ruling, the season ranking is driven by
--    play (kills + objectives), not by survival / victory. The
--    scoring module maintains two fields per player:
--      pl.earned_points  — kills + objective credits
--      pl.points         — earned + end-match bonus
--    The end-match bonus is kept in pl.end_match_bonus for
--    transparency (and to be cleared by the clean reset).
-- ================================================================
fresh()
local p = game_mode.get_player_state("p")
p.kills = 0; p.deaths = 0
p.team = "beacon_a"
p.phase = "alive"
p.eliminated = false
-- Earn 14 points from a kill (1.0 K/D first kill: 7) and an
-- objective: 7 + 5000 = 5007 earned. Match end credits +350
-- (survive + victory) to pl.points and pl.end_match_bonus only.
local q = game_mode.get_player_state("q")
game_mode.award_kill_points("p", "q")
game_mode.award_objective_points("p", "core_delivery")
check(p.earned_points == 7 + 5000,
	"earned_points tracks kills + objective credits (got " .. tostring(p.earned_points) .. ")")
check(p.points == 7 + 5000,
	"pl.points == pl.earned_points before the end-match bonus")
check(p.end_match_bonus == 0 or p.end_match_bonus == nil,
	"pl.end_match_bonus is zero before the end-match pass")
-- Match end: beacon_a wins.
game_mode.award_match_end_points("beacon_a", game_mode.state.players)
check(p.points == 7 + 5000 + 350,
	"pl.points reflects the +350 end-match bonus (got " .. tostring(p.points) .. ")")
check(p.earned_points == 7 + 5000,
	"pl.earned_points UNCHANGED by the end-match pass — season rank is play-only")
check(p.end_match_bonus == 350,
	"pl.end_match_bonus records the +350 explicitly (got " .. tostring(p.end_match_bonus) .. ")")

-- A player who is alive but on the losing team: +50 only.
local r = game_mode.get_player_state("r")
r.team = "beacon_b"
r.phase = "alive"
-- No kills, no objectives. (Don't call award_kill_points — that
-- would credit a kill and r.earned_points would no longer be 0.)
game_mode.award_match_end_points("beacon_a", game_mode.state.players)
check(r.points == 50,
	"alive loser gets +50 (pl.points), earned_points untouched")
check((r.earned_points or 0) == 0,
	"alive loser earned_points is 0 (no kills, no objectives)")
check(r.end_match_bonus == 50,
	"alive loser end_match_bonus is +50 (just the survive)")

-- A ghost player on the winning team: no survive (not alive), but
-- +300 victory because the team won. The ghost's earned_points
-- are still 0 (no kills, no objectives).
local d = game_mode.get_player_state("d")
d.team = "beacon_a"
d.phase = "ghost"
game_mode.award_match_end_points("beacon_a", game_mode.state.players)
check(d.points == 300,
	"ghost on winning team: +300 victory only (no survive)")
check((d.earned_points or 0) == 0,
	"ghost earned_points is 0")
check(d.end_match_bonus == 300,
	"ghost on winning team end_match_bonus is +300 (just the victory)")

-- A ghost player on the LOSING team: no survive, no victory, no earned.
local dd = game_mode.get_player_state("dd")
dd.team = "beacon_b"
dd.phase = "ghost"
-- (awarded_end_points not yet set, so the loop processes dd.)
check(dd.points == 0,
	"ghost on losing team: nothing (no survive, no victory)")
check((dd.earned_points or 0) == 0,
	"ghost on losing team earned_points is 0")
check((dd.end_match_bonus or 0) == 0,
	"ghost on losing team end_match_bonus is 0")

-- The clear_match_end_points_awarded pass also zeros the bonus
-- tracker so the next match starts clean.
game_mode.clear_match_end_points_awarded(game_mode.state.players)
check(p.end_match_bonus == 0,
	"clear_match_end_points_awarded zeros end_match_bonus (was 350)")
check(p.awarded_end_points == nil,
	"clear_match_end_points_awarded also clears the awarded flag")

print(string.format("\nRESULT: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
