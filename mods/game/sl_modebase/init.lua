local modname = minetest.get_current_modname()
local S = minetest.get_translator(modname)
local modpath = minetest.get_modpath(modname)

-- Global shared table for this game mode, similar to ctf_* APIs
game_mode = rawget(_G, "game_mode") or {}
_G.game_mode = game_mode

game_mode.modname = modname
game_mode.S = S
game_mode.modpath = modpath

-- Core configurable constants
game_mode.LIVES_PER_PLAYER = game_mode.LIVES_PER_PLAYER or 5

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
	"entities.lua", -- monster entities
	"nodes.lua",    -- beacon nodes
	"commands.lua"  -- chat commands and privileges
)

minetest.log("action", "[game_mode] Loaded core PvP game mode with beacons and monster master")

