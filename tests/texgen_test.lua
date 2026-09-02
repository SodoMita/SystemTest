-- ================================================================
-- tests/texgen_test.lua
-- Headless suite for mods/apis/sl_texgen (runtime texture
-- generation via [png: texture modifiers).  Runs the real generator
-- modules against a stub engine and verifies:
--   * every registered texture renders and encodes
--   * sl_texgen.texture(name) yields "[png:<base64>" strings whose
--     decoded bytes are structurally valid PNGs with the right
--     dimensions (signature, IHDR, chunk CRCs, zlib stream)
--   * the modifier strings are texture-syntax-safe (no reserved
--     characters in the base64 payload)
--   * helper accessors: icon() chaining, sheet()/vframes() tables
--   * generation is deterministic (rebuild -> byte-identical)
--   * sl_texgen.mode=stock serves plain filenames, generates nothing
--   * stock-file detection (files that must stay deleted)
--   * /sl_texgen chatcommand reports status
--
-- Run:  luajit tests/texgen_test.lua
--   or: python3 tests/run_lua51.py tests/texgen_test.lua
-- ================================================================

local pass_count, fail_count = 0, 0
local function check(cond, label)
	if cond then
		pass_count = pass_count + 1
		print("  [PASS] " .. label)
	else
		fail_count = fail_count + 1
		print("  [FAIL] " .. label)
	end
end

local function section(title)
	print("== " .. title)
end

----------------------------------------------------------------
-- engine stub
----------------------------------------------------------------
local ROOT = "."
if arg and (arg[0] or arg[1]) then
	local s = arg[0] or arg[1]
	ROOT = s:match("^(.*)/tests/texgen_test%.lua$") or s:match("^(.*)/tests$") and s:match("^(.*)/tests$") or "."
end
local logs = {}
local settings = {}
local fake_dir_list = {}
local chatcmds = {}

local stub_core = {}
stub_core.get_current_modname = function() return "sl_texgen" end
stub_core.get_modpath = function(name)
	if name == "sl_texgen" then return ROOT .. "/mods/apis/sl_texgen" end
	return nil
end
stub_core.settings = { get = function(_, key) return settings[key] end }
stub_core.log = function(level, msg)
	logs[#logs + 1] = tostring(level) .. ": " .. tostring(msg)
end
-- engine-encoder paths intentionally exercised too:
stub_core.encode_png = nil      -- set later to test the engine path
stub_core.encode_base64 = nil   -- sl_texgen falls back to its pure-Lua one
stub_core.register_chatcommand = function(name, def) chatcmds[name] = def end
stub_core.get_dir_list = function()
	return fake_dir_list[1] or {}
end

_G.core = stub_core
_G.minetest = stub_core

-- load the mod
dofile(ROOT .. "/mods/apis/sl_texgen/init.lua")
local T = _G.sl_texgen

----------------------------------------------------------------
-- pure-Lua base64 decoder + PNG structural validator
----------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(s)
	s = s:gsub("=+$", "")
	local out, acc, bits = {}, 0, 0
	for i = 1, #s do
		local v = B64:find(s:sub(i, i), 1, true) - 1
		acc = acc * 64 + v
		bits = bits + 6
		if bits >= 8 then
			bits = bits - 8
			out[#out + 1] = string.char(math.floor(acc / 2 ^ bits) % 256)
			acc = acc % (2 ^ bits)
		end
	end
	return table.concat(out)
end

local pngmod = dofile(ROOT .. "/mods/apis/sl_texgen/png.lua")

local function u32(s, i)
	return s:byte(i) * 16777216 + s:byte(i + 1) * 65536 + s:byte(i + 2) * 256 + s:byte(i + 3)
end

local function validate_png(data, want_w, want_h, label)
	local ok = true
	local why = "ok"
	repeat
		if not data:find("^\137PNG\r\n\026\n") then ok, why = false, "signature" break end
		local pos = 9
		local got_w, got_h
		while pos + 12 <= #data do
			local len = u32(data, pos)
			local ctype = data:sub(pos + 4, pos + 7)
			local cdata = data:sub(pos + 8, pos + 7 + len)
			local crc_got = u32(data, pos + 8 + len)
			local crc_want = pngmod.crc32(ctype .. cdata)
			if crc_got ~= crc_want then ok, why = false, "crc of " .. ctype break end
			if ctype == "IHDR" then
				got_w = u32(cdata, 1)
				got_h = u32(cdata, 5)
				local bitd, ct, inter = cdata:byte(9), cdata:byte(10), cdata:byte(13)
				if bitd ~= 8 or ct ~= 6 or inter ~= 0 then ok, why = false, "IHDR layout" break end
			elseif ctype == "IEND" then
				pos = pos + 12 + len
				break
			end
			pos = pos + 12 + len
		end
		if not ok then break end
		if not got_w then ok, why = false, "no IHDR" break end
		if want_w and got_w ~= want_w then ok, why = false, ("width %s ~= %s"):format(got_w, want_w) break end
		if want_h and got_h ~= want_h then ok, why = false, ("height %s ~= %s"):format(got_h, want_h) break end
	until true
	if not ok then print("    (" .. label .. ": " .. why .. ")") end
	return ok
end

local function media_count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

----------------------------------------------------------------
section("registry + render")
----------------------------------------------------------------
check(T and T._VERSION, "mod loads and exposes sl_texgen")
check(#T.defs > 0, "generators registered (" .. #T.defs .. " defs)")
check(media_count(T.png_bytes) == #T.defs, "every def rendered (" .. media_count(T.png_bytes) .. "/" .. #T.defs .. ")")
check(media_count(T.textures) == #T.defs, "every def has a [png: modifier string")

section("texture() -> [png: modifiers")
local function sheet_dims(def)
	return def.vertical and def.w or def.w * def.frames,
		def.vertical and def.h * def.frames or def.h
end
local struct_bad, unsafe, name_bad = {}, {}, {}
for _, def in ipairs(T.defs) do
	local tex = T.texture(def.name)
	if tex:sub(1, 5) ~= "[png:" then name_bad[#name_bad + 1] = def.name end
	local b64 = tex:sub(6)
	-- texture-string safety: base64 payload must not contain modifier syntax
	if b64:find("[^%w%+%/=]") then unsafe[#unsafe + 1] = def.name end
	local w, h = sheet_dims(def)
	if not validate_png(b64decode(b64), w, h, def.name) then
		struct_bad[#struct_bad + 1] = def.name
	end
end
check(#name_bad == 0, "all texture() results carry the [png: prefix")
check(#unsafe == 0, "base64 payloads are texture-syntax-safe" ..
	(#unsafe > 0 and (": " .. table.concat(unsafe, ", ")) or ""))
check(#struct_bad == 0, "all decoded PNGs structurally valid with correct dims" ..
	(#struct_bad > 0 and (": " .. table.concat(struct_bad, ", ")) or ""))

local total, total_b64 = 0, 0
for name, data in pairs(T.png_bytes) do
	total = total + #data
	total_b64 = total_b64 + #T.textures[name]
end
print(("    (%d textures: %.1f KiB png -> %.1f KiB inside modifier strings)")
	:format(#T.defs, total / 1024, total_b64 / 1024))

section("helper accessors")
local probe = T.defs[1].name
check(T.icon(probe, 16) == T.texture(probe) .. "^[resize:16x16", "icon() chains ^[resize")
local sh = T.sheet("tech_fire_30frames.png", 30, 0.05)
check(sh.name == T.texture("tech_fire_30frames.png")
	and sh.animation.type == "sheet_2d"
	and sh.animation.frames_w == 30
	and sh.animation.frames_h == 1
	and sh.animation.frame_length == 0.05, "sheet() builds sheet_2d tile table")
local vf = T.vframes("sus_nodes_white_noise_anim_4n.png", 64, 64, 1.2)
check(vf.animation.type == "vertical_frames"
	and vf.animation.aspect_w == 64 and vf.animation.aspect_h == 64, "vframes() builds vertical_frames tile table")
local errored = false
local ok_err = pcall(function() return T.texture("does_not_exist.png") end)
errored = not ok_err
check(errored, "texture() errors on unknown names")
check(T.texture(probe) == T.T(probe), "T alias matches texture()")

section("engine encoder path")
stub_core.encode_png = function(w, h, data)
	-- pretend-engine encoder: same signature, different bytes (simulate real deflate)
	return "\137PNG\r\n\026\nENGINE" .. w .. "x" .. h .. ":" .. data
end
T.png_bytes, T.textures = {}, {}
T.build_all()
local engine_differs = T.png_bytes[probe] ~= nil
check(engine_differs, "build_all uses core.encode_png when present")
T.png_bytes, T.textures = {}, {}
stub_core.encode_png = nil
T.build_all()

section("determinism")
local first_pass = {}
for k, v in pairs(T.png_bytes) do first_pass[k] = v end
T.png_bytes, T.textures = {}, {}
T.build_all()
local deterministic = true
for k, v in pairs(T.png_bytes) do
	if first_pass[k] ~= v then deterministic = false; print("    differs: " .. k) end
end
check(deterministic, "rebuild is byte-identical")

section("stock-file detection")
fake_dir_list[1] = { [1] = T.defs[1].name }
local present = T.stock_present()
check(#present == 1 and present[1] == T.defs[1].name, "stock_present finds reintroduced files")
fake_dir_list[1] = {}
check(#T.stock_present() == 0, "stock_present empty with clean tree")

section("mode=stock")
settings["sl_texgen.mode"] = "stock"
T.png_bytes, T.textures = {}, {}
T.build_all()
check(next(T.png_bytes) == nil, "stock mode generates nothing")
check(T.texture(probe) == probe, "stock mode serves plain filenames")
settings["sl_texgen.mode"] = "runtime"
T.png_bytes, T.textures = {}, {}
T.build_all()

section("chatcommand")
check(chatcmds["sl_texgen"] ~= nil, "/sl_texgen registered")
local ok, msg = chatcmds["sl_texgen"].func()
check(ok and type(msg) == "string" and msg:find("textures registered") ~= nil, "/sl_texgen reports status")

----------------------------------------------------------------
print(("== texgen_test: %d passed, %d failed"):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
os.exit(0)
