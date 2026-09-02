-- ================================================================
-- sl_chatplay/console.lua -- the headless CONSOLE PLAYER.
--
-- A botmatch fake-player (logical object with inventory/HP/pos)
-- driven by the /cp command language. It joins real matches with
-- real bots; the match logic treats it as any other operator.
-- When botmatch is disabled, the console player does not exist and
-- /cp still works for real, human clients.
-- ================================================================

local C = sl_chatplay

C.console = nil -- PlayerRef once created

-- ----------------------------------------------------------------
-- Movement state (async step-toward, same speed model as bots)
-- ----------------------------------------------------------------
C.move = { target = nil, speed_mult = 1.0 }

-- Movement speed multipliers mirror the physics overrides in
-- sl_modebase/spawn.lua (alive 1.0, ghost 1.5, evil ghost upper bound).
local function speed_mult_for(name)
	local pl = game_mode.get_player_state(name)
	if pl.phase == "evil_ghost" then return 2.2
	elseif pl.phase == "ghost" then return 1.5
	elseif pl.phase == "monster" or pl.phase == "master_monster" then return 1.5 end
	return 1.0
end

local move_accum = 0
minetest.register_globalstep(function(dtime)
	move_accum = move_accum + dtime
	if move_accum < 0.1 then return end
	local dt = move_accum
	move_accum = 0
	local p = C.console
	if not p or not C.move.target then return end
	local pos = p:get_pos()
	local tgt = C.move.target
	local dx, dy, dz = tgt.x - pos.x, tgt.y - pos.y, tgt.z - pos.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 0.2 then
		C.move.target = nil
		return
	end
	local speed = C.cfg.move_speed * C.move.speed_mult * speed_mult_for(p:get_player_name())
	local step = math.min(speed * dt, d)
	p:set_pos({ x = pos.x + dx / d * step, y = pos.y + dy / d * step, z = pos.z + dz / d * step })
end)

-- ----------------------------------------------------------------
-- PlayerRef factory: botmatch fake player + chatplay extensions
-- ----------------------------------------------------------------
function C.make_console_ref(name)
	if not (botmatch and botmatch.modpath) then return nil end
	local fp = dofile(botmatch.modpath .. "/fake_player.lua")
	local bot = fp.new(name)

	-- --- identity for chatplay routing ---
	bot.is_console = true
	bot._aimdir = { x = 0, y = 0, z = 1 }
	bot._wield = ItemStack("")
	bot._velocity = { x = 0, y = 0, z = 0 }
	-- fake_player's set_pos probes _pos_hook; define a quiet one so the
	-- "unimplemented ObjectRef method" warning stays silent.
	bot._pos_hook = function() end

	-- --- overrides ---
	function bot:set_aim(dir)
		self._aimdir = { x = dir.x or 0, y = dir.y or 0, z = dir.z or 0 }
	end
	function bot:get_look_dir() return self._aimdir end
	function bot:get_look_horizontal()
		return math.atan2(self._aimdir.x, self._aimdir.z)
	end
	function bot:get_look_vertical()
		return math.asin(math.max(-1, math.min(1, self._aimdir.y)))
	end
	function bot:get_wielded_item() return self._wield end
	function bot:set_wielded_item(stack)
		self._wield = ItemStack(stack)
		-- The inventory slot keeps a STRING snapshot (InvMeta stores
		-- to_string()), so mag/wear changes to _wield never reach it and
		-- re-wielding restores a stale full magazine. Write the updated
		-- stack back into the matching inventory slot.
		if self._inv and self._inv.set_stack then
			local name = self._wield:get_name()
			if name ~= "" then
				local str = self._wield:to_string()
				for i = 1, (self._inv.size or 32) do
					local st = self._inv:get_stack("main", i)
					if st:get_name() == name then
						-- InvMeta:set_stack stringifies only tables; pass
						-- the serialized form so the slot updates cleanly
						-- (with the new wear/mag) instead of tostring() junk.
						self._inv:set_stack("main", i, str)
						break
					end
				end
			end
		end
	end
	function bot:get_wield_index() return 1 end
	function bot:get_velocity() return self._velocity end
	function bot:set_velocity(v) self._velocity = { x = v.x or 0, y = v.y or 0, z = v.z or 0 } end
	function bot:add_velocity(v)
		self._velocity.x = self._velocity.x + (v.x or 0)
		self._velocity.y = self._velocity.y + (v.y or 0)
		self._velocity.z = self._velocity.z + (v.z or 0)
	end
	-- Punching a monster/entity works (object:punch path); punching a
	-- fake player is routed through C.punch_event instead.
	function bot:punch(obj, time_from_last_punch, tool_capabilities, dir, damage)
		if obj and obj.is_player and obj:is_player() then
			local dmg = tool_capabilities and tool_capabilities.damage_groups
				and tool_capabilities.damage_groups.fleshy or (damage or 0)
			C.punch_event(bot, obj, dmg or 1, 1.0, "melee")
			return
		end
		-- real entities: engine semantics
		local caps = tool_capabilities or { full_punch_interval = 1.0, damage_groups = { fleshy = 1 } }
		obj:punch(bot, time_from_last_punch or 1.0, caps, dir or { x = 0, y = 0, z = 1 }, damage or 1)
	end

	return bot
