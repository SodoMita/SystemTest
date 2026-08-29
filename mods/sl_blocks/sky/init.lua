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
-- Ambient particles — NO ABM (rejected: too slow).
--
-- A low-frequency globalstep samples a small fixed set of
-- blocks around each player (a few cached voxel lookups per
-- 2 s) and emits at most ONE particle per player per tick
-- when a cloud is found. No node scans, no ABMs.
--
-- Note: this engine has no `minetest.particles` global (that
-- was the cause of an AsyncErr crash). Particles are spawned
-- through core.add_particlespawner, which takes a definition
-- table and self-terminates after `time` seconds.
-- ============================================================

local CLOUD_PARTICLE = {
	["sky:cloud"] = {
		texture = "cloud_leaf_particle.png",
		vy = 0.05, vy_max = 0.3, ay = 0.06, vertical = true,
	},
	["sky:cloud_solid"] = {
		texture = "cloud_particle.png",
		vy = 0.0, vy_max = 0.15, ay = -0.02, vertical = false,
	},
}

local OFFSETS = {
	{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1},
	{1, 1}, {-1, -1}, {1, -1}, {-1, 1},
}

-- Spawn a short-lived, low-volume particlespawner at a cloud
-- node. One call per player per 2 s; the spawner lives 2 s and
-- is then gone. No ABM, no persistent objects.
local function emit_for_player(ppos)
	local px = math.floor(ppos.x)
	local py = math.floor(ppos.y)
	local pz = math.floor(ppos.z)
	for dy = -1, 9 do
		for _, o in ipairs(OFFSETS) do
			local n = minetest.get_node_or_nil({x = px + o[1], y = py + dy, z = pz + o[2]})
			if n and CLOUD_PARTICLE[n.name] then
				if math.random() >= 0.5 then return end
				local spec = CLOUD_PARTICLE[n.name]
				local nx = px + o[1] + 0.1
				local ny = py + dy + 0.1
				local nz = pz + o[2] + 0.1
				core.add_particlespawner({
					amount = 4,
					time = 2,
					minpos = { x = nx, y = ny, z = nz },
					maxpos = { x = nx + 0.8, y = ny + 0.8, z = nz + 0.8 },
					minvel = { x = -0.2, y = spec.vy, z = -0.2 },
					maxvel = { x = 0.2, y = spec.vy_max, z = 0.2 },
					minacc = { x = -0.02, y = spec.ay, z = -0.02 },
					maxacc = { x = 0.02, y = spec.ay, z = 0.02 },
					minexptime = 2,
					maxexptime = 4,
					minsize = 2,
					maxsize = 4,
					vertical = spec.vertical,
					texture = spec.texture,
				})
				return
			end
		end
	end
end

-- Guard: if this engine build lacks the spawner API entirely,
-- skip ambient particles instead of crashing.
if type(core.add_particlespawner) == "function" then
	local step_acc = 0
	minetest.register_globalstep(function(dtime)
		step_acc = step_acc + dtime
		if step_acc < 2 then return end
		step_acc = 0
		for _, player in ipairs(minetest.get_connected_players()) do
			local ppos = player:get_pos()
			if ppos then
				emit_for_player(ppos)
			end
		end
	end)
end
