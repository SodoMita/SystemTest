-- ================================================================
-- THE WHISPER — Possessed Betrayer voice channel
-- (Melody design: docs/melody_whisper_spec.md)
--
-- An evil ghost may possess a LIVING BODY, not just an object. The
-- ghost-chat seal applies to the ghost; a body the ghost wears is a
-- loophole. The Betrayer (the vessel) is NOT told "you are possessed."
-- The ghost gets ONE whispering lie-channel per possession; the vessel
-- hears BOTH sides (complicit, not a puppet). The living exorcise a
-- Betrayer the same way they exorcise an object: two punches.
--
-- Ownership: this file is additive to sl_modebase. It does NOT edit
-- WP5's dm_system.lua; it reuses the same SECURE LINK color language
-- and the same 300-char / trim rules, but routes its own chat_send_player
-- calls so the sender can be redacted (a normal DM never redacts). It
-- adds NO cross-package edits.
-- ================================================================

local S = game_mode.S
local state = game_mode.state

-- Betrayal registry: [ghost_name] = { vessel = <player>, whispers = 0, until_time }
state.betrayal = state.betrayal or {}

-- The ghost's single lie-channel. Redacted sender, whisper audio, and
-- an audible echo to the vessel. Reuses the shipped DM formspec/color
-- language; the ONLY real subtraction from a normal DM is the sender
-- is never a clean player tag.
local function ghost_whisper(ghost_name, target_name, message)
	if not ghost_name or not target_name or not message then
		return false, S("Invalid whisper parameters.")
	end
	local pl = game_mode.get_player_state(ghost_name)
	if not pl or pl.phase ~= "evil_ghost" then
		return false, S("Only a revived evil ghost can whisper.")
	end
	if not state.match_active then
		return false, S("The whisper is silent outside a live match.")
	end

	local possession = state.betrayal[ghost_name]
	if not possession then
		return false, S("You are not wearing a body to whisper through.")
	end
	if possession.whispers >= 1 then
		return false, S("This body has already carried your one voice. It is spent.")
	end

	-- Target must be a living player (never the void, never the un-sealed).
	local t_pl = game_mode.get_player_state(target_name)
	if not t_pl or t_pl.phase ~= "alive" then
		return false, S("Your words land on nothing. Choose the living.")
	end

	-- Length + trim (mirror dm_system rules).
	if message.trim then
		message = message:trim()
	else
		message = message:match("^%s*(.-)%s*$") or ""
	end
	if message == "" then
		return false, S("A whisper carries nothing.")
	end
	if #message > 300 then
		return false, S("A whisper is short. (@1 chars max)", "300")
	end

	-- Spend the one voice.
	possession.whispers = possession.whispers + 1

	-- Garbled sender: never a clean tag, preserve identity-neutrality.
	-- (Alphanumeric + underscore only, so it is unambiguous to string.find
	-- and never reads as a player name. [REDACTED] was rejected: brackets
	-- are a Lua pattern character class.)
	local garbled = "SEALED_SOURCE"

	-- To the target: the lie lands as a filthy little DM.
	minetest.chat_send_player(target_name, minetest.colorize("#ff00ff",
		S("[SECURE LINK] @1 -> You: ", garbled)) .. minetest.colorize("#ffffff", message))

	-- To the vessel: audible echo (complicit, not a puppet).
	minetest.chat_send_player(possession.vessel, minetest.colorize("#aa00aa",
		S("[SECURE LINK] your body says -> @1: \"@2\"",
			target_name, message)))

	-- The ghost's own confirmation.
	minetest.chat_send_player(ghost_name, minetest.colorize("#ff00ff",
		S("[SECURE LINK] You whisper through @1 to @2.",
			possession.vessel, target_name)))

	-- The one new audio identity: a low whisper, not a bright click.
	-- (Reuses radio_static.ogg — the low-spec-honest choice; a ghost
	-- that whispers but makes the shiny `click` sound would break tone.)
	minetest.sound_play("radio_static", { to_player = target_name, gain = 0.8 }, true)

	minetest.log("action", string.format(
		"[game_mode][WHISPER] %s (via %s) -> %s: %s",
		ghost_name, possession.vessel, target_name, message))
	return true
