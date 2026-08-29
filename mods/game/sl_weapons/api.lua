-- ================================================================
-- sl_weapons — core API (gates, pools, timing, bloom, incident feed)
-- Everything routes damage through object:punch() so the existing
-- sl_modebase guards (lobby / creative / ghost attackers) stay
-- authoritative (WEAPONS_SPEC §2 pillar 5).
-- ================================================================

local W = sl_weapons
local S = W.S

-- ----------------------------------------------------------------
-- Settings. minetest.settings:get returns nil when unset (engine and
-- stub alike), so defaults live here and not in get_bool.
-- ----------------------------------------------------------------
function W.get_setting_bool(key, default)
	local raw = minetest.settings:get(key)
	if raw == nil then return default end
	return raw == true or raw == "true" or raw == "1"
end

function W.get_setting_number(key, default)
	local raw = minetest.settings:get(key)
	local n = tonumber(raw)
	if n == nil then return default end
	return n
end

W.RAISE_DELAY = W.get_setting_number("sl_weapons_raise_delay", 0.3)

function W.now()
	return minetest.get_us_time() / 1000000
end

-- ----------------------------------------------------------------
-- Ammo pools (per player, match-scoped — swept in on_match_end).
-- The Lash and both cell weapons share the "cells" pool on purpose:
-- every swing is a railgun round you didn't buy (spec §10.1).
-- ----------------------------------------------------------------
W.POOL_MAX = { bullets = 150, shells = 30, cells = 60, rockets = 15 }
W.AMMO_YIELD = { bullets = 40, shells = 8, cells = 15, rockets = 4 }
W.pools = {}

function W.get_pool(name)
	local p = W.pools[name]
	if not p then
		p = { bullets = 0, shells = 0, cells = 0, rockets = 0 }
		W.pools[name] = p
	end
	return p
end

function W.add_ammo(name, kind, n)
	local pool = W.get_pool(name)
	local before = pool[kind] or 0
	pool[kind] = math.min(W.POOL_MAX[kind] or before + n, before + (n or 0))
	return pool[kind] - before
end

function W.take_ammo(name, kind, n)
	local pool = W.get_pool(name)
	if (pool[kind] or 0) >= n then
		pool[kind] = pool[kind] - n
		return true
	end
	return false
end

-- Read-only peek: never materializes a pool entry (the HUD must not
-- resurrect cleared pools after the match-end sweep).
function W.peek_pool(name)
	return W.pools[name] or { bullets = 0, shells = 0, cells = 0, rockets = 0 }
end

-- ----------------------------------------------------------------
-- Fire gates (spec §4): input-time refusal with the punch-guard as
-- the backstop, never the other way around.
-- ----------------------------------------------------------------
function W.fire_gate(user)
	if not W.get_setting_bool("sl_weapons_enabled", true) then
		return S("Weapon systems offline.")
	end
	if not user or not user.is_player or not user:is_player() then
		return "not a player"
	end
	local name = user:get_player_name()
	-- Hands full of line: while attached to the Lash you are a
	-- parcel, not a gunner (spec §10.1, danger 2).
	if W.lash and W.lash[name] then
		return S("Your hands are full of line.")
	end
	if game_mode and game_mode.get_player_state then
		local pl = game_mode.get_player_state(name)
		if pl then
			if pl.role == "monster_master" then
				return S("Your hands are the doctrine.")
			end
			if game_mode.state and game_mode.state.match_active then
				if pl.phase ~= "alive" then
					return S("The dead cannot wield the system's weapons.")
				end
			elseif pl.phase == "ghost" or pl.phase == "evil_ghost" then
				-- Outside a match the range is open (sandbox doctrine,
				-- MT CTF-style: unallocated players fight under full
				-- rules). Only the dead and the Monster Master are
				-- refused; lobby bodies are damageable and may test
				-- their iron on each other.
				return S("The dead cannot wield the system's weapons.")
			end
		end
	end
	return nil
end

-- ----------------------------------------------------------------
-- Fire timing: shared raise delay + per-weapon refire + generic busy
-- (Neon Six cylinder spin). All published constants (spec §3).
-- ----------------------------------------------------------------
W.next_fire = {}   -- [name] = earliest next shot
W.raise_at = {}    -- [name] = raise delay gate
W.busy_until = {}  -- [name] = cylinder spin / autoswitch pause
W.last_weapon = {} -- [name] = last wielded weapon id (switch detection)

