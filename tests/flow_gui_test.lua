-- ================================================================
-- tests/flow_gui_test.lua
-- Headless test for the vendored minetest-flow pilot UI
-- (mods/external/flow + mods/external/formspec_ast).
--
-- The Secure Link DM terminal in mods/apis/sl_gui/dm_system.lua is the
-- first System Looting UI built with flow: a declarative widget tree
-- (VBox/Label/Textlist/Field/Button) instead of hand-placed formspec
-- strings. This suite loads the real vendored libraries under the
-- engine stub and exercises the flow pipeline end to end:
--   * libraries + sl_gui load with flow active
--   * /sl_dm_ui opens the flow terminal (a flow:... form is shown)
--   * textlist selection is decoded by flow and remembered in ctx
--   * TRANSMIT (button) and Enter (on_key_enter) deliver DMs and the
--     redraw clears the message box; chat reaches sender + target
--   * the roster is re-read on every action (ghosts are dropped)
--   * failures surface as an in-form error line, not just chat
--   * CLOSE LINK actually closes the flow form
--   * game_mode.get_dm_formspec still renders a parseable standalone
--
-- Run from the repo root:  luajit tests/flow_gui_test.lua
-- ================================================================

local H = dofile("tests/minetest_stub.lua")

local pass_count, fail_count = 0, 0
local function check(cond, label)
	local ok = cond and true or false
	if ok then
		pass_count = pass_count + 1
		print("  [PASS] " .. label)
	else
		fail_count = fail_count + 1
		print("  [FAIL] " .. label)
	end
	return ok
end

local function section(title)
	print("== " .. title)
end

-- ---------------------------------------------------------------
-- Stub extensions: the shared stub predates flow. Everything here is
-- the small subset of the engine API flow needs, with the same
-- semantics as the real engine.
-- ---------------------------------------------------------------
local modpaths = {
	sl_modebase = "mods/game/sl_modebase",
	sl_gui = "mods/apis/sl_gui",
	flow = "mods/external/flow",
	formspec_ast = "mods/external/formspec_ast",
	player_api = "mods/player_api",
	sl_characters = "mods/content/sl_characters",
}
function minetest.get_modpath(name)
	return modpaths[name] or "mods/game/sl_modebase"
end
function minetest.close_formspec() end
function minetest.is_singleplayer() return false end
-- Which formspec version does this (pretend) client understand?
function minetest.get_player_information(_)
	return { formspec_version = 7, protocol_version = 48, lang_code = "en" }
end
-- The stub's explode_textlist_event always says "nothing", but flow's
-- textlist input processing needs real engine event decoding.
function minetest.explode_textlist_event(value)
	local kind, index = tostring(value):match("^(%u+):(%d*):?$")
	if kind then
		return { type = kind, index = tonumber(index) or 0 }
	end
	return { type = "nothing", index = 0 }
end
function minetest.add_particlespawner() return 1 end
function minetest.delete_particlespawner() end

-- Luanti extends the string library with string.trim, and formspec_ast
-- relies on it. The engine stub predates flow, so add the extension
-- with the engine's semantics here.
string.trim = string.trim or function(s)
	return (tostring(s):gsub("^%s*(.-)%s*$", "%1"))
end

-- minetest.is_yes is a core engine helper formspec_ast uses to decode
-- boolean fields ("true"/"yes" -> true).
minetest.is_yes = minetest.is_yes or function(str)
	str = tostring(str):lower()
	return str == "true" or str == "yes"
end

-- sl_gui hooks into engine callbacks the stub does not implement; stub
-- them so the mods (the thing under test) can load, as ui_layout_test
-- does.
setmetatable(minetest, { __index = function(t, k)
	if type(k) == "string" and k:match("^register_") then
		local noop = function() return true end
		rawset(t, k, noop)
		return noop
	end
	return nil
end })

-- The running/ability systems call a few visual setters (set_fov, ...)
-- on the player object from their globalsteps; give player objects the
-- same auto-noop treatment ui_layout_test applies.
local probe = H.new_player("__probe")
local PlayerMeta = getmetatable(probe)
H.remove_player("__probe")
local pm_index = PlayerMeta.__index
PlayerMeta.__index = function(t, k)
	local v
	if type(pm_index) == "table" then
		v = pm_index[k]
	elseif type(pm_index) == "function" then
		v = pm_index(t, k)
	end
	if v ~= nil then return v end
	if type(k) == "string" and (k:match("^set_") or k:match("^wield")) then
		local noop = function() return nil end
		rawset(t, k, noop)
		return noop
	end
	return nil
end

