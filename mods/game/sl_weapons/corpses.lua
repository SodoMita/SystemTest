-- ================================================================
-- sl_weapons — corpses, traces & the archaeology of a match
-- (WEAPONS_SPEC §7, team decisions 2026-08-29)
--
-- A death is not an event that vanishes. The inventory lands in the
-- body; looting is audible; destruction is explicit only — burial
-- (Trench Shovel -> grave mound), cremation (flare/mortar -> scorch
-- + Ashen Relic at ritual par) — and the residue outlives both.
-- Evil ghosts may walk their own corpse as the Deadwalk Puppet
-- (§7.4 safe variant): visibly dead, 8 HP, harmless.
-- ================================================================

local W = sl_weapons
local S = W.S

W.corpses = {}   -- list of { obj, victim, t, cause, inv, floor, residue_pos, puppeted, in_puppet, removed }
W.traces = {}    -- list of { pos, name } residue/mound/scorch nodes for the reset sweep
W.deadwalks = {} -- list of active deadwalk luaentities

local CORPSE_TEX = "sl_boxman_neon.png^[colorize:#445566:140^[opacity:220"
local DEADWALK_TEX = "sl_boxman_neon.png^[colorize:#8b939c:200"

local function phash(pos)
	return string.format("%d,%d,%d",
		math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
end
W.phash = phash

local function trace_add(pos, nodename)
	table.insert(W.traces, { pos = vector.round(pos), name = nodename })
end

local function set_trace_node(pos, nodename)
	pos = vector.round(pos)
	minetest.set_node(pos, { name = nodename })
	trace_add(pos, nodename)
end

-- ----------------------------------------------------------------
-- Trace nodes
-- ----------------------------------------------------------------
local function trace_node(name, desc, tex, light)
	minetest.register_node(W.modname .. ":" .. name, {
		description = S(desc),
		tiles = { tex },
		paramtype = "light",
		light_source = light or 0,
		groups = { cracky = 2, not_in_creative_inventory = 1 },
		is_ground_content = false,
		walkable = true,
		drop = "",
	})
end

trace_node("residue", "Residue", "sl_weapons_residue.png", 1)
trace_node("mound", "Grave Mound", "sl_weapons_mound.png", 0)
trace_node("scorch", "Scorch", "sl_weapons_scorch.png", 3)

-- ----------------------------------------------------------------
-- The corpse entity
-- ----------------------------------------------------------------
minetest.register_entity(W.modname .. ":corpse", {
	_stub_ray_radius = 1.2,
	sl_corpse = true,
		initial_properties = {
		physical = false,
		collide_with_objects = false,
		visual = "cube",
		textures = { CORPSE_TEX, CORPSE_TEX, CORPSE_TEX, CORPSE_TEX, CORPSE_TEX, CORPSE_TEX },
		visual_size = { x = 3.0, y = 3.0 },
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		pointable = true,
		static_save = false,
		},
	on_punch = function(self, _puncher)
		-- Bodies soak nothing and take no damage: bullets pass
		-- (handled in the fire pipeline); shovels and fire are the
		-- only doctrine here.
		return true
	end,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker.is_player or not clicker:is_player() then return end
		W.corpse_interact(self.entry, clicker)
	end,
})

-- ----------------------------------------------------------------
-- Death capture — called from sl_modebase's on_dieplayer (single
-- additive hook): the fountain lands in the body, a third of the
-- loose ammo is smashed, the biolocked pistol dissolves, and the
-- floor gets a residue node that outlives everything.
-- ----------------------------------------------------------------
local MM_KEEP = {
	["sl_modebase:summon_monster"] = true,
	["sl_modebase:reincarnate"] = true,
}

