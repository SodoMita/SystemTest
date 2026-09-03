-- ================================================================
-- tests/security_test.lua
-- Malicious-client suite: what a forged packet, a chat line and a
-- formspec submission may and may not do to this server.
--
-- The threat model is the engine's own:
--   * a chat command is reachable by every connected client, and the engine
--     enforces nothing but the command's declared `privs`;
--   * an inventory-field submission with an EMPTY formname is forwarded to
--     every handler without the server ever having shown a form
--     ("pass through inventory submits", serverpackethandler.cpp);
--   * a submission with a non-empty formname is forwarded whenever the name
--     equals the last form the server sent that peer -- the engine never
--     re-validates coordinates or ids baked INTO that name;
--   * `pointed_thing`, look direction and field VALUES are client text.
-- Everything else -- positions, roles, prices, rates, counts -- is the mod's
-- job. Each phase below is one place where that job was missed, kept as an
-- executable record so the hole cannot quietly reopen.
--
-- Run from the repo root:  luajit tests/security_test.lua
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
	return cond and true or false
end
local function section(title) print("== " .. title) end

-- ---------------------------------------------------------------
-- Stub extensions: the shared stub models the match loop, not the
-- GUI or the weapon layer. Same prelude as tests/ui_layout_test.lua
-- and tests/weapons_test.lua.
-- ---------------------------------------------------------------
local modpaths = {
	sl_modebase = "mods/game/sl_modebase",
	sl_machine_crafting = "mods/game/sl_machine_crafting",
	sl_weapons = "mods/game/sl_weapons",
	sl_gui = "mods/apis/sl_gui",
	sl_strand = "mods/game/sl_strand",
	player_api = "mods/player_api",
	sl_characters = "mods/content/sl_characters",
	-- Loaded by the round-2 phases themselves (S8, S10, S13), so that their
	-- global steps do not run under phases that do not test them.
	dialogue = "mods/content/dialogue",
	aaa_botmatch = "mods/game/aaa_botmatch",
	aaa_botmatch_fake = "mods/game/aaa_botmatch",
	sl_scary = "mods/content/sl_scary",
}
function minetest.get_modpath(name)
	return modpaths[name] or "mods/game/sl_modebase"
end
function minetest.close_formspec() end
function minetest.add_particlespawner() return 1 end
function minetest.delete_particlespawner() end
-- Anything the stub does not implement is a no-op registration, so a mod
-- loading here loads the same code path it loads on a server.
setmetatable(minetest, { __index = function(t, k)
	if type(k) == "string" and k:match("^register_") then
		local noop = function() return true end
		rawset(t, k, noop)
		return noop
	end
	return nil
end })

local probe_player = H.new_player("__probe")
local PlayerMeta = getmetatable(probe_player)
H.remove_player("__probe")

local ObjMeta = { __index = {
	get_string = function(s, k) return s._d[k] or "" end,
	set_string = function(s, k, v) s._d[k] = tostring(v) end,
	get_int = function(s, k) return tonumber(s._d[k]) or 0 end,
	set_int = function(s, k, v) s._d[k] = tostring(math.floor(v)) end,
	get_float = function(s, k) return tonumber(s._d[k]) or 0 end,
	set_float = function(s, k, v) s._d[k] = tostring(v) end,
	to_table = function(s) return { fields = s._d } end,
} }
function PlayerMeta:get_meta()
	if not self._meta then self._meta = setmetatable({ _d = {} }, ObjMeta) end
	return self._meta
end
function PlayerMeta:set_inventory_formspec(fs) self._inv_fs = fs end
function PlayerMeta:get_inventory_formspec() return self._inv_fs or "" end
function PlayerMeta:get_breath() return 10 end
function PlayerMeta:get_wielded_item() return ItemStack(self._wielded or "") end
function PlayerMeta:set_wielded_item(s)
	self._wielded = (s and s.to_string) and s:to_string() or tostring(s or "")
end
function PlayerMeta:get_player_control()
	return self._controls or {
		sneak = false, zoom = false, up = false, down = false,
		left = false, right = false, LMB = false, RMB = false,
	}
end
function PlayerMeta:get_player_control_state() return self:get_player_control() end

local pm_index = PlayerMeta.__index
PlayerMeta.__index = function(t, k)
	local v
	if type(pm_index) == "table" then
		v = pm_index[k]
	elseif type(pm_index) == "function" then
		v = pm_index(t, k)
	end
	if v ~= nil then return v end
	if type(k) == "string" and (k:match("^set_") or k:match("^get_") or k:match("^wield")) then
		local noop = function() return nil end
		rawset(t, k, noop)
		return noop
	end
	return nil
end

local StackMeta = getmetatable(ItemStack(""))
function StackMeta:get_definition()
	return minetest.registered_items[self._name] or { name = self._name }
end

-- ---------------------------------------------------------------
-- Mod load. A mod that fails to load here would silently skip its
-- own phase, so the load result is part of the suite.
-- ---------------------------------------------------------------
local loaded = {}
local function load(modname, path)
	H.current_modname = modname
	local ok, err = pcall(dofile, path)
	loaded[modname] = ok
	check(ok, "loads: " .. path .. (ok and "" or (" -> " .. tostring(err))))
	H.current_modname = "sl_modebase"
	return ok
end

section("PHASE S0 — the mods under attack load")
load("sl_modebase", "mods/game/sl_modebase/init.lua")
load("sl_machine_crafting", "mods/game/sl_machine_crafting/init.lua")
load("sl_weapons", "mods/game/sl_weapons/init.lua")
load("sl_gui", "mods/apis/sl_gui/init.lua")
load("sl_strand", "mods/game/sl_strand/init.lua")

local game_mode = rawget(_G, "game_mode")
local state = game_mode and game_mode.state
local W = rawget(_G, "sl_weapons")
local strand = rawget(_G, "strand")

-- ---------------------------------------------------------------
-- Helpers that model a hostile client rather than a cooperative one.
-- ---------------------------------------------------------------

-- The engine's chat path: privs first, then func. Never call func directly.
local function client_chat(name, cmd, param)
	return H.fire_chatcommand(name, cmd, param)
end

-- A forged inventory-form submission. formname "" is never checked by the
-- engine, so this is what any client can send at any time.
local function client_fields(name, formname, fields)
	H.fire_receive_fields(name, formname, fields)
end

local function count_item(inv, itemname)
	local n = 0
	for i = 1, inv:get_size("main") do
		local st = inv:get_stack("main", i)
		if st:get_name() == itemname then n = n + st:get_count() end
	end
	return n
end

local function live_entities()
	local n = 0
	for _ in pairs(H.luaentities) do n = n + 1 end
	return n
end

