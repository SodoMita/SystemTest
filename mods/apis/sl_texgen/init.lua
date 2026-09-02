-- ================================================================
-- sl_texgen — runtime procedural texture generation
-- ================================================================
-- Many of this game's textures are placeholder art that was rendered
-- offline by python scripts and shipped as PNG files (spritesheets of
-- nodes, mob strips, labelled panels, noise, ...).  That costs repo
-- and download space for pixels a script can reproduce trivially.
--
-- This mod renders those textures *at server startup* and hands them
-- to clients as [png: texture modifiers (base texture generator, see
-- docs.luanti.org/for-creators/api/texture-modifiers):
--
--     "[png:" .. core.encode_base64(core.encode_png(w, h, pixels))
--
-- The modifier is embedded directly in the tile / item / entity
-- texture strings that mods already send in their definitions, so
-- there is no media-push step, no disk I/O and no client media-cache
-- writes; the client decodes each texture once into its modifier
-- cache.  The corresponding PNG files are deleted from the repo.
--
-- Public API (all usable at load time, after depending on sl_texgen):
--   sl_texgen.texture(name)  -> "[png:..." modifier string
--                               (alias: sl_texgen.T)
--   sl_texgen.icon(name, px) -> texture(name) .. "^[resize:px px"
--   sl_texgen.sheet(name, frames_w, frame_length)
--                            -> tile table with sheet_2d animation
--   sl_texgen.vframes(name, aspect_w, aspect_h, length)
--                            -> tile table with vertical_frames anim
--   sl_texgen.register(def) / .build_all() / .defs / .textures
--
-- Modes (setting `sl_texgen.mode`, default "runtime"):
--   runtime — texture(name) yields the [png: modifier; the PNG files
--               must NOT exist in the repo (CI's texgen_check
--               enforces the delete list against the registry).
--   stock   — texture(name) yields the plain filename; generate
--               nothing (dev escape hatch / bisection aid).
--
-- Determinism: generators use only canvas.lua primitives + the seeded
-- rng, so output is byte-stable across runs and platforms.
-- tests/texgen_test.lua and tools/texgen_check.py verify this and the
-- registry/repo consistency.
-- ================================================================

local modname = core.get_current_modname()
local MP = core.get_modpath(modname)

sl_texgen = {
	_VERSION = "2.0.0",
	canvas = dofile(MP .. "/canvas.lua"),
	png = dofile(MP .. "/png.lua"),
	textures = {},   -- [filename] = "[png:..." modifier string
	png_bytes = {},  -- [filename] = raw png bytes
	defs = {},       -- registry, ordered by filename
}

local C = sl_texgen.canvas

-- ----------------------------------------------------------------
-- encoding: prefer the engine's real-deflate encoder (5.13+), fall
-- back to the pure-Lua one (stored deflate; bigger but correct).
-- ----------------------------------------------------------------
local function encode_png(c)
	if core.encode_png then
		local raw = {}
		for y = 0, c.h - 1 do
			local base = y * c.w * 4
			local row = {}
			for x = 0, c.w - 1 do
				local i = base + x * 4
				row[#row + 1] = string.char(c.px[i + 1] or 0, c.px[i + 2] or 0, c.px[i + 3] or 0, c.px[i + 4] or 0)
			end
			raw[#raw + 1] = table.concat(row)
		end
		local ok, res = pcall(core.encode_png, c.w, c.h, table.concat(raw), 9)
		if ok and type(res) == "string" and #res > 8 then return res end
	end
	return sl_texgen.png.encode(c)
end

local function encode_base64(data)
	if core.encode_base64 then
		local ok, res = pcall(core.encode_base64, data)
		if ok and type(res) == "string" then return res end
	end
	return sl_texgen.png.encode_base64(data)
end

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

--- Render one def to a sheet canvas.
function sl_texgen.build_canvas(def)
	local frames = {}
	for f = 1, def.frames do
		local c = C.new(def.w, def.h)
		local R = C.rng(def.seed * 7919 + f)
		def.draw(c, R, f)
		frames[#frames + 1] = c
	end
	if def.frames > 1 then
		return C.compose(frames, def.vertical)
	end
	return frames[1]
end

--- Render one def; caches png bytes and the [png: modifier string.
function sl_texgen.build(def)
	if not sl_texgen.png_bytes[def.name] then
		local bytes = encode_png(sl_texgen.build_canvas(def))
		sl_texgen.png_bytes[def.name] = bytes
		sl_texgen.textures[def.name] = "[png:" .. encode_base64(bytes)
	end
	return sl_texgen.png_bytes[def.name]
end

--- Render everything (runtime mode only).  Returns png bytes generated.
function sl_texgen.build_all()
	local mode = core.settings:get("sl_texgen.mode") or "runtime"
	if mode == "stock" then
		core.log("action", ("[sl_texgen] mode=stock: serving %d textures from files, nothing generated")
			:format(#sl_texgen.defs))
		return 0
	end
	local total = 0
	for _, def in ipairs(sl_texgen.defs) do
		total = total + #sl_texgen.build(def)
	end
	core.log("action", ("[sl_texgen] mode=runtime: generated %d textures, %.1f KiB of PNG "
		.. "(%.1f KiB as [png: modifiers)"):format(#sl_texgen.defs, total / 1024, total * 4 / 3 / 1024))
	return total
end

-- ----------------------------------------------------------------
-- accessor API for other mods (load-time safe)
-- ----------------------------------------------------------------
local function mode()
	return core.settings:get("sl_texgen.mode") or "runtime"
end

--- texture string for a registered name:
---   runtime mode -> "[png:<base64>"  (docs: base texture generator)
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
-- startup: render
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
		local png, b64, count = 0, 0, 0
		for name, data in pairs(sl_texgen.png_bytes) do
			count = count + 1
			png = png + #data
			b64 = b64 + #sl_texgen.textures[name]
		end
		local present = sl_texgen.stock_present()
		return true, ("sl_texgen %s: mode=%s, %d textures registered, %d generated "
			.. "(%.1f KiB png / %.1f KiB base64), %d stock files still present")
			:format(sl_texgen._VERSION, mode(), #sl_texgen.defs, count,
				png / 1024, b64 / 1024, #present)
	end,
})