function W.capture_death_items(player, pos, inv)
	if not (game_mode and game_mode.state and game_mode.state.match_active) then
		return
	end
	local name = player:get_player_name()
	local pool = W.get_pool(name)
	for kind in pairs(W.POOL_MAX) do
		pool[kind] = math.floor((pool[kind] or 0) * 2 / 3) -- smash a third
	end
	-- Council resolution #3 (spec §5): a gun lifted from a body shows
	-- the dead man's last numbers, frozen. The pools die with the
	-- owner — the note is intel, not inheritance.
	local charge_note = string.format("bullets %d / shells %d / cells %d / rockets %d",
		pool.bullets or 0, pool.shells or 0, pool.cells or 0, pool.rockets or 0)

	local floor = vector.round(pos)
	local corpse_inv = {}
	local dissolved_pistol = false
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		local iname = stack:get_name()
		if iname ~= "" then
			if MM_KEEP[iname] then
				-- stays with the player (MM tooling, per sl_modebase)
			elseif iname == "sl_weapons:pistol" then
				dissolved_pistol = true
			else
				local it = { name = iname, count = stack:get_count() }
				if W.defs_by_item[iname] or iname == W.modname .. ":grapple" then
					it.note = charge_note
				end
				table.insert(corpse_inv, it)
			end
			if not MM_KEEP[iname] then
				inv:set_stack("main", i, ItemStack(""))
			end
		end
	end

	local entry = {
		victim = name,
		t = W.now(),
		cause = W.last_cause[name] or "unknown",
		inv = corpse_inv,
		dissolved_pistol = dissolved_pistol,
		floor = floor,
		puppeted = false,
		in_puppet = false,
		removed = false,
	}

	local obj = minetest.add_entity({ x = floor.x, y = floor.y + 0.15, z = floor.z },
		W.modname .. ":corpse")
	if obj then
		obj:set_velocity({ x = 0, y = 0, z = 0 })
		local lua = obj.get_luaentity and obj:get_luaentity()
		if lua then
			lua.entry = entry
			lua.sl_corpse = true
		end
		entry.obj = obj
	end
	entry.residue_pos = vector.round(floor)
	set_trace_node(entry.residue_pos, W.modname .. ":residue")
	table.insert(W.corpses, entry)

	minetest.sound_play("sl_weapons_body_falls", {
		pos = floor, gain = 0.7, max_hear_distance = 24,
	})
end

-- ----------------------------------------------------------------
-- Examining / looting (audible) / burial / cremation
-- ----------------------------------------------------------------
W.open_corpses = {} -- [player name] = entry

local function cause_text(key)
	return W.CAUSES[key] or key or "unknown"
end

local function corpse_report_lines(entry)
	local lines = {
		S("INCIDENT REPORT"),
		S("Body of @1", entry.victim),
		S("Cause: @1", cause_text(entry.cause)),
	}
	if entry.dissolved_pistol then
		table.insert(lines, S("Biolocked sidearm: dissolved."))
	end
	if #entry.inv == 0 and not entry.looted then
		table.insert(lines, S("Carried: nothing"))
	elseif entry.looted then
		table.insert(lines, S("Carried: nothing (looted)"))
	else
		for _, it in ipairs(entry.inv) do
			local def = minetest.registered_items[it.name]
			table.insert(lines, string.format("• %s ×%d",
				(def and def.description or it.name), it.count))
		end
	end
	return lines
end

function W.corpse_interact(entry, clicker)
	if not entry or entry.removed or entry.in_puppet then
		minetest.chat_send_player(clicker:get_player_name(), S("The body is gone."))
		return
	end
	local name = clicker:get_player_name()
	local wield = clicker.get_wielded_item and clicker:get_wielded_item():get_name() or ""

	-- Explicit destruction first: the doctrine tools.
	if wield == "sl_modebase:trench_shovel" then
		W.bury_corpse(entry, clicker)
		return
	end
	if wield == "sl_modebase:flare" then
		local inv = clicker:get_inventory()
		if inv then inv:remove_item("main", ItemStack("sl_modebase:flare 1")) end
		W.cremate_corpse({ entry = entry })
		return
	end

	-- The evil ghost and its own body (spec §7.4).
	if game_mode then
		local pl = game_mode.get_player_state(name)
		if pl and pl.phase == "evil_ghost" then
			if entry.victim == name then
				W.offer_deadwalk(entry, clicker)
			else
				minetest.chat_send_player(name,
					S("Not your body. The strings know their owner."))
			end
			return
		end
		if pl and pl.phase ~= "alive" then
			minetest.chat_send_player(name, S("The dead cannot touch the dead."))
			return
		end
	end

	-- Living player: the incident report + loot.
	W.open_corpses[name] = entry
	local fs = "formspec_version[4]size[8,9]bgcolor[#10141aff;true]" ..
		"label[0.4,0.6;" .. minetest.formspec_escape(table.concat(corpse_report_lines(entry), "\n")) .. "]"
	if #entry.inv > 0 then
		fs = fs .. "button[0.4,7.4;3.2,1.0;loot_all;" .. S("Take everything") .. "]" ..
			"label[4.0,7.8;" .. S("(loud)") .. "]"
	end
	fs = fs .. "button_close[4.6,7.4;3.0,1.0;" .. S("Close") .. "]"
	minetest.show_formspec(name, W.modname .. ":corpse", fs)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= W.modname .. ":corpse" then return end
	if not fields.loot_all then return end
	local name = player and player:get_player_name()
	local entry = name and W.open_corpses[name]
	if not entry or entry.removed then return end
	local inv = player:get_inventory()
	if not inv then return end
	for _, it in ipairs(entry.inv) do
		local stack = ItemStack(it.name .. " " .. it.count)
		if W.defs_by_item[it.name] then
			-- Found empty: the magazine died with the owner — the
			-- durability bar shows nothing left to fire.
			stack:set_wear(65535)
		end
		if it.note then
			local def = minetest.registered_items[it.name]
			local meta = stack:get_meta()
			if meta and meta.set_string and def then
				meta:set_string("description",
					(def.description or it.name) .. "\nRecovered — last charge: " .. it.note)
			end
		end
		inv:add_item("main", stack)
	end
	entry.inv = {}
	entry.looted = true
	W.open_corpses[name] = nil
	-- Looting is audible (spec §7.1): taking a dead man's mortar is
	-- loud enough to be a decision.
	minetest.sound_play("sl_weapons_loot_hum", {
		pos = entry.obj and entry.obj:get_pos() or entry.floor,
		gain = 0.9,
		max_hear_distance = 16,
	})
	minetest.chat_send_player(name, S("Taken. Everyone close heard it."))
