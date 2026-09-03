-- ================================================================
-- System Looting — MM essence engine (design ruling §13.3)
-- ================================================================
-- The Monster Master's essence is earned by DESTRUCTION of nodes the
-- crew has placed, scaled by the node's price; select crafts credit
-- the pool directly (the objective core is the named +3 craft); the
-- pool is FUEL, never score — points come from killing crew.
--
-- RULES (owner ruling, recorded in MASTER_DESIGN_FULL.md §13.3):
--   1. Destroying a crew-placed node credits the MM pool
--      `essence = price(node)`. Only crew-placed nodes count — map,
--      worldgen and engine nodes do not pay; provenance is the
--      bookkeeper. Any digger pays (the MM destroying a bastion is
--      the intended tension).
--   2. Certain crafts credit the pool on completion — the objective
--      core (+3) is the named example; ESSENCE_CRAFT_CREDITS scales
--      to the Objective Forge later.
--   3. Essence is NOT a score. Points are a separate ladder and come
--      primarily from killing crew. Nothing here touches the
--      kill/points path.
--   4. No-MM matches accrue the pool into AMBIENT HAZARD: at
--      thresholds (settingtypes `sl_essence.thresholds`, default
--      10/25/50) one automated security unit spawns from the Node.
--
-- POOL SEMANTICS (added at implementation): the pool is per-match
-- state, reset at every match start and every match end — nothing
-- carries into the lobby. Provenance is per-match too: it is dropped
-- on dig and cleared wholesale at reset.
--
-- PRICING: `groups.sl_essence_value = N` on a node def is the price
-- (default 0 — rubble, scaffolding and components pay nothing). The
-- craftable output defs carry real values from the crafting economy
-- (fortify blocks 1, hideout 2, spawner unit 4, objective core 5).
-- ================================================================

local S = game_mode.S
local state = game_mode.state
local modname = game_mode.modname

local function mm_state()
	return state.monster_master
end

-- Default ambient-hazard thresholds. "10,25,50" means one automated
-- security unit at pool 10, another at 25, another at 50.
local DEFAULT_THRESHOLDS = { 10, 25, 50 }

local function parse_thresholds()
	local raw = minetest.settings and minetest.settings:get("sl_essence.thresholds")
	local out = {}
	if raw and raw ~= "" then
		for part in tostring(raw):gmatch("(%d+)") do
			local n = tonumber(part)
			if n and n > 0 then table.insert(out, n) end
		end
	end
	if #out == 0 then
		for _, n in ipairs(DEFAULT_THRESHOLDS) do table.insert(out, n) end
	end
	table.sort(out)
	return out
end

-- ----------------------------------------------------------------
-- Per-match pool / provenance / hazard state (reset by
-- game_mode.essence_reset at match start and match end)
-- ----------------------------------------------------------------
local mm = mm_state()
mm.essence_pool = 0          -- int; fuel for the spawner unit + hazard
mm.essence_provenance = {}   -- [pos_hash] = price, for crew-placed nodes
mm.essence_hazard_level = 0  -- automated security units spawned so far
mm.essence_thresholds = parse_thresholds()

