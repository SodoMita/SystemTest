-- ================================================================
-- sl_texgen/gen/weapons.lua — sl_weapons item/entity textures
--
-- The stock icons were 16x16 procedural dithers (two-tone stripe or
-- checker fills with small accents).  Their exact palettes and
-- layouts were lifted from the retired files, so runtime output is
-- visually identical to what shipped before.
-- ================================================================
local C = sl_texgen.canvas

-- name, pattern, base, second, optional accent
local ICONS = {
  { "ammo_bullets.png", "ammo", {85,29,48,255}, {255,77,104,255}},
  { "ammo_cells.png", "ammo", {76,76,62,255}, {229,216,146,255}},
  { "ammo_rockets.png", "ammo", {35,24,37,255}, {107,61,69,255}},
  { "ammo_shells.png", "ammo", {88,80,99,255}, {255,228,255,255}},
  { "blast.png", "stripes", {49,66,51,255}, {53,68,68,255}},
  { "chatter.png", "stripes", {124,11,29,255}, {103,31,53,255}},
  { "driver.png", "stripes", {41,38,95,255}, {47,49,97,255}},
  { "fabricator_base.png", "stripes", {8,60,74,255}, {25,64,83,255}},
  { "fabricator_side.png", "stripes", {1,60,76,255}, {20,64,84,255}},
  { "fabricator_top.png", "stripes", {72,71,82,255}, {68,71,88,255}},
  { "grapple.png", "ammo", {44,87,65,255}, {132,250,155,255}},
  { "grit.png", "stripes", {92,87,126,255}, {81,82,118,255}},
  { "hit.png", "stripes", {23,66,89,255}, {35,68,93,255}},
  { "lance.png", "stripes", {120,29,90,255}, {100,43,94,255}},
  { "lash_hook.png", "stripes", {113,4,28,255}, {95,27,52,255}},
  { "lash_line.png", "stripes", {37,82,89,255}, {45,78,93,255}},
  { "mortar.png", "stripes", {30,44,75,255}, {40,53,84,255}},
  { "mortar_shell.png", "stripes", {125,126,70,255}, {103,108,80,255}},
  { "mound.png", "ammo", {40,65,68,255}, {120,185,163,255}},
  { "neon_six.png", "stripes", {73,28,42,255}, {68,42,62,255}},
  { "pad_ammo_ring.png", "frame", {25,34,63,255}, {17,31,89,255}},
  { "pad_ring.png", "frame", {26,58,51,255}, {18,102,52,255}},
  { "pistol.png", "stripes", {2,45,27,255}, {21,54,52,255}},
  { "pulse_bolt.png", "stripes", {124,117,92,255}, {102,102,95,255}},
  { "repeater.png", "stripes", {97,3,54,255}, {84,26,70,255}},
  { "residue.png", "stripes", {34,18,0,255}, {42,36,34,255}},
  { "scatter.png", "stripes", {122,56,108,255}, {101,61,106,255}},
  { "scorch.png", "stripes", {119,2,71,255}, {99,25,81,255}},
  { "sentry_kit.png", "ammo", {97,64,78,255}, {255,182,193,255}},
  { "severance.png", "blade", {51,66,53,255}, {47,63,28,255}, {174,207,137,255}},
  { "spark.png", "stripes", {73,37,91,255}, {68,48,94,255}},
  { "targeting_log.png", "ammo", {53,101,65,255}, {159,255,153,255}},
  { "tracer.png", "stripes", {50,122,53,255}, {53,105,69,255}},
  { "turret_base.png", "stripes", {114,53,99,255}, {96,59,100,255}},
  { "turret_head.png", "stripes", {46,86,13,255}, {50,81,43,255}},
  { "turret_side.png", "stripes", {35,19,97,255}, {43,36,98,255}},
  { "turret_top.png", "stripes", {60,116,58,255}, {60,101,73,255}},
}

local defs = {}
for _, row in ipairs(ICONS) do
	local name, pattern, base, second, accent = row[1], row[2], row[3], row[4], row[5]
	defs[#defs + 1] = {
		name = "sl_weapons_" .. name,
		w = 16, h = 16,
		seed = 0,
		draw = function(c)
			if pattern == "stripes" then
				-- 1px horizontal two-tone stripes
				C.stripes_h(c, base, second)
			elseif pattern == "ammo" then
				C.clear(c, base)
				C.rect(c, 6, 6, 4, 4, second)
			elseif pattern == "frame" then
				C.clear(c, base)
				C.frame(c, 0, 0, 16, 16, second)
			elseif pattern == "blade" then
				C.clear(c, base)
				C.frame(c, 0, 0, 16, 16, second)
				C.rect(c, 5, 2, 5, 13, accent)
			end
		end,
	}
end
return defs
