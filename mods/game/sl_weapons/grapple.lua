-- ================================================================
-- sl_weapons — the Grapple Lash (spec §10.1)
-- A lasso of light. Fabricated, never rolled (§10.1 "The
-- pilgrimage"). Five cells a swing — every swing is a railgun round
-- you didn't buy. Using it is a published bet: loud crack, visible
-- line, hands full, any damage drops you, anyone can cut the line,
-- and hooking a monster reels you toward the monster.
-- ================================================================

local W = sl_weapons
local S = W.S

local LASH_COST = 5      -- cells per launch
local LASH_COOLDOWN = 2.0
local LASH_SPEED = 30
local LASH_MAXLEN = 24
local LASH_REEL_ACCEL = 2.4  -- velocity added per reel tick (10 Hz)
local LASH_REEL_MAX = 14     -- cap of closing speed
local LASH_MAXTIME = 6.0

W.lash = {}        -- [name] = { anchor = pos, hook = lua, at = time }
W.lash_ready = {}  -- [name] = cooldown until
-- Match generation: bumped at match end. A hook launched in match N
-- must never anchor after the sweep — a stray line from a finished
-- match would ride into the next one attached to a fresh body.
W.match_gen = W.match_gen or 0

minetest.register_entity(W.modname .. ":lash_hook", {
	_stub_ray_radius = 0.25,
	sl_weapon_fx = true,
	visual = "sprite",
	textures = { "sl_weapons_lash_hook.png" },
	visual_size = { x = 0.8, y = 0.8 },
	physical = false,
	collide_with_objects = false,
	pointable = true,
	static_save = false,

	on_punch = function(self, puncher)
		-- One hit severs the line (spec §10.1, danger 4).
		if self.shooter then
			W.lash_detach(self.shooter, "cut")
		end
		if self.object and self.object.remove then
			pcall(function() self.object:remove() end)
		end
		return true
	end,

	on_step = function(self, dtime)
		local obj = self.object
		local pos = obj:get_pos()
		local vel = obj:get_velocity() or { x = 0, y = 0, z = 0 }
		self.life = (self.life or 0) + dtime

		-- Stray from a finished match: the line went with the sweep.
		if self.gen and self.gen ~= W.match_gen then
			obj:remove()
			return
		end

		if not self.anchored then
			local newpos = vector.add(pos, vector.multiply(vel, dtime))
			for hit in minetest.raycast(pos, newpos, true, false) do
				if hit.type == "node" then
					-- Solid faces only: the hook bites.
					local a = hit.under or hit.pos or newpos
					self.anchor = { x = a.x, y = a.y, z = a.z }
					self.anchored = true
					obj:set_velocity({ x = 0, y = 0, z = 0 })
					obj:set_pos(self.anchor)
					if self.shooter then
						W.lash_attach(self.shooter, self.anchor, self)
					end
					minetest.sound_play("sl_weapons_lash_bite", {
						pos = self.anchor, gain = 0.7, max_hear_distance = 18,
					})
					return
				elseif hit.type == "object" then
					local target = hit.ref
					local lua = target.get_luaentity and target:get_luaentity()
					if target ~= obj and not (lua and lua.sl_weapon_fx) then
						-- Hooking a monster does not pull it to you.
						-- It reels you to it (danger 5).
						local tp = target:get_pos()
						self.anchor = { x = tp.x, y = tp.y + 1, z = tp.z }
						self.anchored = true
						obj:set_velocity({ x = 0, y = 0, z = 0 })
						obj:set_pos(self.anchor)
						if self.shooter then
							W.lash_attach(self.shooter, self.anchor, self, true)
						end
						minetest.sound_play("sl_weapons_lash_bite", {
							pos = self.anchor, gain = 0.7, max_hear_distance = 18,
						})
						return
					end
				end
			end
			obj:set_pos(newpos)
			if self.life > (LASH_MAXLEN / LASH_SPEED) + 0.1 then
				obj:remove()
			end
		else
			-- Anchored: hold position, die with the line.
			if not self.shooter or not W.lash[self.shooter] then
				obj:remove()
			end
		end
	end,
})

function W.lash_attach(name, anchor, hook_lua, to_monster)
	W.lash[name] = { anchor = anchor, hook = hook_lua, at = W.now(), monster = to_monster }
	if to_monster then
		minetest.chat_send_player(name, S("The line bit something alive. It reels you."))
	end
end

function W.lash_detach(name, reason)
	local st = W.lash[name]
	if not st then return end
	W.lash[name] = nil
	if st.hook and st.hook.object and st.hook.object.remove then
		pcall(function() st.hook.object:remove() end)
	end
	local player = minetest.get_player_by_name(name)
	if player then
		minetest.sound_play("sl_weapons_lash_snap", {
			pos = player:get_pos(), gain = 0.7, max_hear_distance = 20,
		}, false)
		local why = ({
			damage = S("The line snaps — you took a hit."),
			cut = S("Someone cut your line."),
			arrived = S("Detached."),
			expired = S("The line lets go."),
		})[reason]
		if why then minetest.chat_send_player(name, why) end
	end
end

function W.lash_detach_all()
	for name in pairs(table.copy(W.lash)) do
		W.lash_detach(name, "expired")
	end
end

minetest.register_tool(W.modname .. ":grapple", {
	description = S("Grapple Lash\n(A lasso of light. Expensive. Dangerous.)"),
	inventory_image = "sl_weapons_grapple.png",
	groups = { weapon = 1, not_in_crafting_guide = 1 },

	on_use = function(itemstack, user)
		if not user or not user.is_player or not user:is_player() then return itemstack end
		local name = user:get_player_name()

		-- Fire again = detach (the only clean release besides arrival).
		if W.lash[name] then
			W.lash_detach(name, "arrived")
			return itemstack
		end

		local gate_err = W.fire_gate(user)
		if gate_err then
			minetest.chat_send_player(name, minetest.colorize("#ff8844", gate_err))
			return itemstack
		end
		if (W.lash_ready[name] or 0) > W.now() then
			return itemstack
		end
		if not W.take_ammo(name, "cells", LASH_COST) then
			minetest.sound_play("sl_weapons_dry_click", {
				pos = user:get_pos(), gain = 0.9, max_hear_distance = 16,
			})
			minetest.chat_send_player(name, S("The lash needs @1 cells.", tostring(LASH_COST)))
			return itemstack
		end
		W.lash_ready[name] = W.now() + LASH_COOLDOWN

		local eye, dir = W.aim(user)
		local vel = vector.add(vector.multiply(dir, LASH_SPEED), W.player_velocity(user))
		local obj = minetest.add_entity(vector.add(eye, vector.multiply(dir, 0.5)),
			W.modname .. ":lash_hook")
		if not obj then return itemstack end
		obj:set_velocity(vel)
		local lua = obj.get_luaentity and obj:get_luaentity()
		if lua then
			lua.shooter = name
			lua.sl_weapon_fx = true
			lua.gen = W.match_gen
		end
		-- The launch is a crack the whole block hears (danger 1).
		minetest.sound_play("sl_weapons_lash_launch", {
			pos = eye, gain = 0.9, max_hear_distance = 32,
		})
		return itemstack
	end,
})

-- Any damage detaches the line (danger 3): mid-swing, at altitude,
-- above whatever the stain will be.
minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	local name = player and player.get_player_name and player:get_player_name()
	if name and W.lash[name] and damage and damage > 0 then
		W.lash_detach(name, "damage")
	end
end)

