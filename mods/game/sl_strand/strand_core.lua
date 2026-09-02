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
	-- The Chain Ledger's memory: every earlier loss presses on this run.
	if strand.apply_debt then strand.apply_debt(run) end
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

-- ================================================================
-- Parsing a player action (SECURITY: never evaluate client text)
-- ================================================================
-- `/sl_strand_act` used to run `minetest.deserialize("return " .. param)`,
-- i.e. it handed a raw chat string to loadstring(). The engine's sandbox
-- hides `minetest`/`io`/`os`, but it bounds nothing: one chat line could
-- `while true do end` the server thread (pcall cannot interrupt a running
-- chunk) or allocate hundreds of megabytes. Actions are a closed vocabulary
-- of seven verbs with a handful of string keys, so they are PARSED.
--
-- Both spellings below are data, and both produce the same table:
--   /sl_strand_act vote accused=Crew-3 player_vote=true
--   /sl_strand_act { type = "vote", accused = "Crew-3", player_vote = true }
local ACTION_SCHEMA = {
	read_tell = { bot = "name", target = "name" },
	confide   = { bot = "name" },
	observe   = { bot = "name", target = "name" },
	build     = { socket = "name", kind = "name" },
	reveal    = {},
	choose    = { choice = "name" },
	vote      = { accused = "name", player_vote = "bool" },
}
strand.ACTION_SCHEMA = ACTION_SCHEMA

local ACTION_MAX_LEN = 256   -- a whole action fits in one line of chat
local VALUE_MAX_LEN  = 64    -- crew/socket/kind identifiers are short
local NAME_PATTERN   = "^[%w_%-]+$"

-- The legacy table spelling carries punctuation. Strip it as text: the
-- tokenizer never evaluates anything, so a stray brace is just a character.
local function strip_decorations(word)
	return (word:gsub('[{}%[%]()"\'`,;]', ""))
end

-- Returns an action table, or nil + a reason. Total: no loadstring, no
-- deserialize, no arithmetic on attacker text beyond length checks.
function strand.parse_action(param)
	param = tostring(param or "")
	if #param > ACTION_MAX_LEN then
		return nil, "action too long (" .. ACTION_MAX_LEN .. " characters max)"
	end

	local verb
	local kv = {}
	-- Normalize " key = value " to "key=value", then split on whitespace
	-- and commas so both spellings tokenize the same way.
	for word in (param:gsub("%s*=%s*", "=")):gmatch("[^%s,]+") do
		local key, value = word:match("^([^=]*)=(.*)$")
		if key then
			key = strip_decorations(key)
			value = strip_decorations(value)
			if key == "type" then
				if verb then return nil, "duplicate action type" end
				verb = value
			elseif kv[key] ~= nil then
				return nil, "duplicate key '" .. key .. "'"
			else
				kv[key] = value
			end
		else
			local bare = strip_decorations(word)
			if bare ~= "" then
				if verb then return nil, "unexpected token '" .. bare .. "'" end
				verb = bare
			end
		end
	end

	if not verb or verb == "" then
		return nil, "no action given"
	end
	local schema = ACTION_SCHEMA[verb]
	if not schema then
		local known = {}
		for name in pairs(ACTION_SCHEMA) do known[#known + 1] = name end
		table.sort(known)
		return nil, "unknown action '" .. verb .. "' (known: " .. table.concat(known, " ") .. ")"
	end

	local action = { type = verb }
	for key, value in pairs(kv) do
		local kind = schema[key]
		if not kind then
			return nil, "action '" .. verb .. "' takes no '" .. key .. "'"
		end
		if #value > VALUE_MAX_LEN then
			return nil, "value for '" .. key .. "' is too long (" .. VALUE_MAX_LEN .. " characters max)"
		end
		if kind == "bool" then
			if value ~= "true" and value ~= "false" then
				return nil, "'" .. key .. "' must be true or false"
			end
			action[key] = (value == "true")
		else
			if not value:match(NAME_PATTERN) then
				return nil, "'" .. key .. "' must be letters, digits, '_' or '-'"
			end
			action[key] = value
		end
	end
	return action
end

-- The schema and the dispatcher must never drift apart: a verb in one and
-- not the other is either a dead command or an unparsed action.
for schema_verb in pairs(ACTION_SCHEMA) do
	assert(TURN_ACTIONS[schema_verb], "strand: ACTION_SCHEMA verb without a handler: " .. schema_verb)
end
for handler_verb in pairs(TURN_ACTIONS) do
	assert(ACTION_SCHEMA[handler_verb], "strand: TURN_ACTIONS verb missing from ACTION_SCHEMA: " .. handler_verb)
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
	if (run.debt or 0) > 0 then
		status = status .. " · Debt " .. run.debt
	end
	return status
end

-- Survival summary for the result screen.
function strand.run_summary(run)
	local s = {
		seed = run.seed,
		nights = run.night,
		outcome = run.phase,
		reason = run.defeat_reason or run.victory_reason or "core-complete",
		wrong_votes = run.wrong_votes,
		phantom_bosses = strand.phantom_boss_count(),
		mutation = run.mutation and run.mutation.id,
	}
	-- Chain Ledger settlement, when the run has closed.
	if run.ledger_result then
		s.ending = run.ledger_result.ending.id
		s.ending_title = run.ledger_result.ending.title
		s.flags = run.ledger_result.flags
		s.score = run.ledger_result.score.total
		s.score_breakdown = run.ledger_result.score
		s.ledger = strand.ledger_summary()
	end
	return s
end
