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

-- ----------------------------------------------------------------
-- Magazines (v1.3): rounds live in the weapon stack; the pool is
-- the reserve a load pulls from. Loading is one right-click.
-- ----------------------------------------------------------------
-- Rounds are the durability bar, exactly like CTF's rawf: wear 0 is a
-- full magazine, 65535 is empty. The engine draws the bar in the
-- hotbar, the inventory, and over the wield item -- no custom HUD.
local function mag_cap(stack)
	local def = W.defs_by_item[stack:get_name()]
	return def and def.mag or 1
end

function W.mag_get(stack)
	local cap = mag_cap(stack)
	local used = math.floor(stack:get_wear() * cap / 65535 + 0.5)
	return math.max(0, cap - used)
end

function W.mag_set(stack, n)
	local cap = mag_cap(stack)
	n = math.max(0, math.min(cap, math.floor(n)))
	stack:set_wear(math.floor((cap - n) * 65535 / cap + 0.5))
end

-- A weapon granted loaded to capacity (pads, fabricator, loadouts).
function W.loaded_stack(itemname)
	local st = ItemStack(itemname)
	local def = W.defs_by_item[itemname]
	if def and def.pool and def.mag then
		W.mag_set(st, def.mag)
	end
	return st
end

-- Human labels for the cache items (spec §3 "trade bait").
W.AMMO_LABEL = {
	bullets = "Bullet Cache", shells = "Shell Cache",
	cells = "Cell Cache", rockets = "Rocket Cache",
}

-- Consume ONE ammo cache item of `kind` from the player's main
-- inventory into the reserve pool. Spec §5: "ammunition without guns
-- is trade bait" — the bait is spendable, so a cache in the inventory
-- IS reserve ammo, not decoration. Returns the rounds banked
-- (0 = nothing to unpack).
function W.consume_cache(user, kind)
	if not user or not user.get_inventory then return 0 end
	local name = user.get_player_name and user:get_player_name()
	local inv = user:get_inventory()
	if not name or not inv then return 0 end
	local itemname = W.modname .. ":ammo_" .. kind
	for i = 1, inv:get_size("main") do
		local st = inv:get_stack("main", i)
		if st:get_name() == itemname then
			inv:set_stack("main", i, st:take_item())
			return W.add_ammo(name, kind, W.AMMO_YIELD[kind] or 0)
		end
	end
	return 0
end

-- Pull rounds from the reserve pool into the weapon's magazine. When
-- the pool is empty, a cache item of that kind in the inventory is
-- unpacked first (see W.consume_cache) — so "No @1 for the @2" can
-- only be said when there are none anywhere the player can touch.
function W.mag_load(user, def, stack)
	local name = user and user.get_player_name and user:get_player_name() or nil
	if not name or not def or not stack then return stack end
	local cap = def.mag or 1
	local cur = W.mag_get(stack)
	local room = cap - cur
	if room <= 0 then return stack end
	local pool = W.get_pool(name)
	local have = pool[def.pool] or 0
	local from_cache = 0
	if have < 1 then
		from_cache = W.consume_cache(user, def.pool)
		have = pool[def.pool] or 0
		if have < 1 then
			minetest.chat_send_player(name, S("No @1 for the @2.", def.pool, def.desc))
			return stack
		end
	end
	local take = math.min(room, have)
	pool[def.pool] = have - take
	W.mag_set(stack, cur + take)
	minetest.sound_play("sl_weapons_ammo_load", {
		to_player = name, gain = 0.5,
	}, true)
	if from_cache > 0 then
		minetest.chat_send_player(name,
			S("Unpacked a @1.", W.AMMO_LABEL[def.pool] or def.pool) .. " "
			.. string.format("%s %d/%d", def.desc, cur + take, cap))
	else
		minetest.chat_send_player(name, string.format("%s %d/%d", def.desc, cur + take, cap))
	end
	return stack
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
				-- Open test range (team decision 2026-08-29): weapons
				-- are testable any time. The dead never wield; the
				-- living test freely. Lobby bodies stay immortal by
				-- design -- test fire is loud, not lethal.
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
W.busy_until = {}  -- [name] = cylinder spin pause (Neon Six)
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
	-- Degenerate spread collapses to the unspread aim rather than NaN.
	return vector.safe_dir(out, dir)
