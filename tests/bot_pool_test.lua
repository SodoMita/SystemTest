-- ================================================================
-- tests/bot_pool_test.lua
-- Smoke test for the runtime bot-pool helpers added in
-- mods/game/aaa_botmatch. Verifies that add / remove / clear /
-- list_pool_lines work end-to-end with a synthetic mob_mode session
-- and the engine stub.
--
-- Run: lua5.1 tests/bot_pool_test.lua
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

-- Stub engine bits the harness reads but the engine-stub doesn't ship.
if not minetest.get_version then
	function minetest.get_version() return { string = "stub" } end
end

-- Force mob_mode and enable on before loading the harness.
-- The stub's minetest.settings uses :get_bool, so the values must be
-- Lua booleans (not strings) for the get_bool == true check to pass.
minetest.settings:set("sl_botmatch.enabled", true)
minetest.settings:set("sl_botmatch.mob_mode", true)
minetest.settings:set("sl_botmatch.bots", "0") -- start with no bots; admin adds them

H.current_modname = "aaa_botmatch"
H.modpaths.aaa_botmatch = "mods/game/aaa_botmatch"
H.modpaths.aaa_botmatch_fake = "mods/game/aaa_botmatch"
local ok, err = pcall(dofile, "mods/game/aaa_botmatch/init.lua")
check(ok, "botmatch harness loads" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then os.exit(1) end

-- The harness schedules start_run() 1s after on_mods_loaded; we don't
-- want it running during this unit test, so we override the auto-
-- start path. We also stub spawn_mob_body since the stub engine has
-- no entity registry.
botmatch.config.bots = 0
function botmatch.spawn_mob_body(name, bot)
	botmatch.mobs = botmatch.mobs or {}
	botmatch.mobs[name] = bot
end

-- Block the on_mods_loaded timer so start_run doesn't fire.
botmatch.start_run = function() end
-- Clear out the harness's auto-seeded pool (start_run never ran).
botmatch.pool = botmatch.pool or {}

local function fresh()
	botmatch.pool = {}
	botmatch.bots = {}
	botmatch.bot_order = {}
	botmatch.connected = {}
	botmatch.mobs = {}
	botmatch.current = nil
	-- botmatch.fake_player is shared; ensure the helper works.
end

-- === add_bot ===
fresh()
local ok_a, err_a = botmatch.add_bot("bot_alpha", "beacon_a", false)
check(ok_a, "add_bot returns ok on first call")
check(botmatch.pool[1] and botmatch.pool[1].name == "bot_alpha", "pool entry stored")

local ok_dup, err_dup = botmatch.add_bot("bot_alpha", "beacon_a", false)
check(not ok_dup, "duplicate add rejected")
check(err_dup and err_dup:find("already"), "duplicate error message is descriptive")

local ok_team, err_team = botmatch.add_bot("bot_beta", "red", false)
check(not ok_team, "invalid team rejected")
check(err_team and err_team:find("beacon_a or beacon_b"), "team error mentions allowed values")

local ok_empty, err_empty = botmatch.add_bot("", "beacon_a", false)
check(not ok_empty, "empty name rejected")

-- Pool cap
fresh()
for i = 1, botmatch.POOL_MAX do
	botmatch.add_bot("bot" .. i, i % 2 == 1 and "beacon_a" or "beacon_b", false)
end
local ok_over, err_over = botmatch.add_bot("bot_full", "beacon_a", false)
check(not ok_over, "pool at max rejects further add")
check(err_over and err_over:find("full"), "pool-full error is descriptive")

-- === remove_bot ===
fresh()
botmatch.add_bot("bot_alpha", "beacon_a", false)
botmatch.add_bot("bot_beta", "beacon_b", false)
local ok_r, err_r = botmatch.remove_bot("bot_alpha")
check(ok_r, "remove_bot returns ok")
check(#botmatch.pool == 1, "pool size decreased")
check(botmatch.pool[1].name == "bot_beta", "remaining entry is the one we kept")

local ok_rg, err_rg = botmatch.remove_bot("bot_zeta")
check(not ok_rg, "remove unknown bot rejected")

-- === set_team ===
fresh()
botmatch.add_bot("bot_alpha", "beacon_a", false)
local ok_t, err_t = botmatch.set_team("bot_alpha", "beacon_b")
check(ok_t, "set_team returns ok")
check(botmatch.pool[1].team == "beacon_b", "team was updated")

local ok_tb, err_tb = botmatch.set_team("bot_alpha", "purple")
check(not ok_tb, "set_team rejects invalid team")

local ok_tn, err_tn = botmatch.set_team("bot_zeta", "beacon_a")
check(not ok_tn, "set_team rejects unknown bot")

-- === list_pool_lines ===
fresh()
local lines_empty = botmatch.list_pool_lines()
check(#lines_empty == 0, "empty pool yields empty list")
botmatch.add_bot("bot_alpha", "beacon_a", false)
botmatch.add_bot("bot_beta", "beacon_b", false)
local lines_full = botmatch.list_pool_lines()
check(#lines_full == 2, "list has both entries")
check(lines_full[1]:find("bot_alpha") and lines_full[1]:find("beacon_a"),
	"first line names bot_alpha and beacon_a")

-- === clear_bots ===
botmatch.clear_bots()
check(#botmatch.pool == 0, "clear_bots empties the pool")

-- === mid-match guard ===
fresh()
botmatch.current = { id = 1 } -- simulate a match in progress
local ok_mid, err_mid = botmatch.add_bot("bot_alpha", "beacon_a", false)
check(not ok_mid, "add blocked during match")
check(err_mid and err_mid:find("during a match"), "mid-match error mentions 'during a match'")
botmatch.current = nil

-- === apply_pool (integration) ===
fresh()
botmatch.add_bot("bot_alpha", "beacon_a", false)
botmatch.add_bot("bot_beta", "beacon_b", false)
-- Pre-seed game_mode stubs that apply_pool reads.
game_mode = {
	state = { teams = { beacon_a = { hp = 100 }, beacon_b = { hp = 100 } },
		settings = {}, win_conditions = { elimination = true } },
	players = {},
}
function game_mode.get_player_state(n)
	if not game_mode.players[n] then
		game_mode.players[n] = { team = nil, role = nil, eliminated = false, phase = "lobby" }
	end
	return game_mode.players[n]
end
function game_mode.broadcast(_) end
-- Stub fake_player.new so apply_pool doesn't try to call into a missing file.
package.loaded["aaa_botmatch.fake_player"] = nil
-- Reuse the one already loaded into our runtime.
botmatch.apply_pool()
check(#botmatch.connected == 2, "apply_pool connected both bots")
check(botmatch.bots["bot_alpha"] ~= nil, "bot_alpha ref stored")
check(botmatch.bots["bot_beta"] ~= nil, "bot_beta ref stored")
check(game_mode.get_player_state("bot_alpha").team == "beacon_a", "alpha team applied")
check(game_mode.get_player_state("bot_beta").team == "beacon_b", "beta team applied")

-- apply_pool re-applied to existing connected bots shouldn't double-spawn.
local before = #botmatch.bot_order
botmatch.apply_pool()
check(#botmatch.bot_order == before, "apply_pool is idempotent on connected bots")

-- Adding a third bot to the pool, then apply_pool, should add it.
botmatch.add_bot("bot_gamma", "beacon_a", false)
botmatch.apply_pool()
check(#botmatch.connected == 3, "apply_pool spawns new pool entries")
check(botmatch.bots["bot_gamma"] ~= nil, "bot_gamma ref stored")

-- Removing from pool then apply_pool despawns.
botmatch.remove_bot("bot_gamma")
botmatch.apply_pool()
check(#botmatch.connected == 2, "apply_pool despawns pool removals")
check(botmatch.bots["bot_gamma"] == nil, "bot_gamma ref cleared")

-- ================================================================
-- Formspec smoke: get_matchmaking_formspec doesn't blow up when
-- botmatch is loaded and mob_mode is true. We stub the S() helper
-- and a couple of game_mode calls.
-- ================================================================
H.current_modname = "sl_modebase"
-- The matchmaking formspec reads game_mode.modname (for the lobby
-- terminal node id). Provide the minimum surface so the file loads.
game_mode = game_mode or {}
game_mode.modname = "sl_modebase"
game_mode.S = function(s, ...) return s end
game_mode.state = game_mode.state or {
	teams = { beacon_a = { hp = 100 }, beacon_b = { hp = 100 } },
	settings = { beacon_hp = 100, mm_auto_assign = true, auto_start = false },
	win_conditions = { elimination = true, objective = false },
	monster_master = { player = nil },
	players = {},
	match_active = false,
}
function game_mode.get_player_state(n)
	game_mode.state.players = game_mode.state.players or {}
	if not game_mode.state.players[n] then
		game_mode.state.players[n] = { team = nil, role = nil, eliminated = false, phase = "lobby" }
	end
	return game_mode.state.players[n]
end
function game_mode.get_team_label(t) return t end
function game_mode.broadcast(_) end
function game_mode.set_monster_master(_) end
function game_mode.start_new_match(_) return true end
function game_mode.begin_ready_check(_) return true end
function game_mode.end_match(_, _) end

local ok_mm, err_mm = pcall(dofile, "mods/game/sl_modebase/matchmaking.lua")
check(ok_mm, "matchmaking.lua loads" .. (ok_mm and "" or (" -> " .. tostring(err_mm))))

-- ================================================================
-- Chat command: /sl_bots — every subcommand at least parses and
-- returns without raising. We test the function directly because
-- the engine stub doesn't dispatch chat messages.
-- ================================================================
local cmd = minetest.registered_chatcommands.sl_bots
check(type(cmd) == "table", "/sl_bots chat command registered")
check(cmd.privs and cmd.privs.sl_admin == true, "/sl_bots requires sl_admin")
check(cmd.func ~= nil, "/sl_bots has a func")

-- /sl_bots list (empty)
fresh()
local ok_l, msg_l = cmd.func("admin", "list")
check(ok_l, "list returns ok on empty pool")
check(msg_l:find("empty"), "list reports empty pool")

-- /sl_bots add <name> <team>
local ok_add, msg_add = cmd.func("admin", "add bot_eve beacon_a")
check(ok_add, "/sl_bots add returns ok")
check(botmatch.pool[1] and botmatch.pool[1].name == "bot_eve", "new bot in pool")
check(botmatch.bots["bot_eve"] ~= nil, "new bot is connected (live spawn)")

-- /sl_bots list (now non-empty)
local ok_l2, msg_l2 = cmd.func("admin", "list")
check(ok_l2 and msg_l2:find("bot_eve") and msg_l2:find("beacon_a"),
	"list shows the new entry")

-- /sl_bots add <team> (auto-name form)
local ok_auto, _ = cmd.func("admin", "add beacon_b")
check(ok_auto, "/sl_bots add beacon_b auto-names the bot")
check(#botmatch.pool == 2, "pool size 2 after auto-name add")

-- /sl_bots team <name> <team>
local ok_team_cmd, _ = cmd.func("admin", "team bot_eve beacon_b")
check(ok_team_cmd, "/sl_bots team succeeds")
check(botmatch.pool[1].team == "beacon_b", "team updated by /sl_bots team")

-- /sl_bots remove <name>
local ok_rm, _ = cmd.func("admin", "remove bot_eve")
check(ok_rm, "/sl_bots remove returns ok")
check(botmatch.bots["bot_eve"] == nil, "removed bot is despawned")
local found = false
for _, e in ipairs(botmatch.pool) do if e.name == "bot_eve" then found = true end end
check(not found, "removed bot no longer in pool")

-- /sl_bots clear
local ok_clear, _ = cmd.func("admin", "clear")
check(ok_clear, "/sl_bots clear returns ok")
check(#botmatch.pool == 0, "clear empties the pool")

-- /sl_bots in non-mob mode (harness still enabled). The command is
-- now registered before the enabled-gate, so it's reachable even when
-- the harness is opted out — but it still requires mob_mode = true to
-- do anything. With enabled=true and mob_mode=false, the chat
-- command should reject with a clear "requires mob_mode" message.
local saved_mob = botmatch.config.mob_mode
botmatch.config.mob_mode = false
local ok_nmob, msg_nmob = cmd.func("admin", "list")
check(not ok_nmob, "non-mob mode rejects /sl_bots")
check(msg_nmob:find("mob_mode") or msg_nmob:find("mob mode"),
	"non-mob error mentions mob mode")
botmatch.config.mob_mode = saved_mob

-- /sl_bots with harness disabled (sl_botmatch.enabled = false). The
-- command should still be REGISTERED (it lives above the enabled-gate)
-- but should reject with the "harness not enabled" error.
local saved_enabled = botmatch.enabled
botmatch.enabled = false
local ok_dis, msg_dis = cmd.func("admin", "list")
check(not ok_dis, "disabled harness rejects /sl_bots")
check(msg_dis:find("enabled"), "disabled error mentions 'enabled'")
-- And the command is still registered (Lua table) — that's the whole
-- point of moving it before the enabled-gate.
check(type(cmd) == "table", "/sl_bots is registered even when harness is disabled")
botmatch.enabled = saved_enabled

-- /sl_bots during a match
botmatch.add_bot("bot_alpha", "beacon_a", false)
botmatch.current = { id = 1 }
local ok_mid_cmd, msg_mid_cmd = cmd.func("admin", "add bot_during beacon_a")
check(not ok_mid_cmd, "mid-match add rejected")
check(msg_mid_cmd:find("match"), "mid-match error mentions match")
botmatch.current = nil

-- /sl_bots unknown subcommand
local ok_bad, msg_bad = cmd.func("admin", "frobnicate")
check(not ok_bad, "unknown subcommand rejected")
check(msg_bad:find("Unknown") or msg_bad:find("Try"),
	"unknown-subcommand error is descriptive")

print(string.format("\nRESULT: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