end

-- ----------------------------------------------------------------
-- Join / leave the world
-- ----------------------------------------------------------------
function C.console_join()
	if C.console then return nil, "Console player already on station." end
	if not (botmatch and botmatch.enabled) then
		return nil, "Console player requires the botmatch harness (sl_botmatch.enabled = true)."
	end
	local name = C.cfg.console_name
	if minetest.get_player_by_name(name) then
		return nil, "Name " .. name .. " is already in use."
	end
	local bot = C.make_console_ref(name)
	if not bot then return nil, "Cannot build a console player (botmatch harness missing)." end
	C.console = bot

	-- Register with the harness BEFORE it starts scheduling matches.
	botmatch.bots[name] = bot
	table.insert(botmatch.bot_order, name)
	table.insert(botmatch.connected, name)
	C.console_name = name

	botmatch.fire("joinplayer", bot)
	if game_mode.spawn_player then game_mode.spawn_player(bot) end
	if botmatch.record_event then botmatch.record_event("console_joins", 1) end

	minetest.log("action", "[sl_chatplay] console player " .. name .. " on station.")
	return true, "Console player " .. name .. " on station."
end

-- The auth system cannot be touched during on_mods_loaded (spawn_player
-- reads player privs), so the join is scheduled after server boot and
-- retried a few times if it fails.
function C.console_join_scheduled()
	if C.console then return end
	C._join_attempts = (C._join_attempts or 0) + 1
	local ok, err = C.console_join()
	if not ok then
		minetest.log("warning", "[sl_chatplay] console join attempt " .. C._join_attempts
			.. " failed: " .. tostring(err))
		if C._join_attempts < 3 then
			minetest.after(4, C.console_join_scheduled)
		end
	end
end

function C.console_leave()
	if not C.console then return nil, "No console player." end
	local name = C.console:get_player_name()
	botmatch.fire("leaveplayer", C.console)
	for i, n in ipairs(botmatch.connected) do
		if n == name then table.remove(botmatch.connected, i) break end
	end
	for i, n in ipairs(botmatch.bot_order) do
		if n == name then table.remove(botmatch.bot_order, i) break end
	end
	botmatch.bots[name] = nil
	C.console = nil
	return true, "Console player disembarked."
end

-- ----------------------------------------------------------------
-- botmatch integration: keep the console player OUT of bot AI
-- control (it is driven by /cp commands instead).
-- ----------------------------------------------------------------
function C.hook_botmatch()
	if not (botmatch and botmatch.enabled) then
		if C.cfg.console then
			minetest.log("action", "[sl_chatplay] console player disabled: botmatch harness not enabled.")
		end
		return
	end
	-- start_run re-defines botmatch.behave (dofile behavior.lua), so wrap
	-- start_run and install the behave guard right after it returns.
	local orig_start = botmatch.start_run
	botmatch.start_run = function(...)
		local r = { orig_start(...) }
		if botmatch.behave and not C._behave_wrapped then
			C._behave_wrapped = true
			local orig_behave = botmatch.behave
			botmatch.behave = function(name, dt)
				if name == C.cfg.console_name and C.console then
					return -- remote player: /cp commands steer it
				end
				return orig_behave(name, dt)
			end
			minetest.log("action", "[sl_chatplay] bot AI guard installed for " .. C.cfg.console_name)
		end
		return unpack(r)
	end
end