end

function W.knockback(obj, vel)
	if not obj or not vel then return end
	-- NaN never reaches a client: a non-finite shove is a bug
	-- upstream, and silence beats a segfault (2026-08-29 incident).
	if vector.finite and not vector.finite(vel) then return end
	-- MT CTF pattern (ctf_mode_nade_fight knockback): plain add_velocity
	-- on whatever moves; the old player-only variants are deprecated and
	-- gone from this tree.
	if obj.add_velocity then
		obj:add_velocity(vel)
	else
		local cur = obj.get_velocity and obj:get_velocity() or { x = 0, y = 0, z = 0 }
		obj:set_velocity({ x = cur.x + vel.x, y = cur.y + vel.y, z = cur.z + vel.z })
	end
end

function W.player_velocity(user)
	-- MT CTF pattern: read get_velocity directly. The deprecated
	-- player-only reader is gone from this tree, fallbacks included.
	if user and user.get_velocity then
		return user:get_velocity()
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
	-- THE 2026-08-29 segfault, backstopped at the only funnel: a
	-- puncher passed to ObjectRef:punch must NEVER be nil. The engine
	-- happily pushes a nil puncher into the on_punchplayer handlers,
	-- but PlayerSAO::punch then does `puncher->getType()` with no null
	-- check whenever ANY handler returns true (Luanti 5.15 through
	-- 5.17 and master alike). sl_modebase's lobby/creative guard
	-- returns true unconditionally, so a nil-puncher punch in the
	-- lobby — the open test range, where players actually test the
	-- mortar — is a guaranteed process crash. MT CTF never hits this:
	-- a throw always punches with the thrower's ObjectRef, even
	-- against itself. The fallback to the victim itself keeps the
	-- punch non-nil in every case (a self-punch is legal and the
	-- cause stamp above stays authoritative for the incident feed).
	local puncher = shooter or obj
	local victim_name = obj.is_player and obj:is_player() and obj:get_player_name() or nil
	if victim_name and cause then
		W.last_cause[victim_name] = cause
	end
	local before = obj.get_hp and obj:get_hp() or 1
	obj:punch(puncher, 1.0, {
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
		-- The pistol arrives loaded (v1.3 — it eats ammo like everyone
		-- now), with two magazines of bullets as starting reserve.
		inv:add_item("main", W.loaded_stack("sl_weapons:pistol"))
		inv:add_item("main", ItemStack("sl_modebase:combat_blade"))
		local pool = W.get_pool(name)
		pool.bullets = math.max(pool.bullets or 0, 24)
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
		-- Hand-evolution levels are per-match (team directive
		-- 2026-08-29) -- except in a tournament (v1.3.4), where the
		-- grip rides across matches with the rest of progression.
		if not (game_mode and game_mode.state and game_mode.state.tournament) then
			pcall(function()
				player:get_meta():set_string("sl_mm_hands", "")
			end)
		end
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
	-- additively by mods/apis/sl_gui/achievement_system.lua. In a
	-- tournament (v1.3.4) achievements persist with the rest of
	-- progression; /sl_tournament stop performs the one clean reset.
	if reset_match_achievements
		and not (game_mode and game_mode.state and game_mode.state.tournament) then
		for _, player in ipairs(minetest.get_connected_players()) do
			local ok, err = pcall(reset_match_achievements, player)
			if not ok then
				minetest.log("error", "[sl_weapons] achievement reset: " .. tostring(err))
			end
		end
	end
	minetest.log("action", "[sl_weapons] scene swept — next match starts clean")
end
