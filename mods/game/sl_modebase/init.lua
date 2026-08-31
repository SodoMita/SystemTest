local modname = minetest.get_current_modname()
local S = minetest.get_translator(modname)
local modpath = minetest.get_modpath(modname)

-- Global shared table for this game mode, similar to ctf_* APIs
game_mode = rawget(_G, "game_mode") or {}
_G.game_mode = game_mode

game_mode.modname = modname
game_mode.S = S
game_mode.modpath = modpath

-- ----------------------------------------------------------------
-- Division-by-zero armour (live-server incident 2026-08-29):
-- normalizing a zero-length vector yields NaN, and NaN velocity or
-- position reaching a client segfaults Luanti — a point-blank
-- mortar-jump (blast centre exactly on the player) crashed the
-- client through exactly that hole. Every direction that feeds a
-- movement write goes through safe_dir; every vector that feeds a
-- velocity/position write is checked with vector.finite.
-- (sl_weapons and the rest of the arsenal rely on these being
-- installed before any mod code runs — tests/weapons_test.lua
-- asserts them as the "vector armour" gate.)
-- ----------------------------------------------------------------
function vector.safe_dir(v, fallback)
	fallback = fallback or { x = 0, y = 0, z = 0 }
	if type(v) ~= "table" then return fallback end
	local x, y, z = tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0
	local len = math.sqrt(x * x + y * y + z * z)
	if len ~= len or len < 0.001 then return fallback end
	return { x = x / len, y = y / len, z = z / len }
end

function vector.finite(v)
	if type(v) ~= "table" then return false end
	local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
	if not x or not y or not z then return false end
	return x == x and y == y and z == z
		and math.abs(x) ~= math.huge
		and math.abs(y) ~= math.huge
		and math.abs(z) ~= math.huge
end

-- Core configurable constants
-- (Single-life design: no lives system. First death -> cloud cage.)

-- Helper to include local files, like ctf_core.include_files
local function include_files(...)
	for _, file in ipairs({...}) do
		dofile(modpath .. "/" .. file)
	end
end

include_files(
	"state.lua",    -- persistent state, teams, helpers
	"spawn.lua",    -- spawn logic and join/respawn hooks
	"match.lua",    -- match lifecycle and win conditions
	"matchmaking.lua", -- matchmaking UI and lobby terminal
	"entities.lua", -- monster entities
	"nodes.lua",    -- beacon nodes + loot crate
	"content.lua",  -- craftable items, tools, tactical nodes, interactables
	"whisper.lua", -- THE WHISPER: evil-ghost body possession + one lie-channel (Melody)
	"test_harness.lua", -- headless AI agents and deterministic arena builder
	"commands.lua", -- chat commands and privileges
	"hud.lua"       -- persistent match HUD (identity-neutral)
)

minetest.log("action", "[game_mode] Loaded core PvP game mode with beacons and monster master")

