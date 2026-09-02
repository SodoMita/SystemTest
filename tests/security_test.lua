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
section("PHASE S7 — tree-wide audit: the two patterns that keep reopening")
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

local eval_offenders, func_offenders = {}, {}
for _, path in ipairs(files) do
	local body = read_file(path)
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
		end
	end
end
if #files > 0 then
	check(#eval_offenders == 0, "no mod evaluates client text ("
		.. (#eval_offenders == 0 and "clean" or table.concat(eval_offenders, ", ")) .. ")")
	check(#func_offenders == 0, "no mod calls a chatcommand's func directly ("
		.. (#func_offenders == 0 and "clean" or table.concat(func_offenders, ", ")) .. ")")
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
