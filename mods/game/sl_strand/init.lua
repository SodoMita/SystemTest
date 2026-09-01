-- ================================================================
-- sl_strand / init.lua
-- "SIMULACRUM STRAND" singleplayer mode.  Loads the strand modules,
-- registers the runtime hooks (join / leave / phase), and exposes a
-- small set of /sl_strand_* commands for solo play and testing.
--
-- The core machine (state/trust/vote/wave/core) is designed to be
-- testable headless via tests/strand_test.lua; this file only wires it
-- into the game world and onto the existing bot/ghost scaffolding.
-- ================================================================

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- The strand modules define the global `strand` table and its methods.
dofile(modpath .. "/strand_state.lua")
dofile(modpath .. "/strand_trust.lua")
dofile(modpath .. "/strand_vote.lua")
dofile(modpath .. "/strand_wave.lua")
dofile(modpath .. "/strand_core.lua")
dofile(modpath .. "/strand_ledger.lua")
dofile(modpath .. "/strand_nodes.lua")
dofile(modpath .. "/strand_items.lua")

-- Active singleplayer run: the real player plus (up to) 5 crew-bots.
-- We reuse aaa_botmatch's fake-player surface when it's enabled for the
-- ambient crew; otherwise the bots live purely in strand state and the
-- runtime supplies the player's actions.
strand.active_player = nil
strand.real_player_is_echo = false

-- ---------------------------------------------------------------
-- Solo entry point: start (or continue) a strand run.
-- ---------------------------------------------------------------
function strand.start_solo(seed)
	if strand.run and strand.run.active then
		return nil, "a strand run is already active"
	end
	local run = strand.start_run(seed)
	strand.run = run
	return run
end

function strand.stop_solo()
	strand.run = nil
	return true
end

-- Feed one action from the player into the live run, then broadcast a
-- bite-sized identity-safe status line.
function strand.do_solo(action)
	local run = strand.run
	if not run then return nil, "no active strand run" end
	local result, extra = strand.turn(run, action)
	if result ~= nil then
		strand.broadcast_status(run)
	end
	return result, extra
end

function strand.broadcast_status(run)
	local gm = rawget(_G, "game_mode")
	local line = "[Strand] " .. strand.describe_run(run)
	if gm and gm.broadcast then gm.broadcast(line) else minetest.chat_send_all(line) end
end

-- ---------------------------------------------------------------
-- Runtime hooks
-- ---------------------------------------------------------------
minetest.register_on_joinplayer(function(player)
	if strand.run and not strand.run.active then strand.run = nil end
end)

-- World-gen hook: materialise the pod arena once.  Reuses the existing
-- deterministic arena builder when present; otherwise logs a hint.
minetest.register_on_generated(function(minp, maxp)
	if strand._arena_built then return end
	local gm = rawget(_G, "game_mode")
	if gm and gm.build_test_arena then
		strand._arena_built = true
		gm.build_test_arena({ x = 0, y = 0, z = 0 })
	end
end)

-- ---------------------------------------------------------------
-- Chat commands (solo control)
-- ---------------------------------------------------------------
minetest.register_chatcommand("sl_strand_start", {
	params = "[seed]",
	description = "Start a Simulacrum Strand singleplayer run",
	func = function(name, param)
		local seed = tonumber(param) or nil
		local run, err = strand.start_solo(seed)
		if not run then return false, tostring(err) end
		strand.active_player = name
		return true, "Strand begun. " .. strand.describe_run(run)
	end,
})

minetest.register_chatcommand("sl_strand_act", {
	params = "<action>",
	description = "Issue a strand action (read_tell/confide/observe/build/vote/choose/reveal)",
	func = function(name, param)
		local a = minetest.deserialize("return " .. param) or {}
		local result, extra = strand.do_solo(a)
		if result == nil then return false, tostring(extra) end
		local msg = strand.describe_result(result)
		-- When the action closed the run, show the Chain Ledger settlement.
		local run = strand.run
		if run and not run.active and run.ledger_result then
			msg = msg .. "\n" .. strand.describe_settlement(run.ledger_result)
		end
		return true, msg
	end,
})

-- Resulters for the console (kept small so they are human-readable).
function strand.describe_result(result)
	if type(result) ~= "table" then return tostring(result) end
	if result.message then return result.message end
	if result.read then return result.read end
	if result.wave then
		return string.format("Night %d: %d horde vs %d defense -> %s (Core %d)",
			result.wave.night, result.wave.scale, result.wave.defense,
			result.wave.outcome, result.wave.integrity)
	end
	return "ok"
end

minetest.register_chatcommand("sl_strand_status", {
	description = "Show the current strand run status",
	func = function()
		local run = strand.run
		if not run then return false, "no active run" end
		local msg = strand.describe_run(run)
		local l = strand.ledger_summary()
		msg = msg .. "\n[Chain] score " .. l.score .. " · debt " .. l.debt ..
			" · runs " .. l.runs .. " (" .. l.wins .. " wins) · phantoms " .. l.phantom_bosses
		return true, msg
	end,
})

minetest.register_chatcommand("sl_strand_ledger", {
	description = "Show the Chain Ledger (score, debt, named endings, flags)",
	func = function()
		local l = strand.ledger_summary()
		local endings = {}
		for id, n in pairs(l.endings) do
			local e = strand.ENDINGS[id]
			endings[#endings + 1] = (e and e.title or id) .. " x" .. n
		end
		table.sort(endings)
		local flags = {}
		for f, n in pairs(l.flags) do
			flags[#flags + 1] = f .. " x" .. n
		end
		table.sort(flags)
		return true, string.format(
			"CHAIN LEDGER\nScore %d · Debt %d · Runs %d (%d wins) · Best nights %d · Phantoms %d\nEndings: %s\nFlags: %s",
			l.score, l.debt, l.runs, l.wins, l.best_nights, l.phantom_bosses,
			#endings > 0 and table.concat(endings, ", ") or "none yet",
			#flags > 0 and table.concat(flags, ", ") or "none yet")
	end,
})

minetest.register_chatcommand("sl_strand_stop", {
	description = "Abort the active strand run",
	func = function()
		strand.stop_solo()
		return true, "Strand stopped."
	end,
})

-- ---------------------------------------------------------------
-- Dialogue scenes (vote theatre).  Registered only if the dialogue mod
-- is present; a no-op otherwise so the headless test has no heavy
-- dependency.
-- ---------------------------------------------------------------
local dialogue_mod = rawget(_G, "dialogue")
if dialogue_mod and dialogue_mod.register_scene and dialogue_mod.yaml then
	local function register_yaml(path)
		local ok, data = pcall(dialogue_mod.yaml.load_file, path)
		if ok and type(data) == "table" then
			local scene = data.scene or data.title or "strand_scene"
			dialogue_mod.register_scene(scene, data)
		end
	end
	local dd = modpath .. "/dialogues"
	local files = minetest.get_dir_list(dd, false) or {}
	for _, f in ipairs(files) do
		if f:lower():sub(-5) == ".yaml" or f:lower():sub(-4) == ".yml" then
			register_yaml(dd .. "/" .. f)
		end
	end
end

minetest.log("action", "[sl_strand] Simulacrum Strand singleplayer mode loaded.")