section("PHASE 1 — vendored libraries load under the stub")
H.current_modname = "formspec_ast"
local ok, err = pcall(dofile, "mods/external/formspec_ast/init.lua")
check(ok and rawget(_G, "formspec_ast") ~= nil,
	"formspec_ast loads" .. (ok and "" or (" -> " .. tostring(err))))
if not (ok and rawget(_G, "formspec_ast")) then os.exit(1) end

-- flow speaks the engine's `core` global; under the stub core == minetest.
core = minetest
H.current_modname = "flow"
ok, err = pcall(dofile, "mods/external/flow/init.lua")
check(ok and rawget(_G, "flow") ~= nil,
	"flow loads" .. (ok and "" or (" -> " .. tostring(err))))
if not (ok and rawget(_G, "flow")) then os.exit(1) end
check(type(flow.make_gui) == "function", "flow.make_gui is exposed")
check(type(flow.widgets.VBox) == "function", "flow.widgets exposes VBox")

section("PHASE 2 — sl_gui loads with the flow terminal active")
H.current_modname = "sl_modebase"
ok, err = pcall(dofile, "mods/game/sl_modebase/init.lua")
check(ok, "sl_modebase loads" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then os.exit(1) end

H.current_modname = "sl_gui"
ok, err = pcall(dofile, "mods/apis/sl_gui/init.lua")
check(ok, "sl_gui loads" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then os.exit(1) end

check(game_mode.dm_flow_gui ~= nil, "dm_system built the flow terminal")
check(game_mode.send_dm ~= nil, "game_mode.send_dm exposed")
check(game_mode.get_dm_formspec ~= nil, "game_mode.get_dm_formspec exposed")
check(minetest.registered_chatcommands.sl_dm_ui ~= nil, "/sl_dm_ui registered")
check(minetest.registered_chatcommands.sl_comms ~= nil, "/sl_comms registered")

-- Live roster: alpha (sender) + beta + gamma (targets).
local alpha = H.new_player("alpha")
local beta = H.new_player("beta")
H.new_player("gamma")
H.fire_joinplayer(alpha)
H.fire_joinplayer(beta)
H.fire_joinplayer(H.players["gamma"])
H.advance(1, 0.5)

local beta_pl = game_mode.get_player_state("beta")
local gamma_pl = game_mode.get_player_state("gamma")

local function last_formspec(name)
	local list = H.formspecs[name]
	if not list or #list == 0 then return nil end
	return list[#list]
end

local function chat_count(name)
	return #(H.chat_player[name] or {})
end

-- Fresh terminal open; returns the flow form name shown to alpha.
local function open_terminal()
	local ok_cmd = minetest.registered_chatcommands.sl_dm_ui.func("alpha")
	check(ok_cmd == true, "/sl_dm_ui opened the terminal")
	local shown = last_formspec("alpha")
	assert(shown, "no formspec was shown to alpha")
	return shown.formname
end

section("PHASE 3 — /sl_dm_ui opens the flow terminal")
local dm_formname = open_terminal()
check(tostring(dm_formname):match("^flow:") ~= nil,
	"flow owns the form name (" .. tostring(dm_formname) .. ")")
local dm_fs = last_formspec("alpha").form
check(dm_fs:find("SECURE NEURAL LINK") ~= nil, "terminal title rendered")
check(dm_fs:find("dm_target") ~= nil, "target textlist rendered")
check(dm_fs:find("dm_message") ~= nil, "message field rendered")
check(dm_fs:find("dm_send") ~= nil, "TRANSMIT button rendered")
check(dm_fs:find("dm_close") ~= nil, "CLOSE LINK button rendered")
check(dm_fs:find("beta") ~= nil and dm_fs:find("gamma") ~= nil,
	"both live targets are listed")
check(dm_fs:find("alpha") == nil, "the sender is not listed as a target")

-- Flow renders a size element (auto-fit to the widget tree) and the
-- result parses back through formspec_ast without error.
local parsed = formspec_ast.parse(dm_fs)
check(type(parsed) == "table" and #parsed > 0,
	"rendered formspec parses with formspec_ast")
local size_el
for _, n in ipairs(parsed or {}) do
	if n.type == "size" then size_el = n end
end
check(size_el ~= nil, "terminal has a size[] element")
if size_el then
	check(size_el.w and size_el.h and size_el.w > 6 and size_el.h > 5,
		string.format("terminal sizes sanely (%.1f x %.1f)",
			size_el.w or 0, size_el.h or 0))
end

section("PHASE 4 — flow decodes the textlist event and remembers the row")
local before_chg = last_formspec("alpha")
-- Client picks roster row 2 ("gamma"): engine textlist events arrive as
-- "CHG:<index>:" strings; flow transforms them into ctx.form.dm_target.
H.fire_receive_fields("alpha", dm_formname, { dm_target = "CHG:2:" })
local after_chg = last_formspec("alpha")
check(after_chg ~= nil and after_chg ~= before_chg,
	"selection redrew the terminal (value change)")
check(after_chg and after_chg.formname == dm_formname,
	"redraw kept the same flow form open")

section("PHASE 5 — TRANSMIT sends to the selected target and clears the box")
local gamma_before = chat_count("gamma")
local alpha_before = chat_count("alpha")
H.fire_receive_fields("alpha", dm_formname, {
	dm_message = "  eyes on the north beacon  ",
	dm_send = true,
})
check(chat_count("gamma") == gamma_before + 1,
	"button send reached the selected target (gamma)")
check(chat_count("alpha") == alpha_before + 1,
	"sender got the [SECURE LINK] confirmation")
local after_send = last_formspec("alpha")
check(after_send ~= nil and after_send.formname == dm_formname,
	"terminal stayed open after the send")
-- The successful send clears ctx.form.dm_message, so the redraw shows
-- an empty field default again.
check(after_send and after_send.form:find("dm_message;;") ~= nil,
	"message box was cleared for rapid follow-up")
check(after_send and after_send.form:find("TRANSMISSION FAILED") == nil,
	"no error line after a successful send")

section("PHASE 6 — re-selection + Enter key transmit (on_key_enter)")
H.advance(2, 0.5) -- let the link cooldown lapse
-- Pick row 1 ("beta") now: proves the remembered index follows the
-- selection instead of sticking to the default.
H.fire_receive_fields("alpha", dm_formname, { dm_target = "CHG:1:" })
local beta_before2 = chat_count("beta")
H.fire_receive_fields("alpha", dm_formname, {
	key_enter = true,
	key_enter_field = "dm_message",
	dm_message = "incoming on channel two",
})
check(chat_count("beta") == beta_before2 + 1,
	"Enter key delivered the message to the re-selected target (beta)")
H.advance(2, 0.5)

section("PHASE 7 — ghosts drop off the roster; failure shows in-form")
-- Both targets become ghosts: the next action re-reads the roster and
-- finds nobody left to transmit to.
beta_pl.phase = "ghost"
gamma_pl.phase = "ghost"
local alpha_before2 = chat_count("alpha")
local beta_before3 = chat_count("beta")
H.fire_receive_fields("alpha", dm_formname, {
	dm_message = "beta?",
	dm_send = true,
})
local err_redraw = last_formspec("alpha")
check(err_redraw and err_redraw.form:find("No target selected") ~= nil,
	"send with an empty roster raised an in-form error line")
check(err_redraw and err_redraw.form:find("NO TARGETS AVAILABLE") ~= nil,
	"redraw switched to the no-targets layout")
check(chat_count("alpha") == alpha_before2
	and chat_count("beta") == beta_before3,
	"failed send leaked nothing to chat")
beta_pl.phase = "alive"
gamma_pl.phase = "alive"

section("PHASE 8 — CLOSE LINK closes the flow form")
H.advance(2, 0.5)
local dm_formname2 = open_terminal()
local alpha_before3 = chat_count("alpha")
H.fire_receive_fields("alpha", dm_formname2, { dm_close = true })
H.fire_receive_fields("alpha", dm_formname2, { dm_send = true, dm_message = "after close" })
check(chat_count("alpha") == alpha_before3,
	"events after CLOSE LINK are ignored (flow dropped the form)")

section("PHASE 9 — terminal refuses to open when every target is sealed")
beta_pl.phase = "ghost"
gamma_pl.phase = "ghost"
local ok_refuse, refuse_msg =
	minetest.registered_chatcommands.sl_dm_ui.func("alpha")
check(ok_refuse == false and tostring(refuse_msg):find("bio%-signatures") ~= nil,
	"/sl_dm_ui refused with everyone sealed (" .. tostring(refuse_msg) .. ")")
beta_pl.phase = "alive"
gamma_pl.phase = "alive"

section("PHASE 10 — get_dm_formspec still renders a standalone terminal")
local standalone = game_mode.get_dm_formspec(alpha)
check(type(standalone) == "string" and standalone:find("formspec_version") ~= nil,
	"standalone render carries a formspec version")
check(standalone:find("SECURE NEURAL LINK") ~= nil, "standalone render builds")
local sparsed = formspec_ast.parse(standalone)
check(type(sparsed) == "table" and #sparsed > 0,
	"standalone render parses with formspec_ast")

print("")
print(string.format("RESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