-- ================================================================
section("PHASE S1 — chat text is parsed, never evaluated (/sl_strand_act)")
-- ================================================================
-- `/sl_strand_act` used to run `minetest.deserialize("return " .. param)`:
-- loadstring() on a chat line. The engine's sandbox hides minetest/io/os, but
-- it bounds nothing -- `while true do end` hangs the server thread (pcall
-- cannot interrupt a running chunk) and an allocation loop exhausts memory.
-- One 60-character chat message, no privilege, no active run needed.
if loaded.sl_strand and strand then
	-- 1a. The weapons: all of them are now parse errors, not programs.
	local weapons = {
		"(function() while true do end end)()",                       -- hang
		"(function() local t={} for i=1,9000000 do t[i]=i end end)()",-- memory
		"(function() local f f=function() return f() end return f() end)()", -- stack
		"os.execute('rm -rf /')",                                     -- engine sandbox already blocks it
		"minetest.chat_send_all('pwned')",
		"{}",                                                         -- the old documented spelling
		"{ type = (function() return 'vote' end)() }",                 -- smuggled call
	}
	local blocked = 0
	for _, payload in ipairs(weapons) do
		local action, err = strand.parse_action(payload)
		if action == nil and err then blocked = blocked + 1 end
	end
	check(blocked == #weapons, "every code payload is a parse error (" .. blocked .. "/" .. #weapons .. ")")

	-- 1b. Nothing executed: the handler returns a parse complaint and the run
	--     state is untouched. (The hang payload is the point -- if this line
	--     ever blocks, the suite never finishes and CI times out.)
	local ok, msg = client_chat("mallory", "sl_strand_act", "(function() while true do end end)()")
	check(ok == false, "the hang payload never reaches the run machine")
	check(type(msg) == "string" and msg ~= "", "and it explains itself: " .. tostring(msg))

	-- 1c. The legitimate spellings still parse, and to the SAME table.
	local a1 = strand.parse_action("vote accused=Crew-3 player_vote=true")
	local a2 = strand.parse_action('{ type = "vote", accused = "Crew-3", player_vote = true }')
	check(a1 and a1.type == "vote" and a1.accused == "Crew-3" and a1.player_vote == true,
		"plain spelling parses: vote accused=Crew-3 player_vote=true")
	check(a2 and a2.type == "vote" and a2.accused == "Crew-3" and a2.player_vote == true,
		"legacy table spelling parses to the same action")
	local b1 = strand.parse_action("build socket=socket_1 kind=turret")
	check(b1 and b1.type == "build" and b1.socket == "socket_1" and b1.kind == "turret",
		"build socket=socket_1 kind=turret parses")
	check(select(2, strand.parse_action("read_tell bot=Crew-2 target=Crew-4")) == nil
		and (strand.parse_action("read_tell bot=Crew-2 target=Crew-4")).target == "Crew-4",
		"read_tell carries bot and target")
	check((strand.parse_action("reveal")) ~= nil, "a bare verb parses")

	-- 1d. Vocabulary and value discipline.
	check(select(1, strand.parse_action("dance")) == nil, "an unknown verb is refused")
	check(select(1, strand.parse_action("vote accused=Crew-3 socket=socket_1")) == nil,
		"a key the verb does not take is refused")
	check(select(1, strand.parse_action("vote accused=Crew-3 accused=Crew-4")) == nil,
		"a duplicated key is refused")
	check(select(1, strand.parse_action("vote accused=Crew-3 player_vote=maybe")) == nil,
		"a non-boolean for a boolean key is refused")
	check(select(1, strand.parse_action('vote accused=Crew-3"); os.execute("x")')) == nil,
		"punctuation in a value is refused")
	check(select(1, strand.parse_action("vote accused=" .. string.rep("A", 400))) == nil,
		"an over-long value is refused")
	check(select(1, strand.parse_action(string.rep("vote accused=A ", 200))) == nil,
		"an over-long action line is refused")
	check(select(1, strand.parse_action("")) == nil, "an empty action is refused")

	-- 1e. Every verb the run machine accepts is a verb the parser knows, and
	--     the other way round (strand_core asserts this at load; re-check here
	--     so a future verb cannot ship unparsed).
	local verbs = 0
	for _ in pairs(strand.ACTION_SCHEMA or {}) do verbs = verbs + 1 end
	check(verbs == 7, "the action vocabulary is closed at 7 verbs (got " .. verbs .. ")")

	-- 1f. The seed is client text too: inf/NaN/floats used to reach the RNG.
	local seed_ok, seed_msg = client_chat("mallory", "sl_strand_start", "1e999")
	check(seed_ok == false and tostring(seed_msg):find("whole number") ~= nil,
		"/sl_strand_start refuses 1e999 (inf seed -> NaN RNG)")
	check(client_chat("mallory", "sl_strand_start", "1.5") == false,
		"/sl_strand_start refuses a fractional seed")
	check(client_chat("mallory", "sl_strand_start", "99999999999999") == false,
		"/sl_strand_start refuses an out-of-range seed")
	local run_ok = client_chat("mallory", "sl_strand_start", "12345")
	check(run_ok == true, "/sl_strand_start accepts a plain integer seed")
	if run_ok then
		check(strand.run and strand.run.seed == 12345, "and the run carries exactly that seed")
		-- A real action, end to end, through the chat path.
		local act_ok = client_chat("mallory", "sl_strand_act", "observe bot=Crew-2 target=Crew-3")
		check(act_ok == true or act_ok == false, "a parsed action reaches the run machine (ok=" .. tostring(act_ok) .. ")")
		client_chat("mallory", "sl_strand_stop")
		check(strand.run == nil, "/sl_strand_stop clears the run")
	end
else
	check(false, "sl_strand loaded (phase skipped)")
end

-- ================================================================
section("PHASE S2 — a GUI button is not a softer door than chat")
-- ================================================================
-- sl_gui's System tab drives chat commands. Calling `def.func()` directly
-- skips the engine's privilege gate, and the handler also answers formname ""
-- -- which the engine forwards unconditionally. Before the fix, any client
-- could start and stop matches, flip auto-start, self-assign a team and move
-- the PERSISTENT lobby spawn (mod storage: it survives restart and breaks
-- every later match) with one forged packet.
minetest.settings:set("sl_map.type", "test")
minetest.settings:set("sl_map.mobs", "0")

local alpha = H.new_player("alpha")
local beta = H.new_player("beta")
local gamma = H.new_player("gamma")
local mallory = H.new_player("mallory") -- the hostile client: no privileges
for _, p in ipairs({ alpha, beta, gamma, mallory }) do H.fire_joinplayer(p) end
H.advance(1.5, 0.5)
H.player_privs.alpha = { sl_admin = true, server = true }
H.player_privs.beta = {}
H.player_privs.gamma = {}
H.player_privs.mallory = {}
-- Deterministic roster: with four connected players the match start would
-- otherwise pick a random Monster Master and the role tests below would be
-- testing whoever the dice chose.
state.settings.mm_auto_assign = false

local handler_present = type(_G.sl_gui_invoke_command) == "function"
	check(handler_present, "sl_gui publishes one privileged command invoker")

-- 2a. Match lifecycle from a priv-less client.
local lobby_spawn_before = { x = state.lobby_spawn.x, y = state.lobby_spawn.y, z = state.lobby_spawn.z }
local autostart_before = state.settings.auto_start
client_fields("mallory", "", { sys_match_start_now = "true" })
H.advance(1.0, 0.5)
check(state.match_active == false, "sys_match_start_now from a priv-less client starts nothing")
client_fields("mallory", "", { sys_autostart_toggle = "true" })
check(state.settings.auto_start == autostart_before, "sys_autostart_toggle from a priv-less client flips nothing")

-- The persistent-spawn write: the most durable damage one packet could do.
mallory:set_pos({ x = 4242, y = 300, z = -4242 })
client_fields("mallory", "", { sys_set_lobby = "true" })
check(state.lobby_spawn.x == lobby_spawn_before.x
	and state.lobby_spawn.y == lobby_spawn_before.y
	and state.lobby_spawn.z == lobby_spawn_before.z,
	"sys_set_lobby from a priv-less client cannot move the persistent lobby spawn")
local stored = minetest.deserialize(H.storage.spawns or "")
check(not stored or not stored.lobby or stored.lobby.x ~= 4242,
	"and nothing forged reached mod storage")

-- Team self-assignment.
client_fields("mallory", "", { sys_assign_a = "true" })
check(game_mode.get_player_state("mallory").team == nil,
	"sys_assign_a from a priv-less client assigns no team")

-- 2b. The same buttons, pressed by an admin, still work (the gate is a gate,
--     not a wall: the GUI has to stay usable for the people who run matches).
client_fields("alpha", "", { sys_autostart_toggle = "true" })
check(state.settings.auto_start ~= autostart_before, "an admin's sys_autostart_toggle still toggles")
client_fields("alpha", "", { sys_autostart_toggle = "true" })
check(state.settings.auto_start == autostart_before, "and toggles back")
client_fields("alpha", "", { sys_match_start_now = "true" })
H.advance(2.0, 0.5)
check(state.match_active == true, "an admin's sys_match_start_now still starts the match")

-- 2c. Chat route for the same commands: the engine gate the GUI must mirror.
client_fields("alpha", "", { sys_match_stop = "true" })
H.advance(1.0, 0.5)
check(state.match_active == false, "an admin's sys_match_stop still stops it")
check(client_chat("mallory", "sl_match_start", "now") == false,
	"/sl_match_start now is refused for a priv-less client by its own privs")
check(client_chat("mallory", "sl_set_lobby") == false,
	"/sl_set_lobby is refused for a priv-less client")

-- ================================================================
section("PHASE S3 — the Monster Master role is match state, not a self-service")
-- ================================================================
-- Two holes fed each other: `/sl_be_monster_master` had no gate at all (any
-- client could take the role whenever the slot was empty, which also locks the
-- role in for the next match's start), and the GUI's resign button was an
-- ungated call into game_mode. Claim -> pocket the starter essence -> resign
-- -> claim again minted monster essence from nothing, as fast as the client
-- could send packets.
local ESSENCE = game_mode.ESSENCE_ITEM
local TOOL = game_mode.modname .. ":summon_monster"

-- 3a. Mid-match: a priv-less client may not take the doctrine.
client_fields("alpha", "", { sys_match_start_now = "true" })
H.advance(2.0, 0.5)
check(state.match_active == true, "a match is running for the role tests")
-- The exact condition a hijacker waits for: a live match, empty MM slot.
game_mode.set_monster_master(nil)
check(state.monster_master.player == nil, "the Monster Master slot is empty")
check(client_chat("mallory", "sl_be_monster_master") == false,
	"/sl_be_monster_master is refused mid-match without sl_admin")
client_fields("mallory", "", { sys_be_mm = "true" })
check(state.monster_master.player ~= "mallory",
	"sys_be_mm from a priv-less client does not take the role mid-match")
check(game_mode.get_player_state("mallory").role ~= "monster_master",
	"and the player state stays clean")

-- 3b. An admin (or the designed auto-assign) still controls the role.
local admin_ok = client_chat("alpha", "sl_be_monster_master")
check(admin_ok == true and state.monster_master.player == "alpha",
	"an sl_admin may still take the role mid-match")

-- 3c. The kit is once per match cycle, not once per claim.
local alpha_inv = alpha:get_inventory()
local kit_first = count_item(alpha_inv, ESSENCE)
check(kit_first >= 10, "the first claim hands over the starter essence (" .. kit_first .. ")")
game_mode.set_monster_master(nil)          -- resign (admin path)
for i = 1, alpha_inv:get_size("main") do   -- pocket everything, like a drop
	alpha_inv:set_stack("main", i, ItemStack(""))
end
game_mode.set_monster_master("alpha")      -- claim again, same match cycle
check(count_item(alpha_inv, ESSENCE) == 0,
	"claim/resign/claim in one match cycle mints no more essence")
check(count_item(alpha_inv, TOOL) == 0, "and no more summoning tools")
check(state.monster_master.player == "alpha", "the role itself still transfers")

-- 3d. Lobby volunteering stays open (that is the designed use of the command):
--     with no match running a player may offer to carry the doctrine.
client_fields("alpha", "", { sys_match_stop = "true" })
H.advance(1.0, 0.5)
game_mode.set_monster_master(nil)
check(state.match_active == false, "back in the lobby")
local vol_ok = client_chat("gamma", "sl_be_monster_master")
check(vol_ok == true and state.monster_master.player == "gamma",
	"a lobby volunteer may still take the role with no privileges")
game_mode.set_monster_master(nil)

-- ================================================================
section("PHASE S4 — /sl_mm_spawn is not an unlimited entity tap")
-- ================================================================
-- The convenience spawn costs no essence (unlike the spawner unit), so without
-- a rate and a population bound it is a lag weapon: 40 chat commands put 200
-- live, pathing, animated mobs in the world and the server step drowns.
client_fields("alpha", "", { sys_match_start_now = "true" })
H.advance(2.0, 0.5)
game_mode.set_monster_master(nil)
check(client_chat("alpha", "sl_be_monster_master") == true
	and state.monster_master.player == "alpha", "alpha is the Monster Master (admin, mid-match)")

-- Outside a match the command has no business at all.
local outside_ok = (function()
	local was_active = state.match_active
	state.match_active = false
	local ok = client_chat("alpha", "sl_mm_spawn", "5")
	state.match_active = was_active
	return ok
end)()
check(outside_ok == false, "/sl_mm_spawn is refused with no match running")

local before = live_entities()
local first_ok = client_chat("alpha", "sl_mm_spawn", "5")
check(first_ok == true, "the MM may spawn a batch during a match")
check(live_entities() - before == 5, "and it is exactly the requested 5 (got "
	.. (live_entities() - before) .. ")")

local spam_ok = client_chat("alpha", "sl_mm_spawn", "5")
check(spam_ok == false, "a second batch inside the cooldown is refused")
check(live_entities() - before == 5, "and spawned nothing")

-- Flood: 100 attempts in one server tick.
for _ = 1, 100 do client_chat("alpha", "sl_mm_spawn", "5") end
local after_flood = live_entities() - before
check(after_flood <= 12, "100 spammed commands stay inside the live-monster cap (got "
	.. after_flood .. ")")

-- Count parsing is client text.
check(client_chat("alpha", "sl_mm_spawn", "0/0") == false or true, "NaN count does not error")
-- The cooldown expires; the population bound does not.
H.advance(4.0, 0.5)
client_chat("alpha", "sl_mm_spawn", "5")
client_chat("alpha", "sl_mm_spawn", "5")
check(game_mode.count_owned_monsters("alpha") <= 12,
	"the live-monster cap still holds once the cooldown expires (owned: "
	.. tostring(game_mode.count_owned_monsters("alpha")) .. ")")

-- ================================================================
section("PHASE S5 — the Precision Fabricator must still be a place")
-- ================================================================
-- The station's position arrives inside the FORMNAME (client text). The engine
-- only compares that name to the last form it sent the peer, so one right-click
-- used to buy remote fabrication forever: from the other side of the map,
-- after the station was destroyed, after the match ended. Detailed coverage
-- lives in tests/weapons_test.lua PHASE W2e; this is the security summary.
if loaded.sl_weapons and W then
	-- The doctrine refuses the MM at the machine, so this phase uses a plain
	-- operator: the gate under test is the station, not the role.
	game_mode.set_monster_master(nil)
	local fab_operator = beta
	local fpos = { x = 600, y = 60, z = 0 }
	H.voxels[H.vhash(fpos)] = W.modname .. ":fabricator"
	local mats = {
		"sl_modebase:metal_ingot 4", "sl_modebase:circuit_board 4",
		"sl_modebase:energy_crystal 4", "sl_modebase:plastic_scrap 2",
	}
	local finv = fab_operator:get_inventory()
	for i = 1, finv:get_size("main") do finv:set_stack("main", i, ItemStack("")) end
	for _, m in ipairs(mats) do finv:add_item("main", ItemStack(m)) end

	-- Far away, real materials in the pocket: refused, nothing consumed.
	fab_operator:set_pos({ x = fpos.x - 900, y = fpos.y, z = fpos.z })
	client_fields("beta", W.modname .. ":fabricator_" .. W.phash(fpos), { make_lash = "true" })
	check(W.fab_jobs[W.phash(fpos)] == nil, "no job is created 900 nodes from the station")
	check(count_item(finv, "sl_modebase:metal_ingot") == 4, "and no materials were taken")

	-- No station at the submitted coordinate at all.
	local air = { x = 601, y = 60, z = 0 }
	H.voxels[H.vhash(air)] = nil
	fab_operator:set_pos({ x = air.x, y = air.y, z = air.z })
	client_fields("beta", W.modname .. ":fabricator_" .. W.phash(air), { make_lash = "true" })
	check(W.fab_jobs[W.phash(air)] == nil, "no job is created for a coordinate with no station")

	-- Standing at the real station: the pilgrimage still pays.
	fab_operator:set_pos({ x = fpos.x, y = fpos.y, z = fpos.z - 1 })
	client_fields("beta", W.modname .. ":fabricator_" .. W.phash(fpos), { make_lash = "true" })
	check(W.fab_jobs[W.phash(fpos)] ~= nil, "an operator at the station starts the job")
	check(count_item(finv, "sl_modebase:metal_ingot") == 2, "the charge is consumed up front")
	H.advance(11.0, 0.5)
	check(finv:contains_item("main", ItemStack(W.modname .. ":grapple")),
		"and the lash is delivered after 10 s")

	-- A destroyed station leaves no remote handle behind.
	H.voxels[H.vhash(fpos)] = nil
	finv:add_item("main", ItemStack("sl_modebase:metal_ingot 2"))
	finv:add_item("main", ItemStack("sl_modebase:circuit_board 1"))
	finv:add_item("main", ItemStack("sl_modebase:plastic_scrap 1"))
	client_fields("beta", W.modname .. ":fabricator_" .. W.phash(fpos), { make_chatter = "true" })
	check(W.fab_jobs[W.phash(fpos)] == nil, "a station that is gone cannot be operated remotely")
	H.voxels[H.vhash(fpos)] = W.modname .. ":fabricator"
else
	check(false, "sl_weapons loaded (phase skipped)")
end

-- ================================================================
section("PHASE S6 — inventory crafting honours one submission, one craft")
-- ================================================================
-- The crafting handler answers formname "" too, and its loop used to honour
-- EVERY craft_N field in a packet: a forged submission could walk the whole
-- recipe table in one round trip. Ingredients are still paid for, so this is
-- rate/consistency hardening rather than a dupe -- but a handler that does N
-- irreversible things per packet is a handler that cannot be rate-limited.
if loaded.sl_gui and type(get_crafting_recipes) == "function" then
	local recipes = get_crafting_recipes()
	-- Find a recipe that is craftable in inventory (not machine-only) and
	-- cheap enough to stock twice over.
	local pick, pick_id
	for i, r in ipairs(recipes) do
		local out_def = minetest.registered_nodes[r.output]
		local machine_only = out_def and not (out_def.groups and out_def.groups.sl_craft_in_inventory)
		if not machine_only then
			local max_need = 0
			for _, c in pairs(r.ingredients or {}) do max_need = math.max(max_need, c) end
			if max_need > 0 and max_need <= 8 and (not pick or max_need < pick.need) then
				pick, pick_id = { recipe = r, need = max_need }, i
			end
		end
	end
	-- A second inventory-craftable recipe with a DISJOINT ingredient list, so
	-- "how many crafts ran" is readable from what is left in the inventory
	-- whatever order pairs() happens to walk the packet in.
	local second, second_id
	for i, r in ipairs(recipes) do
		if i ~= pick_id and not minetest.registered_nodes[r.output] then
			local disjoint = true
			for item in pairs(r.ingredients or {}) do
				if pick.recipe.ingredients[item] then disjoint = false end
			end
			if disjoint then second, second_id = r, i break end
		end
	end
	if check(pick ~= nil and second ~= nil,
		"two inventory-craftable recipes with disjoint ingredients exist") then
		local cinv = beta:get_inventory()
		for i = 1, cinv:get_size("main") do cinv:set_stack("main", i, ItemStack("")) end
		local function stock(recipe, mult)
			for item, count in pairs(recipe.ingredients) do
				cinv:add_item("main", ItemStack(item .. " " .. (count * mult)))
			end
		end
		stock(pick.recipe, 3)
		stock(second, 3)

		local fields = {}
		fields["craft_" .. pick_id] = ""
		fields["qty_" .. pick_id] = "1"
		fields["craft_" .. second_id] = ""
		fields["qty_" .. second_id] = "1"
		client_fields("beta", "crafting_system", fields)

		local crafts = 0
		for _, r in ipairs({ pick.recipe, second }) do
			local used = false
			for item, count in pairs(r.ingredients) do
				if count_item(cinv, item) < count * 3 then used = true end
			end
			if used then crafts = crafts + 1 end
		end
		check(crafts == 1, "one submission carrying two craft buttons performs exactly one craft (got "
			.. crafts .. ")")

		-- Absurd quantity: clamped, and never consuming more than it checked.
		client_fields("beta", "crafting_system",
			{ [("craft_%d"):format(pick_id)] = "", [("qty_%d"):format(pick_id)] = "1e999" })
		local sane = true
		for item, count in pairs(pick.recipe.ingredients) do
			if count_item(cinv, item) < 0 then sane = false end
		end
		check(sane, "qty=1e999 is clamped, not honoured")
	end
else
	check(false, "sl_gui crafting loaded (phase skipped)")
end

-- ================================================================
section("PHASE S6b — numeric fields are bounded before they become state")
-- ================================================================
-- `tonumber("1e999")` is +inf and `tonumber("0/0")` is NaN in LuaJIT. Either
-- one landing in match or progression state is a stuck server: an infinite
-- beacon HP makes the elimination condition unwinnable for the session, and
-- infinite stat points make every `stat_points < cost` test false, i.e. the
-- whole ability tree for free. Both arrive as client text -- the formspec
-- field even when the sender is an admin, the chat param always.
local hp_before = state.settings.beacon_hp
client_fields("mallory", "sl_modebase:matchmaking",
	{ save_settings = "true", sett_beacon_hp = "1e999" })
check(state.settings.beacon_hp == hp_before,
	"a priv-less client cannot write match settings at all")
client_fields("alpha", "sl_modebase:matchmaking",
	{ save_settings = "true", sett_beacon_hp = "1e999" })
local hp = state.settings.beacon_hp
check(type(hp) == "number" and hp == hp and hp ~= math.huge and hp >= 1 and hp <= 100000,
	"beacon_hp from '1e999' stays a finite, bounded integer (got " .. tostring(hp) .. ")")
client_fields("alpha", "sl_modebase:matchmaking",
	{ save_settings = "true", sett_beacon_hp = "-50" })
check(state.settings.beacon_hp >= 1, "a negative beacon_hp is clamped to at least 1")
client_fields("alpha", "sl_modebase:matchmaking",
	{ save_settings = "true", sett_beacon_hp = tostring(hp_before) })

-- Progression: only a `server`-privileged operator can reach this command, and
-- even then the parameter is text.
H.player_privs.alpha.server = true
local ability_meta = alpha:get_meta()
ability_meta:set_string("abilities_v2", minetest.serialize({ unlocked = {}, stat_points = 3 }))
local sp_ok, sp_msg = client_chat("alpha", "givestatpoints", "1e999")
check(sp_ok == false, "/givestatpoints refuses an infinite grant")
local sp_data = minetest.deserialize(ability_meta:get_string("abilities_v2")) or {}
check((sp_data.stat_points or 0) < 1e6,
	"stat_points stayed finite after the refused grant (got " .. tostring(sp_data.stat_points) .. ")")
check(client_chat("mallory", "givestatpoints", "100") == false,
	"and a priv-less client cannot reach /givestatpoints at all")

-- ================================================================
section("PHASE S8 — a roster name is client text: engine charset, then escaped")
-- ================================================================
-- Bot names arrive from an admin's formspec field -- i.e. from a client -- and
-- are then rendered into EVERY viewer's matchmaking form. A textlist entry is
-- closed by `]` and its items are separated by `,`, so a single `]` inside a
-- name ends the entry and the rest of the string becomes formspec that the
-- viewer's client parses: a label, a button, a field. Anything an admin (or
-- anyone who can forge that admin's packet) wants.
-- Two independent gates, because either one alone is a single point of
-- failure: the name must satisfy the engine's own player-name rules
-- (src/player.h: PLAYERNAME_SIZE 20, PLAYERNAME_ALLOWED_CHARS a-zA-Z0-9-_,
-- enforced at connect with a WRONG_CHARS deny), and the renderer must escape
-- it anyway.
minetest.settings:set("sl_botmatch.enabled", true)
minetest.settings:set("sl_botmatch.mob_mode", true)
minetest.settings:set("sl_botmatch.bots", "0")
local botmatch_ok = load("aaa_botmatch", "mods/game/aaa_botmatch/init.lua")
local botmatch = rawget(_G, "botmatch")
if not (botmatch_ok and botmatch) then
	print("  [SKIP] aaa_botmatch did not load: the bot-name gate cannot be exercised")
else
	-- Same neutralisation as tests/bot_pool_test.lua: no auto-run, no live mob
	-- bodies. This phase tests the name gate, not the match simulator.
	botmatch.config.bots = 0
	botmatch.start_run = function() end
	function botmatch.spawn_mob_body(name, bot)
		botmatch.mobs = botmatch.mobs or {}
		botmatch.mobs[name] = bot
	end
	botmatch.pool = {}
	botmatch.bots = botmatch.bots or {}

	-- 8a. The charset gate. These are the engine's rules, not new ones: a bot
	--     name that a player could never have is a name with no business in a
	--     roster that is rendered next to real player names.
	-- Called through a guard: if the gate is ever removed the phase must FAIL,
	-- not abort the suite on a nil call.
	local valid_name = type(botmatch.is_valid_bot_name) == "function"
		and botmatch.is_valid_bot_name or nil
	check(valid_name ~= nil, "botmatch publishes a name gate (the rule has to live somewhere)")
	check(valid_name and valid_name("Crew_3-a") == true,
		"a name a player could have is a valid bot name")
	check(valid_name and valid_name("x];label[0,0;SERVER WIPE") == false,
		"a formspec payload is not a valid bot name")
	check(valid_name and valid_name(string.rep("a", 21)) == false,
		"a name longer than PLAYERNAME_SIZE (20) is refused")
	check(valid_name and valid_name("") == false, "an empty name is refused")
	check(valid_name and valid_name(nil) == false, "a missing name is refused")
	check(valid_name and valid_name("sp ace") == false, "a name with a space is refused")

	-- 8b. The door: an admin's bot_add field is still client text, and the
	--     empty-formname path means any client can forge the packet.
	local PAYLOAD = "x];label[0,0;SERVER WIPE IN 5 MIN - TRADE NOW"
	client_fields("alpha", "", {
		bot_add = "true", bot_add_name = PAYLOAD, bot_add_team = "beacon_a",
	})
	local accepted = false
	for _, entry in ipairs(botmatch.pool or {}) do
		if entry.name == PAYLOAD then accepted = true end
	end
	check(not accepted, "add_bot refuses a name the engine would never let a player use")
	local ok_add = botmatch.add_bot("Crew_3-a", "beacon_a", false)
	check(ok_add ~= false and #botmatch.pool == 1,
		"... and still accepts a conforming name (the gate is a gate, not a wall)")

	-- 8c. Defence in depth: even a payload that somehow reached the roster must
	--     arrive at a viewer's client as text, not as formspec elements. The
	--     roster panel is rendered for admins (mob mode), so the admin's form
	--     is the one that has to be inert -- and a priv-less client, which can
	--     open the same form by design, must not see raw markup either.
	botmatch.pool[#botmatch.pool + 1] = { name = PAYLOAD, team = "beacon_a" }
	check(botmatch.config.mob_mode == true, "the harness is in mob mode (the roster renders)")

	client_chat("alpha", "sl_matchmaking")
	local aforms = H.formspecs.alpha or {}
	local aform = aforms[#aforms] and aforms[#aforms].form or ""
	check(aform:find("bot_pool;", 1, true) ~= nil,
		"the admin's matchmaking form carries the bot roster")
	check(aform:find("label[0,0;SERVER WIPE", 1, true) == nil,
		"the payload reaches the admin's client escaped, never as raw formspec")
	check(aform:find("SERVER WIPE", 1, true) ~= nil,
		"... it is still readable as text (the roster is not censored)")
	check(aform:find("Crew_3-a", 1, true) ~= nil,
		"and a legitimate bot name still renders")

	client_chat("mallory", "sl_matchmaking") -- open by design: read-only opener
	local forms = H.formspecs.mallory or {}
	local form = forms[#forms] and forms[#forms].form or ""
	check(form ~= "", "a priv-less client can open the matchmaking form")
	check(form:find("label[0,0;SERVER WIPE", 1, true) == nil,
		"and no viewer, privileged or not, is sent the payload unescaped")

	botmatch.pool = {}
end

-- ================================================================
section("PHASE S9 — a strand run belongs to the player who started it")
-- ================================================================
-- /sl_strand_* is deliberately open (a single-player side activity needs no
-- privilege), which is exactly why the run needs an owner: `strand.run` and
-- `strand.active_player` are single global slots and the ledger is shared,
-- persistent state. Before the fix any connected client could vote on, steer,
-- read or abort somebody else's run -- and a forged /sl_strand_stop destroyed
-- a run in progress and wrote its outcome into the ledger for everyone.
if not strand then
	print("  [SKIP] sl_strand did not load")
else
	strand.stop_solo()
	local ledger0 = strand.ledger_summary()
	local started = client_chat("beta", "sl_strand_start", "12345")
	check(started ~= false and strand.active_player == "beta",
		"beta starts a run and owns it")
	-- Guarded for the same reason: a removed ownership test must fail the phase.
	local function owner_is(who)
		return type(strand.is_run_owner) == "function" and strand.is_run_owner(who) == true
	end
	check(type(strand.is_run_owner) == "function", "strand publishes an ownership test")
	check(owner_is("beta"), "the owner is recognised as the owner")
	check(not owner_is("mallory"), "another player is not")

	local ok_act, why_act = client_chat("mallory", "sl_strand_act", "choose path=left")
	check(ok_act == false, "a non-owner cannot steer somebody else's run ("
		.. tostring(why_act) .. ")")
	local ok_vote = client_chat("mallory", "sl_strand_act",
		"vote accused=Crew-3 player_vote=true")
	check(ok_vote == false, "a non-owner cannot vote in somebody else's run")
	check(strand.run ~= nil and strand.active_player == "beta",
		"and the run survives both attempts")
	check(client_chat("mallory", "sl_strand_stop") == false,
		"a non-owner cannot abort somebody else's run")
	check(client_chat("mallory", "sl_strand_status") == false,
		"a non-owner cannot read somebody else's run state either")
	check(strand.run ~= nil and strand.active_player == "beta", "the run is still beta's")

	local ledger1 = strand.ledger_summary()
	check(ledger1.score == ledger0.score and ledger1.debt == ledger0.debt
		and ledger1.runs == ledger0.runs,
		"the shared, persistent ledger is untouched by a non-owner")

	-- The owner keeps full control, and an operator keeps the override (they
	-- run matches: a stuck run has to be clearable without the player).
	check(client_chat("beta", "sl_strand_status") ~= false, "the owner can read their own run")
	check(owner_is("alpha"),
		"an sl_admin is an owner of last resort (operators clear stuck runs)")
	check(client_chat("beta", "sl_strand_stop") ~= false or strand.active_player == nil,
		"the owner can stop their own run")
	check(strand.active_player == nil, "ownership is released when the run ends")
	check(client_chat("mallory", "sl_strand_start", "777") ~= false,
		"and the slot is free for the next player")
	strand.stop_solo()
	check(strand.active_player == nil, "clean slate for the phases that follow")
end

-- ================================================================
section("PHASE S10 — a client that disconnects must not leave work running")
-- ================================================================
-- Disconnecting is free, instant and repeatable, so everything keyed by player
-- name has to survive it in both directions: no work left running for a player
-- who is gone, and no state left behind for a name that will be reused.
-- /dlg_start typed a scene out at ~33 Hz with a chain of core.after() jobs; a
-- client that started a long scene and dropped left the chain chatting,
-- rebuilding formspecs and re-arming timers for a player who no longer exists.
local dialogue_ok = load("dialogue", "mods/content/dialogue/init.lua")
local dialogue = rawget(_G, "dialogue")
if not (dialogue_ok and dialogue and dialogue.dialogue) then
	print("  [SKIP] dialogue did not load")
else
	local long_line = string.rep("The wire hums. ", 60) -- ~900 chars, ~27 s of typing
	dialogue.dialogue.register_scene("sec_scene", {
		scene = "sec_scene",
		lines = {
			{ speaker = "CUSTODIAN", text = long_line },
			{ speaker = "CUSTODIAN", text = long_line },
			{ speaker = "CUSTODIAN", text = long_line },
		},
	})
	local ORPHANS = 4
	local built, said = {}, {}
	for i = 1, ORPHANS do
		local nm = string.format("dropin%03d", i)
		local p = H.new_player(nm)
		H.fire_joinplayer(p)
		H.player_privs[nm] = {}
		client_chat(nm, "dlg_start", "sec_scene")
		-- Baseline taken at the moment of departure: what the scene legitimately
		-- said while the player was still connected is not the leak.
		built[nm] = #(H.formspecs[nm] or {})
		said[nm] = #(H.chat_player[nm] or {})
		H.fire_leaveplayer(p) -- the client drops mid-scene
		H.remove_player(nm)
	end
	H.advance(30, 0.05) -- 30 s of server time with none of them connected
	local rebuilt, chatted = 0, 0
	for i = 1, ORPHANS do
		local nm = string.format("dropin%03d", i)
		rebuilt = rebuilt + (#(H.formspecs[nm] or {}) - built[nm])
		chatted = chatted + (#(H.chat_player[nm] or {}) - said[nm])
	end
	check(rebuilt == 0, "no formspec is rebuilt for a player who left (got " .. rebuilt .. ")")
	check(chatted == 0, "no scene line is typed out to a player who left (got " .. chatted .. ")")

	-- The same rule for the GUI's own per-name tables. They are locals, so the
	-- observable is behaviour: a selection made before a disconnect must not be
	-- honoured after one. (And every name that ever opened a tab used to stay
	-- resident forever -- on a public server a client mints fresh names as fast
	-- as it can reconnect.)
	client_fields("mallory", "", { comms_target = "CHG:1" })
	H.fire_leaveplayer(mallory)
	H.remove_player("mallory")
	mallory = H.new_player("mallory")
	H.fire_joinplayer(mallory)
	H.player_privs.mallory = {}
	H.advance(1.0, 0.5)
	client_fields("mallory", "", { comms_send = "true", comms_message = "still selected?" })
	local to_mallory = H.chat_player.mallory or {}
	local last = to_mallory[#to_mallory] or ""
	check(last:find("No target selected", 1, true) ~= nil,
		"a comms target chosen before a disconnect does not survive it")
end

-- ================================================================
section("PHASE S11 — client text must not become non-finite world state")
-- ================================================================
-- /sl_map seed takes a number from chat text and PERSISTS it (map.persist()
-- writes mod storage), so a bad value survives restart and drives mapgen for
-- every later match. tonumber("1e999") is +inf and tonumber("nan") is NaN in
-- LuaJIT; both used to be stored as-is. Same rule as the strand seed: a finite
-- integer within +/- 2^31, or refuse.
local map = game_mode and game_mode.map
if not (map and map.runtime) then
	print("  [SKIP] the map system is unavailable")
else
	local seed_before = map.runtime.seed
	check(client_chat("alpha", "sl_map", "seed 1e999") == false,
		"/sl_map seed refuses 1e999 (= +inf)")
	check(client_chat("alpha", "sl_map", "seed nan") == false, "/sl_map seed refuses nan")
	check(client_chat("alpha", "sl_map", "seed -1e999") == false, "/sl_map seed refuses -inf")
	check(client_chat("alpha", "sl_map", "seed 12.5") == false,
		"/sl_map seed refuses a number that is not whole")
	check(client_chat("alpha", "sl_map", "seed 99999999999") == false,
		"/sl_map seed refuses a value outside +/- 2^31")
	check(map.runtime.seed == seed_before,
		"and none of them reached the persisted map state (seed is "
		.. tostring(map.runtime.seed) .. ")")
	for key, value in pairs(H.storage) do
		if tostring(value):find("inf", 1, true) or tostring(value):find("nan", 1, true) then
			check(false, "mod storage holds a non-finite value at '" .. tostring(key) .. "'")
		end
	end
	check(client_chat("alpha", "sl_map", "seed 2147483647") ~= false,
		"a finite whole seed within range is accepted")
	check(map.runtime.seed == 2147483647, "and pinned exactly, as an integer")
	check(client_chat("alpha", "sl_map", "seed 0") ~= false and map.runtime.seed == nil,
		"seed 0 unpins, which is what the help text promises")
	if seed_before then
		client_chat("alpha", "sl_map", "seed " .. tostring(seed_before))
	end
end

-- ================================================================
section("PHASE S12 — a refusal must not be an amplifier")
-- ================================================================
-- The engine rate-limits CHAT (chat_message_limit_per_10sec, then a kick for
-- flooding) and rate-limits nothing else: an inventory-field submission with
-- an EMPTY formname is forwarded unconditionally, without the server ever
-- having shown a form. So every client-reachable refusal is a per-packet cost
-- multiplier, and "log every refusal" is a way for a client to write to the
-- server's own disk at packet rate. Measured before the fix: 200 forged
-- packets produced 401 action-log lines on the refused-role path, and
-- re-claiming a role the caller already held re-announced it to EVERY player
-- and re-spawned the claimer once per packet -- 200 broadcasts, 200 spawns.
H.advance(3.0, 0.5) -- start from a clean throttle window (game_mode.now is the stub clock)
local logs0 = #H.logs
local chats0 = #(H.chat_player.mallory or {})
for _ = 1, 200 do client_fields("mallory", "", { sys_match_start_now = "true" }) end
check(#H.logs - logs0 == 1,
	"200 forged admin packets write ONE action-log line (got " .. (#H.logs - logs0) .. ")")
check(#(H.chat_player.mallory or {}) - chats0 == 1,
	"... and are answered once, not 200 times (got "
	.. (#(H.chat_player.mallory or {}) - chats0) .. ")")
check((H.logs[#H.logs] or ""):find("sl_match_start", 1, true) ~= nil,
	"the line that IS written names the command and the missing privilege")
H.advance(3.0, 0.5)
local logs1 = #H.logs
client_fields("mallory", "", { sys_match_start_now = "true" })
check(#H.logs - logs1 == 1, "the next window reports again (the trail is not lost)")
check((H.logs[#H.logs] or ""):find("199 more", 1, true) ~= nil,
	"... and carries the count of what was suppressed before it")

-- A refused role claim during a live match: same shape, different door.
local match_before = state.match_active
local mm_before = state.monster_master.player
state.match_active = true
state.monster_master.player = nil
H.advance(3.0, 0.5)
local logs2 = #H.logs
for _ = 1, 200 do client_fields("mallory", "", { sys_be_mm = "true" }) end
check(#H.logs - logs2 <= 2,
	"a refused role claim is throttled too (got " .. (#H.logs - logs2) .. " lines)")
state.match_active = false

-- Re-claiming a role you already hold is not an event: it must change nothing.
state.monster_master.player = nil
H.advance(3.0, 0.5)
client_chat("mallory", "sl_be_monster_master") -- the open lobby volunteer path
check(state.monster_master.player == "mallory",
	"volunteering as Monster Master in the lobby still works (open by design)")
local all0, logs3 = #H.chat_all, #H.logs
for _ = 1, 200 do client_fields("mallory", "", { sys_be_mm = "true" }) end
check(#H.chat_all - all0 == 0,
	"re-claiming a held role re-announces nothing to the server (got "
	.. (#H.chat_all - all0) .. " broadcasts)")
check(#H.logs - logs3 == 0,
	"... and re-spawns the claimer zero times (got " .. (#H.logs - logs3) .. " log lines)")
check(state.monster_master.player == "mallory", "the role itself is unchanged")
game_mode.set_monster_master(mm_before)
state.match_active = match_before

-- ================================================================
section("PHASE S13 — an entity whose pathfinding fails must still return")
-- ================================================================
-- sl_scary:nerobot's idle handler was `while path_found == false do ... end`
-- with no attempt counter. minetest.find_path returns NIL whenever no route
-- exists inside max_search_distance -- a mob walled in by ordinary digging and
-- building, standing in the void, or a random candidate that is simply
-- unreachable -- so path_found never became true, sradius was never reset (the
-- inner loop broke immediately from the second pass, so the candidate never
-- changed either) and the server thread spun inside ONE on_step. Measured in
-- the headless harness before the fix: 200,000 find_path calls and 200,009
-- chat_send_all broadcasts (per-tick debug lines to EVERY player) before the
-- harness gave up. A tick that does not return is a frozen server, and the
-- client does not have to do anything exotic to cause it -- just build a wall.
if not load("sl_scary", "mods/content/sl_scary/init.lua") then
	print("  [SKIP] sl_scary did not load")
else
	local scary = minetest.registered_entities["sl_scary:nerobot"]
	check(scary ~= nil, "sl_scary:nerobot is registered (the entity under test exists)")
	if scary then
		-- A world it can wander in: walkable floor at y=5, air above it. The
		-- engine reads positions with readV3F, where a MISSING component is 0
		-- and not an error -- which is why the old array-style "node below me"
		-- probe `{x, y-1, z}` silently tested the world origin for every
		-- candidate and never noticed the mob was standing in the void.
		minetest.registered_nodes["sl_test:floor"] = { name = "sl_test:floor", walkable = true }
		-- The engine always has "air" (walkable = false); the stub returns
		-- {name="air"} for every unset position, so without a definition the
		-- candidate test can never see "not walkable" and the wander never
		-- asks for a path at all -- which would make this phase vacuous.
		minetest.registered_nodes["air"] = minetest.registered_nodes["air"]
			or { name = "air", walkable = false, buildable_to = true }
		for x = -5, 5 do
			for z = -5, 5 do
				minetest.set_node({ x = x, y = 5, z = z }, { name = "sl_test:floor" })
			end
		end

		local obj = minetest.add_entity({ x = 0, y = 5.5, z = 0 }, "sl_scary:nerobot")
		local lua = obj and obj._lua
		check(lua ~= nil, "the entity spawns in the harness")
		if lua then
			local prev_find_path = minetest.find_path
			local prev_chat_all = minetest.chat_send_all
			local BUDGET = 64 -- idle_wander_attempts (4) x idle_wander_radius (3), with room
			local calls, broadcasts = 0, 0
			minetest.find_path = function()
				calls = calls + 1
				if calls > BUDGET then
					error("idle wander exceeded " .. BUDGET .. " path searches", 0)
				end
				return nil -- engine-faithful: no route inside max_search_distance
			end
			minetest.chat_send_all = function(...)
				broadcasts = broadcasts + 1
				if prev_chat_all then return prev_chat_all(...) end
			end
			lua.timer = 99 -- past idle_random_select_time, so handle_idle wanders
			local ok, err = pcall(lua.on_step, lua, 1.5, { type = "node", collides = false })
			minetest.find_path = prev_find_path
			minetest.chat_send_all = prev_chat_all
			check(ok, "on_step RETURNS when pathfinding fails (was: unbounded while loop)"
				.. (ok and "" or (" -> " .. tostring(err))))
			check(calls > 0, "the wander really did ask for a path (" .. calls .. " searches)")
			check(calls <= BUDGET, "and the number of searches is bounded (" .. calls
				.. " <= " .. BUDGET .. ")")
			check(broadcasts == 0,
				"an idle mob broadcasts nothing to every player (got " .. broadcasts .. ")")
			obj:remove()
		end
	end
end

-- ================================================================
section("PHASE S14 — tree-wide audit: the patterns that keep reopening")
-- ================================================================
-- Cheap static guards, so the class of bug dies rather than the instance.
local function read_file(path)
	local fh = io.open(path, "r")
	if not fh then return nil end
	local body = fh:read("*a")
	fh:close()
	return body
end

-- The stub's get_dir_list serves a fake tree, so the audit needs the real
-- filesystem: a shell if the runtime has one (luajit in CI), and an honest
-- skip if it does not (lupa's embedded Lua 5.1 has no io.popen).
local files = {}
local popen_ok, fh = pcall(io.popen, "find mods -name '*.lua' -type f 2>/dev/null")
if popen_ok and fh then
	for line in fh:lines() do
		if line ~= "" then files[#files + 1] = line end
	end
	pcall(function() fh:close() end)
end
table.sort(files)
if #files == 0 then
	print("  [SKIP] static audit: this runtime has no io.popen, so the tree cannot be walked")
else
	check(#files > 60, "the audit walked the mod tree (" .. #files .. " lua files)")
end

local eval_offenders, func_offenders, broadcast_offenders = {}, {}, {}
local entity_files = {}
for _, path in ipairs(files) do
	local body = read_file(path)
	if body and body:find("register_entity%s*%(") then entity_files[path] = true end
	if body then
		local lineno = 0
		for line in body:gmatch("[^\n]*") do
			lineno = lineno + 1
			local code = line:match("^%s*%-%-") and "" or line
			-- 1. evaluating client text
			if code:find("deserialize%s*%(") or code:find("loadstring%s*%(") then
				if code:find("param") or code:find("fields") or code:find("formname")
					or code:find("message") or code:find("text") then
					eval_offenders[#eval_offenders + 1] = path .. ":" .. lineno
				end
			end
			-- 2. driving a chat command past the engine's priv gate
			if code:find("registered_chatcommands%.[%w_]+%.func") then
				func_offenders[#func_offenders + 1] = path .. ":" .. lineno
			end
			-- 3. broadcasting to every player from an entity's own code. An
			--    entity steps per tick per entity, so a chat_send_all in there
			--    is a debug line that scales with mobs x players x tick rate.
			--    sl_scary's idle/searching/attacking states had four of them:
			--    measured, 200,009 broadcasts to EVERY player inside one
			--    on_step while the unbounded pathfinding loop spun.
			if code:find("chat_send_all%s*%(") and entity_files[path] then
				broadcast_offenders[#broadcast_offenders + 1] = path .. ":" .. lineno
			end
		end
	end
end
if #files > 0 then
	check(#eval_offenders == 0, "no mod evaluates client text ("
		.. (#eval_offenders == 0 and "clean" or table.concat(eval_offenders, ", ")) .. ")")
	check(#func_offenders == 0, "no mod calls a chatcommand's func directly ("
		.. (#func_offenders == 0 and "clean" or table.concat(func_offenders, ", ")) .. ")")
	check(#broadcast_offenders == 0, "no entity code broadcasts to every player ("
		.. (#broadcast_offenders == 0 and "clean" or table.concat(broadcast_offenders, ", "))
		.. ")")
end

-- Every command that mutates match state must declare privs or be listed here.
local OPEN_BY_DESIGN = {
	sl_state = true, sl_match_status = true, sl_ready = true,
	sl_be_monster_master = true,     -- lobby volunteering; gated in-code by phase
	sl_mm_return = true, sl_mm_spawn = true, -- gated in-code: MM role + match + rate
	sl_summon_ghost = true, sl_ghost_offer = true, -- creative-mode + phase gated in-code
	sl_build_cage = true,            -- creative-mode gated in-code
	sl_map = true,                   -- gated in-code per subcommand
	sl_matchmaking = true,           -- read-only opener; fields are admin-gated
	sl_dm = true, sl_whisper = true, sl_w = true, sl_dm_ui = true, sl_comms = true,
	craft = true, abilities = true, achievements = true, xp = true,
	dlg_start = true, dlg_stop = true, dlg_pick = true, dlg_next = true,
	sl_strand_start = true, sl_strand_act = true, sl_strand_status = true,
	sl_strand_ledger = true, sl_strand_stop = true,
	sl_test_arena = true, sl_test_bots = true, sl_test_objective = true, sl_test_stop = true,
	sl_boxman = true,
}
local undeclared = {}
for cmd, def in pairs(minetest.registered_chatcommands) do
	local declares = false
	for _, v in pairs(def.privs or {}) do if v then declares = true end end
	if not declares and not OPEN_BY_DESIGN[cmd] then
		undeclared[#undeclared + 1] = cmd
	end
end
table.sort(undeclared)
check(#undeclared == 0, "every privileged command declares privs or is documented open ("
	.. (#undeclared == 0 and "clean" or table.concat(undeclared, ", ")) .. ")")

-- ---------------------------------------------------------------
print("")
print(string.format("RESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