end
game_mode.ghost_whisper = ghost_whisper

-- Possess a living body. Expensive, one concurrent body per ghost, and
-- the vessel stays visually identical (GDD:106 intact).
function game_mode.possess_player(ghost_name, vessel_name)
	if not ghost_name or not vessel_name then return false, S("Invalid possession.") end
	if not state.match_active then
		return false, S("Possession only works during an active match.")
	end

	local g_pl = game_mode.get_player_state(ghost_name)
	if not g_pl or g_pl.phase ~= "evil_ghost" then
		return false, S("Only a revived evil ghost can possess a body.")
	end
	if state.betrayal[ghost_name] then
		return false, S("You already carry one body.")
	end
	-- One concurrent possession total: if the ghost currently holds an
	-- OBJECT (possession_pos is a node hash, not a "betrayal:" marker),
	-- they cannot also slip into a body.
	if g_pl.possession_pos and not g_pl.possession_pos:find("betrayal:", 1, true) then
		return false, S("You already hold an object. Release it before reaching into a body.")
	end

	local pl = game_mode.get_player_state(vessel_name)
	-- Must be a living beacon-team player, not already possessed, not a ghost.
	if pl.phase ~= "alive" then
		return false, S("That body is not walking among the living.")
	end
	if not game_mode.is_beacon_team(pl.team or "") then
		return false, S("You can only slip into a body on the beacon teams.")
	end
	for _, b in pairs(state.betrayal) do
		if b.vessel == vessel_name then
			return false, S("That body is already spoken through.")
		end
	end

	-- Costly: a body is worth more than a door. Hard cooldown.
	local now = game_mode.now()
	if (g_pl.possession_ready_at or 0) > now then
		return false, S("The focus is still recharging (@1 s).",
			tostring(math.ceil(g_pl.possession_ready_at - now)))
	end

	-- Body possession eats the same one-concurrent slot + a longer
	-- ready-time than object possession. The vessel feels nothing.
	state.betrayal[ghost_name] = {
		vessel = vessel_name,
		whispers = 0,
		until_time = now + game_mode.POSSESSION_DURATION,
	}
	g_pl.possession_pos = "betrayal:" .. ghost_name
	g_pl.possession_ready_at = now + (game_mode.POSSESSION_DURATION
		+ (game_mode.POSSESSION_COOLDOWN or 45))

	-- Identity-neutral broadcast; the vessel is NOT told they are possessed.
	game_mode.broadcast(S("Something has reached into a body."))
	minetest.sound_play("alert", { to_player = vessel_name, gain = 0.6 })
	minetest.log("action", string.format("[game_mode] %s possessed body %s",
		ghost_name, vessel_name))
	return true
end

-- Release a body possession independently (exorcism, death, match end).
function game_mode.release_betrayal(ghost_name, reason)
	local possession = state.betrayal[ghost_name]
	if not possession then return false end
	state.betrayal[ghost_name] = nil
	local g_pl = game_mode.get_player_state(ghost_name)
	if g_pl and g_pl.possession_pos == "betrayal:" .. ghost_name then
		g_pl.possession_pos = nil
	end
	minetest.log("action", string.format("[game_mode] betrayal released (%s)",
		reason or "expired"))
	return true
end

-- Purge every body possession. Wired into match end via the existing
-- clear_all_possession wrapper so the reset path stays single-source.
function game_mode.clear_all_betrayal()
	for ghost_name in pairs(state.betrayal) do
		game_mode.release_betrayal(ghost_name, "purged")
	end
	-- Clean reset: no vessel/whisper bookkeeping survives a match.
	for _, pl in pairs(state.players) do
		if pl.possession_pos and pl.possession_pos:find("betrayal:") then
			pl.possession_pos = nil
		end
	end
