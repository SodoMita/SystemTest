-- ================================================================
-- aaa_botmatch/fake_player.lua
-- Simulated player references for headless soak testing.
--
-- Implements the ObjectRef/InvRef/MetaDataRef surface that this
-- game's mods actually call, backed by plain Lua state. Bots are
-- NOT engine players: they exist only in the Lua layer, and the
-- harness in init.lua routes minetest.get_player_by_name /
-- get_connected_players through them. Everything the mods do to a
-- bot (properties, physics, inventory, HUD, meta) is recorded and
-- inert.
--
-- Returns a constructor module: dofile(...) => { new = function(name) }
-- ================================================================

local M = {}

-- ---------------------------------------------------------------
-- Fake inventory (string-slot backed, merge semantics like engine)
-- ---------------------------------------------------------------
local InvMeta = {}
InvMeta.__index = InvMeta

local function new_inv(size)
	return setmetatable({ lists = { main = {} }, size = size or 32 }, InvMeta)
end

function InvMeta:get_size(_) return self.size end

function InvMeta:get_stack(list, i)
	return ItemStack((self.lists[list] or {})[i] or "")
end

function InvMeta:set_stack(list, i, stack)
	self.lists[list] = self.lists[list] or {}
	local str = (type(stack) == "table" and stack.to_string) and stack:to_string() or tostring(stack or "")
	self.lists[list][i] = (str ~= "") and str or nil
	return true
end

function InvMeta:set_list(list, stacks)
	self.lists[list] = {}
	for i, s in ipairs(stacks or {}) do
		local str = (type(s) == "table" and s.to_string) and s:to_string() or tostring(s or "")
		if str ~= "" then self.lists[list][i] = str end
	end
end

function InvMeta:get_list(list)
	local out = {}
	for i = 1, self.size do
		out[i] = ItemStack((self.lists[list] or {})[i] or "")
	end
	return out
end

function InvMeta:is_empty(list)
	for _, s in pairs(self.lists[list] or {}) do
		if s ~= "" then return false end
	end
	return true
end

function InvMeta:contains_item(list, item)
	local stack = ItemStack(item)
	local want = stack:get_count()
	local have = 0
	for _, s in pairs(self.lists[list] or {}) do
		local it = ItemStack(s)
		if it:get_name() == stack:get_name() then have = have + it:get_count() end
	end
	return have >= want
end

function InvMeta:add_item(list, item)
	local stack = ItemStack(item)
	local name, count = stack:get_name(), stack:get_count()
	if name == "" or count == 0 then return ItemStack("") end
	self.lists[list] = self.lists[list] or {}
	for i = 1, self.size do
		local cur = ItemStack(self.lists[list][i] or "")
		if cur:get_name() == name then
			self.lists[list][i] = name .. " " .. (cur:get_count() + count)
			return ItemStack("")
		end
	end
	for i = 1, self.size do
		if not self.lists[list][i] then
			self.lists[list][i] = name .. " " .. count
			return ItemStack("")
		end
	end
	return stack
end

function InvMeta:remove_item(list, item)
	local stack = ItemStack(item)
	local name, count = stack:get_name(), stack:get_count()
	local removed = 0
	for i = 1, self.size do
		if removed >= count then break end
		local cur = ItemStack(self.lists[list][i] or "")
		if cur:get_name() == name and cur:get_count() > 0 then
			local take = math.min(count - removed, cur:get_count())
			removed = removed + take
			local left = cur:get_count() - take
			self.lists[list][i] = (left > 0) and (name .. " " .. left) or nil
		end
	end
	return ItemStack(removed > 0 and (name .. " " .. removed) or "")
end

-- ---------------------------------------------------------------
-- Fake metadata (player meta + generic)
-- ---------------------------------------------------------------
local MetaRef = {}
MetaRef.__index = MetaRef

local function new_meta()
	return setmetatable({ _data = {} }, MetaRef)
end

function MetaRef:get_string(k) return self._data[k] or "" end
function MetaRef:set_string(k, v) self._data[k] = tostring(v) end
function MetaRef:get_int(k) return tonumber(self._data[k] or 0) end
function MetaRef:set_int(k, v) self._data[k] = tostring(v) end
function MetaRef:get_float(k) return tonumber(self._data[k] or 0) end
function MetaRef:set_float(k, v) self._data[k] = tostring(v) end
function MetaRef:to_table() return { fields = self._data } end
function MetaRef:from_table(t) self._data = (t and t.fields) or {} end
function MetaRef:contains(k) return self._data[k] ~= nil end

-- ---------------------------------------------------------------
-- Fake player reference
-- ---------------------------------------------------------------
local PlayerRef = {}
PlayerRef.__index = function(self, key)
	local v = rawget(PlayerRef, key)
	if v ~= nil then return v end
	-- Unknown ObjectRef methods: return an inert no-op that logs once,
	-- so a missing method surfaces as a harvested bug, not a crash.
	return function(_, ...)
		if not PlayerRef._warned then PlayerRef._warned = {} end
		if not PlayerRef._warned[key] then
			PlayerRef._warned[key] = true
			minetest.log("warning", "[botmatch] unimplemented ObjectRef method: " .. tostring(key))
		end
		return nil
	end
