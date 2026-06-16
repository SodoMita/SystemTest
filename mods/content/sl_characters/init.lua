-- sl_characters
-- Holds custom character models for System Looting.
--
-- This mod currently only ships model assets (models/SimpleOutlinedBoxman.glb).
-- It is kept as a loadable mod so the model directory is registered in the media
-- system and can be referenced by player_api / entities once a model is wired in.
--
-- TODO (Phase 1+): register the boxman model with player_api, e.g.:
--   player_api.register_model("SimpleOutlinedBoxman.glb", { ... })
-- and switch the default player model to it.

local modname = minetest.get_current_modname()
minetest.log("action", "[" .. modname .. "] loaded (model assets only; no models registered yet)")