-- ----------------------------------------------------------------
-- Pricing
-- ----------------------------------------------------------------
-- The canonical price field is `groups.sl_essence_value` on the node
-- def. Default 0: ground blocks, components and cheap scaffolding pay
-- nothing (the ruling's "cheap scaffolding" line).
function game_mode.essence_price(node_name)
	local def = minetest.registered_nodes and minetest.registered_nodes[node_name]
	if not def or not def.groups then return 0 end
	return tonumber(def.groups.sl_essence_value) or 0
end

-- ----------------------------------------------------------------
-- Provenance: crew-placed nodes -> price
-- ----------------------------------------------------------------
-- Composes with the map journal's own on_placenode/on_dignode
-- handlers (both run; nothing is clobbered). Map-placed nodes never
-- pay: the map system materializes under map.building, and the
-- beacons / altar / MM pad / spawner are all map anchors. Sl_weapons
-- residue and scorch (no player) never pay.
minetest.register_on_placenode(function(pos, newnode, placer, oldnode)
	if not state.match_active then return end
	if game_mode.map and game_mode.map.building then return end
	if not placer or not placer.is_player or not placer:is_player() then return end

	local name = placer:get_player_name()
	local pl = state.players[name]
	if not pl or not game_mode.is_beacon_team(pl.team) then return end

	local price = game_mode.essence_price(newnode and newnode.name)
	if not price or price <= 0 then return end

	-- A replacement overwrites the old provenance (the new node is
	-- what the MM can destroy now; the crew chose the exchange).
	mm_state().essence_provenance[game_mode.pos_hash(pos)] = price
end)

minetest.register_on_dignode(function(pos, oldnode, digger)
	if not state.match_active then return end
	local hash = game_mode.pos_hash(pos)
	local price = mm_state().essence_provenance[hash]
	if not price then return end

	mm_state().essence_provenance[hash] = nil
	-- Any digger pays the pool — MM destroying a bastion credits the
	-- MM (ruling rule 1); the provenance is spent, no double-pay.
	game_mode.add_mm_essence(price, "node:" .. (oldnode and oldnode.name or "?"))
end)

-- ----------------------------------------------------------------
-- Pool credit API
-- ----------------------------------------------------------------
-- The single credit path for the pool: node destruction (above) and
-- named crafts (on_craft_essence). Refuses outside a match — the
-- pool is per-match state.
function game_mode.add_mm_essence(amount, source)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount <= 0 then return false end
	if not state.match_active then return false end
	mm_state().essence_pool = (mm_state().essence_pool or 0) + amount
	game_mode.essence_hazard_check()
	return true
end

function game_mode.essence_pool()
	return mm_state().essence_pool or 0
end

-- ----------------------------------------------------------------
-- Named crafts pay directly (ruling rule 2)
-- ----------------------------------------------------------------
-- The objective core is the named +3 craft; the same hook scales to
-- the Objective Forge. Fired by the crafting handler on completion.
game_mode.ESSENCE_CRAFT_CREDITS = {
	[modname .. ":objective_core"] = 3,
}

function game_mode.on_craft_essence(output_name, count)
	if not state.match_active then return end
	local credit = game_mode.ESSENCE_CRAFT_CREDITS[output_name]
	if not credit then return end
	count = math.max(1, math.floor(tonumber(count) or 1))
	game_mode.add_mm_essence(credit * count, "craft:" .. tostring(output_name))
end

-- ----------------------------------------------------------------
-- Ambient hazard (ruling rule 4)
-- ----------------------------------------------------------------
-- With no Monster Master in the match the pool accrues; at each
-- threshold one automated security unit spawns from the Node (the
-- MM redoubt anchor, falling back to the MM base spawn). A live MM
-- means no automation — the pool is theirs to spend.
local HAZARD_VARIANT = "custodian"

function game_mode.essence_hazard_check()
	if not state.match_active then return end
	if mm_state().player then return end

	local thresholds = mm_state().essence_thresholds or parse_thresholds()
	local level = mm_state().essence_hazard_level or 0
	local next_threshold = thresholds[level + 1]
	if not next_threshold then return end
	if (mm_state().essence_pool or 0) < next_threshold then return end

	local pos
	if game_mode.map and game_mode.map.current and game_mode.map.current.anchor
		and game_mode.map.current.anchor.mm_pad then
		local pad = game_mode.map.current.anchor.mm_pad
		pos = { x = pad.x, y = pad.y + 1, z = pad.z }
	else
		local base = mm_state().base_spawn
		pos = { x = base.x, y = base.y + 1, z = base.z }
	end

	local obj = game_mode.spawn_monster(pos, HAZARD_VARIANT)
	if not obj then
		minetest.log("warning", "[game_mode] essence hazard could not spawn a "
			.. HAZARD_VARIANT .. " at " .. minetest.pos_to_string(pos))
		return
	end
	mm_state().essence_hazard_level = level + 1
	game_mode.broadcast(S("The Node's security unit materializes. (essence @1)",
		tostring(mm_state().essence_pool)))
end

-- ----------------------------------------------------------------
-- Per-match reset
-- ----------------------------------------------------------------
-- Called at match start (after the map is prepared) and at match end
-- (after the map reset) — the pool, provenance and hazard counter
-- never survive into the lobby or leak into the next match.
function game_mode.essence_reset()
	local m = mm_state()
	m.essence_pool = 0
	m.essence_provenance = {}
	m.essence_hazard_level = 0
	m.essence_thresholds = parse_thresholds()
end