end)

function W.remove_corpse_entity(entry)
	if entry.obj and entry.obj.remove then
		pcall(function() entry.obj:remove() end)
	end
	entry.obj = nil
end

-- Burial: decent, anonymous, costs a shovel swing, pays nothing.
function W.bury_corpse(entry, clicker)
	local floor = entry.floor
	minetest.remove_node(floor) -- residue out, mound in: the grave covers the stain
	set_trace_node(floor, W.modname .. ":mound")
	W.remove_corpse_entity(entry)
	entry.removed = true
	minetest.sound_play("sl_weapons_shovel_bury", {
		pos = floor, gain = 0.9, max_hear_distance = 20,
	})
	if clicker then
		minetest.chat_send_player(clicker:get_player_name(),
			S("Buried. The mound keeps no name."))
	end
end

-- Cremation: scorch + Ashen Relic at ritual par (team decision
-- 2026-08-29 — burned evidence is not secondhand evidence).
function W.cremate_corpse(lua)
	local entry = lua and (lua.entry or lua)
	if not entry or entry.removed then return end
	local pos = (entry.obj and entry.obj.get_pos and entry.obj:get_pos()) or entry.floor
	local above = { x = entry.floor.x, y = entry.floor.y + 1, z = entry.floor.z }
	local node_above = minetest.get_node(above).name
	if node_above == "air" then
		set_trace_node(above, W.modname .. ":scorch")
	else
		minetest.remove_node(entry.floor)
		set_trace_node(entry.floor, W.modname .. ":scorch")
	end
	minetest.add_item(pos, ItemStack("sl_modebase:ritual_ashen_relic 1"))
	W.remove_corpse_entity(entry)
	entry.removed = true
	minetest.sound_play("sl_weapons_cremation", {
		pos = pos, gain = 1.0, max_hear_distance = 32,
	})
	for _ = 1, 14 do
		minetest.add_particle({
			pos = pos,
			velocity = { x = (math.random() - 0.5) * 3, y = math.random() * 5, z = (math.random() - 0.5) * 3 },
			acceleration = { x = 0, y = 2, z = 0 },
			expirationtime = 1.4,
			size = 4,
			texture = "sl_weapons_blast.png",
			glow = 12,
		})
	end
end

-- ----------------------------------------------------------------
-- The Deadwalk Puppet (spec §7.4, approved safe variant)
-- Fools the marksman, never the witness: ashen, flickering, wrong
-- gait. 8 HP, no healing, no attacking, no crafting, no building,
-- no inventory, no looting. Doors only… and for now it doesn't even
-- get those (W2.1 polish note): it shambles after its ghost.
-- ----------------------------------------------------------------
local DEADWALK_SPEED = 3.2 -- ×0.8 of walk
local DEADWALK_HP = 8

minetest.register_entity(W.modname .. ":deadwalk", {
	_stub_ray_radius = 0.6,
	sl_weapon_fx = false,
		initial_properties = {
		physical = false,
		collide_with_objects = false,
		visual = "cube",
		textures = { DEADWALK_TEX, DEADWALK_TEX, DEADWALK_TEX, DEADWALK_TEX, DEADWALK_TEX, DEADWALK_TEX },
		visual_size = { x = 6.0, y = 6.0 },
		collisionbox = { -0.3, 0.0, -0.3, 0.3, 1.6, 0.3 },
		pointable = true,
		hp_max = DEADWALK_HP,
		static_save = false,
		},
	on_step = function(self, dtime)
		local ghost = self.ghost and minetest.get_player_by_name(self.ghost)
		local now = W.now()
		if (self.until_t or 0) <= now or not ghost then
			W.end_deadwalk(self, "expired")
			return
		end
		local obj = self.object
		local pos = obj:get_pos()
		local gpos = ghost:get_pos()
		local to_ghost = vector.subtract(gpos, pos)
		local dist = vector.distance(pos, gpos)
		if dist > 2.5 then
			-- The gait reads broken: a half-second stutter every few
			-- steps. Deterministic-ish is fine; it must look wrong.
			self.stutter = (self.stutter or 0) + dtime
			local speed = DEADWALK_SPEED
			if self.stutter % 2.0 > 1.5 then speed = 0.4 end
			obj:set_velocity(vector.multiply(vector.normalize(to_ghost), speed))
		else
			obj:set_velocity({ x = 0, y = 0, z = 0 })
		end
		self.fx_t = (self.fx_t or 0) + dtime
		if self.fx_t > 0.4 then
			self.fx_t = 0
			minetest.add_particle({
				pos = vector.add(pos, { x = 0, y = 1.0, z = 0 }),
				velocity = { x = 0, y = -0.6, z = 0 },
				acceleration = { x = 0, y = -1, z = 0 },
				expirationtime = 1.0,
				size = 2,
				texture = "sl_weapons_grit.png",
			})
		end
	end,

	on_death = function(self, _cause)
		W.puppet_collapse(self)
	end,
})

