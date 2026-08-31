-- ================================================================
-- sl_strand / strand_state.lua
-- "SIMULACRUM STRAND" — singleplayer roguelike social-deduction mode.
--
-- Owns the run's persistent-ish state, the seeded Echo roll (which
-- may quietly cast the PLAYER as the Echo), the phase machine, and a
-- small deterministic RNG so the whole loop is testable headless.
--
-- Faithful to the council brief:
--   * 6 entities total: the player + 5 crew-bots.  One is the Echo.
--   * Across runs a seeded chance that the PLAYER is the Echo and does
--     not know it.  The only systemic lie is this role reveal.
--   * Loop: Build -> Watch/Trust -> Suspect -> Vote -> Survive(night)
--     -> Mutate.
-- ================================================================

strand = rawget(_G, "strand") or {}
_G.strand = strand

local math_byte = function(s, i) return s:byte(i or 1) end

-- ---------------------------------------------------------------
-- Deterministic, seedable PRNG (xorshift32).  Independent of the
-- global math.random so tests and live runs are reproducible from a
-- single seed.  `strand.rng` is (re)created each run.
-- ---------------------------------------------------------------
local function xor32(x)
	x = x or 1
	x = x == 0 and 1 or x
	x = x ~ (x << 13); x = x % 0xFFFFFFFF
	x = x ~ (x >> 17); x = x % 0xFFFFFFFF
	x = x ~ (x << 5);  x = x % 0xFFFFFFFF
	return x
end

function strand.make_rng(seed)
	local state = (seed or 1) % 0xFFFFFFFF
	if state <= 0 then state = state + 0xFFFFFFFF end
	return {
		state = state,
		-- return integer in [0, n)
		next = function(self, n)
			self.state = xor32(self.state)
			return self.state % (n or 0xFFFFFFFF)
		end,
		-- float in [0,1)
		fraction = function(self)
			self.state = xor32(self.state)
			return self.state / 0xFFFFFFFF
		end,
		-- int in [lo, hi] inclusive
		range = function(self, lo, hi)
			return lo + self:next((hi - lo) + 1)
		end,
	}
end

function strand.hash_seed(str)
	local h = 2166136261
	for i = 1, #str do
		h = h ~= math_byte(str, i)
		h = h * 16777619
		h = h % 0xFFFFFFFF
	end
	return h
end

-- ---------------------------------------------------------------
-- Config (server setting overrides).  Read once at load; the test
-- harness can mutate strand.config directly before seeding a run.
-- ---------------------------------------------------------------
strand.config = {
	crew_size = tonumber(minetest.settings:get("sl_strand.crew_size") or "5") or 5,
	-- inclusive range of nights to survive for a crew victory
	-- (the "Al Dente" target).
	core_target = tonumber(minetest.settings:get("sl_strand.core_target") or "7") or 7,
	core_integrity = tonumber(minetest.settings:get("sl_strand.core_integrity") or "100") or 100,
	-- Chance the PLAYER is secretly the Echo (across runs).
	player_echo_chance = tonumber(minetest.settings:get("sl_strand.player_echo_chance") or "0.15") or 0.15,
	-- Trust points granted each Build/Watch turn.
	trust_per_turn = tonumber(minetest.settings:get("sl_strand.trust_per_turn") or "4") or 4,
	-- Wrongful exiles allowed before the run is overrun.
	vote_limit = tonumber(minetest.settings:get("sl_strand.vote_limit") or "3") or 3,
	-- Persistence: module storage for cross-run phantom bosses.
	storage_key = "sl_strand:persisted",
}

-- ---------------------------------------------------------------
-- Persistence abstraction.  Prefer engine mod storage, but fall back
-- to a plain Lua table so the headless test needs no engine storage.
-- ---------------------------------------------------------------
function strand.get_storage()
	if strand._storage then return strand._storage end
	local ms = minetest.get_mod_storage
	if ms then
		strand._storage = {
			get_string = function(_, k) return ms():get_string(k) end,
			set_string = function(_, k, v) return ms():set_string(k, v) end,
		}
	else
		strand._storage = {
			_data = {},
			get_string = function(self, k) return self._data[k] or "" end,
			set_string = function(self, k, v) self._data[k] = v end,
		}
	end
	return strand._storage
end

function strand.load_persisted()
	local st = strand.get_storage()
	local raw = st:get_string(strand.config.storage_key)
	if raw == "" then return { phantom_bosses = {}, runs = 0 } end
	local ok, data = pcall(minetest.deserialize, raw)
	if ok and type(data) == "table" then
		data.phantom_bosses = data.phantom_bosses or {}
		data.runs = data.runs or 0
		return data
	end
	return { phantom_bosses = {}, runs = 0 }
end

function strand.save_persisted(p)
	strand.persisted = p
	local st = strand.get_storage()
	st:set_string(strand.config.storage_key, minetest.serialize(p))
end

strand.persisted = strand.load_persisted()

