-- ============================================================
-- Sky / cloud nodes.
--
-- Sky textures belong in the sl_blocks modpack, not in the
-- upstream `default` mod. This mod is also the home of any
-- future sky-layer nodes (void, high-altitude fog, etc.).
--
-- Old worlds that stored `default:cloud` are remapped here via
-- aliases so they keep loading after the node moved.
--
-- Three cloud types:
--   sky:cloud        — plant-like foliage clump (clip alpha)
--   sky:cloud_solid  — opaque, seamless, walkable, unbreakable
--   sky:cloud_water  — transparent white liquid: swimmable,
--                      static (no flow), obviously not water
-- ============================================================

-- Foliage cloud: a dense clump of plant-like leaves.
minetest.register_node("sky:cloud", {
	description = "Cloud (Foliage)",
	tiles = {"cloud.png"},
	use_texture_alpha = "clip",
	is_ground_content = false,
	groups = { choppy = 3 },
	sounds = default.node_sound_leaves_defaults(),
})

-- Solid cloud: opaque, seamless surface you can walk on.
-- Unbreakable by design — it is arena structure, not loot.
minetest.register_node("sky:cloud_solid", {
	description = "Cloud (Solid)",
	tiles = {"cloud_solid.png"},
	is_ground_content = false,
	walkable = true,
	groups = { unbreakable = 1 },
	sounds = default.node_sound_defaults(),
})

-- Cloud water: a white, translucent liquid cloud. Swimmable
-- (liquid physics with damping) but static — it has no flowing
-- alternative, so it never moves or spreads. Not water: no
-- pouring, no flow, just a walk/swim-through white haze.
minetest.register_node("sky:cloud_water", {
	description = "Cloud Water",
	tiles = {"cloud_water.png"},
	drawtype = "normal",
	use_texture_alpha = "blend",
	is_ground_content = false,
	walkable = true,
	climbable = true,
	liquidtype = "source",
	liquid_damping = 0.5,
	node_placement_prediction = "",
	groups = { liquid = 1, oddly_breakable_by_hand = 1 },
	sounds = default.node_sound_water_defaults(),
})

minetest.register_alias("default:cloud", "sky:cloud")
minetest.register_alias("cloud", "sky:cloud")

-- ============================================================
-- Ambient particles: drifting leaf specks around foliage
-- clouds and slow-rising dust motes around solid clouds.
-- Only emitted when a player is nearby (ABM keeps it cheap).
-- ============================================================

local function player_near(pos, radius)
	for _, p in ipairs(minetest.get_connected_players()) do
		local pp = p:get_pos()
		if pp and vector.distance(pp, pos) <= radius then
			return true
		end
	end
	return false
end

minetest.register_abm({
	label = "sky:cloud_particles",
	nodenames = {"sky:cloud", "sky:cloud_solid"},
	interval = 3,
	chance = 2,
	action = function(pos)
		if not player_near(pos, 28) then return end
		if math.random() >= 0.5 then return end
		local rnd = math.random
		local ppos = vector.new(pos.x + (rnd() - 0.5) * 1.6,
			pos.y + rnd() * 1.4, pos.z + (rnd() - 0.5) * 1.6)
		local solid = minetest.get_node(pos).name == "sky:cloud_solid"
		minetest.particles:add(ppos,
			solid and "cloud_particle.png" or "cloud_leaf_particle.png", {
			velocity = vector.new((rnd() - 0.5) * 0.5,
				0.1 + rnd() * 0.25, (rnd() - 0.5) * 0.5),
			acceleration = solid and vector.new(0, -0.03, 0) or vector.new(0, 0.08, 0),
			expirationtime = 2.5 + rnd() * 1.5,
			size = 2 + rnd() * 2,
			vertical = not solid,
		})
	end,
})
