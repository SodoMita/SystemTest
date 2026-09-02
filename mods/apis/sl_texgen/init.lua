-- ================================================================
-- sl_texgen — runtime texture generation, compiled for the client
-- ================================================================
-- Placeholder art in this game is not shipped as PNG files.  Instead
-- this mod COMPILES each texture into a pure texture-modifier
-- program — a "[combine:WxH:x,y=term:..." string built from a
-- handful of tiny grayscale bases (textures/stx_*.png, ~34 KiB
-- total, texture-packable, media-cached, sent once) — and embeds
-- that string in the node/item/entity texture fields mods send
-- anyway (https://docs.luanti.org/for-creators/api/texture-modifiers/).
--
-- The program is *executed by the client*: the server never
-- rasterizes or ships per-texture pixels, and the strings are tiny
-- (bytes to a few KiB) next to any image payload.  Clients render
-- them at their own (hi-res) texture scale and cache the results in
-- the normal texture-modifier cache.
--
-- Public API (load time, after depending on sl_texgen):
--   sl_texgen.texture(name)  -> "[combine:..." program string
--                               (alias: sl_texgen.T)
--   sl_texgen.icon(name, px) -> texture(name) .. "^[resize:px px"
--   sl_texgen.sheet(name, frames_w, frame_length)
--                            -> tile table with sheet_2d animation
--   sl_texgen.vframes(name, aspect_w, aspect_h, length)
--                            -> tile table with vertical_frames anim
--   sl_texgen.register(def) / .build_all() / .defs / .textures
--
-- def = { name = "file.png", w, h, frames = 1, vertical = false,
--         seed = int, draw = function(p, R, f) ... end }
-- draw() paints frame f (1-based) onto the program p with rng R
-- using stx ops (glow/solid/ring/label/...); frame offsets are
-- applied automatically for strip layouts.
--
-- Modes (setting `sl_texgen.mode`, default "runtime"):
--   runtime — texture(name) yields the compiled program; the PNG
--               files must NOT exist in the repo (CI's
--               texgen_check --verify enforces the delete list).
--   stock   — texture(name) yields the plain filename (dev escape
--               hatch / bisection aid).
--
-- Determinism: generators use only stx ops + the seeded rng, so
-- programs are byte-stable across runs and platforms.
-- tests/texgen_test.lua validates the programs; tools/texgen_check.py
-- --verify executes them in a reference interpreter and checks the
-- registry/repo consistency.
-- ================================================================

local modname = core.get_current_modname()
local MP = core.get_modpath(modname)

sl_texgen = {
	_VERSION = "3.0.0",
	stx = dofile(MP .. "/stx.lua"),
	textures = {},   -- [filename] = compiled "[combine:..." program
	programs = {},   -- [filename] = { def = def, program = string }
	defs = {},       -- registry, ordered by filename
}
local stx = sl_texgen.stx

-- ----------------------------------------------------------------
-- registry
-- ----------------------------------------------------------------
function sl_texgen.register(def)
	assert(type(def.name) == "string", "texgen def needs a name")
	assert(def.name:match("%.png$"), "texgen def name must end in .png: " .. def.name)
	assert(type(def.w) == "number" and type(def.h) == "number", def.name .. " needs numeric w/h")
	assert(type(def.draw) == "function", def.name .. " needs a draw function")
	def.frames = def.frames or 1
	def.seed = def.seed or 0
	for _, other in ipairs(sl_texgen.defs) do
		assert(other.name ~= def.name, "duplicate texgen def: " .. def.name)
	end
	table.insert(sl_texgen.defs, def)
	table.sort(sl_texgen.defs, function(a, b) return a.name < b.name end)
end

-- ----------------------------------------------------------------
-- generator modules (each returns a list of defs)
-- ----------------------------------------------------------------
local GEN_FILES = {
	"construction", "forest", "ground", "scary", "workshops", "modebase",
	"weapons", "mvp", "clothing", "formspec", "dignodes", "gui",
}
for _, fname in ipairs(GEN_FILES) do
	local ok, defs = pcall(dofile, MP .. "/gen/" .. fname .. ".lua")
	if not ok then
		core.log("error", "[sl_texgen] generator module " .. fname .. " failed: " .. tostring(defs))
	else
		for _, def in ipairs(defs) do
			sl_texgen.register(def)
		end
	end
end

-- ----------------------------------------------------------------
-- build
-- ----------------------------------------------------------------

--- Compile one def (all frames) to its program string.
function sl_texgen.build(def)
	if not sl_texgen.programs[def.name] then
		local sheet_w = def.vertical and def.w or def.w * def.frames
		local sheet_h = def.vertical and def.h * def.frames or def.h
		local p = stx.new(sheet_w, sheet_h, { name = def.name, finishing = def._finish })
		for f = 1, def.frames do
			p._ox = def.vertical and 0 or (f - 1) * def.w
			p._oy = def.vertical and (f - 1) * def.h or 0
			def.draw(p, stx.rng(def.seed * 7919 + f), f)
		end
		local program = stx.compile(p)
		sl_texgen.programs[def.name] = { def = def, program = program }
		sl_texgen.textures[def.name] = program
	end
	return sl_texgen.textures[def.name]
end

--- Compile everything (runtime mode only).  Returns bytes of program.
function sl_texgen.build_all()
	local mode = core.settings:get("sl_texgen.mode") or "runtime"
	if mode == "stock" then
		core.log("action", ("[sl_texgen] mode=stock: serving %d textures from files, nothing compiled")
			:format(#sl_texgen.defs))
		return 0
	end
	local total = 0
	for _, def in ipairs(sl_texgen.defs) do
		total = total + #sl_texgen.build(def)
	end
	core.log("action", ("[sl_texgen] mode=runtime: compiled %d textures into %.1f KiB of "
		.. "[combine programs (client-rendered)"):format(#sl_texgen.defs, total / 1024))
	return total
end

-- ----------------------------------------------------------------
-- accessor API for other mods (load-time safe)
-- ----------------------------------------------------------------
local function mode()
	return core.settings:get("sl_texgen.mode") or "runtime"
end

--- texture string for a registered name:
---   runtime mode -> "[combine:..." program (client-rendered)
---   stock mode   -> the plain filename
function sl_texgen.texture(name)
	if mode() == "runtime" then
		local t = sl_texgen.textures[name]
		if not t then
			error("[sl_texgen] unknown texture: " .. tostring(name)
				.. " (registered names are in sl_texgen.defs)", 2)
		end
		return t
	end
	return name
end
sl_texgen.T = sl_texgen.texture

--- inventory icon from a sheet/frame texture: "^[resize:NxN"
function sl_texgen.icon(name, px)
	return sl_texgen.texture(name) .. ("^[resize:%dx%d"):format(px, px)
end

--- node tile table with a sheet_2d animation (horizontal strip)
function sl_texgen.sheet(name, frames_w, frame_length)
	return {
		name = sl_texgen.texture(name),
		animation = {
			type = "sheet_2d",
			frames_w = frames_w,
			frames_h = 1,
			frame_length = frame_length,
		},
	}
end

--- node tile table with a vertical_frames animation
function sl_texgen.vframes(name, aspect_w, aspect_h, length)
	return {
		name = sl_texgen.texture(name),
		animation = {
			type = "vertical_frames",
			aspect_w = aspect_w,
			aspect_h = aspect_h,
			length = length,
		},
	}
end

-- ----------------------------------------------------------------
-- stock-file watchdog: in runtime mode a reintroduced PNG is dead
--- weight (and git-tracked bloat), never referenced by the game.
-- ----------------------------------------------------------------
function sl_texgen.stock_present()
	local present = {}
	local ok, files = pcall(core.get_dir_list, MP .. "/textures", false)
	if not ok or not files then return present end
	local set = {}
	for _, f in ipairs(files) do set[f] = true end
	for _, def in ipairs(sl_texgen.defs) do
		if set[def.name] then present[#present + 1] = def.name end
	end
	table.sort(present)
	return present
end

-- ----------------------------------------------------------------
-- startup: compile
-- ----------------------------------------------------------------
sl_texgen.build_all()

local present = sl_texgen.stock_present()
if #present > 0 then
	core.log("warning", ("[sl_texgen] %d generated textures also exist as stock files (bloat; "
		.. "delete them or set sl_texgen.mode=stock). First few: %s")
		:format(#present, table.concat(present, ", ", 1, math.min(5, #present))))
end

-- ----------------------------------------------------------------
-- status chatcommand: /sl_texgen
-- ----------------------------------------------------------------
core.register_chatcommand("sl_texgen", {
	description = "sl_texgen: runtime texture generation status",
	func = function()
		local bytes, count = 0, 0
		local biggest, biggest_n = 0, "-"
		for name, entry in pairs(sl_texgen.programs) do
			count = count + 1
			bytes = bytes + #entry.program
			if #entry.program > biggest then
				biggest, biggest_n = #entry.program, name
			end
		end
		return true, ("sl_texgen %s: mode=%s, %d textures compiled into %.1f KiB of client-side "
			.. "[combine programs (largest: %s at %.1f KiB)")
			:format(sl_texgen._VERSION, mode(), count, bytes / 1024,
				biggest_n, biggest / 1024)
	end,
})