end

-- Additive wrapper: the match-end reset already calls clear_all_possession,
-- so betrayal rides the same single call site (no new cross-package hook).
local base_clear_all_possession = game_mode.clear_all_possession
function game_mode.clear_all_possession()
	base_clear_all_possession()
	game_mode.clear_all_betrayal()
end

-- Body possessions expire on the same 1 Hz tick as object possessions.
-- Additive wrapper over game_mode.possession_step (owned by nodes.lua) —
-- we read state.betrayal and release expired betrayals, then defer to the
-- base tick so no behavior is replaced.
local base_possession_step = game_mode.possession_step
function game_mode.possession_step(dtime)
	-- Expire body possessions whose window closed (or match no longer live).
	local now = game_mode.now()
	for ghost_name, possession in pairs(state.betrayal) do
		if (not state.match_active) or now >= (possession.until_time or 0) then
			game_mode.release_betrayal(ghost_name, "expired")
		end
	end
	base_possession_step(dtime)
end

-- Living exorcism: two punches drive the ghost out of the vessel.
-- A Betrayer is a BODY (a player), so the living exorcise it by punching
-- the PLAYER, not a node. A vessel cannot exorcise themselves — only
-- another living soul can drive it out (otherwise the "proof" is free).
minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch,
	tool_capabilities, dir, damage)
	if not player or not hitter then return end
	local vessel = player:get_player_name()
	local hitter_name = hitter:get_player_name()

	for ghost_name, possession in pairs(state.betrayal) do
		if possession.vessel == vessel then
			-- No self-exorcism: the vessel cannot punch itself free.
			if vessel == hitter_name then
				minetest.chat_send_player(hitter_name,
					S("You cannot drive it out of yourself. Only another living soul can."))
				return
			end

			local hitter_pl = game_mode.get_player_state(hitter_name)
			if not hitter_pl or hitter_pl.phase ~= "alive" then
				minetest.chat_send_player(hitter_name,
					S("Only the living can drive a presence out of a body."))
				return
			end

			possession._hits = (possession._hits or 0) + 1
			if possession._hits < (game_mode.POSSESSION_EXORCISM_HITS or 2) then
				minetest.chat_send_player(hitter_name,
					S("The body resists. (@1/@2)",
						tostring(possession._hits),
						tostring(game_mode.POSSESSION_EXORCISM_HITS or 2)))
				minetest.sound_play("click", { to_player = hitter_name, gain = 0.5 })
				return
			end

			local g_pl = game_mode.get_player_state(ghost_name)
			if g_pl then
				g_pl.possession_ready_at = game_mode.now()
					+ (game_mode.POSSESSION_EXORCISM_PENALTY or 30)
			end
			game_mode.release_betrayal(ghost_name, "exorcised")
			minetest.chat_send_player(vessel,
				S("The presence is gone. It was in you the whole time."))
			minetest.chat_send_player(hitter_name, S("You drove it out. They are free."))
			minetest.sound_play("default_tool_break", { to_player = hitter_name, gain = 0.5 })
			return
		end
	end
end)

-- Release on leave, so a departed Betrayer doesn't keep a ghost's voice alive.
minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	for ghost_name, possession in pairs(state.betrayal) do
		if possession.vessel == name then
			game_mode.release_betrayal(ghost_name, "vessel left")
		end
	end
end)

-- The ghost's whisper is deliberately NOT a chatcommand. Ghost chat is
-- sealed; a typed /command is a leak surface — discoverable, and it sits
-- in the same command space as the living DM aliases (/sl_whisper at
-- dm_system.lua:231), which is exactly the collision Carmack flagged.
-- The channel is an EVENT the ghost opens while it wears a body, never a
-- typed command. Carmack's catch accepted: the /sl_whisper_ghost command
-- is removed.
--
-- NOTE (honest state): the whisper is exposed as an API (game_mode
-- .ghost_whisper) and driven directly by tests/smoke_test.lua PHASE 10c.
-- A live in-world trigger — the possession-focus on_use opening the
-- whisper when the ghost is already wearing a body — is the next build
-- step and is NOT yet wired. A command must never come back.

