-- ================================================================
-- tests/texgen_test.lua
-- Headless suite for mods/apis/sl_texgen (runtime texture
-- generation via client-side [combine programs).  Runs the real
-- generator modules against a stub engine and verifies:
--   * programs compile for every registered texture
--   * programs are pure [combine programs (no [png:, no media refs
--     beyond the shared stx_* bases), escape-correct, and their
--     declared sheet size matches the def (frames layout)
--   * animation params: sheet()/vframes() tables agree with the
--     compiled program's frame count
--   * helpers: icon() chaining, texture() error on unknown names
--   * compilation is deterministic (rebuild -> byte-identical)
--   * sl_texgen.mode=stock serves plain filenames, compiles nothing
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
stub_core.log = function() end
stub_core.register_chatcommand = function(name, def) chatcmds[name] = def end
stub_core.get_dir_list = function()
	return fake_dir_list[1] or {}
end

_G.core = stub_core
_G.minetest = stub_core

dofile(ROOT .. "/mods/apis/sl_texgen/init.lua")
local T = _G.sl_texgen
local stx = T.stx

----------------------------------------------------------------
-- [combine program validator
----------------------------------------------------------------
local BASES = {
	["stx_px.png"] = true, ["stx_glow.png"] = true, ["stx_ring.png"] = true,
	["stx_noise.png"] = true, ["stx_noise_rgb.png"] = true, ["stx_x.png"] = true,
	["stx_rhombus.png"] = true, ["stx_font.png"] = true,
}

--- split on unescaped ':' at top level; returns parts (escaped as-is)
local function split_unescaped(s, sep)
	local parts = {}
	local cur = {}
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "\\" then
			cur[#cur + 1] = c
			cur[#cur + 1] = s:sub(i + 1, i + 1)
			i = i + 2
		elseif c == sep then
			parts[#parts + 1] = table.concat(cur)
			cur = {}
			i = i + 1
		else
			cur[#cur + 1] = c
			i = i + 1
		end
	end
	parts[#parts + 1] = table.concat(cur)
	return parts
end

local function unescape(s)
	return (s:gsub("\\(.)", "%1"))
end

--- validate one blit term (unescaped): base must be a known stx
--- base, modifiers must be from the supported set with sane args
local function validate_term(term, errs, ctx)
	local ops = {}
	for op in term:gmatch("[^\^]+") do
		ops[#ops + 1] = op
	end
	for oi, op in ipairs(ops) do
		local u = op
		if oi == 1 then
			if not BASES[u] then
				errs[#errs + 1] = ctx .. ": unknown base texture '" .. u .. "'"
			end
		else
			local kind, args = u:match("^%[(%a+):?(.*)$")
			if kind == "resize" then
				local w, h = args:match("^(%d+)x(%d+)$")
				if not w then errs[#errs + 1] = ctx .. ": bad resize '" .. u .. "'" end
			elseif kind == "multiply" then
				if not args:match("^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
					errs[#errs + 1] = ctx .. ": bad multiply color '" .. u .. "'"
				end
			elseif kind == "opacity" then
				local n = tonumber(args)
				if not n or n < 0 or n > 255 or math.floor(n) ~= n then
					errs[#errs + 1] = ctx .. ": bad opacity '" .. u .. "'"
				end
			elseif kind == "sheet" then
				local w, h, x, y = args:match("^(%d+)x(%d+):(%d+),(%d+)$")
				if not w then
					errs[#errs + 1] = ctx .. ": bad sheet '" .. u .. "'"
				elseif stx.GLYPH_COUNT and tonumber(y) * 8 + tonumber(x) >= stx.GLYPH_COUNT then
					errs[#errs + 1] = ctx .. ": sheet index out of atlas '" .. u .. "'"
				end
			else
				errs[#errs + 1] = ctx .. ": unsupported modifier '" .. u .. "'"
			end
		end
	end
end

--- full program validation; returns list of problems + blit count
local function validate_program(prog, def)
	local errs = {}
	local blits = 0
	if prog:find("%[png:") then
		errs[#errs + 1] = "contains [png: (server rasterization is forbidden)"
	end
	-- strip grouping parens + finishing modifiers (e.g. "^[multiply:#...")
	local finishing = {}
	local core = prog
	if core:sub(1, 1) == "(" then
		-- find the matching close paren (programs contain no parens inside)
		local close = core:find(")", 1, true)
		if not close then
			errs[#errs + 1] = "unbalanced grouping paren"
			return errs, blits
		end
		finishing = split_unescaped(core:sub(close + 1), "^")
		core = core:sub(2, close - 1)
	end
	for i, f in ipairs(finishing) do
		if i > 1 or f ~= "" then
			local kind, args = f:match("^%[(%a+):?(.*)$")
			if kind == "multiply" then
				if not args:match("^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
					errs[#errs + 1] = "bad finishing multiply '" .. f .. "'"
				end
			elseif kind == "opacity" then
				local n = tonumber(args)
				if not n or n < 0 or n > 255 then errs[#errs + 1] = "bad finishing opacity" end
			else
				errs[#errs + 1] = "unsupported finishing modifier '" .. f .. "'"
			end
		end
	end
	local header, hcap, body = core:match("^%[combine:(%d+)x(%d+):?(.*)$")
	if not header then
		errs[#errs + 1] = "not a [combine program"
		return errs, blits
	end
	local W = tonumber(core:match("^%[combine:(%d+)"))
	local H = tonumber(core:match("^%[combine:%d+x(%d+)"))
	local want_w = def.vertical and def.w or def.w * def.frames
	local want_h = def.vertical and def.h * def.frames or def.h
	if W ~= want_w then errs[#errs + 1] = ("sheet width %s ~= %s"):format(W, want_w) end
	if H ~= want_h then errs[#errs + 1] = ("sheet height %s ~= %s"):format(H, want_h) end
	if body ~= "" then
		for _, blit in ipairs(split_unescaped(body, ":")) do
			blits = blits + 1
			local x, y, term = unescape(blit):match("^(-?%d+),(-?%d+)=(.+)$")
			if not x then
				errs[#errs + 1] = "malformed blit: " .. unescape(blit):sub(1, 60)
			else
				-- the escaped slice must roundtrip, and its unescaped
				-- term must only use known bases/modifiers
				local esc = blit:match("=(.+)$")
				if unescape(esc) ~= term then
					errs[#errs + 1] = "escape roundtrip mismatch at blit " .. blits
				else
					validate_term(term, errs, def.name .. " blit@" .. x .. "," .. y)
				end
			end
			if blits > 2000 then errs[#errs + 1] = "blit count runaway"; break end
		end
	end
	return errs, blits
end

----------------------------------------------------------------
section("registry + compile")
----------------------------------------------------------------
check(T and T._VERSION, "mod loads and exposes sl_texgen")
check(#T.defs > 0, "generators registered (" .. #T.defs .. " defs)")
local n_prog = 0
for _ in pairs(T.programs) do n_prog = n_prog + 1 end
check(n_prog == #T.defs, "every def compiled (" .. n_prog .. "/" .. #T.defs .. ")")

section("program validity")
local all_errs, total_bytes = {}, 0
local max_blits, max_name = 0, ""
for _, def in ipairs(T.defs) do
	local prog = T.textures[def.name]
	total_bytes = total_bytes + #prog
	local errs, blits = validate_program(prog, def)
	if blits > max_blits then max_blits, max_name = blits, def.name end
	for _, e in ipairs(errs) do all_errs[#all_errs + 1] = def.name .. ": " .. e end
end
check(#all_errs == 0, "all programs valid ([combine], dims, bases, escapes)" ..
	(#all_errs > 0 and ("\n    " .. table.concat(all_errs, "\n    ", 1, math.min(8, #all_errs))) or ""))
print(("    (%d textures, %.1f KiB of program strings; largest sheet: %s with %d blits)")
	:format(#T.defs, total_bytes / 1024, max_name, max_blits))

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
local ok_err = pcall(function() return T.texture("does_not_exist.png") end)
check(not ok_err, "texture() errors on unknown names")
check(T.texture(probe) == T.T(probe), "T alias matches texture()")

section("determinism")
local first_pass = {}
for k, v in pairs(T.textures) do first_pass[k] = v end
T.textures, T.programs = {}, {}
T.build_all()
local deterministic = true
for k, v in pairs(T.textures) do
	if first_pass[k] ~= v then deterministic = false; print("    differs: " .. k) end
end
check(deterministic, "recompile is byte-identical")

section("stock-file detection")
fake_dir_list[1] = { [1] = T.defs[1].name }
local present = T.stock_present()
check(#present == 1 and present[1] == T.defs[1].name, "stock_present finds reintroduced files")
fake_dir_list[1] = {}
check(#T.stock_present() == 0, "stock_present empty with clean tree")

section("mode=stock")
settings["sl_texgen.mode"] = "stock"
T.textures, T.programs = {}, {}
T.build_all()
check(next(T.programs) == nil, "stock mode compiles nothing")
check(T.texture(probe) == probe, "stock mode serves plain filenames")
settings["sl_texgen.mode"] = "runtime"
T.textures, T.programs = {}, {}
T.build_all()

section("chatcommand")
check(chatcmds["sl_texgen"] ~= nil, "/sl_texgen registered")
local ok, msg = chatcmds["sl_texgen"].func()
check(ok and type(msg) == "string" and msg:find("compiled") ~= nil, "/sl_texgen reports status")

----------------------------------------------------------------
print(("== texgen_test: %d passed, %d failed"):format(pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
os.exit(0)
