-- ================================================================
-- sl_solo/director.lua — THE SIMULATION plays the Monster Master.
-- ================================================================
-- A scripted asymmetric commander: escalating waves of mode monsters
-- and sl_scary horror entities, deployed around both beacon teams and
-- the midfield altar. No Monster Master human, no spawner unit, no
-- essence economy — the Simulation IS the economy. Wave size and mix
-- come from the difficulty preset chosen at /solo_start.
--
-- Deployment reuses the real content pipeline:
--   game_mode.spawn_monster(pos, variant, owner)
-- which covers the shared monster variants (stalker/scout/brute) and
-- deploys sl_scary entities (dredger/wraith/containment) as-is.
-- ================================================================

local S = sl_solo.S

-- Wave announcements cycle in order; the Simulation's voice.
local WAVE_FLAVOR = {
	"The hungry code arrives. Feed it.",
	"Your perimeter is a rounding error.",
	"Salvage is theft. The fee is due.",
	"I have worn crews like this one before.",
	"Format yourself for deletion.",
	"The walls remember every scream you muffled.",
	"You are not the first crew to negotiate.",
	"Panic is a valid data point. Continue.",
	"Your beacon prays to me. It told me everything.",
}

-- Build the monster list for wave `w` under a difficulty preset.
function sl_solo.wave_composition(w, preset)
	local wc = preset.waves
	local list = {}

	local function add(variant, n)
		for _ = 1, n do table.insert(list, variant) end
	end

	add("stalker", wc.stalker_base + math.floor(w * wc.stalker_growth))
	if w >= (wc.scout_from or 99) then
		add("scout", math.floor((w - wc.scout_from + 2) * wc.scout_growth))
	end
	if wc.brute_from and wc.brute_from > 0 and w >= wc.brute_from then
		add("brute", math.floor((w - wc.brute_from + 2) * (wc.brute_growth or 0.34)))
	end
	if wc.dredger_from and wc.dredger_from > 0 and w >= wc.dredger_from then
		add("dredger", 1 + math.floor(w / 4))
	end
	if wc.wraith_from and wc.wraith_from > 0 and w >= wc.wraith_from then
		add("wraith", 1)
	end
	if wc.containment_from and wc.containment_from > 0 and w >= wc.containment_from then
		add("containment", 1)
	end

	-- Deterministic-ish shuffle so waves do not clump identically.
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	while #list > (wc.cap or 9) do table.remove(list) end
	return list
end

-- Spawn ring around a point on the arena floor (y=0 floor, bots and
-- beacons live at y>=1). Keeps a polite 5-9 m ring so spawns never
-- materialize inside melee.
local function ring_pos(center, half_extent)
	local ang = math.random() * 2 * math.pi
	local r = 5 + math.random() * 4
	local x = center.x + math.cos(ang) * r
	local z = center.z + math.sin(ang) * r
	local lim = (half_extent or 16) - 1
	x = math.max(-lim, math.min(lim, x))
	z = math.max(-lim, math.min(lim, z))
	return { x = math.floor(x), y = 1.5, z = math.floor(z) }
end

function sl_solo.director_step(dtime)
	local st = sl_solo.state
	local preset = st.preset
	if not preset then return end

	-- Endless (nightmare) or until the wave budget is spent.
	if preset.total_waves > 0 and st.wave >= preset.total_waves then return end

	local now = game_mode.now()
	if now < st.next_wave_at then return end

	st.wave = st.wave + 1
	st.next_wave_at = now + preset.wave_interval

	local gm = game_mode
	local comp = sl_solo.wave_composition(st.wave, preset)

	-- Pressure is distributed: CORE A ring, CORE B ring, and midfield
	-- rotate as anchor points so neither team (nor the altar) is safe.
	local anchors = {}
	local a_spawn = gm.state.teams.beacon_a and gm.state.teams.beacon_a.spawn
	local b_spawn = gm.state.teams.beacon_b and gm.state.teams.beacon_b.spawn
	if a_spawn then table.insert(anchors, { x = a_spawn.x, y = a_spawn.y, z = a_spawn.z }) end
	if b_spawn then table.insert(anchors, { x = b_spawn.x, y = b_spawn.y, z = b_spawn.z }) end
	table.insert(anchors, { x = 0, y = 1, z = 0 }) -- altar / midfield

	local spawned = 0
	for i, variant in ipairs(comp) do
		local anchor = anchors[((i - 1) % #anchors) + 1]
		local pos = ring_pos(anchor)
		local obj = gm.spawn_monster(pos, variant, "THE_SIMULATION")
		if obj then
			table.insert(st.wave_mobs, obj)
			spawned = spawned + 1
		end
	end

	sl_solo.flavor_i = st.flavor_i + 1
	local flavor = WAVE_FLAVOR[((st.flavor_i - 1) % #WAVE_FLAVOR) + 1]
	sl_solo.announce(S("THE SIMULATION: WAVE @1 — @2 (@3 hostiles)",
		tostring(st.wave), flavor, tostring(spawned)))
	sl_solo.log(string.format("wave %d deployed: %d hostiles (difficulty %s)",
		st.wave, spawned, st.difficulty))
end

-- Count live hostiles (HUD / status).
function sl_solo.count_monsters()
	local n = 0
	for _, le in pairs(minetest.luaentities) do
		if type(le) == "table" and le.name and sl_solo.monster_names[le.name] then
			n = n + 1
		end
	end
	return n
end

-- Nearest hostile object to pos within range (crew reflex + Echo cowardice).
function sl_solo.nearest_monster(pos, range)
	local best, best_d = nil, range
	for _, le in pairs(minetest.luaentities) do
		if type(le) == "table" and le.name and sl_solo.monster_names[le.name]
				and le.object and le.object.get_pos then
			local ok, opos = pcall(le.object.get_pos, le.object)
			if ok and opos then
				local d = vector.distance(pos, opos)
				if d < best_d then
					best, best_d = le.object, d
				end
			end
		end
	end
	return best, best_d
end

-- End of run: the Simulation withdraws. Removes registered wave mobs
-- plus any stragglers of the known hostile flavors.
function sl_solo.clear_monsters()
	local st = sl_solo.state
	for _, obj in ipairs(st.wave_mobs) do
		if obj and obj.remove then
			pcall(obj.remove, obj)
		end
	end
	st.wave_mobs = {}
	-- Collect before removing: removal mutates the engine's active
	-- entity list, and mutating a table during pairs() is undefined.
	local stragglers = {}
	for _, le in pairs(minetest.luaentities) do
		if type(le) == "table" and le.name and sl_solo.monster_names[le.name]
				and le.object and le.object.remove then
			table.insert(stragglers, le.object)
		end
	end
	for _, obj in ipairs(stragglers) do
		pcall(obj.remove, obj)
	end
end