-- ---------------------------------------------------------------
-- Empty run template
-- ---------------------------------------------------------------
function strand.new_run_state(seed)
	local rng = strand.make_rng(seed)
	return {
		active = true,
		seed = seed,
		phase = "build",          -- build | watch | vote | wave | resolving | mutating | victory | defeat
		night = 0,                 -- nights survived so far
		rng = rng,
		crew = {},                 -- list of crew-bot records (see strand_trust)
		echo_identity = nil,       -- name of the Echo (a crew-bot OR the player)
		player_is_echo = false,    -- seeded reveal; the systemic lie
		player_has_learned = false,-- already revealed to the player this run
		player_choice = nil,       -- once revealed: "survive" | "give_up"
		trust = strand.config.trust_per_turn,
		presence_spent = 0,
		core = {
			integrity = strand.config.core_integrity,
			target = strand.config.core_target,
		},
		wrong_votes = 0,
		vote_limit = strand.config.vote_limit,
		exiled = {},               -- names removed this run
		phantom_bosses_this_run = {}, -- names that became phantoms
		wave_log = {},             -- per-night summary for the HUD/result
		started_at = os.time(),
	}
end

-- ---------------------------------------------------------------
-- Stitch a crew roster onto a run.  Pure and testable.
-- ---------------------------------------------------------------
local CREW_TEMPLATE = {
	"Bot 1", "Bot 2", "Bot 3", "Bot 4", "Bot 5",
}

function strand.make_crew(run, seed)
	local size = strand.config.crew_size
	local names = {}
	for i = 1, size do
		names[i] = "Crew-" .. i
	end
	run.crew_names = names
	run.crew = {}
	for i, name in ipairs(names) do
		run.crew[i] = {
			name = name,
			alive = true,
			leadership = run.rng:range(35, 75), -- how persuasive / suspected
			persona = {},   -- [target_name] = what this bot CLAIMS (public tell)
			memory = {},    -- [target_name] = what this bot actually observed
			trust = {},     -- [target_name] = private belief score (0..100)
			accused = false,
			voted_out = false,
		}
	end
	return names
end

-- ---------------------------------------------------------------
-- Seeded Echo roll.  Returns the echo name; if the roll picks the
-- player it sets run.player_is_echo and stores a sentinel identity.
-- ---------------------------------------------------------------
strand.ECHO_PLAYER_NAME = "YOU"

function strand.roll_echo(run)
	local size = #run.crew_names
	-- 1-in-(size+1) chance the player is the Echo, OR the configured
	-- player_echo_chance, whichever the seed dictates.
	local r = run.rng:fraction()
	if r < strand.config.player_echo_chance and run.rng:fraction() < 0.5 then
		run.player_is_echo = true
		run.echo_identity = strand.ECHO_PLAYER_NAME
		return strand.ECHO_PLAYER_NAME
	end
	local idx = run.rng:range(1, size)
	local name = run.crew_names[idx]
	run.player_is_echo = false
	run.echo_identity = name
	return name
end

-- ---------------------------------------------------------------
-- Phase machine.  Phases advance on a tick; the test drives them.
-- ---------------------------------------------------------------
strand.PHASES = { "build", "watch", "vote", "wave", "resolving" }
strand.PHASE_ORDER = {
	build = 1, watch = 2, vote = 3, wave = 4, resolving = 5,
}

function strand.advance_phase(run)
	if run.phase == "build" then run.phase = "watch"
	elseif run.phase == "watch" then run.phase = "vote"
	elseif run.phase == "vote" then run.phase = "wave"
	elseif run.phase == "wave" then run.phase = "resolving"
	elseif run.phase == "resolving" then
		run.night = run.night + 1
		-- Grant trust for the next turn.
		run.trust = run.trust + strand.config.trust_per_turn
		if run.night >= run.core.target and run.core.integrity > 0 then
			run.phase = "victory"
		else
			run.phase = "build"
		end
	end
	return run.phase
end

-- ---------------------------------------------------------------
-- End-of-run helpers
-- ---------------------------------------------------------------
function strand.run_victory(run)
	run.active = false
	run.phase = "victory"
	strand.save_persisted(strand.persisted)
	return true
end

function strand.run_defeat(run, reason)
	run.active = false
	run.phase = "defeat"
	run.defeat_reason = reason or "core breach"
	-- A self-echoed player who is exiled is "deleted" and haunts the
	-- chain as a phantom boss (true permadeath / difficulty scaling).
	-- A self-surrender is the one clean cut: no phantom is born.
	if run.player_is_echo and run.player_has_learned and not run._surrender then
		strand.record_phantom_boss({
			name = strand.ECHO_PLAYER_NAME,
			seed = run.seed,
			night = run.night,
			score = run.wrong_votes,
		})
	end
	strand.save_persisted(strand.persisted)
	return true
end

-- ---------------------------------------------------------------
-- Phantom-boss ledger (cross-run persistence)
-- ---------------------------------------------------------------
function strand.record_phantom_boss(entry)
	local p = strand.persisted
	p.phantom_bosses = p.phantom_bosses or {}
	p.runs = (p.runs or 0) + 1
	table.insert(p.phantom_bosses, entry)
	strand.save_persisted(p)
	return #p.phantom_bosses
end

function strand.phantom_boss_count()
	local p = strand.persisted
	return p and #(p.phantom_bosses or {}) or 0
end
