-- ================================================================
-- sl_chatplay/commands.lua -- the /cp command language.
--
-- One verb namespace, exposed as the chat command "cp" (and as the
-- mailbox/HTTP API). Every handler works for real clients and for
-- the console player; real players additionally keep the mouse path.
-- ================================================================

local C = sl_chatplay
local state = game_mode.state
local W = rawget(_G, "sl_weapons")
local S = C.S

C.who = function(player) return player:get_player_name() end

-- ----------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------
local function verbose_item(stack)
	local name = stack:get_name()
	local n = stack:get_count()
	local short = name:match("^[^:]+:(.+)$") or name
	if W and W.defs_by_item and W.defs_by_item[name] and W.mag_get then
		local mag = W.mag_get(stack)
		return string.format("%s x%d [%d/%d]", short, n, mag, W.defs_by_item[name].mag or 1)
	end
	if n > 1 then return short .. " x" .. n end
	return short
end

local function inv_summary(player)
	local inv = player:get_inventory()
	if not inv then return "" end
	local parts = {}
	local seen = {}
	for i = 1, 32 do
		local stack = inv:get_stack("main", i)
		if stack and stack:get_name() ~= "" then
			local key = stack:get_name()
			if not seen[key] then
				seen[key] = true
				parts[#parts + 1] = verbose_item(stack)
			end
		end
	end
	if #parts == 0 then return "(empty)" end
	return table.concat(parts, ", ")
end

local function phase_label(pl)
	local labels = { alive = "ALIVE", ghost = "GHOST (cloud cage)",
		evil_ghost = "EVIL GHOST", monster = "MONSTER", master_monster = "MONSTER" }
	return labels[pl.phase] or tostring(pl.phase)
end

local function fmt_time(secs)
	secs = math.max(0, math.floor(secs or 0))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function is_admin(name)
	if name == C.cfg.console_name and C.console then
		-- the harness console player is a test seat, not an auth entry
		return true
	end
	local privs = minetest.get_player_privs(name)
	return privs.sl_admin or privs.server
end

local function creative_on()
	return minetest.settings:get_bool("creative_mode")
end

local function call_command(name, cmdname, param, with_creative)
	local cmd = minetest.registered_chatcommands[cmdname]
	if not cmd then return nil, "command not found: " .. tostring(cmdname) end
	local was = creative_on()
	if with_creative and not was then minetest.settings:set_bool("creative_mode", true) end
	local ok, res = cmd.func(name, param or "")
	if with_creative and not was then minetest.settings:set_bool("creative_mode", was) end
	return ok, res
end

local function expand_item(short)
	if short:find(":") then
		if minetest.registered_items[short] then return short end
		return nil
	end
	for _, mod in ipairs({ game_mode.modname, "sl_weapons", "sl_gui", "sl_scary", "sl_energy" }) do
		local full = mod .. ":" .. short
		if minetest.registered_items[full] then return full end
	end
	return nil
end

local function beacon_line()
	local out = {}
	for _, team_id in ipairs(state.teams_order or { "beacon_a", "beacon_b" }) do
		local t = state.teams[team_id]
		if t then
			local mark = ""
			if state.sabotage then
				for _, e in pairs(state.sabotage) do
					if e.pos and t.spawn and C.pos_key(e.pos) == C.pos_key(t.spawn) then
						mark = mark .. " CORRUPTED"
					end
				end
			end
			out[#out + 1] = string.format("%s %d%s", game_mode.get_team_label(team_id), t.hp or 0, mark)
		end
	end
	return table.concat(out, " | ")
end

function C.cmd_status(player)
	local name = C.who(player)
	local pl = game_mode.get_player_state(name)
	local pos = player:get_pos()
	local lines = {}
	lines[#lines + 1] = string.format("%s -- %s", name, phase_label(pl))
	if pl.team then
		lines[#lines + 1] = "Team: " .. game_mode.get_team_label(pl.team)
	elseif pl.role == "monster_master" then
		lines[#lines + 1] = "Role: Monster Master"
	else
		lines[#lines + 1] = "Team: none"
	end
	lines[#lines + 1] = string.format("HP %d | Pos %s | Points %d%s",
		player:get_hp() or 0,
		pos and minetest.pos_to_string(vector.round(pos)) or "?",
		pl.points or 0,
		pl.eliminated and " | ELIMINATED" or "")
	if state.match_active then
		local elapsed = game_mode.now() - (state.match_started_at or 0)
		local dur = state.settings.match_duration or 0
		lines[#lines + 1] = string.format("Match #%d | %s / %s | Beacons: %s",
			state.match_count or 0, fmt_time(elapsed), fmt_time(dur), beacon_line())
	elseif state.ready_check and state.ready_check.active then
		lines[#lines + 1] = "Ready check running. /cp ready to confirm."
	else
		lines[#lines + 1] = "No active match (lobby). /cp lobby for matchmaking."
	end
	lines[#lines + 1] = "Wield: " .. verbose_item(player:get_wielded_item())
	lines[#lines + 1] = "Inventory: " .. inv_summary(player)
	if player.get_breath and player:get_breath() and player:get_breath() < 10 then
		lines[#lines + 1] = "Breath: " .. tostring(player:get_breath())
	end
	local mm = state.monster_master and state.monster_master.player
	if mm then lines[#lines + 1] = "Monster Master: " .. mm end
	if W and W.pools and W.pools[name] then
		local p = W.pools[name]
		local pool_parts = {}
		for _, k in ipairs({ "bullets", "shells", "cells", "rockets" }) do
			if p[k] and p[k] > 0 then pool_parts[#pool_parts + 1] = k .. " " .. p[k] end
		end
		if #pool_parts > 0 then lines[#lines + 1] = "Ammo pool: " .. table.concat(pool_parts, ", ") end
	end
	if state.monster_master and state.monster_master.player == name and game_mode.ESSENCE_ITEM then
		local inv = player:get_inventory()
		if inv then
			local n = 0
			for i = 1, 32 do
				local st = inv:get_stack("main", i)
				if st:get_name() == game_mode.ESSENCE_ITEM then n = n + st:get_count() end
			end
			lines[#lines + 1] = "Monster Essence: " .. n
		end
	end
	return table.concat(lines, "\n")
end

-- ----------------------------------------------------------------
-- Public roster (mirrors the matchmaking formspec player list)
-- ----------------------------------------------------------------
function C.cmd_roster()
	local lines = { "Operators:" }
	local connected = minetest.get_connected_players()
	for _, p in ipairs(connected) do
		local n = p:get_player_name()
		local ps = game_mode.get_player_state(n)
		local tag = ""
		if n == state.monster_master.player then
			tag = " [MM]"
		elseif ps.team then
			tag = " [" .. game_mode.get_team_label(ps.team) .. "]"
		end
		lines[#lines + 1] = "  " .. n .. tag
	end
	return table.concat(lines, "\n")
end

function C.cmd_lobby(player)
	local sett = state.settings
	local lines = {
		"SYSTEM MATCHMAKING",
		"Status: " .. (state.match_active and "MATCH IN PROGRESS" or "LOBBY - READY TO START"),
		"Win conditions: elimination=" .. tostring(state.win_conditions.elimination)
			.. " objective=" .. tostring(state.win_conditions.objective),
		string.format("Settings: beacon_hp=%d mm_auto_assign=%s auto_start=%s match_duration=%ds",
			sett.beacon_hp or 100, tostring(sett.mm_auto_assign), tostring(sett.auto_start),
			sett.match_duration or 120),
		"Monster Master: " .. (state.monster_master.player or "None"),
	}
	if not state.match_active then
		lines[#lines + 1] = "Actions: /cp mm take | /cp mm resign | /cp ready | /cp start (admin)"
	else
		lines[#lines + 1] = "Actions: /cp stop (admin)"
	end
	return table.concat(lines, "\n") .. "\n" .. C.cmd_roster()
end

-- ----------------------------------------------------------------
-- Target resolution
-- ----------------------------------------------------------------
function C.resolve_target(player, spec)
	local pname = C.who(player)
	local s = spec or ""
	local low = s:lower()

	local function by_name(nm)
		local ref = minetest.get_player_by_name(nm)
		if ref then return { class = "player", ref = ref, name = nm, label = nm } end
		return nil
	end

	local ent = low:match("^e(%d+)$")
	if ent then
		local n = tonumber(ent)
		local count = 0
		for _, obj in ipairs(minetest.get_objects_inside_radius(player:get_pos(), 20)) do
			local lua = obj.get_luaentity and obj:get_luaentity()
			if lua and not (lua.sl_weapon_fx or lua.sl_corpse) then
				count = count + 1
				if count == n then
					return { class = "entity", ref = obj, label = (lua.name or "entity") }
				end
			end
		end
		return nil, "No such entity nearby."
	end

	if low == "beacon" or low == "enemy" or low == "enemy_beacon" then
		local pl = game_mode.get_player_state(pname)
		local target = (pl.team == "beacon_a") and "beacon_b" or "beacon_a"
		if pl.role == "monster_master" then
			return nil, "The doctrine carries no ranged siege. The Monster Master chooses no beacon."
		end
		local bpos = state.teams[target] and state.teams[target].spawn
		if not bpos then return nil, "No enemy beacon online." end
		return { class = "node", pos = { x = bpos.x, y = bpos.y - 1, z = bpos.z }, label = "beacon" }
	elseif low == "own_beacon" then
		local pl = game_mode.get_player_state(pname)
		local bpos = state.teams[pl.team] and state.teams[pl.team].spawn
		if not bpos then return nil, "No beacon." end
		return { class = "node", pos = { x = bpos.x, y = bpos.y - 1, z = bpos.z }, label = "beacon" }
	end

	local named = { crate = "sl_modebase:loot_crate", altar = "sl_modebase:ghost_altar",
		spawner = "sl_modebase:monster_spawner", pickup = "sl_modebase:item_pickup",
		terminal = "sl_modebase:terminal", turret = "sl_weapons:turret",
		weaponpad = "sl_weapons:pad_weapon", ammopad = "sl_weapons:pad_ammo" }
	local kind = named[low]
	if kind then
		local pos = C.nearest_node(player, { kind }, low == "turret" and 24 or 12)
		if not pos then return nil, "No " .. (C.labels and C.labels[low] or low) .. " nearby." end
		return { class = "node", pos = pos, label = low }
	end

	-- P# = Nth player body within range (same enumeration as /cp sense)
	local pb = low:match("^p(%d+)$")
	if pb then
		local n = tonumber(pb)
		local count = 0
		for _, p in ipairs(minetest.get_connected_players()) do
			local nm = p:get_player_name()
			if nm ~= pname and p:get_pos() then
				local d = vector.distance(player:get_pos(), p:get_pos())
				if d <= 20 then
					count = count + 1
					if count == n then
						return { class = "player", ref = p, name = nm, label = nm }
					end
				end
			end
		end
		return nil, "No body #" .. n .. " nearby."
	end

	local l1 = low:match("^player%s+(%S+)$")
	if l1 then
		local r = by_name(l1)
		if not r then return nil, "No such player: " .. l1 end
		return r
	end
	local r = by_name(low)
	if r then return r end

	local x, y, z = s:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)$")
	if x then
		return { class = "node", pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }, label = "point" }
	end
	return nil, "Unknown target: " .. s
end

C.labels = { crate = "loot crate", altar = "ghost altar", spawner = "monster spawner",
	pickup = "pickup", terminal = "terminal", turret = "sentry turret",
	weaponpad = "weapon pad", ammopad = "ammo pad" }

-- ----------------------------------------------------------------
-- /cp dispatch table
-- ----------------------------------------------------------------
local handlers = {}

handlers.ping = function(player, param)
	return true, string.format("Channel open. %s server time %s; match_active=%s phase=%s",
		minetest.get_version().string, os.date("%H:%M:%S"),
		tostring(state.match_active),
		phase_label(game_mode.get_player_state(C.who(player))))
end

handlers.status = function(player)
	return true, C.cmd_status(player)
end

handlers.hud = function(player, param)
	local arg = (param or ""):lower():match("^(%S+)") or "on"
	if arg == "on" or arg == "auto" then
		C.pulse.on = true
		return true, "Pulse on: automatic status to your feed every " .. math.floor(C.pulse.every) .. "s."
	elseif arg == "off" then
		C.pulse.on = false
		return true, "Pulse off."
	elseif arg == "every" then
		local n = tonumber((param or ""):match("(%d+)"))
		if n and n >= 3 then C.pulse.every = n end
		return true, "Pulse every " .. math.floor(C.pulse.every) .. "s."
	end
	return true, "Pulse: " .. (C.pulse.on and "on" or "off") .. " every " .. math.floor(C.pulse.every) .. "s."
end

handlers.sense = function(player, param)
	return true, C.cmd_sense(player, param)
end
handlers.near = handlers.sense

handlers.look = function(player, param)
	return true, C.cmd_look(player)
end

handlers.aim = function(player, param)
	local arg = (param or ""):lower():match("^(%S+)") or ""
	local dir = C.dir_from_bearing(arg)
	if not dir then return false, "Aim: n|s|e|w|ne|nw|se|sw|up|down" end
	if not C.set_aim(player, dir) then
		return false, "The engine owns your look. Point with the mouse (this is console-only aiming)."
	end
	return true, "Aim set: " .. arg .. "."
end

handlers.move = function(player, param)
	local arg = param or ""
	if not arg or arg == "" then return false, "move n|s|e|w|ne|nw|se|sw [meters] | move to X Z [Y] | fly up|down [m] | stop" end
	local dirword, rest = arg:match("^([%a]+)(.*)$")
	if not dirword then return false, "Unknown move." end
	local low = dirword:lower()
	if low == "stop" then
		C.move.target = nil
		return true, "Movement halted."
	end
	if low == "to" then
		rest = (rest or ""):gsub("^%s+", "")
		local x, z, y = rest:match("^(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%-?%d+%.?%d*)$")
		if not x then
			x, z = rest:match("^(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)$")
		end
		if not x then return false, "move to X Z [Y]" end
		local pos = player:get_pos()
		C.move.target = { x = tonumber(x), y = y and tonumber(y) or pos.y, z = tonumber(z) }
		C.move.speed_mult = 1.0
		return true, string.format("Moving to %s.", minetest.pos_to_string(C.move.target))
	elseif low == "fly" then
		local updown = rest:match("^%s*(%a+)") or "up"
		local d = tonumber(rest:match("(%d+%.?%d*)")) or 5
		local pos = player:get_pos()
		local dy = (updown == "down") and -d or d
		local pl = game_mode.get_player_state(C.who(player))
		if pl.phase ~= "ghost" and pl.phase ~= "evil_ghost" and pl.role ~= "monster_master" then
			return false, "Only ghosts and the Monster Master may hover."
		end
		C.move.target = { x = pos.x, y = pos.y + dy, z = pos.z }
		C.move.speed_mult = 1.0
		return true, "Hovering " .. updown .. " " .. d .. "m."
	end
	local dist = tonumber(rest:match("(%d+%.?%d*)")) or 1
	dist = math.max(0.5, math.min(200, dist))
	local dir = C.dir_from_bearing(low)
	if not dir then return false, "move: n s e w ne nw se sw | to | fly | stop" end
	local pos = player:get_pos()
	C.move.target = { x = pos.x + dir[1] * dist, y = pos.y, z = pos.z + dir[3] * dist }
	C.move.speed_mult = 1.0
	return true, string.format("Moving %s %dm at %dm/s.", low, dist, C.cfg.move_speed)
end

handlers.stop = function(player)
	C.move.target = nil
	return true, "Halted."
end

handlers.warp = function(player, param)
	if not creative_on() then
		return false, "Warp is a creative/test facility (creative_mode)."
	end
	local x, y, z = (param or ""):match("^(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)$")
	if not x then return false, "warp X Y Z" end
	player:set_pos({ x = tonumber(x), y = tonumber(y), z = tonumber(z) })
	C.move.target = nil
	return true, "Warped to " .. minetest.pos_to_string({ x = tonumber(x), y = tonumber(y), z = tonumber(z) }) .. "."
end

handlers.wield = function(player, param)
	local spec = (param or ""):match("^(%S+)") or ""
	if spec == "" then
		return true, "Wielded: " .. verbose_item(player:get_wielded_item())
	end
	local inv = player:get_inventory()
	if not inv then return false, "No inventory." end
	local slot = tonumber(spec)
	if slot and slot >= 1 and slot <= 32 then
		local st = inv:get_stack("main", slot)
		if st:get_name() == "" then return false, "Slot empty." end
		player:set_wielded_item(st)
		C.set_wield(player, st)
		return true, "Wielding " .. verbose_item(st) .. " (slot " .. slot .. ")."
	end
	local full = expand_item(spec)
	if not full then return false, "Unknown item: " .. spec end
	for i = 1, 32 do
		local st = inv:get_stack("main", i)
		if st:get_name() == full then
			player:set_wielded_item(st)
			C.set_wield(player, st)
			return true, "Wielding " .. verbose_item(st) .. "."
		end
	end
	return false, "You don't carry " .. spec .. "."
end

function C.melee_dmg(player)
	local st = player:get_wielded_item()
	local def = minetest.registered_tools[st:get_name()]
	local caps = def and def.tool_capabilities
	return (caps and caps.damage_groups and caps.damage_groups.fleshy) or 1
end

handlers.fire = function(player, param)
	local pl = game_mode.get_player_state(C.who(player))
	if pl.phase ~= "alive" then
		return false, "Only the living fire. (" .. phase_label(pl) .. ")"
	end
	local stack = player:get_wielded_item()
	local name = stack:get_name()
	local def = W and W.defs_by_item and W.defs_by_item[name]
	local spec = (param or ""):match("^(%S+)%s*") or ""

	if spec ~= "" then
		local ok, err = C.resolve_target(player, spec)
		if not ok then return false, tostring(err) end
		local target = ok
		if target.class == "player" and C.ref_is_fake(target.ref) then
			if not def then return false, "Empty hands. Wield a weapon (/cp wield)." end
			C.face_target(player, target.ref:get_pos())
			local msg = C.synthetic_shot(player, def, stack, target.ref, target.name)
			return msg and false or true, msg or "[fired " .. (def.id or "?") .. " at " .. target.name .. "]"
		elseif target.class == "player" then
			local look = player:get_look_dir()
			local me = player:get_pos()
			local tp = target.ref:get_pos()
			local to_t = vector.normalize(vector.subtract(tp, { x = me.x, y = me.y + 1.2, z = me.z }))
			local dot = look and vector.dot(look, to_t) or 0
			if dot < 0.93 then
				return false, "You aren't looking at " .. target.name .. "."
			end
			local ok_los0 = C.los_clear({ x = me.x, y = me.y + 1.2, z = me.z }, tp)
			if not ok_los0 then return false, "Line of sight blocked." end
			if def then
				local msg = C.real_shot(player, def, stack)
				return msg and false or true, msg or "[fired " .. (def.id or "?") .. " at " .. target.name .. "]"
			end
			C.punch_event(player, target.ref, 1, 0.35, "melee")
			return true, "Punched."
		elseif target.class == "node" then
			C.face_target(player, target.pos)
			C.move.target = nil
			if not def then
				return true, "Empty hands, but you press your palm to " .. (C.labels[target.label] or target.label) .. "."
			end
			local msg = C.real_shot(player, def, stack)
			return msg and false or true, msg or "[fired " .. (def.id or "?") .. " at " .. target.label .. "]"
		elseif target.class == "entity" then
			local op = target.ref.get_pos and target.ref:get_pos()
			if op then C.face_target(player, op) end
			if not def then
				target.ref:punch(player, 1.0, { full_punch_interval = 0.8, damage_groups = { fleshy = 1 } })
				return true, "Struck " .. target.label .. "."
			end
			local msg = C.real_shot(player, def, stack)
			return msg and false or true, msg or "[fired " .. (def.id or "?") .. " at " .. target.label .. "]"
		end
	end

	if not def then
		return true, "Empty hands. (/cp wield a weapon, or /cp fire <target> for a palm strike.)"
	end
	local msg = C.real_shot(player, def, stack)
	if msg then return false, msg end
	local seen = C.cmd_look(player)
	return true, "[fired along current aim]\n" .. seen
end

handlers.melee = function(player, param)
	local spec = (param or ""):match("^(%S+)") or ""
	if spec == "" then return false, "melee <target>" end
	local target, err = C.resolve_target(player, spec)
	if not target then return false, tostring(err) end
	if target.class == "player" then
		if C.ref_is_fake(target.ref) then
			local me = player:get_pos()
			local tp = target.ref:get_pos()
			local d = me and tp and vector.distance(me, tp) or 0
			if d > 8 then return false, "Too far to reach (" .. math.floor(d) .. "m)." end
			C.melee(player, target.ref, target.name)
			return true, "Struck " .. target.name .. "."
		end
		local me = player:get_pos()
		local tp = target.ref:get_pos()
		local d = vector.distance(me, tp)
		if d > 8 then return false, "Too far to reach (" .. math.floor(d) .. "m)." end
		target.ref:punch(player, 1.0, { full_punch_interval = 0.8, damage_groups = { fleshy = C.melee_dmg(player) } })
		return true, "Struck " .. target.name .. "."
	elseif target.class == "entity" then
		target.ref:punch(player, 1.0, { full_punch_interval = 0.8, damage_groups = { fleshy = C.melee_dmg(player) } })
		return true, "Struck " .. target.label .. "."
	elseif target.class == "node" then
		local me = player:get_pos()
		local d = vector.distance(me, target.pos)
		if d > 8 then return false, "Too far to reach (" .. math.floor(d) .. "m)." end
		C.face_target(player, target.pos)
		return true, C.punch_node(target.pos, player)
	end
	return false, "melee needs a player, entity, or node target."
end

handlers.load = function(player)
	if not W then return false, "sl_weapons unavailable." end
	local stack = player:get_wielded_item()
	local def = W.defs_by_item and W.defs_by_item[stack:get_name()]
	if not def or not def.pool then
		return false, "Wielded item is not a magazine weapon."
	end
	local out = W.mag_load(player, def, stack)
	player:set_wielded_item(out)
	C.set_wield(player, out)
	local pname = C.who(player)
	local pool = W.pools[pname]
	local mag = W.mag_get(out)
	local reserve = pool and (pool[def.pool] or 0) or 0
	return true, string.format("Loaded %s: %d in mag, %d in reserve pool.", def.id, mag, reserve)
end

handlers.ammo = function(player, param)
	local kind = (param or ""):match("^(%S+)") or ""
	if not W then return false, "sl_weapons unavailable." end
	if kind == "pool" or kind == "" then
		local name = C.who(player)
		local p = W.pools[name] or { bullets = 0, shells = 0, cells = 0, rockets = 0 }
		local parts = {}
		for _, k in ipairs({ "bullets", "shells", "cells", "rockets" }) do
			parts[#parts + 1] = k .. "=" .. (p[k] or 0)
		end
		return true, "Pool: " .. table.concat(parts, " ")
	end
	if not W.AMMO_YIELD[kind] then
		return false, "kinds: bullets shells cells rockets | pool"
	end
	local pos = C.nearest_node(player, { "sl_weapons:pad_ammo", "sl_weapons:pad_ammo_dim" }, 4)
	if not pos then
		return false, "No ammo pad in reach. (pads: /cp sense)"
	end
	local node = minetest.get_node(pos)
	local def = minetest.registered_nodes[node.name]
	if def and def.on_rightclick then
		def.on_rightclick(pos, node, player, player:get_wielded_item(), { type = "node", under = pos })
		return true, "Ammo pad tapped: " .. kind .. "."
	end
	return false, "Pad inert."
end

handlers.pad = function(player, param)
	local sub, rest = (param or ""):match("^(%S+)%s*(.*)$")
	sub = (sub or ""):lower()
	if sub == "" or sub == "list" then
		local lines = {}
		local n = 0
		for _, entry in pairs(W.pads or {}) do
			n = n + 1
			lines[#lines + 1] = string.format("  %d  %s (%s) %s",
				n, entry.kind, tostring(entry.item),
				entry.armed and "armed" or "depleted")
		end
		if n == 0 then return true, "No pads registered." end
		return true, "Pads:\n" .. table.concat(lines, "\n")
	elseif sub == "place" then
		if not (creative_on() or is_admin(C.who(player))) then
			return false, "Placing pads is a test/admin facility."
		end
		local kind, arg = (rest or ""):match("^(%S+)%s*(.*)$")
		if kind == "weapon" then
			local id = arg:match("^(%S+)") or "pistol"
			if not W.weapons[id] then return false, "Unknown weapon id." end
			local pos = player:get_pos()
			W.place_weapon_pad({ x = pos.x, y = pos.y, z = pos.z }, id)
			return true, "Weapon pad placed at your feet (" .. id .. ")."
		elseif kind == "ammo" then
			local a = arg:match("^(%S+)") or "bullets"
			if not W.AMMO_YIELD[a] then return false, "Unknown ammo kind." end
			local pos = player:get_pos()
			W.place_ammo_pad({ x = pos.x, y = pos.y, z = pos.z }, a)
			return true, "Ammo pad placed at your feet (" .. a .. ")."
		end
		return false, "pad place weapon <id> | pad place ammo <kind>"
	elseif sub == "use" then
		local pos = C.nearest_node(player, { "sl_weapons:pad_weapon", "sl_weapons:pad_weapon_dim",
			"sl_weapons:pad_ammo", "sl_weapons:pad_ammo_dim" }, 4)
		if not pos then return false, "No pad in reach." end
		local node = minetest.get_node(pos)
		local def = minetest.registered_nodes[node.name]
		if def and def.on_rightclick then
			def.on_rightclick(pos, node, player, player:get_wielded_item(), { type = "node", under = pos })
			return true, "Pad tapped."
		end
		return false, "Pad inert."
	end
	return true, "pad list | pad use | pad place weapon <id> | pad place ammo <kind>"
end

handlers.beacon = function(player)
	local lines = { "Beacon integrity (public):" }
	for _, team_id in ipairs(state.teams_order or { "beacon_a", "beacon_b" }) do
		local t = state.teams[team_id]
		if t then
			local pos = t.spawn
			local dir = "unknown"
			if pos and player:get_pos() then
				dir = C.bearing(pos.x - player:get_pos().x, pos.z - player:get_pos().z)
				dir = dir .. " " .. math.floor(vector.distance(pos, player:get_pos()) + 0.5) .. "m"
			end
			lines[#lines + 1] = string.format("  %s: HP %d (%s)", game_mode.get_team_label(team_id), t.hp or 0, dir)
		end
	end
	return true, table.concat(lines, "\n")
end

handlers.scan = function(player)
	local def = minetest.registered_tools[game_mode.modname .. ":scanner"]
	if not def then return false, "Scanner unavailable." end
	def.on_use(ItemStack(game_mode.modname .. ":scanner"), player, nil)
	return true, "Sweep issued (result lands in your feed)."
end

handlers.repair = function(player, param)
	local target, err = C.resolve_target(player, (param or ""):match("^(%S+)") or "")
	if not target then return false, tostring(err) end
	if target.class ~= "node" then return false, "repair needs a system node." end
	local was_sab = game_mode.is_sabotaged and game_mode.is_sabotaged(target.pos)
	local was_pos = game_mode.is_possessed and game_mode.is_possessed(target.pos)
	if not was_sab and not was_pos then
		return true, "Nothing to repair there (no corruption, no possession)."
	end
	local punches = was_pos and 2 or 1
	C.punch_node(target.pos, player, punches)
	return true, "Intervention executed (" .. punches .. " punches)."
end

handlers.use = function(player, param)
	local target, err = C.resolve_target(player, (param or ""):match("^(%S+)") or "")
	if not target then return false, tostring(err) end
	if target.class ~= "node" then return false, "use needs a node target." end
	local msg = C.rightclick(target.pos, player)
	return msg and false or true, msg or ("Interface opened on " .. target.label .. ".")
end

handlers.loot = function(player)
	local pos = C.nearest_node(player, { "sl_modebase:loot_crate" }, 5)
	if not pos then return true, "No loot crate in reach." end
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	if not inv then return true, "Crate has no inventory." end
	local pinv = player:get_inventory()
	local moved = {}
	for i = 1, 32 do
		local st = inv:get_stack("main", i)
		if st:get_name() ~= "" then
			local leftover = pinv:add_item("main", st)
			if leftover:get_count() < st:get_count() then
				moved[#moved + 1] = verbose_item(st)
			end
			inv:set_stack("main", i, leftover)
		end
	end
	if #moved == 0 then return true, "Crate is empty." end
	return true, "Taken: " .. table.concat(moved, ", ")
end

handlers.stash = function(player, param)
	local target, err = C.resolve_target(player, (param or ""):match("^(%S+)") or "crate")
	if not target or target.class ~= "node" then return false, "stash <crate>" end
	local meta = minetest.get_meta(target.pos)
	local inv = meta:get_inventory()
	if not inv then return false, "Not a container." end
	local st = player:get_wielded_item()
	if st:get_name() == "" then return false, "Wield something to stash." end
	local leftover = inv:add_item("main", st)
	player:set_wielded_item(leftover)
	C.set_wield(player, leftover)
	return true, "Stashed " .. verbose_item(st) .. "."
end

handlers.read = function(player, param)
	local spec = (param or ""):match("^(%S+)") or ""
	local full = expand_item(spec) or spec
	local def = minetest.registered_craftitems[full]
	if not def then return false, "Not a readable item." end
	def.on_use(ItemStack(full), player, nil)
	return true, "Read."
end

handlers.craft = function(player, param)
	local sub = (param or ""):match("^(%S+)") or ""
	if sub == "list" or sub == "" then
		if not get_craft_recipes then return false, "Crafting bridge unavailable (sl_gui)." end
		local recipes = get_craft_recipes()
		local lines = {}
		for _, r in ipairs(recipes) do
			local ing = {}
			for k, n in pairs(r.ingredients) do ing[#ing + 1] = k .. "x" .. n end
			lines[#lines + 1] = string.format("  #%-3d %-24s [%s] = %s",
				r.id, r.description, r.category, table.concat(ing, " "))
		end
		return true, "Craft (" .. #recipes .. "):\n" .. table.concat(lines, "\n")
	end
	local rid = tonumber(sub)
	if not rid then return false, "craft list | craft <id> [qty]" end
	if not craft_recipe_by_id then return false, "Crafting bridge unavailable (sl_gui)." end
	local qty = tonumber((param or ""):match("(%d+)")) or 1
	local ok, msg = craft_recipe_by_id(player, rid, qty)
	return ok, msg
end

handlers.roster = function(player)
	return true, C.cmd_roster()
end
handlers.players = handlers.roster

handlers.mm = function(player, param)
	local sub, rest = (param or ""):match("^(%S+)%s*(.*)$")
	sub = (sub or "status"):lower()
	local name = C.who(player)
	local pl = game_mode.get_player_state(name)
	local is_mm = pl.role == "monster_master"

	if sub == "status" or sub == "" then
		local lines = {
			"Monster Master: " .. (state.monster_master.player or "None"),
			"You: " .. (is_mm and "the Monster Master" or "not the Monster Master"),
		}
		if is_mm then
			lines[#lines + 1] = "Doctrine: bare hands only (ranged items stripped)."
			lines[#lines + 1] = "Tools: /cp mm summon | spawner <variant> | feed <n> | return | grip <0-3>"
		elseif state.monster_master.player == nil then
			lines[#lines + 1] = "The seat is open: /cp mm take"
		end
		return true, table.concat(lines, "\n")
	elseif sub == "take" then
		return call_command(name, "sl_be_monster_master", "")
	elseif sub == "resign" then
		if not is_mm then return false, "You are not the Monster Master." end
		game_mode.set_monster_master(nil)
		return true, "You resigned the doctrine."
	elseif sub == "summon" then
		if not is_mm then return false, "Only the Monster Master." end
		local def = minetest.registered_tools[game_mode.modname .. ":summon_monster"]
		if not def then return false, "Summon tool missing." end
		def.on_use(ItemStack(game_mode.modname .. ":summon_monster"), player, nil)
		return true, "Summon issued."
	elseif sub == "spawner" then
		if not is_mm then return false, "Only the Monster Master." end
		local pos = C.nearest_node(player, { "sl_modebase:monster_spawner" }, 12)
		if not pos then return false, "No spawner unit in reach. (/cp mm place is a test facility)" end
		local variant = (rest or ""):match("^(%S+)") or "stalker"
		local ok = game_mode.spawner_activate(name, pos, variant)
		return ok, ok and ("Spawner produced a " .. variant .. ".") or "Spawner refused."
	elseif sub == "place" then
		if not (creative_on() or is_admin(name)) then return false, "Test facility." end
		local pos = player:get_pos()
		minetest.set_node({ x = pos.x, y = pos.y, z = pos.z },
			{ name = game_mode.modname .. ":monster_spawner" })
		local meta = minetest.get_meta({ x = pos.x, y = pos.y, z = pos.z })
		local inv = meta:get_inventory()
		if inv and inv:get_size("feed") == 0 then inv:set_size("feed", 4) end
		return true, "Spawner unit materialized at your feet."
	elseif sub == "feed" then
		if not is_mm then return false, "Only the Monster Master." end
		local pos = C.nearest_node(player, { "sl_modebase:monster_spawner" }, 12)
		if not pos then return false, "No spawner in reach." end
		local n = tonumber((rest or ""):match("(%d+)")) or 1
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		if not inv or not game_mode.count_feed_essence then return false, "Spawner not ready." end
		local pinv = player:get_inventory()
		local removed = pinv:remove_item("main", ItemStack(game_mode.ESSENCE_ITEM .. " " .. math.max(1, math.min(64, n))))
		local count = removed:get_count()
		if count == 0 then return false, "No essence to feed." end
		if inv:get_size("feed") == 0 then inv:set_size("feed", 4) end
		inv:add_item("feed", removed)
		return true, "Fed " .. count .. " essence into the unit (feed now: "
			.. game_mode.count_feed_essence(inv) .. ")."
	elseif sub == "return" then
		return call_command(name, "sl_mm_return", "")
	elseif sub == "grip" then
		if not is_mm then return false, "Only the Monster Master." end
		local n = tonumber((rest or ""):match("(%d)")) or 0
		if W and W.set_mm_levels then
			W.set_mm_levels(player, { grip = math.max(0, math.min(3, n)) })
			return true, "Tyrant Grip level " .. n .. " (punch damage " .. (W.MM_GRIP_DAMAGE[n] or "?") .. ")."
		end
		return false, "sl_weapons unavailable."
	elseif sub == "spawn" then
		local count = tonumber((rest or ""):match("(%d+)")) or 1
		return call_command(name, "sl_mm_spawn", tostring(math.max(1, math.min(5, count))))
	end
	return true, "mm status|take|resign|summon|spawn [n]|spawner <variant>|place|feed <n>|return|grip <0-3>"
end

handlers.ghost = function(player, param)
	local sub, rest = (param or ""):match("^(%S+)%s*(.*)$")
	sub = (sub or ""):lower()
	local name = C.who(player)
	local pl = game_mode.get_player_state(name)

	if sub == "offer" then
		if pl.phase ~= "ghost" then return false, "You are not a contained ghost." end
		local target = (rest or ""):match("^(%S+)")
		local kind = rest and rest:match("(%S+)$")
		if not target or not kind then
			return false, "ghost offer <living> <security|logistics|medical>"
		end
		return call_command(name, "sl_ghost_offer", target .. " " .. kind, true)
	elseif sub == "revive" then
		if pl.phase ~= "ghost" then return false, "Only a contained ghost may revive." end
		local def = minetest.registered_craftitems[game_mode.modname .. ":reincarnate"]
		if not def then return false, "No reincarnate item." end
		if not player:get_inventory():contains_item("main", ItemStack(game_mode.modname .. ":reincarnate")) then
			return false, "You don't hold the reincarnate option (your cage inventory)."
		end
		def.on_use(ItemStack(game_mode.modname .. ":reincarnate"), player, nil)
		return true, "Revival initiated... a morally negative choice."
	elseif sub == "sabotage" then
		if pl.phase ~= "evil_ghost" then return false, "Only an evil ghost (you are " .. phase_label(pl) .. ")." end
		local target, err = C.resolve_target(player, (rest or ""):match("^(%S+)") or "")
		if not target or target.class ~= "node" then return false, "sabotage <beacon|crate|altar|spawner>" end
		local def = minetest.registered_tools[game_mode.modname .. ":sabotage_charge"]
		if not def then return false, "No sabotage charge." end
		def.on_use(ItemStack(game_mode.modname .. ":sabotage_charge"), player, { type = "node", under = target.pos })
		return true, "Charge primed."
	elseif sub == "possess" then
		if pl.phase ~= "evil_ghost" then return false, "Only an evil ghost." end
		local target, err = C.resolve_target(player, (rest or ""):match("^(%S+)") or "")
		if not target or target.class ~= "node" then return false, "possess <crate|spawner|pad|turret|terminal>" end
		local def = minetest.registered_tools[game_mode.modname .. ":possession_focus"]
		if not def then return false, "No focus." end
		game_mode.grant_evil_ghost_kit(player)
		def.on_use(ItemStack(game_mode.modname .. ":possession_focus"), player, { type = "node", under = target.pos })
		return true, "Focus applied."
	elseif sub == "summon" then
		local living = (rest or ""):match("^(%S+)")
		if not living then return false, "ghost summon <living>" end
		if pl.phase ~= "alive" then return false, "Only the living summon." end
		return call_command(name, "sl_summon_ghost", living, true)
	elseif sub == "status" then
		return true, C.cmd_status(player)
	end
	return true, "ghost offer <living> <kind> | ghost revive | ghost summon <living> | ghost sabotage <t> | ghost possess <t>"
end

handlers.ritual = function(player)
	local target, err = C.resolve_target(player, "altar")
	if not target then return false, tostring(err) end
	local msg = C.rightclick(target.pos, player)
	return msg and false or true, msg or "Altar ritual performed (kit consumed if blessed)."
end

handlers.tool = function(player, param)
	local spec = (param or ""):match("^(%S+)") or ""
	if spec == "" then return true, "tool <name> (flare | scanner | targeting_log | data_pad_*)" end
	local full = expand_item(spec) or spec
	local def = minetest.registered_craftitems[full] or minetest.registered_tools[full]
	if not def or not def.on_use then return false, "No such usable item." end
	local st = def.on_use(ItemStack(full), player, nil)
	if st and st:get_name() ~= full then
		player:set_wielded_item(st)
		C.set_wield(player, st)
	end
	return true, "Used " .. spec .. "."
end

handlers.whisper = function(player, param)
	local target, msg = (param or ""):match("^(%S+)%s+(.+)$")
	if not target then return false, "whisper <player> <msg>" end
	if not minetest.get_player_by_name(target) then return false, "No such operator." end
	local wcmd = minetest.registered_chatcommands.w or minetest.registered_chatcommands.msg
	if wcmd and wcmd.func then
		return wcmd.func(C.who(player), target .. " " .. msg)
	end
	minetest.chat_send_player(target, "[" .. C.who(player) .. " whispers] " .. msg)
	return true, "Whispered."
end

handlers.say = function(player, param)
	local text = param or ""
	if text == "" then return false, "say <text>" end
	minetest.chat_send_all("<" .. C.who(player) .. "> " .. text)
	return true, "Sent."
end

handlers.feed = function(player, param)
	local n = tonumber((param or ""):match("(%d+)")) or 25
	n = math.max(1, math.min(200, n))
	local name = C.who(player)
	local lines = {}
	for i = #C.feed - n + 1, #C.feed do
		if i >= 1 then
			local e = C.feed[i]
			if e.who == "ALL" or e.who == name then
				lines[#lines + 1] = string.format("[%s] %s", os.date("%H:%M:%S", e.t), e.text)
			end
		end
	end
	if #lines == 0 then return true, "(feed quiet)" end
	return true, table.concat(lines, "\n")
end

handlers.lobby = function(player)
	return true, C.cmd_lobby(player)
end

handlers.set = function(player, param)
	if not is_admin(C.who(player)) then return false, "Admin only." end
	local key, val = (param or ""):match("^(%S+)%s*(%S+)$")
	if not key then return false, "set beacon_hp <n> | mm_auto on/off | auto_start on/off" end
	local s = state.settings
	if key == "beacon_hp" then
		local n = tonumber(val)
		if not n or n < 1 then return false, "beacon_hp needs a number." end
		s.beacon_hp = math.floor(n)
		return true, "Beacon HP set to " .. s.beacon_hp .. " (applies next match)."
	elseif key == "mm_auto" then
		s.mm_auto_assign = val == "on" or val == "true"
		return true, "MM auto-assign: " .. tostring(s.mm_auto_assign)
	elseif key == "auto_start" then
		s.auto_start = val == "on" or val == "true"
		return true, "Auto-start: " .. tostring(s.auto_start)
	end
	return false, "set beacon_hp | mm_auto | auto_start"
end

handlers.start = function(player, param)
	return call_command(C.who(player), "sl_match_start", (param or ""):match("^(%S+)") or "")
end

handlers.ready = function(player)
	return call_command(C.who(player), "sl_ready", "")
end

-- Admin/test: mark every connected operator ready for the countdown
-- (botmatch does this itself when it schedules matches; for manually
-- started matches an admin needs the same lever).
handlers.readyall = function(player)
	if not is_admin(C.who(player)) then return false, "Admin only." end
	if not state.ready_check.active then
		return false, "No ready check running."
	end
	local n = 0
	for _, name in ipairs(game_mode.get_connected_player_names()) do
		game_mode.mark_ready(name)
		n = n + 1
	end
	return true, "Marked " .. n .. " operators ready."
end

handlers.stopmatch = function(player)
	return call_command(C.who(player), "sl_match_stop", "")
end

handlers.autostart = function(player, param)
	return call_command(C.who(player), "sl_autostart", (param or ""):match("^(%S+)") or "")
end

handlers.console = function(player, param)
	local sub = (param or ""):match("^(%S+)") or "status"
	if sub == "status" then
		return true, C.console and ("Console player on station: " .. C.console:get_player_name()) or "No console player."
	elseif sub == "join" then
		return C.console_join()
	elseif sub == "leave" then
		return C.console_leave()
	end
	return true, "console status|join|leave"
end

handlers.give = function(player, param)
	local item, n = (param or ""):match("^(%S+)%s*(%d*)")
	if not item then return false, "give <item> [count]" end
	if not (creative_on() or is_admin(C.who(player))) then
		return false, "give is a creative/test facility."
	end
	local full = expand_item(item) or item
	local count = tonumber(n) or 1
	if not minetest.registered_items[full] then return false, "Unknown item: " .. full end
	local inv = player:get_inventory()
	if not inv then return false, "No inventory." end
	local leftover = inv:add_item("main", ItemStack(full .. " " .. count))
	return true, "Gave " .. full .. " x" .. count .. (leftover:get_count() > 0 and " (partial)" or "") .. "."
end

-- Debug/admin: trace the ray from the eye toward a target and report hits.
handlers.trace = function(player, param)
	local spec = (param or ""):match("^(%S+)") or ""
	if spec == "" then return false, "trace <target>" end
	local target, err = C.resolve_target(player, spec)
	if not target then return false, tostring(err) end
	local pos = player:get_pos()
	local eye_h = 1.625
	local props = player.get_properties and player:get_properties()
	if props and props.eye_height then eye_h = props.eye_height end
	local eye = { x = pos.x, y = pos.y + eye_h, z = pos.z }
	local tpos = target.class == "player" and target.ref:get_pos() or target.pos
	local dir = vector.normalize(vector.subtract(tpos, eye))
	local lookdir = player.get_look_dir and player:get_look_dir() or nil
	local endpoint = vector.add(eye, vector.multiply(dir, 80))
	local lines = { string.format("eye=%s target=%s aim=(%.3f,%.3f,%.3f) lookdir=%s",
		minetest.pos_to_string(vector.round(eye)), minetest.pos_to_string(vector.round(tpos)),
		dir.x, dir.y, dir.z,
		lookdir and string.format("(%.3f,%.3f,%.3f)", lookdir.x, lookdir.y, lookdir.z) or "nil") }
	for hit in minetest.raycast(eye, endpoint, true, false) do
		if hit.type == "node" then
			lines[#lines + 1] = string.format("NODE %s %s", minetest.pos_to_string(hit.under or hit.pos), (minetest.get_node(hit.under or hit.pos)).name)
			break
		elseif hit.type == "object" then
			lines[#lines + 1] = "OBJECT at " .. minetest.pos_to_string((hit.ref.get_pos and hit.ref:get_pos()) or {x=0,y=0,z=0})
		end
	end
	return true, table.concat(lines, "\n")
end

-- Debug/admin: report exactly what W.fire_hitscan will see.
handlers.probe = function(player)
	if not W or not W.aim then return false, "sl_weapons unavailable." end
	local eye, dir = W.aim(player)
	local lines = {
		"W.aim: eye=" .. minetest.pos_to_string(eye) .. " dir=("
			.. string.format("%.3f,%.3f,%.3f", dir.x, dir.y, dir.z) .. ")",
		"get_look_dir=(" .. string.format("%.3f,%.3f,%.3f",
			player:get_look_dir().x, player:get_look_dir().y, player:get_look_dir().z) .. ")",
	}
	if W.mag_get then
		lines[#lines + 1] = "wielded mag=" .. tostring(W.mag_get(player:get_wielded_item()))
	end
	-- replicate W.fire_hitscan's ray exactly
	local stack = player:get_wielded_item()
	local def = W.defs_by_item and W.defs_by_item[stack:get_name()]
	if def then
		local range = def.range or 60
		local endpoint = vector.add(eye, vector.multiply(dir, range))
		local n = 0
		for hit in minetest.raycast(eye, endpoint, true, false) do
			n = n + 1
			if hit.type == "node" then
				local node = minetest.get_node(hit.under or hit.pos)
				lines[#lines + 1] = string.format("FIRE-RAY hit#%d NODE %s %s",
					n, minetest.pos_to_string(hit.under or hit.pos), node and node.name or "?")
				break
			elseif hit.type == "object" then
				lines[#lines + 1] = string.format("FIRE-RAY hit#%d OBJECT at %s",
					n, minetest.pos_to_string((hit.ref.get_pos and hit.ref:get_pos()) or {x=0,y=0,z=0}))
			end
		end
		if n == 0 then lines[#lines + 1] = "FIRE-RAY: nothing in " .. range .. "m" end
	end
	return true, table.concat(lines, "\n")
end

handlers.history = function(player)
	if botmatch and botmatch.stats then
		local lines = { "Botmatch-soak history (matches: " .. #(botmatch.stats.matches or {}) .. "):" }
		for _, m in ipairs(botmatch.stats.matches or {}) do
			lines[#lines + 1] = string.format("  #%d winner=%s %.0fs", m.id, tostring(m.winner), m.duration_s or 0)
		end
		return true, table.concat(lines, "\n")
	end
	return true, "No match history."
end

handlers.help = function(player, param)
	local pl = game_mode.get_player_state(C.who(player))
	local common = {
		"cp status        full readout (HP/pos/inv/ammo/phase)",
		"cp sense [r]     text vision: nearby systems/entities/bodies, bearings",
		"cp look          what your beam sees",
		"cp roster        operators (public matchmaking list)",
		"cp feed [n]      recent broadcast/system lines",
		"cp move <dir> <m> | to X Z | fly up/down | stop   |   cp aim <n|s|e|w|ne|...>",
		"cp wield <item|slot> | cp load | cp fire [target] | cp melee <player>",
		"cp use <crate|altar|spawner|pad|turret|terminal> | cp loot | cp stash",
		"cp scan          signal sweep (corruption/possession)",
		"cp beacon        public beacon integrity",
		"cp craft list | cp ghost ... | cp mm ... | cp pad ... | cp ammo <kind>",
		"cp lobby | cp ready | cp start [now] (admin) | cp stopmatch (admin)",
		"cp whisper <p> <msg> | cp say <msg>",
	}
	local lines = { "CHATPLAY command surface:" }
	for _, l in ipairs(common) do table.insert(lines, "  " .. l) end
	if pl.phase == "ghost" then
		lines[#lines + 1] = "GHOST: cp ghost offer <living> <kind> | cp ghost revive (seal: no public chat)"
	elseif pl.phase == "evil_ghost" then
		lines[#lines + 1] = "EVIL: cp ghost sabotage <t> | cp ghost possess <t> | move/fly (seal: no public chat)"
	elseif pl.role == "monster_master" then
		lines[#lines + 1] = "MM: cp mm summon | spawner <variant> | feed <n> | return | grip <0-3>"
	end
	lines[#lines + 1] = "Agent transport: world/agent_inbox/cmd.txt -> out.txt + feed.log"
	return true, table.concat(lines, "\n")
end

-- ----------------------------------------------------------------
-- The dispatcher
-- ----------------------------------------------------------------

-- Debug/admin verbs. `trace` and `probe` replicate the engine's ray
-- and fire path and were indispensable while fixing combat, but they
-- leak internals (ray endpoints, aim vectors, node names) that a
-- player has no business reading. They stay available for headless
-- debugging behind sl_chatplay.debug_verbs; set it false to hide
-- them completely from a shipped build.
local DEBUG_VERBS = { trace = true, probe = true }

function C.run(player, param)
	local verb, rest = (param or ""):match("^(%S+)%s*(.*)$")
	if not verb or verb == "" then
		return handlers.help(player, "")
	end
	verb = verb:lower()
	if DEBUG_VERBS[verb] and not sl_chatplay.cfg.debug_verbs then
		return false, "Unknown /cp verb: " .. verb .. " (try /cp help)"
	end
	local h = handlers[verb]
	if not h then
		return false, "Unknown /cp verb: " .. verb .. " (try /cp help)"
	end
	local ok, msg = h(player, rest)
	return ok, msg
end

-- Chat command registration. sl_modebase's ghost guard wraps all chat
-- commands at mods-loaded time; we re-register AFTER that with our own
-- phase policy so the designed ghost channels (/cp status, ghost
-- offer/revive) stay reachable while the comms seal is preserved.
function C.install_cp()
	minetest.register_chatcommand("cp", {
		params = "<verb> [args]",
		description = "Chatplay: play System Looting with text commands (see /cp help)",
		func = function(name, param)
			local player = minetest.get_player_by_name(name)
			if not player then return false, "No player ref." end
			local pl = game_mode.get_player_state(name)

			if pl and (pl.phase == "ghost" or pl.phase == "evil_ghost") then
				local verb = (param or ""):match("^(%S+)") or ""
				verb = verb:lower()
				local allowed_ghost = { status = true, feed = true, help = true, ping = true,
					stop = true, move = true, aim = true, look = true, sense = true,
					wield = true, read = true, ghost = true, say = false }
				if pl.phase == "ghost" then
					allowed_ghost.move = false
					allowed_ghost.wield = false
					allowed_ghost.read = false
				end
				if not allowed_ghost[verb] then
					return false, "Ghost communications are sealed."
				end
			end

			return C.run(player, param)
		end,
	})
end

C.install_cp()
