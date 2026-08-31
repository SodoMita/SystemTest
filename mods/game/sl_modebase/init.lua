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