W.deadwalk_ready = {} -- [ghost name] = cooldown until

function W.offer_deadwalk(entry, clicker)
	local name = clicker:get_player_name()
	if entry.puppeted then
		minetest.chat_send_player(name, S("The strings are burned. One walk per body."))
		return
	end
	if (W.deadwalk_ready[name] or 0) > W.now() then
		minetest.chat_send_player(name, S("The body is not ready to walk again."))
		return
	end
	W.raise_deadwalk(entry, name)
end

function W.raise_deadwalk(entry, ghost_name)
	local pos = (entry.obj and entry.obj:get_pos()) or entry.floor
	W.remove_corpse_entity(entry)
	entry.puppeted = true
	entry.in_puppet = true
	local obj = minetest.add_entity(pos, W.modname .. ":deadwalk")
	if not obj then return end
	obj:set_hp(DEADWALK_HP)
	local lua = obj.get_luaentity and obj:get_luaentity()
	local duration = (game_mode and game_mode.POSSESSION_DURATION) or 20
	if lua then
		lua.ghost = ghost_name
		lua.entry = entry
		lua.until_t = W.now() + duration
		table.insert(W.deadwalks, lua)
	end
	entry.puppet_lua = lua
	W.deadwalk_ready[ghost_name] = W.now() + ((game_mode and game_mode.POSSESSION_COOLDOWN) or 45)
	minetest.sound_play("sl_weapons_deadwalk_rise", {
		pos = pos, gain = 0.9, max_hear_distance = 24,
	})
	minetest.chat_send_player(ghost_name, S("Walk it. Harmless, half-dead, visible. Make them spend."))
end

function W.end_deadwalk(lua, reason)
	local entry = lua.entry
	local obj = lua.object
	for i, l in ipairs(W.deadwalks) do
		if l == lua then table.remove(W.deadwalks, i) break end
	end
	local pos = obj and obj.get_pos and obj:get_pos() or (entry and entry.floor)
	if obj and obj.remove then pcall(function() obj:remove() end) end
	if not entry then return end
	entry.in_puppet = false
	entry.puppet_lua = nil
	if reason == "expired" then
		-- Ghost ejected; the corpse returns, strings burned.
		local nobj = minetest.add_entity(pos or entry.floor, W.modname .. ":corpse")
		if nobj then
			local nlua = nobj.get_luaentity and nobj:get_luaentity()
			if nlua then
				nlua.entry = entry
				nlua.sl_corpse = true
			end
			entry.obj = nobj
		end
	else
		-- Collapse: the corpse is consumed; the residue remains.
		entry.removed = true
		W.incident("a deadwalk", "puppet")
		minetest.sound_play("sl_weapons_puppet_collapse", {
			pos = pos or entry.floor, gain = 0.8, max_hear_distance = 24,
		})
	end
end

function W.puppet_collapse(lua)
	W.end_deadwalk(lua, "collapse")
end

-- ----------------------------------------------------------------
-- Match-end sweep (spec §7.3 "match end" row)
-- ----------------------------------------------------------------
function W.sweep_scene()
	for _, lua in ipairs(table.copy(W.deadwalks)) do
		if lua.object and lua.object.remove then
			pcall(function() lua.object:remove() end)
		end
	end
	W.deadwalks = {}
	for _, entry in ipairs(W.corpses) do
		W.remove_corpse_entity(entry)
		entry.removed = true
	end
	W.corpses = {}
	for _, tr in ipairs(W.traces) do
		local node = minetest.get_node(tr.pos)
		if node and node.name == tr.name then
			minetest.remove_node(tr.pos)
		end
	end
	W.traces = {}
	W.open_corpses = {}
	W.deadwalk_ready = {}
end