-- Returns ok, reason ("raising" | "refire" | "busy").
function W.fire_timing_ok(name, weapon_id, refire)
	local t = W.now()
	if W.last_weapon[name] ~= weapon_id then
		W.raise_at[name] = t + W.RAISE_DELAY
		W.last_weapon[name] = weapon_id
	end
	if (W.busy_until[name] or 0) > t then
		return false, "busy"
	end
	if (W.raise_at[name] or 0) > t then
		return false, "raising"
	end
	if (W.next_fire[name] or 0) > t then
		return false, "refire"
	end
	W.next_fire[name] = t + refire
	return true
end

-- ----------------------------------------------------------------
-- Chatter bloom — a published function, never a die roll (spec §3).
--   deg(shot n of a held burst) = min(4.0, 0.5 + (n-1) * BLOOM_STEP)
-- A burst is broken by BLOOM_RESET seconds without firing.
-- ----------------------------------------------------------------
W.BLOOM_MIN = 0.5
W.BLOOM_MAX = 4.0
W.BLOOM_STEP = 0.315 -- ≈ 3.5°/s at the 0.09 s refire
W.BLOOM_RESET = 0.6
W.bloom = {} -- [name] = { deg = current, shots = n, last = t }

function W.bloom_advance(name)
	local t = W.now()
	local st = W.bloom[name]
	if not st or (t - st.last) >= W.BLOOM_RESET then
		st = { deg = W.BLOOM_MIN, shots = 1, last = t }
	else
		st.shots = st.shots + 1
		st.deg = math.min(W.BLOOM_MAX, W.BLOOM_MIN + (st.shots - 1) * W.BLOOM_STEP)
		st.last = t
	end
	W.bloom[name] = st
	return st.deg
end

function W.bloom_current(name)
	local st = W.bloom[name]
	if not st then return W.BLOOM_MIN end
	if (W.now() - st.last) >= W.BLOOM_RESET then return W.BLOOM_MIN end
	return st.deg
end

-- ----------------------------------------------------------------
-- Geometry helpers
-- ----------------------------------------------------------------
function W.aim(user)
	local pos = user:get_pos()
	local eye_h = (user:get_properties() or {}).eye_height or 1.625
	return { x = pos.x, y = pos.y + eye_h, z = pos.z }, user:get_look_dir()
end

function W.spread_dir(dir, deg)
	if not deg or deg <= 0 then return dir end
	local up
	if math.abs(dir.y) > 0.95 then up = { x = 1, y = 0, z = 0 } else up = { x = 0, y = 1, z = 0 } end
	local right = vector.normalize(vector.cross(dir, up))
	local true_up = vector.cross(right, dir)
	local a = math.random() * math.pi * 2
	local r = math.tan(math.rad(deg)) * math.sqrt(math.random())
	local out = vector.add(dir, vector.add(
		vector.multiply(right, math.cos(a) * r),
		vector.multiply(true_up, math.sin(a) * r)))
	return vector.normalize(out)
end

function W.knockback(obj, vel)
	if not obj or not vel then return end
	if obj:is_player() then
		if obj.add_player_velocity then
			obj:add_player_velocity(vel)
		elseif obj.add_to_velocity then
			obj:add_to_velocity(vel)
		end
	else
		local cur = obj.get_velocity and obj:get_velocity() or { x = 0, y = 0, z = 0 }
		obj:set_velocity({ x = cur.x + vel.x, y = cur.y + vel.y, z = cur.z + vel.z })
	end
end

function W.player_velocity(user)
	if user and user.get_player_velocity then
		return user:get_player_velocity()
	end
	return { x = 0, y = 0, z = 0 }
end

-- ----------------------------------------------------------------
-- Incident feed (spec §5): a death is a document, not a joke.
--   "0:34  beta — cause: arc discharge — range: long"
-- Never an adjective, never an attacker's name.
-- ----------------------------------------------------------------
W.CAUSES = {
	pistol = "pulse round",
	chatter = "bullet storm",
	scatter = "scatter burst",
	lance = "arc discharge",
	mortar = "mortar detonation",
	mortar_self = "own mortar",
	driver = "plasma burn",
	six = "revolver round",
	repeater = "lever round",
	sentry = "sentry fire",
	puppet = "puppet collapse",
	melee = "close combat",
	monster = "monster",
}

function W.range_bucket(m)
	if not m then return nil end
	if m <= 4 then return "point blank" end
	if m <= 12 then return "short" end
	if m <= 24 then return "mid" end
	if m <= 48 then return "long" end
	return "extreme"
end