-- The reel: velocity toward the anchor, momentum conserved, hands
-- full the whole way (weapons refuse while attached — spec danger 2
-- is enforced in api.fire_gate callers via W.lash check below).
local lash_accum = 0
minetest.register_globalstep(function(dtime)
	lash_accum = lash_accum + dtime
	if lash_accum < 0.1 then return end
	lash_accum = 0
	for name, st in pairs(table.copy(W.lash)) do
		local player = minetest.get_player_by_name(name)
		if not player then
			W.lash_detach(name, "expired")
		elseif (W.now() - st.at) > LASH_MAXTIME then
			W.lash_detach(name, "expired")
		else
			local ppos = player:get_pos()
			local to = vector.subtract(st.anchor, ppos)
			local dist = vector.distance(ppos, st.anchor)
			if dist < 1.6 then
				W.lash_detach(name, "arrived")
				W.knockback(player, { x = 0, y = 2.5, z = 0 })
			else
				local dir = vector.normalize(to)
				local vel = W.player_velocity(player)
				local closing = vel.x * dir.x + vel.y * dir.y + vel.z * dir.z
				if closing < LASH_REEL_MAX then
					W.knockback(player, vector.multiply(dir, LASH_REEL_ACCEL))
				end
				-- The glowing line is visible to everyone (danger 1).
				for i = 1, 3 do
					minetest.add_particle({
						pos = vector.add(ppos, vector.multiply(to, i / 4)),
						velocity = { x = 0, y = 0, z = 0 },
						acceleration = { x = 0, y = 0, z = 0 },
						expirationtime = 0.2,
						size = 2,
						texture = "sl_weapons_lash_line.png",
						glow = 14,
					})
				end
			end
		end
	end
end)
