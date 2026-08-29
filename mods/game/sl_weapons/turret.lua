-- ================================================================
-- sl_weapons — the Sentry Kit (spec §6)
-- Player-deployable zone denial. Deployer-only IFF: it shoots every
-- living player except the person who placed it, plus all monsters —
-- never teams (a team-aware turret is an identity oracle).
-- 90 s battery (a timer is a decision), 25 HP, dies into scrap and
-- its targeting log: the sentry is a witness; destroying it acquires
-- its testimony (council resolution #9).
-- ================================================================

local W = sl_weapons
local S = W.S

W.turrets = {} -- [phash] = entry
W.last_logs = {} -- FIFO of destroyed-turret logs (fallback reads)

local TURRET_RANGE = 12
local TURRET_HP = 25
local TURRET_TRACK = { acquire = 0.4, lose = 1.5, shot = 0.8, dmg = 2, sweep = 60 }

local function turret_limits()
	return {
		player = W.get_setting_number("sl_weapons_turret_max_player", 1),
		team = W.get_setting_number("sl_weapons_turret_max_team", 3),
		lifetime = W.get_setting_number("sl_weapons_turret_lifetime", 90),
	}
end

-- ----------------------------------------------------------------
-- Targeting log item
-- ----------------------------------------------------------------
minetest.register_craftitem(W.modname .. ":targeting_log", {
	description = S("Targeting Log\n(Read a sentry's last 30 seconds)"),
	inventory_image = "sl_weapons_targeting_log.png",
	on_use = function(itemstack, user)
		if not user or not user.is_player or not user:is_player() then return itemstack end
		local name = user:get_player_name()
		-- Engine: per-stack metadata (full fidelity). Stub: most
		-- recent destroyed turret's log (data decays quickly).
		local lines = nil
		local meta = itemstack.get_meta and itemstack:get_meta()
		if meta then
			local raw = meta:get_string("sl_log")
			if raw ~= "" then lines = minetest.deserialize(raw) end
		end
		if not lines and #W.last_logs > 0 then
			lines = W.last_logs[1]
		end
		if not lines or #lines == 0 then
			minetest.chat_send_player(name, S("The log is blank. The witness saw nothing."))
			return itemstack
		end
		minetest.chat_send_player(name, minetest.colorize("#66ddff",
			S("TARGETING LOG — deposition of a dead sentry")))
		for _, l in ipairs(lines) do
			minetest.chat_send_player(name, "  " .. l)
		end
		return itemstack
	end,
})

local function log_push(entry, text)
	table.insert(entry.log, string.format("%d:%02d  %s",
		math.floor(W.now() % 3600 / 60), math.floor(W.now() % 60), text))
	while #entry.log > 30 do table.remove(entry.log, 1) end
end

-- ----------------------------------------------------------------
-- Turret node + cosmetic head
-- ----------------------------------------------------------------
minetest.register_entity(W.modname .. ":turret_head", {
	sl_weapon_fx = true,
	_stub_ray_radius = 0.3,
	initial_properties = {
		visual = "cube",
		textures = { "sl_weapons_turret_head.png" },
		visual_size = { x = 4, y = 4 },
		physical = false,
		pointable = false,
		static_save = false,
	},
	on_step = function(self, _dtime)
		-- Idle sweep handled by the turret tick (rotation feedback).
	end,
})

minetest.register_node(W.modname .. ":turret", {
	description = S("Sentry Turret"),
	tiles = { "sl_weapons_turret_top.png", "sl_weapons_turret_base.png",
		"sl_weapons_turret_side.png" },
	paramtype2 = "facedir",
	light_source = 4,
	groups = { cracky = 2, possessable = 1, not_in_creative_inventory = 1 },
	is_ground_content = false,
	drop = "",

	can_dig = function() return false end, -- destroyed by damage, not dug

	on_destruct = function(pos)
		W.remove_turret(pos, "dug")
	end,

	on_rightclick = function(pos, node, clicker)
		if game_mode and game_mode.refuse_if_possessed
			and game_mode.refuse_if_possessed(pos, clicker) then
			return
		end
		local entry = W.turrets[W.phash(pos)]
		if not entry then return end
		local name = clicker:get_player_name()
		minetest.chat_send_player(name, minetest.colorize("#66ddff",
			S("SENTRY STATUS — @1 s battery — @2",
				tostring(math.max(0, math.floor(entry.battery_end - W.now()))),
				tostring(entry.hp) .. "/25 HP")))
		if #entry.log > 0 then
			minetest.chat_send_player(name, S("Recent activity:"))
			for i = math.max(1, #entry.log - 4), #entry.log do
				minetest.chat_send_player(name, "  " .. entry.log[i])
			end
		else
			minetest.chat_send_player(name, S("Recent activity: nothing"))
		end
	end,

	on_punch = function(pos, node, puncher)
		local wield = puncher and puncher.get_wielded_item
			and puncher:get_wielded_item():get_name() or ""
		local def = W.defs_by_item[wield]
		local dmg
		if def then
			dmg = def.damage or 2
		elseif wield:find("blade") or wield:find("axe") or wield:find("pick") then
			dmg = 5 -- blades crack machines faster than fists
		else
			dmg = 3
		end
		W.damage_turret(pos, dmg, puncher)
	end,
})

-- ----------------------------------------------------------------
-- Deployment
-- ----------------------------------------------------------------
minetest.register_craftitem(W.modname .. ":sentry_kit", {
	description = S("Sentry Kit\n(Deploy on a solid surface)"),
	inventory_image = "sl_weapons_sentry_kit.png",

	on_place = function(itemstack, placer, pointed_thing)
		if not placer or not placer.is_player or not placer:is_player() then
			return itemstack
		end
		local name = placer:get_player_name()
		if not W.get_setting_bool("sl_weapons_enabled", true) then
			return itemstack
		end
		if game_mode then
			local pl = game_mode.get_player_state(name)
			if pl and pl.role == "monster_master" then
				minetest.chat_send_player(name, minetest.colorize("#ff8844",
					S("The system does not take your orders twice.")))
				return itemstack
			end
			if not (game_mode.state and game_mode.state.match_active) then
				minetest.chat_send_player(name, S("Turrets deploy only during an active match."))
				return itemstack
			end
			if pl and pl.phase ~= "alive" then
				minetest.chat_send_player(name, S("The dead build nothing."))
				return itemstack
			end
		end
		if not pointed_thing or pointed_thing.type ~= "node" then
			return itemstack
		end
		local pos = vector.round(pointed_thing.above)
		local below = minetest.get_node({ x = pos.x, y = pos.y - 1, z = pos.z })
		if below.name == "air" then
			minetest.chat_send_player(name, S("The sentry needs solid ground."))
			return itemstack
		end
		if minetest.get_node(pos).name ~= "air" then
			return itemstack
		end

		-- Limits: 1 per player, 3 per beacon team (spec §6 table).
		local limits = turret_limits()
		local counts = { player = 0, team = 0 }
		local team
		if game_mode then
			local pl = game_mode.get_player_state(name)
			team = pl and pl.team or nil
		end
		for _, e in pairs(W.turrets) do
			if e.deployer == name then counts.player = counts.player + 1 end
			if team and e.team == team then counts.team = counts.team + 1 end
		end
		if counts.player >= limits.player then
			minetest.chat_send_player(name, S("You keep one sentry at a time."))
			return itemstack
		end
		if team and counts.team >= limits.team then
			minetest.chat_send_player(name, S("Your team's sentry grid is at capacity (@1).",
				tostring(limits.team)))
			return itemstack
		end

		minetest.set_node(pos, { name = W.modname .. ":turret" })
		local head = minetest.add_entity({ x = pos.x, y = pos.y + 0.85, z = pos.z },
			W.modname .. ":turret_head")
		local entry = {
			pos = pos,
			deployer = name,
			team = team,
			hp = TURRET_HP,
			battery_end = W.now() + limits.lifetime,
			head = head,
			log = {},
			next_shot = 0,
			acquire_at = 0,
			lose_at = 0,
			target = nil,
		}
		W.turrets[W.phash(pos)] = entry
		log_push(entry, "deployed — battery " .. tostring(limits.lifetime) .. " s")
		minetest.sound_play("sl_weapons_turret_deploy", {
			pos = pos, gain = 0.8, max_hear_distance = 20,
		})
		itemstack:take_item()
		return itemstack
	end,
})

-- ----------------------------------------------------------------
-- Damage / destruction
-- ----------------------------------------------------------------
function W.damage_turret(pos, dmg, attacker)
	local entry = W.turrets[W.phash(pos)]
	if not entry then return end
	entry.hp = entry.hp - dmg
	minetest.sound_play("sl_weapons_turret_hit", {
		pos = pos, gain = 0.5, max_hear_distance = 14,
	})
	log_push(entry, "takes damage — " .. tostring(dmg))
	if entry.hp <= 0 then
		W.destroy_turret(pos, attacker, "shot")
	end
end

function W.destroy_turret(pos, attacker, how)
	local entry = W.turrets[W.phash(pos)]
	if not entry then return end
	W.turrets[W.phash(pos)] = nil
	local battery_left = math.max(0, entry.battery_end - W.now())

	-- The witness files its report (council resolution #9).
	table.insert(W.last_logs, 1, table.copy(entry.log))
	while #W.last_logs > 5 do table.remove(W.last_logs, #W.last_logs) end
	local log_stack = ItemStack(W.modname .. ":targeting_log 1")
	local meta = log_stack.get_meta and log_stack:get_meta()
	if meta and meta.set_string then
		meta:set_string("sl_log", minetest.serialize(entry.log))
	end
	minetest.add_item(pos, log_stack)
	if how == "shot" and battery_left > 0 and math.random(100) <= 50 then
		minetest.add_item(pos, ItemStack(W.modname .. ":sentry_kit 1"))
	end

	if entry.head and entry.head.remove then
		pcall(function() entry.head:remove() end)
	end
	minetest.set_node(pos, { name = "air" })
	minetest.sound_play("sl_weapons_turret_death", {
		pos = pos, gain = 0.9, max_hear_distance = 28,
	})
	for _ = 1, 10 do
		minetest.add_particle({
			pos = pos,
			velocity = { x = (math.random() - 0.5) * 6, y = math.random() * 6, z = (math.random() - 0.5) * 6 },
			acceleration = { x = 0, y = -8, z = 0 },
			expirationtime = 0.7,
			size = 3,
			texture = "sl_weapons_spark.png",
			glow = 12,
		})
	end
end

function W.remove_turret(pos, how)
	local entry = W.turrets[W.phash(pos)]
	if not entry then return end
	W.turrets[W.phash(pos)] = nil
	if entry.head and entry.head.remove then
		pcall(function() entry.head:remove() end)
	end
	if how == "dug" then
		minetest.log("action", "[sl_weapons] turret removed at " .. minetest.pos_to_string(pos))
	end
end

function W.turrets_sweep()
	for hash, entry in pairs(W.turrets) do
		if entry.head and entry.head.remove then
			pcall(function() entry.head:remove() end)
		end
		minetest.set_node(entry.pos, { name = "air" })
		W.turrets[hash] = nil
	end
end

-- ----------------------------------------------------------------
-- The tick: battery, possession flip, sabotage, targeting, fire.
-- ----------------------------------------------------------------
local function target_ok(entry, obj, possessed)
	if not obj or not obj.get_pos then return false end
	if W.is_fx_object(obj) then
		-- heads and hooks: skip; corpses are not targets either
		local lua = obj.get_luaentity and obj:get_luaentity()
		if lua and lua.sl_corpse then return false end
		return false
	end
	if obj:is_player() then
		local name = obj:get_player_name()
		if name == entry.deployer and not possessed then return false end
		if game_mode then
			local pl = game_mode.get_player_state(name)
			if not pl or pl.phase ~= "alive" then return false end
		end
		return true
	end
	return W.is_monster_object(obj)
end

local function los_blocked(from, to)
	-- Nodes only: the sightline cares about cover, not bodies.
	for hit in minetest.raycast(from, to, true, false) do
		if hit.type == "node" then
			return true
		end
	end
	return false
end

local function target_label(obj)
	if obj:is_player() then
		return "contact: " .. obj:get_player_name()
	end
	local lua = obj.get_luaentity and obj:get_luaentity()
	if lua and lua.monster_variant then
		return "lifeform: " .. tostring(lua.monster_variant)
	end
	return "unidentified lifeform"
end

local turret_accum = 0
minetest.register_globalstep(function(dtime)
	turret_accum = turret_accum + dtime
	if turret_accum < 0.2 then return end
	turret_accum = 0
	local now = W.now()

	-- NOTE: iterate the LIVE registry — table.copy would deep-copy every
	-- entry and all per-tick mutation (target, log, next_shot) would land
	-- on the copies. Removals are deferred to after the loop instead.
	local expired = {}
	for hash, entry in pairs(W.turrets) do
		-- Battery: a timer is a decision (team decision 2026-08-29).
		if now >= entry.battery_end then
			table.insert(expired, hash)
		else
			local possessed = game_mode and game_mode.is_possessed
				and game_mode.is_possessed(entry.pos) or false
			local sabotaged = game_mode and game_mode.is_sabotaged
				and game_mode.is_sabotaged(entry.pos) or false

			-- Validate current target
			if entry.target and (not target_ok(entry, entry.target, possessed)
				or vector.distance(entry.pos, entry.target:get_pos()) > TURRET_RANGE + 1) then
				if now >= (entry.lose_at or 0) then
					entry.target = nil
				end
			elseif entry.target then
				entry.lose_at = now + TURRET_TRACK.lose
			end

			-- Acquire
			if not entry.target and not sabotaged then
				local center = { x = entry.pos.x, y = entry.pos.y + 1.2, z = entry.pos.z }
				local best, bestd
				for _, obj in ipairs(minetest.get_objects_inside_radius(center, TURRET_RANGE)) do
					if target_ok(entry, obj, possessed) then
						local d = vector.distance(center, obj:get_pos())
						if not bestd or d < bestd then
							best, bestd = obj, d
						end
					end
				end
				if best then
					entry.target = best
					entry.acquire_at = now + TURRET_TRACK.acquire
					entry.lose_at = now + TURRET_TRACK.lose
					log_push(entry, "acquiring " .. target_label(best))
					minetest.sound_play("sl_weapons_turret_acquire", {
						pos = entry.pos, gain = 0.6, max_hear_distance = 18,
					})
				end
			end

			-- Fire: hitscan 2 dmg every 0.8 s once acquired.
			if entry.target and not sabotaged and now >= entry.acquire_at
				and now >= entry.next_shot then
				local from = { x = entry.pos.x, y = entry.pos.y + 1.4, z = entry.pos.z }
				local tpos = entry.target:get_pos()
				local to = { x = tpos.x, y = tpos.y + 1.0, z = tpos.z }
				if not los_blocked(from, to) then
					entry.next_shot = now + TURRET_TRACK.shot
					W.punch_object(nil, entry.target, TURRET_TRACK.dmg, "sentry",
						vector.distance(from, tpos))
					W.tracer_fx(from, to)
					minetest.sound_play("sl_weapons_turret_fire", {
						pos = from, gain = 0.5, max_hear_distance = 20,
					})
					log_push(entry, "fired at " .. target_label(entry.target))
				else
					entry.target = nil -- sightline lost
				end
			end

			-- Possessed turret: the strings are someone else's now.
			if possessed and not entry.flipped then
				entry.flipped = true
				log_push(entry, "CONTROL ANOMALY — IFF inverted")
				minetest.sound_play("sl_weapons_deadwalk_rise", {
					pos = entry.pos, gain = 0.8, max_hear_distance = 20,
				})
			elseif not possessed then
				entry.flipped = false
			end
		end
	end

	for _, hash in ipairs(expired) do
		local entry = W.turrets[hash]
		if entry then
			W.turrets[hash] = nil
			minetest.add_item(entry.pos, ItemStack("sl_modebase:scrap_metal 2"))
			log_push(entry, "battery spent — self-dismantle")
			table.insert(W.last_logs, 1, table.copy(entry.log))
			while #W.last_logs > 5 do table.remove(W.last_logs, #W.last_logs) end
			if entry.head and entry.head.remove then
				pcall(function() entry.head:remove() end)
			end
			minetest.set_node(entry.pos, { name = "air" })
			minetest.sound_play("sl_weapons_turret_powerdown", {
				pos = entry.pos, gain = 0.6, max_hear_distance = 16,
			})
		end
	end
end)
