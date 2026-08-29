-- ============================================================
-- Sky / cloud nodes.
--
-- Owner art directive 2026-08: clouds must look like real
-- clouds.  Two flavours:
--
--   sky:cloud        the classic opaque, walkable cloud block
--                    (solid white, soft pixel edges)
--   sky:cloud_puff   a leaves-style puffy cloud you can walk
--                    through; drifts off white glow particles
--
-- Sky textures belong in the sl_blocks modpack, not in the
-- upstream `default` mod.  This mod is also the home for any
-- future sky-layer nodes (void, high-altitude fog, etc.).
--
-- Old worlds that stored `default:cloud` are remapped here via
-- aliases so they keep loading after the node moved.
-- ============================================================

local function cloud_sounds()
	if default and default.node_sound_defaults then
		return default.node_sound_defaults()
	end
	return {}
end

-- Opaque, walkable cumulus slab.
minetest.register_node("sky:cloud", {
	description = "Cloud",
	tiles = {"sky_cloud.png"},
	use_texture_alpha = "opaque",
	walkable = true,
	is_ground_content = false,
	sounds = cloud_sounds(),
	groups = {not_in_creative_inventory = 1, choppy = 3},
})

-- Puffy, walk-through vapor (leaves-style drawtime look, white glow).
minetest.register_node("sky:cloud_puff", {
	description = "Cloud Puff",
	drawtype = "allfaces",
	tiles = {{name = "sky_cloud_puff.png", align_style = "node"}},
	inventory_image = "sky_cloud_puff.png",
	wield_image = "sky_cloud_puff.png",
	use_texture_alpha = "clip",
	visual_scale = 1.3,
	walkable = false,
	pointable = true,
	diggable = true,
	is_ground_content = false,
	sunlight_propagates = true,
	sounds = cloud_sounds(),
	groups = {not_in_creative_inventory = 1, choppy = 3, oddly_breakable_by_hand = 1},
})

if minetest.settings:get_bool("sky_cloud_drift", true) then
	minetest.register_abm({
		label = "cloud puff drift glow",
		nodenames = {"sky:cloud_puff"},
		interval = 1.6,
		chance = 3,
		action = function(pos)
			minetest.add_particle({
				pos = vector.offset(pos,
					math.random() - 0.5, math.random() * 0.6 - 0.2, math.random() - 0.5),
				velocity = vector.new((math.random() - 0.5) * 0.2, 0.15,
					(math.random() - 0.5) * 0.2),
				acceleration = vector.new(0, 0.02, 0),
				expiration = 2.5,
				size = 0.6 + math.random() * 0.8,
				collisiondetection = false,
				texture = "sky_glow.png",
				animation = {type = "vertical_frames",
					aspect_w = 16, aspect_h = 16, length = 2.5},
				glow = 6,
			})
		end,
	})
end

minetest.register_alias("default:cloud", "sky:cloud")
minetest.register_alias("cloud", "sky:cloud")
