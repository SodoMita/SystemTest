-- Boxman player model registration.

local MODEL_NAME = "SimpleOutlinedBoxman.glb"
local MODEL_TEXTURE = "sl_boxman_neon.png"

-- The source GLB is a simple object-animated prototype model.  Luanti's player
-- API expects a common animation table; these ranges are intentionally broad and
-- safe for a model that may have only a few imported animation channels.  Missing
-- or static ranges simply render as the model's rest pose rather than breaking.
local boxman_animations = {
	stand     = {x = 0,  y = 0},
	walk      = {x = 1/60,  y = 40/60},
	mine      = {x = 41/60,  y = 60/60},
	walk_mine = {x = 61/60,  y = 99/60},
	-- Used by the existing player_api crawl/zoom logic.
	sit       = {
		x = 101/60, y = 101/60,
		eye_height = 0.8,
		override_local = true,
		collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.0, 0.3},
	},
	crawl     = {
		x = 100/60, y = 100/60,
		eye_height = 0.55,
		override_local = true,
		collisionbox = {-0.3, 0.0, -0.3, 0.3, 0.8, 0.3},
	},
	lay       = { -- death actually
		x = 102/60, y = 102/60,
		eye_height = 0.3,
		override_local = true,
		collisionbox = {-0.6, 0.0, -0.6, 0.6, 0.3, 0.6},
	},
	die       = {
		x = 102/60, y = 102/60,
		eye_height = 0.3,
		override_local = true,
		collisionbox = {-0.6, 0.0, -0.6, 0.6, 0.3, 0.6},
	},
}

player_api.register_model(MODEL_NAME, {
	animation_speed = 2,
	textures = {MODEL_TEXTURE},
	animations = boxman_animations,

	-- The GLB is larger than a normal Luanti player; scale it down to roughly
	-- player height while keeping normal collision and eye height.
	visual_size = {x=10,y=10},
	collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
	stepheight = 0.6,
	eye_height = 1.47,
})

local function apply_boxman(player)
	if not player or not player:is_player() then
		return
	end
	player_api.set_model(player, MODEL_NAME)
	player_api.set_textures(player, {MODEL_TEXTURE})
end

-- Export a tiny API for later team skins/outfits to call if they need to reset
-- the base body model.
sl_characters = rawget(_G, "sl_characters") or {}
sl_characters.default_model = MODEL_NAME
sl_characters.default_texture = MODEL_TEXTURE
sl_characters.apply_default_model = apply_boxman

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	-- Run one tick later so this wins over player_api's own default join callback
	-- and any other immediate join-time appearance setup.
	minetest.after(0, function()
		local p = minetest.get_player_by_name(name)
		if p then
			apply_boxman(p)
		end
	end)
end)

minetest.register_on_mods_loaded(function()
	-- Helpful during /reload-style development and harmless during normal startup.
	minetest.after(0, function()
		for _, player in ipairs(minetest.get_connected_players()) do
			apply_boxman(player)
		end
	end)
end)

minetest.register_chatcommand("sl_boxman", {
	description = "Reset your visible player model to System Looting's outlined boxman.",
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		apply_boxman(player)
		return true, "Boxman player model applied."
	end,
})

minetest.log("action", "[sl_characters] registered player model " .. MODEL_NAME)
