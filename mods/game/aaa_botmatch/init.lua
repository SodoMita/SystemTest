-- ================================================================
-- aaa_botmatch — headless soak-test harness for System Looting.
--
-- WHY THE aaa_ PREFIX: Luanti sorts mods alphabetically. This mod
-- must load BEFORE every other mod so it can wrap the callback
-- registration functions (register_on_dieplayer, ...) and collect
-- every handler any mod registers. When a simulated player dies,
-- punches, chats, or respawns, the harness replays the collected
-- handlers exactly like the engine would — so sl_modebase's real
-- match logic runs unmodified.
--
-- INERT UNLESS ENABLED: the harness (bots, soak loop, arena, mob
-- entities) is gated behind the setting
--   sl_botmatch.enabled = true
-- so normal servers never load any of that behavior. The /sl_bots
-- admin chat command is registered regardless — once
--   sl_botmatch.mob_mode = true
-- is set, an sl_admin can use it to add/remove bots at runtime even
-- if the rest of the harness is opted out. The chat command itself
-- checks both gates and returns a clear error if either is missing.
--
-- TELEMETRY: writes <world>/botmatch_stats.json after every match
-- and at run end. Lua errors triggered by simulated play are
-- captured (pcall) into stats.bugs and logged as
-- "[botmatch][BUG] ..." lines, which the soak driver harvests.
-- ================================================================

local modname = minetest.get_current_modname()
local S = minetest.get_translator(modname)

botmatch = rawget(_G, "botmatch") or {}
_G.botmatch = botmatch

botmatch.modpath = minetest.get_modpath(modname)
botmatch.enabled = minetest.settings:get_bool("sl_botmatch.enabled")

-- Initialize the pool table BEFORE the enabled-gate so /sl_bots can
-- reach it from a session where the harness is opted out. The
-- chat-command handler rejects with a clear error if the harness is
-- not enabled, so this is purely a no-op safety net.
botmatch.pool = botmatch.pool or {}

-- Register the /sl_bots admin chat command BEFORE the enabled-gate so
-- it's available whenever aaa_botmatch is loaded. The harness itself
-- (bots, arena, soak loop) still requires sl_botmatch.enabled = true;
-- the chat command's func checks both gates and returns a friendly
-- error if either is missing.
local BOT_NAMES = { "bot_alpha", "bot_beta", "bot_gamma", "bot_delta", "bot_epsilon", "bot_zeta" }
local function pool_index_of(name)
	for i, entry in ipairs(botmatch.pool or {}) do
		if entry.name == name then return i end
	end
	return nil
end
local function next_default_bot_name()
	for _, n in ipairs(BOT_NAMES) do
		if not pool_index_of(n) and not (botmatch.bots and botmatch.bots[n]) then
			return n
		end
	end
	return nil