end

function M.new(name)
	local self = setmetatable({
		_name = name,
		_pos = { x = 0, y = 10, z = 0 },
		_hp = 20,
		_props = { hp_max = 20, breath_max = 10, visual_size = { x = 1, y = 1 } },
		_armor = {},
		_physics = {},
		_inv = new_inv(32),
		_meta = new_meta(),
		_huds = {},
		_hud_seq = 0,
		dead = false,
		-- harness bookkeeping (not engine surface)
		bm = { next_attack = 0, next_act = 0, offered = false, revived_at = 0, kit = false },
	}, PlayerRef)
	return self
end

function PlayerRef:is_player() return true end
function PlayerRef:get_player_name() return self._name end
function PlayerRef:get_pos() return { x = self._pos.x, y = self._pos.y, z = self._pos.z } end
function PlayerRef:set_pos(p) self._pos = { x = p.x, y = p.y, z = p.z } end
function PlayerRef:get_hp() return self._hp end
function PlayerRef:set_hp(hp)
	self._hp = hp
	if hp <= 0 and not self.dead then
		self.dead = true
		-- Death chain is driven by the harness (botmatch.kill) so it can
		-- attribute kills and schedule respawns deterministically.
		if botmatch and botmatch.on_bot_lethal then
			botmatch.on_bot_lethal(self)
		end
	end
end
function PlayerRef:get_properties() return self._props end
function PlayerRef:set_properties(props)
	for k, v in pairs(props or {}) do self._props[k] = v end
end
function PlayerRef:set_armor_groups(g) self._armor = g or {} end
function PlayerRef:get_armor_groups() return self._armor end
function PlayerRef:set_physics_override(p) self._physics = p or {} end
function PlayerRef:get_inventory() return self._inv end
function PlayerRef:get_meta() return self._meta end
function PlayerRef:set_attribute(k, v) self._meta:set_string(k, v) end
function PlayerRef:get_attribute(k) return self._meta:get_string(k) end
function PlayerRef:set_nametag_attributes(a) self._nametag = a end
function PlayerRef:get_nametag_attributes() return self._nametag or {} end
function PlayerRef:set_inventory_formspec(_) end
function PlayerRef:set_fov(_) end
function PlayerRef:set_animation() end
function PlayerRef:set_local_animation() end
function PlayerRef:get_animation() return nil end
function PlayerRef:get_velocity() return { x = 0, y = 0, z = 0 } end
function PlayerRef:get_breath() return 10 end
function PlayerRef:get_look_dir() return { x = 0, y = 0, z = 1 } end
function PlayerRef:get_look_horizontal() return 0 end
function PlayerRef:get_look_vertical() return 0 end
function PlayerRef:get_eye_position() return self:get_pos() end
function PlayerRef:get_player_control()
	return { up = false, down = false, left = false, right = false,
		jump = false, aux1 = false, sneak = false, zoom = false, dig = false, place = false }
end
function PlayerRef:get_player_control_bits() return 0 end
function PlayerRef:get_wielded_item() return ItemStack("") end
function PlayerRef:get_wield_index() return 1 end
function PlayerRef:get_wield_list() return "main" end
function PlayerRef:hud_add(def)
	self._hud_seq = self._hud_seq + 1
	self._huds[self._hud_seq] = def
	return self._hud_seq
end
function PlayerRef:hud_change(id, key, value)
	local h = self._huds[id]
	if h and key then h[key] = value end
end
function PlayerRef:hud_remove(id) self._huds[id] = nil end
function PlayerRef:hud_get(id) return self._huds[id] end
function PlayerRef:hud_get_flags()
	return {
		hotbar = true, healthbar = true, crosshair = true, wielditem = true,
		breathbar = true, minimap = true, minimap_radar = true,
		basic_debug = true, chat_all = true, chat_recent = true,
	}
end
function PlayerRef:hud_set_flags(_) end
function PlayerRef:hud_replace(_, _) end
-- Cosmetic engine calls some mods make on join; inert for bots.
function PlayerRef:set_sky(_) end
function PlayerRef:set_stars(_) end
function PlayerRef:set_sun(_) end
function PlayerRef:set_moon(_) end
function PlayerRef:set_clouds(_) end
function PlayerRef:set_formspec_prepend(_) end
function PlayerRef:override_day_night_ratio(_) end
function PlayerRef:set_tone_mapping(_) end
function PlayerRef:punch(_) end
function PlayerRef:get_bone_position(_) return nil end
function PlayerRef:get_attach() return nil end
function PlayerRef:get_children() return {} end

return M
