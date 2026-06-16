-- sl_characters
-- Custom player character setup for System Looting.
--
-- The playable player mesh is the outlined boxman GLB shipped in this mod:
--   models/SimpleOutlinedBoxman.glb
--
-- player_api still provides animation/collision handling, but this mod registers
-- the boxman and applies it on join so the game no longer uses Luanti/MTG's
-- built-in character.b3d as the visible player model.

local modpath = minetest.get_modpath(minetest.get_current_modname())
dofile(modpath .. "/model_boxman.lua")
