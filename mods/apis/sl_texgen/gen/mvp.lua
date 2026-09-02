-- ================================================================
-- sl_texgen/gen/mvp.lua — sl_mvp_assets textures
--
-- Neon cube, cursor crosshair, HUD panels (O2/HP/SIG bars), the
-- 16-cell font sheet and the labelled model panels — all compiled
-- to client-side [combine programs over the shared bases.
-- ================================================================
local stx = sl_texgen.stx

local function neon_cube(p)
	stx.solid(p, 0, 0, 64, 64, "#050710", 255)
	for i = 0, 7 do
		local a = (i % 2 == 0) and 140 or 80
		stx.vline(p, i * 8, 0, 64, "#00EBFF", a)
		stx.hline(p, 0, i * 8, 64, "#FF00D2", a)
	end
	stx.frame(p, 1, 1, 62, 62, "#00FFFF", 235)
	stx.frame(p, 2, 2, 60, 60, "#00FFFF", 180)
	stx.frame(p, 8, 8, 48, 48, "#FF00C8", 180)
	-- pseudo-3d cube edges (isometric suggestion)
	stx.solid(p, 20, 44, 12, 1, "#78FFFF", 220)
	stx.solid(p, 44, 44, 12, 1, "#78FFFF", 220)
	stx.solid(p, 31, 20, 1, 12, "#78FFFF", 220)
	stx.solid(p, 20, 44, 1, 1, "#78FFFF", 220)
	stx.solid(p, 55, 44, 1, 1, "#78FFFF", 220)
end

local function cursor(p)
	stx.ring(p, 16, 16, 6, 230, "#00FFFF")
	stx.vline(p, 16, 2, 8, "#00FFFF", 230)
	stx.vline(p, 16, 22, 8, "#00FFFF", 230)
	stx.hline(p, 2, 16, 8, "#00FFFF", 230)
	stx.hline(p, 22, 16, 8, "#00FFFF", 230)
end

local BARS = {
	{ label = "o2", color = "#00DCFF", w = 150 },
	{ label = "hp", color = "#FF4664", w = 175 },
	{ label = "sig", color = "#FFD700", w = 200 },
}

local function hud_panel(p, frame_only)
	stx.solid(p, 4, 4, 248, 56, "#050A14", frame_only and 40 or 130)
	stx.frame(p, 4, 4, 248, 56, "#00DCFF", 220)
	stx.frame(p, 5, 5, 246, 54, "#00DCFF", 120)
	for i, bar in ipairs(BARS) do
		local y = 10 + (i - 1) * 16
		stx.label(p, 12, y, bar.label, "#D2F5FF", 230, 1)
		stx.frame(p, 42, y - 2, 194, 12, "#00DCFF", 180)
		if not frame_only then
			stx.solid(p, 44, y, bar.w, 8, bar.color, 160)
		end
	end
end

local FONT_CHARS = "0123456789:-%"

local function font_sheet(p)
	-- 128x48, 16x24 cells, glyph centered via the shared atlas
	for i = 1, #FONT_CHARS do
		local x = (i - 1) % 8 * 16
		local y = math.floor((i - 1) / 8) * 24
		stx.frame(p, x, y, 16, 24, "#00B4FF", 60)
		stx.label(p, x + 4, y + 7, string.sub(FONT_CHARS, i, i), "#00F5FF", 245, 1)
	end
end

local PANELS = {
	{ "player_texture.png", "#283C50", "#00D2F0", "player" },
	{ "monster_texture.png", "#1E1428", "#C8285A", "monster" },
	{ "platform_texture.png", "#2D323C", "#78DCFF", "platform" },
	{ "terminal_texture.png", "#142830", "#00F0A0", "terminal" },
	{ "door_texture.png", "#322D23", "#E6BE5A", "door" },
	{ "item_texture.png", "#282D37", "#FFE678", "item" },
	{ "pulse_texture.png", "#050A12", "#00DCDC", "pulse" },
	{ "flare_light_texture.png", "#281E0A", "#FFB43C", "flare" },
	{ "particle_texture.png", "#141923", "#B4DCFF", "particle" },
}

local function panel(base, accent, label)
	return function(p, R)
		stx.solid(p, 0, 0, 64, 64, base, 255)
		stx.noise(p, 0, 0, 64, 64, 55)
		stx.frame(p, 0, 0, 64, 64, accent, 210)
		stx.solid(p, 14, 14, 36, 24, accent, 60)
		stx.label(p, 32 - math.floor(stx.text_width(label, 1) / 2), 22, label, "#F0FAFF", 235, 1)
		stx.glow(p, 32, 48, 16, 130, accent)
	end
end

local defs = {
	{ name = "neon_cube.png", w = 64, h = 64, seed = 0, draw = neon_cube },
	{ name = "cursor.png", w = 32, h = 32, seed = 0, draw = cursor },
	{ name = "hud.png", w = 256, h = 64, seed = 0, draw = function(p) hud_panel(p, false) end },
	{ name = "hud_frame.png", w = 256, h = 64, seed = 0, draw = function(p) hud_panel(p, true) end },
	{ name = "font.png", w = 128, h = 48, seed = 0, draw = font_sheet },
}
for _, spec in ipairs(PANELS) do
	defs[#defs + 1] = {
		name = spec[1], w = 64, h = 64, seed = 0,
		draw = panel(spec[2], spec[3], spec[4]),
	}
end
return defs