end
minetest.register_chatcommand("sl_bots", {
	params = "add [name] <beacon_a|beacon_b> | remove <name> | team <name> <beacon_a|beacon_b> | list | clear",
	description = S("Add, remove, retag, list, or clear the bot roster (mob mode, sl_admin)."),
	privs = { sl_admin = true },
	func = function(caller, param)
		-- Two gates: the harness must be enabled, AND mob_mode must be on.
		-- Either missing → a clear error so the admin knows what to set.
		if not botmatch.enabled or not botmatch.config then
			return false, S("/sl_bots requires sl_botmatch.enabled = true in minetest.conf.")
		end
		if not botmatch.config.mob_mode then
			return false, S("/sl_bots requires sl_botmatch.mob_mode = true in minetest.conf.")
		end

		local args = {}
		for word in (param or ""):gmatch("%S+") do
			table.insert(args, word)
		end
		local sub = args[1] or "list"

		if sub == "list" or sub == "" then
			local lines = botmatch.list_pool_lines()
			if #lines == 0 then
				return true, S("Bot pool is empty. Add some with /sl_bots add <name> <beacon_a|beacon_b>.")
			end
			return true, S("Bot pool (@1): @2", tostring(#lines), table.concat(lines, ", "))

		elseif sub == "add" then
			local name, team = args[2], args[3]
			if not team and (name == "beacon_a" or name == "beacon_b") then
				team, name = name, next_default_bot_name()
				if not name then
					return false, S("Pool is full (max @1 bots) and no canonical name is free.", tostring(botmatch.POOL_MAX))
				end
			elseif not name or not team then
				return false, S("Usage: /sl_bots add [name] <beacon_a|beacon_b>")
			end
			local ok, err = botmatch.add_bot(name, team, true)
			if not ok then return false, err end
			return true, S("Added bot @1 on @2. Use /sl_match_start to begin.", name, team)

		elseif sub == "remove" then
			local name = args[2]
			if not name then return false, S("Usage: /sl_bots remove <name>") end
			local ok, err = botmatch.remove_bot(name)
			if not ok then return false, err end
			return true, S("Removed bot @1.", name)

		elseif sub == "team" then
			local name, team = args[2], args[3]
			if not name or not team then
				return false, S("Usage: /sl_bots team <name> <beacon_a|beacon_b>")
			end
			local ok, err = botmatch.set_team(name, team)
			if not ok then return false, err end
			return true, S("Bot @1 reassigned to @2.", name, team)

		elseif sub == "clear" then
			local ok, err = botmatch.clear_bots()
			if not ok then return false, err end
			return true, S("Cleared the bot pool.")

		else
			return false, S("Unknown subcommand '@1'. Try: add, remove, team, list, clear.", sub)
		end
	end,
})

if not botmatch.enabled then
	minetest.log("action", "[botmatch] disabled (set sl_botmatch.enabled = true to run soak tests; /sl_bots is still available)")
	return
end

-- Coexistence: botmatch builds and owns its arena. Disable the standalone
-- test_harness auto-arena (sl_modebase loads after this mod) so the two
-- arena builders do not overwrite each other mid-run.
minetest.settings:set("sl_test.auto_arena", "false")

botmatch.config = {
	bots = tonumber(minetest.settings:get("sl_botmatch.bots") or "4") or 4,
	matches = tonumber(minetest.settings:get("sl_botmatch.matches") or "3") or 3,
	seed = tonumber(minetest.settings:get("sl_botmatch.seed") or "20260827") or 20260827,
	match_duration = tonumber(minetest.settings:get("sl_botmatch.match_duration") or "120") or 120,
	bot_speed = tonumber(minetest.settings:get("sl_botmatch.bot_speed") or "4") or 4,
	attack_interval = tonumber(minetest.settings:get("sl_botmatch.attack_interval") or "2.5") or 2.5,
	inter_match_delay = tonumber(minetest.settings:get("sl_botmatch.inter_match_delay") or "4") or 4,
	combat_damage = tonumber(minetest.settings:get("sl_botmatch.combat_damage") or "5") or 5,
	respawn_delay = tonumber(minetest.settings:get("sl_botmatch.respawn_delay") or "2") or 2,
	-- Turbo profile: bases placed next to each other, tiny beacon HP, fast
	-- swings — a full match cycle completes in ~5 s. Same code paths,
	-- compressed clocks. Individual settings above still override.
	turbo = minetest.settings:get_bool("sl_botmatch.turbo"),
	-- Mob mode: bots get physical entity bodies with engine pathfinding.
	-- A real admin player can join; bots auto-ready and otherwise behave
	-- exactly like players. Matches are admin-driven (/sl_match_start),
	-- unless auto_start is set (headless soak of the mob mode itself).
	mob_mode = minetest.settings:get_bool("sl_botmatch.mob_mode"),
	auto_start = minetest.settings:get_bool("sl_botmatch.auto_start"),
	beacon_spacing = tonumber(minetest.settings:get("sl_botmatch.beacon_spacing") or "24") or 24,
	-- Pathfinding tuning. Defaults below are calibrated for the
	-- build_arena auto-arena; bespoke handmade maps can override
	-- via minetest.conf. See mob_player.lua pathfind_walk for
	-- why these specific values.
	path_searchdistance = tonumber(minetest.settings:get("sl_botmatch.path_searchdistance") or "80") or 80,
	path_max_jump       = tonumber(minetest.settings:get("sl_botmatch.path_max_jump") or "1") or 1,
	path_max_drop       = tonumber(minetest.settings:get("sl_botmatch.path_max_drop") or "2") or 2,
	disconnect_test = minetest.settings:get_bool("sl_botmatch.disconnect_test")
		or minetest.settings:get("sl_botmatch.disconnect_test") == nil,
}

-- Turbo overrides (explicit settings always win because they were read first).
if botmatch.config.turbo then
	local s = minetest.settings
	local function overridden(key) return s:get("sl_botmatch." .. key) ~= nil end
	if not overridden("beacon_spacing") then botmatch.config.beacon_spacing = 4 end
	-- Single-life pacing: softer hits + sturdier beacons keep matches in
	-- the 6-12 s band so the ghost economy still gets its windows.
	if not overridden("attack_interval") then botmatch.config.attack_interval = 1.0 end
	if not overridden("combat_damage") then botmatch.config.combat_damage = 5 end
	if not overridden("respawn_delay") then botmatch.config.respawn_delay = 0.5 end
	if not overridden("inter_match_delay") then botmatch.config.inter_match_delay = 1 end
	-- Shorter possession window keeps the exorcism counterplay relevant
	-- inside ~10 s matches (WP3's possession_setting reads this key).
	turbo_possession_duration = 12
end

math.randomseed(botmatch.config.seed)

botmatch.bots = {}
botmatch.bot_order = {}
botmatch.connected = {}
botmatch.callbacks = {
	dieplayer = {}, respawnplayer = {}, punchplayer = {},
	chat_message = {}, punchnode = {}, joinplayer = {}, leaveplayer = {},
}
botmatch.bugs = {}
botmatch.match_index = 0
botmatch.current = nil
botmatch.summon_in_progress = false
botmatch.finished = false

botmatch.stats = {
	seed = botmatch.config.seed,
	matches_requested = botmatch.config.matches,
	matches_completed = 0,
	engine = minetest.get_version().string,
	started_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	matches = {},
}

-- ================================================================
-- Callback interception (must run before other mods register)
-- ================================================================
local intercepted = {
	dieplayer = "register_on_dieplayer",
	respawnplayer = "register_on_respawnplayer",
	punchplayer = "register_on_punchplayer",
	chat_message = "register_on_chat_message",
	punchnode = "register_on_punchnode",
	joinplayer = "register_on_joinplayer",
	leaveplayer = "register_on_leaveplayer",
}
for kind, register_name in pairs(intercepted) do
	local original = minetest[register_name]
	if original then
		minetest[register_name] = function(fn, ...)
			table.insert(botmatch.callbacks[kind], fn)
			return original(fn, ...)
		end
	end
end

-- Route player lookups through the bot registry.
local engine_get_player_by_name = minetest.get_player_by_name
minetest.get_player_by_name = function(name)
	return botmatch.bots[name] or engine_get_player_by_name(name)
end

local engine_get_connected_players = minetest.get_connected_players
minetest.get_connected_players = function()
	local list = engine_get_connected_players()
	for _, n in ipairs(botmatch.connected) do
		if botmatch.bots[n] then
			table.insert(list, botmatch.bots[n])
		end
	end
	return list
end

-- Engine player information lookup: return a synthetic modern client
-- record for bots so builtin HUD code (minimap gating etc.) works.
local engine_get_player_information = minetest.get_player_information
minetest.get_player_information = function(name)
	local bot = botmatch.bots[name]
	if bot then
		-- version_string carries the bot's kind so HUD code or
		-- any caller inspecting the synthetic record can see
		-- whether this is a stub (no engine body) or a mob
		-- (real entity with pathfinding) without poking at
		-- botmatch internals. The kind was stamped at spawn
		-- time by spawn_one_bot; if it's missing for any
		-- reason (legacy bot from an older version) we
		-- fall back to "stub" because that's the safe
		-- default — a stub never claims capabilities it
		-- doesn't have.
		local kind = (bot.bm and bot.bm.kind) or "stub"
		return {
			protocol_version = 44,
			formspec_version = 4,
			lang_code = "en",
			major = 5, minor = 10, patch = 0,
			version_string = "botmatch:" .. kind,
			address = "127.0.0.1",
			ip_version = 4,
			connection_time = 0,
		}
	end
	return engine_get_player_information(name)
end

-- ================================================================
-- Safe invocation + bug harvesting
-- ================================================================
function botmatch.safe(context, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		table.insert(botmatch.bugs, {
			context = context,
			error = tostring(err),
			match = botmatch.match_index,
			t = minetest.get_us_time() / 1000000,
		})
		minetest.log("error", "[botmatch][BUG] " .. context .. ": " .. tostring(err))
	end
	return ok
end

-- Replay collected handlers like the engine does. For punchplayer and
-- chat_message a non-nil return short-circuits (cancels), matching
-- engine semantics.
function botmatch.fire(kind, ...)
	local canceled = false
	for _, fn in ipairs(botmatch.callbacks[kind]) do
		local results = { pcall(fn, ...) }
		if not results[1] then
			table.insert(botmatch.bugs, {
				context = "on_" .. kind,
				error = tostring(results[2]),
				match = botmatch.match_index,
				t = minetest.get_us_time() / 1000000,
			})
			minetest.log("error", "[botmatch][BUG] on_" .. kind .. ": " .. tostring(results[2]))
		elseif results[2] ~= nil and (kind == "punchplayer" or kind == "chat_message") then
			canceled = true
		end
	end
	return canceled
end

function botmatch.is_connected(name)
	for _, n in ipairs(botmatch.connected) do
		if n == name then return true end
	end
	return false
end

-- ================================================================
-- Bot roster (runtime-configurable pool)
-- ================================================================
-- The "pool" is the source of truth for which bots exist for the next
-- match. On server start, spawn_bots() seeds it from
-- sl_botmatch.bots (preserving the existing soak path). Admins can
-- add/remove/retag bots at runtime via /sl_bots; the changes take
-- effect on the next start_new_match (mid-match edits are rejected
-- because they would corrupt an in-flight simulation).
--
-- Each pool entry: { name = "<unique>", team = "beacon_a"|"beacon_b" }
-- Names that are already connected real players are rejected.
-- Team is required (the user asked for explicit team assignment;
-- no auto-balancing). If a match can't be started because one team
-- is empty, sl_modebase.start_new_match returns its own error.
botmatch.pool = botmatch.pool or {}
botmatch.POOL_MAX = 6 -- matches the names[] table in spawn_bots
local POOL_VALID_TEAMS = { beacon_a = true, beacon_b = true }

-- pool_index_of is defined above the enabled-gate (so /sl_bots can
-- reach it). Reuse that one here.

-- Spawn one bot: create the fake player ref, optionally its mob body,
-- add to the connected/ordered lists, and fire on_joinplayer so any
-- sl_modebase handler (e.g. spawn_player scheduling) runs.
local function spawn_one_bot(name, team)
	local fp = dofile(botmatch.modpath .. "/fake_player.lua")
	local bot = fp.new(name)
	-- If the caller passed an explicit team, attach it to the
	-- logical player state immediately. (apply_pool always does
	-- this; the start_run path may not, in which case the team
	-- defaults to nil and the body spawn falls back to the lobby
	-- area — that's intentional, the first match will assign a
	-- team on insertion.)
	if team and rawget(_G, "game_mode") then
		local pl = game_mode.get_player_state(name)
		pl.team = team
	end
	-- Stamp the bot's "kind" so /sl_bots list, in-world nametags,
	-- and the player_information synthetic record can all show
	-- whether this bot is a stub (headless Lua state, no engine
	-- body, straight-line step_toward) or a mob (engine entity,
	-- A* pathfinding, GLB model). The kind is decided at spawn
	-- time from botmatch.config.mob_mode and is immutable for
	-- the life of the bot: a mid-match config flip should never
	-- make a stub become a mob or vice versa.
	bot.bm = bot.bm or {}
	bot.bm.kind = botmatch.config.mob_mode and "mob" or "stub"
	botmatch.bots[name] = bot
	table.insert(botmatch.bot_order, name)
	table.insert(botmatch.connected, name)
	if botmatch.config.mob_mode and botmatch.spawn_mob_body then
		botmatch.spawn_mob_body(name, bot)
	end
	botmatch.fire("joinplayer", bot)
end

-- Reverse of spawn_one_bot: remove the mob body, fire leaveplayer,
-- drop the bot from the connected/ordered lists. Caller has already
-- validated that the bot is currently connected.
local function despawn_one_bot(name)
	botmatch.fire("leaveplayer", botmatch.bots[name])
	if botmatch.mobs and botmatch.mobs[name] then
		pcall(function() botmatch.mobs[name]:remove() end)
		botmatch.mobs[name] = nil
	end
	for i, n in ipairs(botmatch.connected) do
		if n == name then table.remove(botmatch.connected, i) break end
	end
	for i, n in ipairs(botmatch.bot_order) do
		if n == name then table.remove(botmatch.bot_order, i) break end
	end
	-- Clear any per-match bookkeeping; state.players is owned by
	-- sl_modebase and will be reset by its own clean reset.
	botmatch.bots[name] = nil
end

-- Add a bot to the pool. team must be "beacon_a" or "beacon_b".
-- live_spawn=true spawns the body immediately (so the admin can see
-- them in the lobby before the next match); false just records the
-- preference for the next spawn_bots() call.
function botmatch.add_bot(name, team, live_spawn)
	if type(name) ~= "string" or name == "" then
		return false, "name must be a non-empty string"
	end
	if not POOL_VALID_TEAMS[team] then
		return false, "team must be beacon_a or beacon_b"
	end
	if pool_index_of(name) then
		return false, "bot '" .. name .. "' is already in the pool"
	end
	if botmatch.bots[name] then
		return false, "bot '" .. name .. "' is already connected"
	end
	if minetest.get_player_by_name(name) and not botmatch.bots[name] then
		return false, "'" .. name .. "' is a real player name, not a bot"
	end
	if #botmatch.pool >= botmatch.POOL_MAX then
		return false, "pool is full (max " .. botmatch.POOL_MAX .. " bots)"
	end
	if botmatch.current and botmatch.current.id then
		return false, "cannot add bots during a match (wait for lobby)"
	end
	table.insert(botmatch.pool, { name = name, team = team })
	-- Default roster ordering: bots are spawned in pool order, so the
	-- behavior tick's round-robin stays stable across additions.
	if live_spawn then
		-- BUGFIX: pass `team` so the bot's pl.team is set on
		-- the player state before the mob body is spawned. Without
		-- this, pl.team stays nil at spawn time, the body lands
		-- in the lobby area instead of near the bastion, and
		-- match.lua's auto-balance runs on the first match
		-- insertion (it sees pl.team == nil and assigns the bot
		-- to the OPPOSITE team of the explicit assignment).
		-- The pool row carries the team; thread it through.
		spawn_one_bot(name, team)
	end
	return true
end

function botmatch.remove_bot(name)
	if not pool_index_of(name) then
		return false, "bot '" .. (name or "?") .. "' is not in the pool"
	end
	if botmatch.current and botmatch.current.id then
		return false, "cannot remove bots during a match (wait for lobby)"
	end
	if botmatch.bots[name] then despawn_one_bot(name) end
	for i, entry in ipairs(botmatch.pool) do
		if entry.name == name then table.remove(botmatch.pool, i) break end
	end
	return true
end

function botmatch.set_team(name, team)
	local idx = pool_index_of(name)
	if not idx then
		return false, "bot '" .. (name or "?") .. "' is not in the pool"
	end
	if not POOL_VALID_TEAMS[team] then
		return false, "team must be beacon_a or beacon_b"
	end
	if botmatch.current and botmatch.current.id then
		return false, "cannot retag bots during a match (wait for lobby)"
	end
	botmatch.pool[idx].team = team
	-- BUGFIX: if the bot is currently connected, sync the
	-- player-state team so the next match insertion honors the
	-- retag immediately. Without this, /sl_bots team updates
	-- only the pool row; the live bot's pl.team stays on the
	-- old team, and the match starts with the bot on the wrong
	-- side until the next apply_pool call.
	-- (apply_pool also syncs pl.team for already-spawned bots,
	-- but apply_pool only runs at start_run and on /sl_bots
	-- apply — set_team can be called between those without
	-- touching the live state.)
	if botmatch.bots[name] and rawget(_G, "game_mode") then
		local pl = game_mode.get_player_state(name)
		pl.team = team
	end
	return true
end

function botmatch.clear_bots()
	if botmatch.current and botmatch.current.id then
		return false, "cannot clear pool during a match (wait for lobby)"
	end
	-- Despawn any currently connected bots first.
	for i = #botmatch.connected, 1, -1 do
		despawn_one_bot(botmatch.connected[i])
	end
	botmatch.pool = {}
	return true
end

-- Return the kind label ("stub" or "mob") for a bot, decided at
-- spawn time. Returns "stub" if the bot is unknown or the kind
-- was never stamped (defensive default — a missing bot should
-- never advertise itself as the more capable kind).
function botmatch.kind_of(name)
	local bot = botmatch.bots[name]
	if not bot or not bot.bm or not bot.bm.kind then return "stub" end
	return bot.bm.kind
end

-- Human-readable display form of a bot name, with its kind in
-- brackets. Used by /sl_bots list, the in-world nametag (mob
-- bodies only — stub bots have no world presence), and any
-- future admin UI. Format: "[kind] name" so the kind is the
-- first thing the reader sees. Example: "[mob] bot_alpha" or
-- "[stub] bot_alpha".
function botmatch.display_name(name)
	return string.format("[%s] %s", botmatch.kind_of(name), name)
end

-- Human-readable listing for /sl_bots list and the formspec.
function botmatch.list_pool_lines()
	local lines = {}
	for _, entry in ipairs(botmatch.pool) do
		local connected = botmatch.bots[entry.name] and "connected" or "lobby"
		-- The kind tag tells the admin at a glance which bots
		-- will get a physical body with engine pathfinding
		-- ("mob") versus which are headless Lua stubs that
		-- straight-line toward their target ("stub"). Without
		-- this tag, two pools with the same bot names look
		-- identical in /sl_bots list even though one walks
		-- around the arena and the other teleports in a Lua
		-- table.
		local tag = botmatch.kind_of(entry.name)
		table.insert(lines, string.format("[%s] %s -> %s (%s)",
			tag, entry.name, entry.team, connected))
	end
	return lines
end

-- Re-run the spawn pipeline to honor current pool state. Called by
-- start_run() at boot and by /sl_bots apply (after a batch of edits).
-- Existing connected bots (matched by name) are kept; their team is
-- re-applied to the player state so the next match picks it up.
function botmatch.apply_pool()
	-- 1. Remove currently connected bots that are no longer in the pool.
	for i = #botmatch.connected, 1, -1 do
		local name = botmatch.connected[i]
		if not pool_index_of(name) then
			despawn_one_bot(name)
		end
	end
	-- 2. Spawn pool entries that aren't connected yet.
	for _, entry in ipairs(botmatch.pool) do
		if not botmatch.bots[entry.name] then
			-- Initialize the logical player state with the pool-
			-- assigned team BEFORE the mob body is spawned. The
			-- spawn search uses bot.team to anchor the position
			-- near the right bastion, and behaviour.lua reads
			-- pl.team to pick targets — both must agree on the
			-- team from the very first tick.
			if rawget(_G, "game_mode") then
				local pl = game_mode.get_player_state(entry.name)
				pl.team = entry.team
				pl.role = nil
				pl.eliminated = false
			end
			spawn_one_bot(entry.name, entry.team)
		elseif rawget(_G, "game_mode") then
			-- Already-spawned bot: keep its player-state team in
			-- sync with the pool entry. (Admin retag via
			-- /sl_bots team <name> <team> lands here.)
			local pl = game_mode.get_player_state(entry.name)
			pl.team = entry.team
			pl.role = nil
			pl.eliminated = false
		end
	end
end

-- ================================================================
-- Death / kill accounting
-- ================================================================
function botmatch.on_bot_lethal(bot)
	local name = bot:get_player_name()
	bot.bm.kit = false -- ritual kit drops with the body
	botmatch.record_death(name)
	botmatch.fire("dieplayer", bot, { type = "punch" })
	-- Engine would show the respawn screen; simulate the delay.
	minetest.after(botmatch.config.respawn_delay or 2, function()
		-- Purged/eliminated players stay out until the clean reset at
		-- match end — respawning them would farm kills and skew stats.
		local pl = game_mode.get_player_state(name)
		if pl.eliminated then
			minetest.log("action", "[botmatch] " .. name .. " eliminated; stays out until match end")
			return
		end
		bot.dead = false
		bot._hp = 1 -- respawn handlers (spawn_player) restore full HP
		botmatch.fire("respawnplayer", bot)
		-- Fixed starting equipment is re-issued every life, so the ritual
		-- kit returns with its designated carrier after respawn.
		if bot.bm.carrier and game_mode.state.match_active
				and game_mode.get_player_state(name).phase == "alive" then
			local inv = bot:get_inventory()
			inv:add_item("main", ItemStack("sl_modebase:ritual_ashen_relic"))
			inv:add_item("main", ItemStack("sl_modebase:ritual_soul_shard"))
			inv:add_item("main", ItemStack("sl_modebase:ritual_signal_ink"))
			bot.bm.kit = true
		end
	end)
end

function botmatch.attribute_kill(attacker, victim)
	local m = botmatch.current
	if not m then return end
	local ab = m.bots[attacker]
	if ab then
		ab.kills = ab.kills + 1
		local ateam = game_mode.get_player_state(attacker).team
		if ateam and m.teams[ateam] then m.teams[ateam].kills = m.teams[ateam].kills + 1 end
	end
	local vb = m.bots[victim]
	if vb then
		local vteam = game_mode.get_player_state(victim).team
		if vteam and m.teams[vteam] then m.teams[vteam].deaths = m.teams[vteam].deaths + 1 end
	end
	-- Also credit the per-player point model. In mob mode a real
	-- admin can join and kill bots, or a bot can kill a real admin
	-- (when the bot AI targets them); both flows go through
	-- attribute_kill and both should land in the killer's pl.points
	-- using the same K/D-weighted formula as a real-player kill.
	-- award_kill_points is a no-op for suicides and for inactive
	-- matches, so it is safe to call unconditionally.
	if game_mode and game_mode.award_kill_points then
		game_mode.award_kill_points(attacker, victim)
	end
end

function botmatch.record_death(name)
	local m = botmatch.current
	if not m or not m.bots[name] then return end
	m.bots[name].deaths = m.bots[name].deaths + 1
end

function botmatch.record_event(key, amount)
	local m = botmatch.current
	if m then m.events[key] = (m.events[key] or 0) + (amount or 1) end
end

function botmatch.record_bot_flag(name, flag)
	local m = botmatch.current
	if m and m.bots[name] then m.bots[name][flag] = true end
end

function botmatch.record_beacon_damage(team_id, amount, attacker)
	local m = botmatch.current
	if not m or not m.teams[team_id] then return end
	amount = amount or 0
	local tdef = game_mode.state.teams[team_id]
	local hp_before = (tdef and tdef.hp) or 0
	m.teams[team_id].damage_taken = m.teams[team_id].damage_taken + amount
	if attacker and m.bots[attacker] then
		local ateam = game_mode.get_player_state(attacker).team
		if ateam and m.teams[ateam] then
			m.teams[ateam].damage_dealt = m.teams[ateam].damage_dealt + amount
		end
	end
	if hp_before > 0 and hp_before - amount <= 0 then
		m.events.beacon_destructions = m.events.beacon_destructions + 1
	end
end

-- ================================================================
-- Hook the game_mode API (deferred: game_mode loads after this mod)
-- ================================================================
function botmatch.hook_game_mode()
	if botmatch.hooked or not rawget(_G, "game_mode") then return end
	botmatch.hooked = true
	local gm = game_mode

	local orig_end = gm.end_match
	gm.end_match = function(winner, reason)
		if gm.state.match_active then
			botmatch.finish_match(winner, reason)
		end
		orig_end(winner, reason)
		-- sl_modebase's clean reset (called inside orig_end) now
		-- releases the spawn-search claim table
		-- (game_mode.clear_spawn_claims). We don't need to clear
		-- it from here — the centralised path keeps real players
		-- and bot bodies on the same bookkeeping. The old local
		-- botmatch.clear_mob_spawn_claims call is now a no-op
		-- shim that forwards to game_mode.clear_spawn_claims;
		-- leaving the call in is harmless but adds an extra
		-- function hop. Removed.
		botmatch.schedule_next()
	end

	local orig_damage = gm.damage_beacon
	gm.damage_beacon = function(team_id, amount, attacker, silent)
		botmatch.record_beacon_damage(team_id, amount, attacker)
		orig_damage(team_id, amount, attacker, silent)
	end

	-- Whoever starts the match (botmatch schedule, game auto-start, or an
	-- admin command), the telemetry record opens at insertion.
	local orig_start = gm.start_new_match
	gm.start_new_match = function(initiator)
		if not botmatch.current then botmatch.open_match_record() end
		local ok, err = orig_start(initiator)
		if ok then
			botmatch.on_match_inserted()
		else
			botmatch.current = nil
		end
		return ok, err
	end

	if botmatch.config.mob_mode then
		-- Admin-driven flow: when a human opens the ready check, every mob
		-- marks itself ready so the countdown only waits for the admin.
		local orig_begin = gm.begin_ready_check
		gm.begin_ready_check = function(initiator)
			local ok, err = orig_begin(initiator)
			if ok then
				for _, n in ipairs(botmatch.connected) do
					gm.mark_ready(n)
				end
			end
			return ok, err
		end
	end
end

-- ================================================================
-- Run lifecycle
-- ================================================================
function botmatch.start_run()
	if not rawget(_G, "game_mode") then
		minetest.log("error", "[botmatch][BUG] start_run: game_mode not loaded")
		return
	end
	botmatch.hook_game_mode()

	local state = game_mode.state
	-- Botmatch owns match scheduling unless it is explicitly running in
	-- game-driven mob mode (admin/auto_start drives, bots participate).
	if not (botmatch.config.mob_mode and not botmatch.config.auto_start) then
		state.settings.auto_start = false
	end
	state.settings.match_duration = botmatch.config.match_duration
	state.settings.mm_auto_assign = false -- deterministic roster
	state.win_conditions.elimination = true
	if botmatch.config.turbo then
		-- Compressed clocks: 1 s countdown; tiny beacon HP so adjacent-base
		-- matches resolve in seconds.
		local s = minetest.settings
		if s:get("sl_botmatch.countdown") == nil then state.settings.countdown = 1 end
		if s:get("sl_botmatch.beacon_hp") == nil then state.settings.beacon_hp = 50 end
		if s:get("sl_botmatch.possession_duration") == nil then
			state.settings.possession_duration = botmatch.config.turbo_possession_duration or 12
		end
	end

	dofile(botmatch.modpath .. "/behavior.lua")
	-- NOTE: mob_player.lua is included at LOAD time (bottom of this file):
	-- minetest.register_entity requires the mod-load context for its
	-- modname-prefix check, which a runtime dofile does not have.

	botmatch.build_arena()
	botmatch.spawn_bots()

	if botmatch.config.mob_mode and not botmatch.config.auto_start then
		-- Admin-driven: bots wait in the lobby until a human (or admin
		-- command) opens the ready check; bots auto-mark ready.
		minetest.log("action", "[botmatch] mob mode: bodies spawned; waiting for admin /sl_match_start")
	else
		minetest.after(1.5, botmatch.next_match)
	end
end

function botmatch.spawn_bots()
	-- Seed the pool from the sl_botmatch.bots setting when empty.
	-- This preserves the original soak behaviour: an untouched
	-- minetest.conf + sl_botmatch.enabled = true boots with the
	-- configured roster and balanced teams. Round-robin (A, B, A, B)
	-- matches the previous default ordering.
	if #botmatch.pool == 0 and botmatch.config.bots > 0 then
		local names = { "bot_alpha", "bot_beta", "bot_gamma", "bot_delta", "bot_epsilon", "bot_zeta" }
		for i = 1, math.min(botmatch.config.bots, #names) do
			local team = (i % 2 == 1) and "beacon_a" or "beacon_b"
			botmatch.pool[#botmatch.pool + 1] = { name = names[i], team = team }
		end
	end
	botmatch.apply_pool()
	minetest.log("action", "[botmatch] " .. #botmatch.bot_order
		.. (botmatch.config.mob_mode and " mob players embodied (pathfinding entities)"
			or " simulated players connected")
		.. " (pool size " .. #botmatch.pool .. ")")
end

-- Bridge: a real player (admin) punches a mob body. Damage is routed
-- through the same registered punchplayer handlers as any combat.
function botmatch.external_punch(bot_name, attacker_name, damage)
	local victim = botmatch.bots[bot_name]
	if not victim or victim.dead then return end
	local attacker = attacker_name and minetest.get_player_by_name(attacker_name) or nil
	local dmg = damage or 5
	local canceled = botmatch.fire("punchplayer", victim, attacker, 1.0,
		{ full_punch_interval = 1.0, damage_groups = { fleshy = dmg } }, nil, dmg)
	if not canceled then
		victim:set_hp(victim:get_hp() - dmg)
		if victim:get_hp() <= 0 and attacker_name then
			botmatch.attribute_kill(attacker_name, bot_name)
		end
	end
end

-- Opens the per-match telemetry record. Called from the start_new_match
-- wrapper (below), so records open no matter WHO starts the match —
-- botmatch scheduling, the game-side auto-start, or an admin command.
function botmatch.open_match_record()
	botmatch.match_index = botmatch.match_index + 1

	local bots_stats = {}
	for _, name in ipairs(botmatch.bot_order) do
		local pl = game_mode.get_player_state(name)
		bots_stats[name] = {
			team = pl.team or "?", kills = 0, deaths = 0,
			revived_evil = false, final_phase = "?",
		}
	end
	botmatch.current = {
		id = botmatch.match_index,
		started = minetest.get_us_time() / 1000000,
		winner = nil, reason = nil, duration_s = nil,
		teams = {
			beacon_a = { kills = 0, deaths = 0, damage_dealt = 0, damage_taken = 0, hp_end = 0 },
			beacon_b = { kills = 0, deaths = 0, damage_dealt = 0, damage_taken = 0, hp_end = 0 },
		},
		bots = bots_stats,
		events = {
			ghost_summons = 0, offers = 0, revivals = 0,
			sabotages = 0, repairs = 0, possessions = 0, exorcisms = 0,
			disconnects = 0, beacon_destructions = 0,
		},
	}
	botmatch.summon_in_progress = false
end

function botmatch.next_match()
	if botmatch.finished then return end
	if botmatch.match_index >= botmatch.config.matches then
		botmatch.finish_run()
		return
	end

	local ok, err = game_mode.begin_ready_check("botmatch")
	if not ok then
		table.insert(botmatch.bugs, { context = "ready_check", error = tostring(err) })
		minetest.log("error", "[botmatch][BUG] ready_check: " .. tostring(err))
		minetest.after(5, botmatch.next_match)
		return
	end
	for _, name in ipairs(botmatch.connected) do
		game_mode.mark_ready(name)
	end
	-- Insertion itself runs from the countdown; the start_new_match
	-- wrapper opens the record and fires on_match_inserted.
end

function botmatch.schedule_next()
	if botmatch.finished then return end
	if botmatch.config.mob_mode and not botmatch.config.auto_start then
		botmatch.write_stats()
		minetest.log("action", "[botmatch] mob mode: match recorded; waiting for admin to start the next one")
		return
	end
	if botmatch.match_index >= botmatch.config.matches then
		minetest.after(1, botmatch.finish_run)
	else
		minetest.after(botmatch.config.inter_match_delay, botmatch.next_match)
	end
end

function botmatch.finish_match(winner, reason)
	local m = botmatch.current
	if not m then return end
	local state = game_mode.state

	m.duration_s = (minetest.get_us_time() / 1000000) - m.started
	if winner == "beacons" then
		m.winner = "beacons"
	elseif winner and state.teams[winner] then
		m.winner = winner
	else
		m.winner = "draw"
	end
	m.reason = tostring(reason or "")

	-- Snapshot finals BEFORE sl_modebase's clean reset normalizes phases.
	for name, bs in pairs(m.bots) do
		local pl = game_mode.get_player_state(name)
		bs.final_phase = pl.phase
		bs.team = pl.team or bs.team
	end
	for _, team_id in ipairs({ "beacon_a", "beacon_b" }) do
		m.teams[team_id].hp_end = math.max(0, state.teams[team_id].hp or 0)
	end

	table.insert(botmatch.stats.matches, m)
	botmatch.stats.matches_completed = #botmatch.stats.matches
	botmatch.current = nil
	botmatch.write_stats()
	minetest.log("action", string.format("[botmatch] match %d complete: winner=%s duration=%.1fs events=[summons=%d revivals=%d sabotages=%d repairs=%d disconnects=%d]",
		m.id, m.winner, m.duration_s, m.events.ghost_summons, m.events.revivals,
		m.events.sabotages, m.events.repairs, m.events.disconnects))
end

local function compute_aggregate()
	local matches = botmatch.stats.matches
	local agg = {
		matches = #matches,
		win_rate = { beacon_a = 0, beacon_b = 0, draw = 0, beacons = 0 },
		avg_duration_s = 0,
		kills_total = 0, deaths_total = 0,
		avg_beacon_damage_taken = 0,
		events = { ghost_summons = 0, offers = 0, revivals = 0, sabotages = 0,
			repairs = 0, possessions = 0, exorcisms = 0,
			disconnects = 0, beacon_destructions = 0 },
	}
	if #matches == 0 then return agg end
	local dur_sum, dmg_sum = 0, 0
	for _, m in ipairs(matches) do
		agg.win_rate[m.winner] = (agg.win_rate[m.winner] or 0) + 1
		dur_sum = dur_sum + (m.duration_s or 0)
		for k, v in pairs(m.events) do agg.events[k] = (agg.events[k] or 0) + v end
		for _, team_id in ipairs({ "beacon_a", "beacon_b" }) do
			dmg_sum = dmg_sum + m.teams[team_id].damage_taken
		end
		for _, bs in pairs(m.bots) do
			agg.kills_total = agg.kills_total + bs.kills
			agg.deaths_total = agg.deaths_total + bs.deaths
		end
	end
	for k in pairs(agg.win_rate) do
		agg.win_rate[k] = agg.win_rate[k] / #matches
	end
	agg.avg_duration_s = dur_sum / #matches
	agg.avg_beacon_damage_taken = dmg_sum / (#matches * 2)
	-- Side bias: positive favors beacon_a. A balanced mode trends to 0.
	agg.side_bias = (agg.win_rate.beacon_a or 0) - (agg.win_rate.beacon_b or 0)
	return agg
end

function botmatch.finish_run()
	if botmatch.finished then return end
	botmatch.finished = true
	botmatch.stats.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
	botmatch.stats.aggregate = compute_aggregate()
	botmatch.stats.bugs = botmatch.bugs
	botmatch.write_stats()
	minetest.log("action", string.format("[botmatch] RUN COMPLETE: %d/%d matches, %d bug events. Stats written to botmatch_stats.json",
		botmatch.stats.matches_completed, botmatch.config.matches, #botmatch.bugs))
end

-- ================================================================
-- Minimal JSON encoder + atomic stats writer
-- ================================================================
local function json_escape(s)
	return (tostring(s):gsub('[%c"\\]', function(c)
		local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
		return map[c] or string.format("\\u%04x", c:byte())
	end))
end

local function is_array(t)
	local n = 0
	for k in pairs(t) do
		n = n + 1
		if type(k) ~= "number" then return false end
	end
	return n == #t
end

local function json_encode(v)
	local tv = type(v)
	if tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if math.floor(v) == v and math.abs(v) < 2 ^ 52 then return string.format("%d", v) end
		return string.format("%.4f", v)
	elseif tv == "boolean" then
		return v and "true" or "false"
	elseif tv == "string" then
		return '"' .. json_escape(v) .. '"'
	elseif tv == "table" then
		if is_array(v) then
			local parts = {}
			for _, item in ipairs(v) do table.insert(parts, json_encode(item)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local parts = {}
		for _, k in ipairs(keys) do
			table.insert(parts, '"' .. json_escape(k) .. '":' .. json_encode(v[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function botmatch.write_stats()
	local path = minetest.get_worldpath() .. "/botmatch_stats.json"
	local payload = botmatch.stats
	payload.bugs = botmatch.bugs
	local f = io.open(path .. ".tmp", "w")
	if not f then
		minetest.log("error", "[botmatch][BUG] cannot write stats file: " .. path)
		return
	end
	f:write(json_encode(payload))
	f:close()
	os.rename(path .. ".tmp", path)
end

-- ================================================================
-- Behavior tick
-- ================================================================
local tick_accum = 0
minetest.register_globalstep(function(dtime)
	if botmatch.finished then return end
	botmatch.hook_game_mode()
	tick_accum = tick_accum + dtime
	if tick_accum < 0.5 then return end
	local dt = tick_accum
	tick_accum = 0

	if rawget(_G, "game_mode") and game_mode.state.match_active and botmatch.behave then
		-- Round-robin action order: a fixed iteration order would give the
		-- first bot a systematic first-strike advantage (measurable side bias).
		botmatch.tick_n = (botmatch.tick_n or 0) + 1
		local n = #botmatch.bot_order
		for i = 0, n - 1 do
			local name = botmatch.bot_order[(botmatch.tick_n + i - 1) % n + 1]
			local bot = botmatch.bots[name]
			if botmatch.is_connected(name) and not bot.dead then
				botmatch.safe("behavior:" .. name, botmatch.behave, name, dt)
			end
		end
	end
end)

minetest.register_on_mods_loaded(function()
	minetest.log("action", string.format(
		"[botmatch] soak harness ONLINE: %d bots, %d matches, seed %d%s",
		botmatch.config.bots, botmatch.config.matches, botmatch.config.seed,
		botmatch.config.mob_mode and " [MOB MODE]" or ""))
	minetest.after(1, botmatch.start_run)
end)

-- Load-time include: entity registration needs the mod-load context
-- (get_current_modname) that a runtime dofile lacks.
if botmatch.config.mob_mode then
	dofile(botmatch.modpath .. "/mob_player.lua")
end
