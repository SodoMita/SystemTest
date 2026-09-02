-- ================================================================
-- sl_texgen/gen/mvp.lua — sl_mvp_assets textures
--
-- Ports the MVP placeholder set: neon_cube (glowing wireframe cube
-- on grid), cursor (crosshair), hud / hud_frame (O2/HP/SIG bar
-- panels), font (16px digit/punct cells) and the model textures
-- (player/monster/terminal/door/platform/item/pulse/flare/particle
-- 64x64 labeled panels in their stock palettes).
-- ================================================================
local C = sl_texgen.canvas

local function alpha(col, a) return { col[1], col[2], col[3], a } end

----------------------------------------------------------------
-- neon cube: dark bg, cyan/magenta grid, double neon frame
----------------------------------------------------------------
local function neon_cube(c)
	C.clear(c, { 5, 7, 16, 255 })
	for i = 0, 63, 8 do
		local a = (i % 16 == 0) and 140 or 80
		C.line(c, i, 0, i, 63, alpha({ 0, 235, 255 }, a))
		C.line(c, 0, i, 63, i, alpha({ 255, 0, 210 }, a))
	end
	C.frame(c, 1, 1, 62, 62, alpha({ 0, 255, 255 }, 235))
	C.frame(c, 2, 2, 60, 60, alpha({ 0, 255, 255 }, 180))
	C.frame(c, 8, 8, 48, 48, alpha({ 255, 0, 200 }, 180))
	-- pseudo-3d cube edges (isometric suggestion)
	C.line(c, 20, 44, 32, 32, alpha({ 120, 255, 255 }, 220))
	C.line(c, 44, 44, 32, 32, alpha({ 120, 255, 255 }, 220))
	C.line(c, 32, 32, 32, 20, alpha({ 120, 255, 255 }, 220))
end

----------------------------------------------------------------
-- cursor: 32x32 crosshair
----------------------------------------------------------------
local function cursor(c)
	C.clear(c, { 0, 0, 0, 0 })
	local col = { 0, 255, 255, 230 }
	C.ring(c, 16, 16, 3, col)
	C.line(c, 16, 2, 16, 10, col)
	C.line(c, 16, 22, 16, 30, col)
	C.line(c, 2, 16, 10, 16, col)
	C.line(c, 22, 16, 30, 16, col)
end

----------------------------------------------------------------
-- hud: 256x64 rounded panel with O2/HP/SIG labeled bars
----------------------------------------------------------------
local BARS = {
	{ label = "o2", color = { 0, 220, 255, 160 }, w = 150 },
	{ label = "hp", color = { 255, 70, 100, 160 }, w = 175 },
	{ label = "sig", color = { 255, 215, 0, 140 }, w = 200 },
}

local function hud_panel(c, frame_only)
	C.clear(c, { 0, 0, 0, 0 })
	C.round_rect(c, 4, 4, 248, 56, 8, { 5, 10, 20, frame_only and 40 or 130 })
	C.frame(c, 4, 4, 248, 56, { 0, 220, 255, 220 })
	C.frame(c, 5, 5, 246, 54, { 0, 220, 255, 120 })
	for i, bar in ipairs(BARS) do
		local y = 10 + (i - 1) * 16
		C.text(c, 12, y, bar.label, { 210, 245, 255, 230 })
		C.frame(c, 42, y - 2, 194, 12, { 0, 220, 255, 180 })
		if not frame_only then
			C.rect(c, 44, y, bar.w, 8, bar.color)
		end
	end
end

----------------------------------------------------------------
-- font sheet: 128x48, "0123456789:-%" in 16x24 cells (stock layout)
----------------------------------------------------------------
local function font_sheet(c)
	C.clear(c, { 0, 0, 0, 0 })
	local chars = "0123456789:-%"
	for i = 1, #chars do
		local x = (i - 1) % 8 * 16
		local y = math.floor((i - 1) / 8) * 24
		C.frame(c, x, y, 16, 24, alpha({ 0, 180, 255 }, 60))
		-- glyph centered, scale 3 (3x5 -> 9x15)
		C.text_center(c, x + 8, y + 5, string.sub(chars, i, i), alpha({ 0, 245, 255 }, 245), 3)
	end
end

----------------------------------------------------------------
-- model textures: 64x64 labeled panels in stock palettes
----------------------------------------------------------------
local PANELS = {
	{ "player_texture.png", { 40, 60, 90 }, { 0, 210, 240 }, "player" },
	{ "monster_texture.png", { 30, 20, 40 }, { 200, 40, 90 }, "monster" },
	{ "platform_texture.png", { 45, 50, 60 }, { 120, 220, 255 }, "platform" },
	{ "terminal_texture.png", { 20, 40, 45 }, { 0, 240, 160 }, "terminal" },
	{ "door_texture.png", { 50, 45, 35 }, { 230, 190, 90 }, "door" },
	{ "item_texture.png", { 40, 45, 55 }, { 255, 230, 120 }, "item" },
	{ "pulse_texture.png", { 5, 10, 18 }, { 0, 255, 220 }, "pulse" },
	{ "flare_light_texture.png", { 40, 30, 10 }, { 255, 180, 60 }, "flare" },
	{ "particle_texture.png", { 20, 25, 35 }, { 180, 220, 255 }, "particle" },
}

local function panel(c, R, base, accent, label)
	C.speckle(c, R, base, 0.15)
	C.frame(c, 0, 0, 64, 64, alpha(accent, 210))
	C.rect(c, 14, 14, 36, 24, alpha(accent, 60))
	C.text_center(c, 32, 24, label, alpha({ 240, 250, 255 }, 235), 1)
	-- radial glow dot, the stock "emissive" hint
	C.radial(c, 32, 46, 8, alpha(accent, 130), alpha(base, 0))
end

local defs = {
	{ name = "neon_cube.png", w = 64, h = 64, seed = 0, draw = neon_cube },
	{ name = "cursor.png", w = 32, h = 32, seed = 0, draw = cursor },
	{ name = "hud.png", w = 256, h = 64, seed = 0, draw = function(c) hud_panel(c, false) end },
	{ name = "hud_frame.png", w = 256, h = 64, seed = 0, draw = function(c) hud_panel(c, true) end },
	{ name = "font.png", w = 128, h = 48, seed = 0, draw = font_sheet },
}
for i, spec in ipairs(PANELS) do
	local name, base, accent, label = spec[1], spec[2], spec[3], spec[4]
	defs[#defs + 1] = {
		name = name, w = 64, h = 64, seed = 600 + i,
		draw = function(c, R) panel(c, R, base, accent, label) end,
	}
end
return defs