function W.incident(victim, cause, opts)
	opts = opts or {}
	local clock = "--:--"
	if game_mode and game_mode.state and game_mode.state.match_active then
		local started = game_mode.state.match_started_at or W.now()
		local dt = math.max(0, W.now() - started)
		clock = string.format("%d:%02d", math.floor(dt / 60), math.floor(dt % 60))
	end
	local line = string.format("%s  %s — cause: %s",
		clock, tostring(victim), W.CAUSES[cause] or tostring(cause))
	if opts.range then
		line = line .. " — range: " .. opts.range
	end
	if game_mode and game_mode.broadcast then
		game_mode.broadcast(line)
	else
		minetest.chat_send_all(line)
	end
	return line
end

-- ----------------------------------------------------------------
-- Damage routing. All weapon damage flows through object:punch();
-- on a kill we emit the incident line. W.last_cause is stamped
-- BEFORE the punch so the corpse (spawned inside on_dieplayer,
-- which fires synchronously inside set_hp(0)) can read it.
-- ----------------------------------------------------------------
W.last_cause = {} -- [victim name] = cause key

function W.punch_object(shooter, obj, dmg, cause, range_m)
	if not obj or not dmg or dmg <= 0 then return end
	local victim_name = obj.is_player and obj:is_player() and obj:get_player_name() or nil
	if victim_name and cause then
		W.last_cause[victim_name] = cause
	end
	local before = obj.get_hp and obj:get_hp() or 1
	obj:punch(shooter, 1.0, {
		full_punch_interval = 1.0,
		damage_groups = { fleshy = dmg },
	}, { x = 0, y = 0, z = 1 })
	local after = obj.get_hp and obj:get_hp() or 0
	if after <= 0 and before > 0 then
		local label = victim_name or "a lifeform"
		W.incident(label, cause, { range = W.range_bucket(range_m) })
	end
end

-- Is this object something a bullet should pass through / ignore?
-- (own projectiles, cosmetic heads, corpse bodies — bullets pass
-- through bodies; fire handles those. Spec §7.)
function W.is_fx_object(obj)
	local lua = obj.get_luaentity and obj:get_luaentity()
	return lua and (lua.sl_weapon_fx or lua.sl_corpse) or false
end

function W.is_monster_object(obj)
	local lua = obj.get_luaentity and obj:get_luaentity()
	if not lua or not lua.name then return false end
	if lua.name == (game_mode and game_mode.MONSTER_NAME or "sl_modebase:monster") then
		return true
	end
	if lua.sl_monster then return true end
	return lua.name:find("^sl_scary:") ~= nil
end

-- Loadout (spec §3 / setting sl_weapons_spawn_loadout): everyone
-- walks in with the pistol and a blade. The walk to anything better
-- is the game.
function W.give_loadout(player)
	if not W.get_setting_bool("sl_weapons_spawn_loadout", true) then return end
	local name = player:get_player_name()
	if game_mode then
		local pl = game_mode.get_player_state(name)
		if pl and pl.role == "monster_master" then
			return -- hands, not ordnance (spec §6.1)
		end
	end
	local inv = player:get_inventory()
	if inv then
		inv:add_item("main", ItemStack("sl_weapons:pistol"))
		inv:add_item("main", ItemStack("sl_modebase:combat_blade"))
	end
end

function W.on_match_start()
	W.pools = {}
	W.next_fire = {}
	W.raise_at = {}
	W.busy_until = {}
	W.last_weapon = {}
	W.bloom = {}
	W.last_cause = {}
	if W.pads_rearm_all then W.pads_rearm_all() end
	for _, player in ipairs(minetest.get_connected_players()) do
		W.give_loadout(player)
	end
end

function W.on_match_end()
	-- Kill the generation first: any lash hook still in flight dies
	-- before it can anchor into the swept scene.
	W.match_gen = (W.match_gen or 0) + 1
	-- Scene sweep (spec §7.3 "match end" row): the next match starts
	-- with a clean scene — bodies, traces, turrets, puppets, lines.
	if W.sweep_scene then W.sweep_scene() end
	if W.turrets_sweep then W.turrets_sweep() end
	if W.pads_rearm_all then W.pads_rearm_all() end
	if W.lash_detach_all then W.lash_detach_all() end
	W.possession_hits = {}
	W.pools = {}
	W.next_fire = {}
	W.busy_until = {}
	W.last_weapon = {}
	W.bloom = {}

	-- Achievement lifecycle (spec §12.1): the match forgets, the
	-- count survives. reset_match_achievements is provided
	-- additively by mods/apis/sl_gui/achievement_system.lua.
	if reset_match_achievements then
		for _, player in ipairs(minetest.get_connected_players()) do
			local ok, err = pcall(reset_match_achievements, player)
			if not ok then
				minetest.log("error", "[sl_weapons] achievement reset: " .. tostring(err))
			end
		end
	end
	minetest.log("action", "[sl_weapons] scene swept — next match starts clean")
end