-- ================================================================
-- LIVE TRIGGER — the whisper is an EVENT, opened through the possession
-- focus, NOT a typed command.
--
-- Carmack's house style: formspec, rendered on event, never per-tick.
-- The ghost, while it already wears a body (state.betrayal[ghost]),
-- aims the possession focus at a LIVING player and uses it. That opens
-- a bare whisper formspec ([SECURE LINK] house style); submitting it
-- spends the ghost's ONE voice. This wires the focus ADDITIVELY — the
-- original on_use (node possession) is preserved and only refrained
-- from when the ghost is wearing a body and pointing at a person.
-- ================================================================
local FOCUS_NAME = game_mode.modname .. ":possession_focus"
local WHISPER_FORM = "sl_modebase:whisper"

-- Build the whisper formspec: target + message, minimal chrome.
local function whisper_formspec(target_name)
	return "formspec_version[4]" ..
		"size[7,4.5]" ..
		"label[0.4,0.6;" .. S("Whisper to @1", target_name) .. "]" ..
		"textarea[0.4,1.0,6.2,2.4;whisper_msg;" .. S("One voice. Spend it.") .. "]" ..
		"button[0.4,3.6,2.8,0.8;whisper;" .. S("Whisper") .. "]" ..
		"button[3.8,3.6,2.8,0.8;no_whisper;" .. S("Keep it") .. "]"
end

-- Wire the trigger on the already-registered possession focus. whisper.lua
-- loads after content.lua (init.lua), so the tool def exists here.
local focus_def = minetest.registered_tools[FOCUS_NAME]
local base_on_use = focus_def and focus_def.on_use
if focus_def and base_on_use then
	focus_def.on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() then return itemstack end
		local name = user:get_player_name()

		-- Wearing a body? Then this focus-use is a WHISPER, if aimed at a
		-- living player. Otherwise deferred to node possession below.
		local possession = state.betrayal[name]
		if possession then
			local t_pl = game_mode.get_player_state(possession.vessel)
			if pointed_thing and pointed_thing.type == "object"
				and pointed_thing.ref and pointed_thing.ref:is_player() then
				local target = pointed_thing.ref:get_player_name()
				-- The vessel cannot whisper to themselves; the whisper is a
				-- lie TO someone else, and one voice per possession.
				if target ~= possession.vessel and possession.whispers < 1 then
					if t_pl and t_pl.phase ~= "alive" then
						minetest.chat_send_player(name, S("The body is not among the living."))
						return itemstack
					end
					minetest.show_formspec(name,
						WHISPER_FORM .. ":" .. target, whisper_formspec(target))
					return itemstack
				end
				-- Already spent, or aiming at the vessel: explain, don't leak.
				if possession.whispers >= 1 then
					minetest.chat_send_player(name, S("This body has already carried your one voice."))
					return itemstack
				end
			end
		end

		-- Not a whisper: fall through to the standard node possession.
		return base_on_use(itemstack, user, pointed_thing)
	end
end

-- Receive the whisper formspec submission.
minetest.register_on_player_receive_fields(function(player, formname, fields)
	local target = formname:match("^" .. WHISPER_FORM .. ":([%w_%-]+)$")
	if not target or not player then return end
	local name = player:get_player_name()
	if fields.no_whisper ~= nil then
		minetest.chat_send_player(name, S("You keep the words in the dark."))
		return
	end
	if fields.whisper == nil and not fields.whisper_msg then return end

	-- The ghost's own confirmation lives in ghost_whisper; only spend if
	-- the ghost is still wearing this body.
	local ok, err = game_mode.ghost_whisper(name, target, fields.whisper_msg or "")
	if not ok then
		minetest.chat_send_player(name, err or S("The whisper failed."))
	end
end)
