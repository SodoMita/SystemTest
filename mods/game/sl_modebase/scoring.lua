-- ================================================================
-- sl_modebase/scoring.lua — per-player match score model.
--
-- Source of truth for the value of an action. Anything in the game
-- that credits or debits pl.points goes through one of these three
-- entry points:
--
--   game_mode.award_kill_points(killer, victim)
--     Called at the moment a kill is confirmed. Killer's score goes
--     up by max(1, round(K/D × 7)) where K/D is the killer's
--     current match K/D ratio (>= 1 kill, >= 1 death; this is the
--     MT-CTF formula, minus the flag-carrier multiplier which is
--     a flag-specific mechanic that doesn't apply here). A
--     consistent 1.0 K/D player earns 7 per kill; a 0.5 K/D earns
--     4; a 2.0 K/D earns 14. Suicide (killer == victim) is
--     silently ignored.
--
--   game_mode.award_objective_points(actor, kind)
--     Called at the moment an objective is completed. "core_delivery"
--     is worth +5000, "beacon_destruction" is worth +1000. These
--     dwarf the kill reward on purpose — a match that ends on a
--     single objective is the team's reward, not the killer's.
--
--   game_mode.award_match_end_points(winner, players_state)
--     Called from end_match right before the clean reset. Each
--     player gets:
--       +50  if they survived (not eliminated, not a ghost)
--       +300 if they are on the winning team
--     A living winner ends with +350 from this; a dead winner
--     +300; a living loser +50; a dead loser 0.
--
-- Two score fields are maintained per player:
--
--   pl.earned_points  — kills + objective completions only.
--                       This is what the tournament season
--                       score is banked from, so the season
--                       ranking reflects PLAY (kills +
--                       objectives) and not the act of having
--                       survived / won. Per the §13.3 owner
--                       ruling: "Points come primarily from
--                       killing crew. Essence is not a score."
--                       A separate "survive / win" line on
--                       the per-match result screen still
--                       rewards showing up, but it does not
--                       bleed into the season score.
--
--   pl.points         — the total shown on the result screen.
--                       earned_points + end_match_bonus
--                       (survival + victory). Reading this
--                       field for end-of-match display is
--                       always correct; reading this field
--                       for season banking is no longer
--                       correct (use earned_points instead).
--
--   pl.end_match_bonus — survival + victory total (0 for a
--                       player who didn't survive and isn't
--                       on the winning team). Kept on the
--                       state so the clean reset can roll
--                       it back to 0 between matches without
--                       losing the per-match result-screen
--                       value mid-flight.
--
-- All credits land in state.players[name].points (and the two
-- companions). pl.points is read by the result screen,
-- pl.earned_points by the tournament banking block, pl.kills /
-- pl.deaths / pl.awarded_end_points are reset by the clean
-- reset in match.lua. The three point-tracking fields are also
-- reset by the clean reset.
-- ================================================================

local S = game_mode.S
local state = game_mode.state

local POINTS_PER_CORE_DELIVERY    = 5000
local POINTS_PER_BEACON_DESTRUCTION = 1000
local POINTS_PER_SURVIVE          = 50
local POINTS_PER_VICTORY          = 300

local function get_or_zero(name)
	-- Use the canonical get_player_state: it lazy-creates an entry
	-- if the caller (a real player who just joined, a bot that was
	-- just spawned by aaa_botmatch, or a fresh name) isn't yet in
	-- the players table. Without this, the very first kill of a
	-- brand-new player would silently no-op because state.players[name]
	-- would still be nil.
	local pl = game_mode.get_player_state and game_mode.get_player_state(name) or state.players[name]
	if not pl then return nil end
	if pl.points == nil then pl.points = 0 end
	if pl.earned_points == nil then pl.earned_points = 0 end
	if pl.end_match_bonus == nil then pl.end_match_bonus = 0 end
	return pl
end

-- MT-CTF kill score: max(1, round(K/D × 7)). The K/D denominator
-- uses 1 instead of 0 so the first kill is always worth at least
-- the base (7 for a 1.0 K/D player, 7 for a 0.0 K/D player
-- because kills=1, deaths=0 → K/D treated as 1). After at least
-- one death the formula settles into the player's true K/D.
local function calculate_kill_score(killer_pl)
	local kills = killer_pl.kills or 0
	local deaths = killer_pl.deaths or 0
	local kd = kills / math.max(1, deaths)
	return math.max(1, math.floor(kd * 7 + 0.5))
end

-- Award kill points to a confirmed killer. Silently no-ops if either
-- side is missing, if it's a suicide, or if the match is not active.
-- Records the per-player kill/death counters used by the K/D
-- weighting so a player's kill value reflects their real match
-- performance, not whatever the score was at the time of the
-- previous kill.
function game_mode.award_kill_points(killer_name, victim_name)
	if not state.match_active then return end
	if not killer_name or killer_name == victim_name then return end
	local kpl = get_or_zero(killer_name)
	local vpl = get_or_zero(victim_name)
	if not kpl or not vpl then return end

	kpl.kills = (kpl.kills or 0) + 1
	vpl.deaths = (vpl.deaths or 0) + 1

	local reward = calculate_kill_score(kpl)
	kpl.points = (kpl.points or 0) + reward
	kpl.earned_points = (kpl.earned_points or 0) + reward
end

-- Award objective completion points. kind is one of:
--   "core_delivery"      — the Objective Core was delivered (game win)
--   "beacon_destruction" — the enemy beacon was destroyed (game win)
-- Both terminate the match, so the actor's team is implicitly the
-- winner — no need to also credit a victory bonus (the end_match
-- pass handles that uniformly).
function game_mode.award_objective_points(actor_name, kind)
	if not actor_name then return end
	local pl = get_or_zero(actor_name)
	if not pl then return end
	local reward
	if kind == "core_delivery" then
		reward = POINTS_PER_CORE_DELIVERY
	elseif kind == "beacon_destruction" then
		reward = POINTS_PER_BEACON_DESTRUCTION
	else
		return
	end
	pl.points = (pl.points or 0) + reward
	pl.earned_points = (pl.earned_points or 0) + reward
end

-- Walk every player once at end-of-match and credit the survival
-- and victory bonuses. The bonuses are stored separately from
-- earned points: they show up on the per-match result screen
-- (via pl.points) but do NOT bleed into the tournament season
-- score (which is banked from pl.earned_points — see match.lua).
-- This honours the §13.3 owner ruling: season rank is driven by
-- kills + objectives, not by having survived / won.
--
-- Idempotent within a match (safe to call more than once from
-- end_match paths that fan out, e.g. an end_tournament pass that
-- re-replays the per-match award). The 'awarded' flag lives on
-- the player state and is cleared by the clean reset in end_match.
function game_mode.award_match_end_points(winner, players_state)
	players_state = players_state or state.players
	for name, pl in pairs(players_state) do
		if pl.awarded_end_points then
			-- Already credited this match (idempotent).
		else
			pl.awarded_end_points = true
			if pl.points == nil then pl.points = 0 end
			if pl.end_match_bonus == nil then pl.end_match_bonus = 0 end
			local bonus = 0
			local alive = (pl.phase == "alive") and not pl.eliminated
			if alive then
				bonus = bonus + POINTS_PER_SURVIVE
			end
			if winner and state.teams[winner] and pl.team == winner then
				bonus = bonus + POINTS_PER_VICTORY
			end
			if bonus > 0 then
				pl.points = pl.points + bonus
				pl.end_match_bonus = (pl.end_match_bonus or 0) + bonus
			end
		end
	end
end

-- Clear the per-match awarded flag and the per-match end_match_bonus
-- so the next match re-credits from a clean slate. Called from the
-- match.lua clean reset path. Lives here so the scoring module owns
-- its own bookkeeping.
function game_mode.clear_match_end_points_awarded(players_state)
	players_state = players_state or state.players
	for _, pl in pairs(players_state) do
		pl.awarded_end_points = nil
		pl.end_match_bonus = 0
	end
end

minetest.log("action", "[sl_modebase] scoring module loaded"
	.. " (kill=K/D×7, core=" .. POINTS_PER_CORE_DELIVERY
	.. ", beacon=" .. POINTS_PER_BEACON_DESTRUCTION
	.. ", survive=" .. POINTS_PER_SURVIVE
	.. ", victory=" .. POINTS_PER_VICTORY
	.. ", earned-points banking)")
