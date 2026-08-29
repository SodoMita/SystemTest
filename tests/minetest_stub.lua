-- ================================================================
-- tests/minetest_stub.lua
-- Minimal headless stub of the Luanti engine API, just large enough
-- to load mods/game/sl_modebase and drive its match logic on a
-- deterministic virtual clock. Not a full emulator: only the API
-- surface actually used by the mod is implemented.
--
-- Usage:
--   local H = dofile("tests/minetest_stub.lua")
--   H.current_modname = "sl_modebase"
--   dofile("mods/game/sl_modebase/init.lua")
-- ================================================================

local M = {}

-- ---------------------------------------------------------------
-- Virtual clock + capture buffers
-- ---------------------------------------------------------------
M.clock_us = 0
M.chat_all = {}        -- list of broadcast lines
M.chat_player = {}     -- [name] = { lines }
M.formspecs = {}       -- [name] = { { formname, form } }
M.logs = {}
M.settings = { creative_mode = false }
M.storage = {}         -- mod storage key/values
M.voxels = {}          -- ["x,y,z"] = node name
M.player_privs = {}    -- [name] = privs table
M.players = {}         -- [name] = FakePlayer
M.connected = {}       -- list of FakePlayer
M.globalsteps = {}
M.afters = {}
M.luaentities = {}
M.current_modname = "sl_modebase"
M.entity_spawns = {}  -- list of { pos = ..., name = ... }, in spawn order

local handlers = {
	joinplayer = {}, leaveplayer = {}, respawnplayer = {}, dieplayer = {},
	punchplayer = {}, chat_message = {}, punchnode = {},
	player_receive_fields = {}, mods_loaded = {},
}

local function vhash(p)
	return string.format("%d,%d,%d", math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5))
end
M.vhash = vhash

function M.now()
	return M.clock_us / 1000000
end

-- ---------------------------------------------------------------
-- ItemStack
-- ---------------------------------------------------------------
local StackMeta = {}
StackMeta.__index = StackMeta

function StackMeta:get_name() return self._name end
function StackMeta:get_count() return self._count end
function StackMeta:is_empty() return self._name == "" or self._count <= 0 end
function StackMeta:set_count(n) self._count = math.max(0, math.floor(n)) end
function StackMeta:take_item(n)
	n = math.floor(n or 1)
	if n < 1 then n = 1 end
	local taken = math.min(n, self._count)
	self._count = self._count - taken
	if self._count <= 0 then self._name, self._count = "", 0 end
	return ItemStack((self._name ~= "" and self._name or "") .. (taken > 0 and (" " .. taken) or ""))
end
function StackMeta:add_item(item)
	local other = ItemStack(item)
	if other._name == "" then return ItemStack("") end
	if self._name == "" or self._name == other._name then
		self._name = other._name
		self._count = self._count + other._count
		return ItemStack("")
	end
	return other
end
function StackMeta:get_meta()
	if not self._stackmeta then
		self._stackmeta = setmetatable({ _d = {} }, {
			__index = {
				get_string = function(s, k) return s._d[k] or "" end,
				set_string = function(s, k, v) s._d[k] = tostring(v) end,
				get_int = function(s, k) return tonumber(s._d[k]) or 0 end,
				set_int = function(s, k, v) s._d[k] = tostring(math.floor(v)) end,
			},
		})
	end
	return self._stackmeta
end
function StackMeta:to_string()
	if self:is_empty() then return "" end
	if self._count == 1 then return self._name end
	return self._name .. " " .. self._count
end

function ItemStack(x)
	local s = setmetatable({}, StackMeta)
	if type(x) == "table" and x.__is_stack then
		s.__is_stack = true
		s._name = x._name
		s._count = x._count
		if x._stackmeta then
			local d = {}
			for k, v in pairs(x._stackmeta._d) do d[k] = v end
			s._stackmeta = setmetatable({ _d = d }, getmetatable(x._stackmeta))
		end
		return s
	end
	local str = tostring(x or "")
	local name, count = str:match("^(%S+)%s+(%d+)$")
	if name then
		s._name, s._count = name, tonumber(count)
	else
		s._name, s._count = str, (str == "" and 0 or 1)
	end
	s.__is_stack = true
	return s
end

-- ---------------------------------------------------------------
-- Fake inventory
-- ---------------------------------------------------------------
local InvMeta = {}
InvMeta.__index = InvMeta

local function stack_has_meta(s)
	return s._stackmeta ~= nil and next(s._stackmeta._d) ~= nil
end

local function copy_stack(s)
	local c = ItemStack("")
	c._name, c._count = s._name, s._count
	if s._stackmeta then
		local d = {}
		for k, v in pairs(s._stackmeta._d) do d[k] = v end
		c._stackmeta = setmetatable({ _d = d }, getmetatable(s._stackmeta))
	end
	return c
end

local function new_inv(size)
	return setmetatable({ lists = { main = {} }, sizes = {}, size = size or 32 }, InvMeta)
end

function InvMeta:get_size(list)
	if list and self.sizes and self.sizes[list] then
		return self.sizes[list]
	end
	return self.size
end

function InvMeta:set_size(list, size)
	self.sizes[list] = size
end

function InvMeta:get_stack(list, i)
	local cur = (self.lists[list] or {})[i]
	if cur == nil then return ItemStack("") end
	return copy_stack(cur)
end

function InvMeta:set_stack(list, i, stack)
	self.lists[list] = self.lists[list] or {}
	local s = type(stack) == "table" and stack.__is_stack and stack or ItemStack(stack)
	self.lists[list][i] = (not s:is_empty()) and copy_stack(s) or nil
	return true
end

function InvMeta:set_list(list, stacks)
	self.lists[list] = {}
	for i, s in ipairs(stacks or {}) do
		self:set_stack(list, i, s)
	end
end

function InvMeta:get_list(list)
	local out = {}
	for i = 1, self:get_size(list) do
		out[i] = self:get_stack(list, i)
	end
	return out
end

function InvMeta:is_empty(list)
	for _, s in pairs(self.lists[list] or {}) do
		if s ~= nil then return false end
	end
	return true
end

function InvMeta:contains_item(list, item)
	local stack = ItemStack(item)
	local want = stack:get_count()
	local have = 0
	for i = 1, self:get_size(list) do
		local it = self:get_stack(list, i)
		if it:get_name() == stack:get_name() then
			have = have + it:get_count()
		end
	end
	return have >= want
end

function InvMeta:add_item(list, item)
	local stack = ItemStack(item)
	local name, count = stack:get_name(), stack:get_count()
	if name == "" or count == 0 then return ItemStack("") end
	self.lists[list] = self.lists[list] or {}
	-- Metadata makes stacks unstackable (engine rule).
	if not stack_has_meta(stack) then
		for i = 1, self:get_size(list) do
			local cur = self:get_stack(list, i)
			if cur:get_name() == name and not stack_has_meta(cur) then
				self:set_stack(list, i, ItemStack(name .. " " .. (cur:get_count() + count)))
				return ItemStack("")
			end
		end
	end
	for i = 1, self:get_size(list) do
		if not self.lists[list][i] then
			self.lists[list][i] = copy_stack(stack)
			return ItemStack("")
		end
	end
	return stack -- inventory full
end

function InvMeta:remove_item(list, item)
	local stack = ItemStack(item)
	local name, count = stack:get_name(), stack:get_count()
	local removed = 0
	for i = 1, self:get_size(list) do
		if removed >= count then break end
		local cur = ItemStack(self.lists[list][i] or "")
		if cur:get_name() == name and cur:get_count() > 0 then
			local take = math.min(count - removed, cur:get_count())
			removed = removed + take
			local left = cur:get_count() - take
			self:set_stack(list, i, ItemStack(left > 0 and (name .. " " .. left) or ""))
		end
	end
	return ItemStack(removed > 0 and (name .. " " .. removed) or "")
end

-- ---------------------------------------------------------------
-- Fake player
-- ---------------------------------------------------------------
local PlayerMeta = {}
PlayerMeta.__index = PlayerMeta

function M.new_player(name)
	local p = setmetatable({
		_name = name,
		_pos = { x = 0, y = 0, z = 0 },
		_hp = 20,
		_props = { hp_max = 20 },
		_armor = {},
		_physics = {},
		_inv = new_inv(32),
		_huds = {},
		_hud_texts = {},
		_hud_seq = 0,
		_dead = false,
	}, PlayerMeta)
	M.players[name] = p
	table.insert(M.connected, p)
	return p
end

function M.remove_player(name)
	for i, p in ipairs(M.connected) do
		if p._name == name then table.remove(M.connected, i) break end
	end
	M.players[name] = nil
end

function PlayerMeta:is_player() return true end
function PlayerMeta:get_player_name() return self._name end
function PlayerMeta:get_pos() return { x = self._pos.x, y = self._pos.y, z = self._pos.z } end
function PlayerMeta:set_pos(p) self._pos = { x = p.x, y = p.y, z = p.z } end
function PlayerMeta:get_hp() return self._hp end
function PlayerMeta:set_hp(hp)
	self._hp = hp
	if hp <= 0 and not self._dead then
		self._dead = true
		for _, fn in ipairs(handlers.dieplayer) do
			fn(self, { type = "unknown" })
		end
	end
end
function PlayerMeta:get_properties() return self._props end
function PlayerMeta:set_properties(props)
	for k, v in pairs(props or {}) do self._props[k] = v end
end
function PlayerMeta:set_armor_groups(g) self._armor = g end
function PlayerMeta:set_physics_override(p) self._physics = p end
function PlayerMeta:get_inventory() return self._inv end
function PlayerMeta:set_nametag_attributes(a) self._nametag = a end
function PlayerMeta:hud_add(def)
	self._hud_seq = self._hud_seq + 1
	self._huds[self._hud_seq] = def
	self._hud_texts[self._hud_seq] = def.text or ""
	return self._hud_seq
end
function PlayerMeta:hud_change(id, key, value)
	if key == "text" then self._hud_texts[id] = value end
end
function PlayerMeta:hud_remove(id) self._huds[id] = nil end
function PlayerMeta:get_look_dir() return { x = 0, y = 0, z = 1 } end

function M.respawn(p)
	p._dead = false
	p._hp = 20
	for _, fn in ipairs(handlers.respawnplayer) do
		fn(p)
	end
end

-- ---------------------------------------------------------------
-- Time control
-- ---------------------------------------------------------------
function M.step(dtime)
	M.clock_us = M.clock_us + math.floor(dtime * 1000000)
	-- Fire due after() callbacks (repeat: callbacks can schedule more).
	local fired = true
	while fired do
		fired = false
		for i, entry in ipairs(M.afters) do
			if entry.due <= M.clock_us then
				table.remove(M.afters, i)
				entry.fn()
				fired = true
				break
			end
		end
	end
	for _, fn in ipairs(M.globalsteps) do
		fn(dtime)
	end
end

function M.advance(seconds, dtime)
	dtime = dtime or 0.5
	local steps = math.ceil(seconds / dtime)
	for _ = 1, steps do M.step(dtime) end
end

-- ---------------------------------------------------------------
-- minetest table
-- ---------------------------------------------------------------
minetest = {}

minetest.registered_nodes = {}
minetest.registered_craftitems = {}
minetest.registered_tools = {}
minetest.registered_chatcommands = {}
minetest.registered_entities = {}
minetest.registered_items = {}
minetest.luaentities = M.luaentities

function minetest.get_current_modname() return M.current_modname end
function minetest.get_modpath(_) return "mods/game/sl_modebase" end
function minetest.get_translator(_)
	return function(str, ...)
		local args = { ... }
		return (tostring(str):gsub("@(%d)", function(n)
			return tostring(args[tonumber(n)] or "")
		end))
	end
end
function minetest.log(level, msg)
	table.insert(M.logs, level .. ": " .. tostring(msg))
end

-- Storage
function minetest.get_mod_storage()
	return {
		get_string = function(_, key) return M.storage[key] or "" end,
		set_string = function(_, key, value) M.storage[key] = value end,
	}
end

-- Registration
local function register_thing(table_, name, def)
	def.name = name
	table_[name] = def
	minetest.registered_items[name] = def
	return def
end
function minetest.register_node(name, def) return register_thing(minetest.registered_nodes, name, def) end
function minetest.register_craftitem(name, def) return register_thing(minetest.registered_craftitems, name, def) end
function minetest.register_tool(name, def) return register_thing(minetest.registered_tools, name, def) end
function minetest.register_entity(name, def) minetest.registered_entities[name] = def end
function minetest.register_abm(_) end
function minetest.register_lbm(_) end
function minetest.register_on_generated(_) end
function minetest.register_privilege(_, _) end
function minetest.register_craft(_) end
function minetest.register_globalstep(fn) table.insert(M.globalsteps, fn) end

function minetest.register_chatcommand(name, def)
	def.params = def.params or ""
	def.description = def.description or ""
	def.privs = def.privs or {}
	minetest.registered_chatcommands[name] = def
end

function minetest.register_on_joinplayer(fn) table.insert(handlers.joinplayer, fn) end
function minetest.register_on_leaveplayer(fn) table.insert(handlers.leaveplayer, fn) end
function minetest.register_on_respawnplayer(fn) table.insert(handlers.respawnplayer, fn) end
function minetest.register_on_dieplayer(fn) table.insert(handlers.dieplayer, fn) end
function minetest.register_on_punchplayer(fn) table.insert(handlers.punchplayer, fn) end
function minetest.register_on_chat_message(fn) table.insert(handlers.chat_message, fn) end
function minetest.register_on_punchnode(fn) table.insert(handlers.punchnode, fn) end
function minetest.register_on_player_receive_fields(fn) table.insert(handlers.player_receive_fields, fn) end
function minetest.register_on_mods_loaded(fn) table.insert(handlers.mods_loaded, fn) end

-- Handler firing (harness-side)
function M.fire_chat_message(name, message)
	for _, fn in ipairs(handlers.chat_message) do
		if fn(name, message) ~= nil then return true end
	end
	return false
end

function M.fire_punchnode(pos, node, puncher, pointed_thing)
	for _, fn in ipairs(handlers.punchnode) do
		fn(pos, node, puncher, pointed_thing)
	end
end

-- Engine semantics: any handler returning non-nil cancels the damage.
function M.fire_punchplayer(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	local canceled = false
	for _, fn in ipairs(handlers.punchplayer) do
		if fn(player, hitter, time_from_last_punch, tool_capabilities, dir, damage) ~= nil then
			canceled = true
		end
	end
	return canceled
end

function M.fire_receive_fields(name, formname, fields)
	local player = M.players[name]
	for _, fn in ipairs(handlers.player_receive_fields) do
		fn(player, formname, fields)
	end
end

function M.fire_joinplayer(p)
	for _, fn in ipairs(handlers.joinplayer) do fn(p) end
end

function M.run_mods_loaded()
	for _, fn in ipairs(handlers.mods_loaded) do fn() end
end

-- Players
function minetest.get_connected_players() return M.connected end
function minetest.get_player_by_name(name) return M.players[name] end
function minetest.get_player_privs(name)
	M.player_privs[name] = M.player_privs[name] or {}
	return M.player_privs[name]
end
function minetest.set_player_privs(name, privs) M.player_privs[name] = privs end
function minetest.check_player_privs(name, _)
	local privs = minetest.get_player_privs(name)
	return privs.server == true
end

-- Chat
function minetest.chat_send_all(msg) table.insert(M.chat_all, msg) end
function minetest.chat_send_player(name, msg)
	M.chat_player[name] = M.chat_player[name] or {}
	table.insert(M.chat_player[name], msg)
end
function minetest.colorize(_, text) return text end
function minetest.formspec_escape(s) return tostring(s or "") end
function minetest.show_formspec(name, formname, form)
	M.formspecs[name] = M.formspecs[name] or {}
	table.insert(M.formspecs[name], { formname = formname, form = form })
end
function minetest.explode_textlist_event(_) return { type = "nothing" } end

-- Settings
minetest.settings = {
	get_bool = function(_, key) return M.settings[key] == true end,
	get = function(_, key) return M.settings[key] end,
}

-- Time
function minetest.get_us_time() return M.clock_us end
function minetest.after(seconds, fn)
	table.insert(M.afters, { due = M.clock_us + math.floor(seconds * 1000000), fn = fn })
end

-- Serialize/deserialize (Lua-source based; enough for spawn tables)
function minetest.serialize(value)
	local function ser(v)
		local t = type(v)
		if t == "number" or t == "boolean" then return tostring(v)
		elseif t == "string" then return string.format("%q", v)
		elseif t == "table" then
			local parts = {}
			for k, val in pairs(v) do
				local key
				if type(k) == "number" then key = "[" .. k .. "]"
				else key = "[" .. string.format("%q", tostring(k)) .. "]" end
				table.insert(parts, key .. "=" .. ser(val))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		error("cannot serialize type " .. t)
	end
	return ser(value)
end
function minetest.deserialize(str)
	if not str or str == "" then return nil end
	local fn, err = loadstring("return " .. str)
	if not fn then
		minetest.log("error", "deserialize failed: " .. tostring(err))
		return nil
	end
	return fn()
end

-- World
function minetest.pos_to_string(p)
	return string.format("(%d,%d,%d)", math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5))
end
function minetest.get_node(pos)
	return { name = M.voxels[vhash(pos)] or "air", param1 = 0, param2 = 0 }
end
function minetest.get_node_or_nil(pos)
	return { name = M.voxels[vhash(pos)] or "air", param1 = 0, param2 = 0 }
end
function minetest.set_node(pos, node) M.voxels[vhash(pos)] = node.name end
function minetest.remove_node(pos) M.voxels[vhash(pos)] = nil end
function minetest.load_area(_) return true end

-- Node meta (per-position, created on demand)
local MetaMeta = {}
MetaMeta.__index = MetaMeta
function MetaMeta:get_string(key) return self._data[key] or "" end
function MetaMeta:set_string(key, value) self._data[key] = value end
function MetaMeta:get_int(key) return tonumber(self._data[key] or 0) end
function MetaMeta:set_int(key, value) self._data[key] = tostring(value) end
function MetaMeta:get_inventory()
	self._inv = self._inv or new_inv(32)
	return self._inv
end

local metas = {}
function minetest.get_meta(pos)
	local h = vhash(pos)
	if not metas[h] then
		metas[h] = setmetatable({ _data = {} }, MetaMeta)
	end
	return metas[h]
end

-- Entities / items in world
function minetest.add_item(_, stack)
	local obj = { set_velocity = function() end, remove = function() end }
	return obj
end
function minetest.add_entity(pos, name)
	local obj = {
		_pos = pos,
		_props = {},
		set_properties = function(self, props)
			for k, v in pairs(props or {}) do self._props[k] = v end
		end,
		get_properties = function(self) return self._props end,
		get_pos = function(self) return self._pos end,
		set_velocity = function() end,
		remove = function() end,
		get_luaentity = function() return { name = name } end,
	}
	table.insert(M.entity_spawns, { pos = pos, name = name })
	return obj
end
function minetest.add_particle(_) end
function minetest.sound_play(_, _) end

-- Protection base (the mod wraps this global at load time)
minetest.is_protected = function(_, _) return false end

-- ---------------------------------------------------------------
-- vector + table extensions the engine provides
-- ---------------------------------------------------------------
vector = {
	add = function(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end,
	subtract = function(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end,
	direction = function(a, b)
		local d = { x = b.x - a.x, y = b.y - a.y, z = b.z - a.z }
		local l = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
		if l < 1e-9 then return { x = 0, y = 0, z = 0 } end
		return { x = d.x / l, y = d.y / l, z = d.z / l }
	end,
	round = function(v)
		return {
			x = math.floor(v.x + 0.5),
			y = math.floor(v.y + 0.5),
			z = math.floor(v.z + 0.5),
		}
	end,
	equals = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end,
	distance = function(a, b)
		return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
	end,
	normalize = function(v)
		local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
		if len == 0 then return { x = 0, y = 0, z = 0 } end
		return { x = v.x / len, y = v.y / len, z = v.z / len }
	end,
	dir_to_rotation = function(_) return { x = 0, y = 0, z = 0 } end,
}

table.copy = function(t, seen)
	seen = seen or {}
	if type(t) ~= "table" then return t end
	if seen[t] then return seen[t] end
	local out = {}
	seen[t] = out
	for k, v in pairs(t) do out[k] = table.copy(v, seen) end
	return out
end

table.indexof = function(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
	return -1
end

-- ---------------------------------------------------------------
-- player_api stub (only what sl_modebase calls)
-- ---------------------------------------------------------------
player_api = {
	register_model = function() end,
	register_animation = function() end,
	set_animation = function() end,
	get_animation = function() return nil end,
	set_model = function(player, _)
		player:set_properties({
			collisionbox = { -0.3, 0.0, -0.3, 0.3, 1.75, 0.3 },
			eye_height = 1.625,
		})
	end,
}

-- ================================================================
-- sl_weapons extensions (additive, 2026-08: WEAPONS_SPEC §12/§14)
-- - modpath routing so multiple mods can load
-- - sound / particle capture buffers
-- - vector.cross / multiply / dot
-- - PlayerMeta: look dir override, meta, wielded item, velocity,
--   punch() with the on_punchplayer cancel pipeline
-- - entities with real luaentity instances driven from M.step
-- - minetest.raycast over M.voxels + objects (sorted along ray)
-- - minetest.get_objects_inside_radius / get_gametime / get_item_group
-- ================================================================

M.modpaths = {}
M.sounds = {}     -- { name = ..., params = ... }
M.particles = {}  -- particle defs / spawner defs
M.entity_seq = 0

local raw_get_modpath = minetest.get_modpath
minetest.get_modpath = function(name)
	return M.modpaths[name] or raw_get_modpath(name)
end

minetest.sound_play = function(name, params)
	table.insert(M.sounds, { name = name, params = params or {} })
	return #M.sounds
end
minetest.add_particle = function(def)
	table.insert(M.particles, def or {})
end
minetest.add_particlespawner = function(def)
	table.insert(M.particles, def or {})
	return #M.particles
end

minetest.get_gametime = function() return M.clock_us / 1000000 end

minetest.get_item_group = function(name, group)
	local def = minetest.registered_items[name]
	return (def and def.groups and def.groups[group]) or 0
end

vector.cross = function(a, b)
	return {
		x = a.y * b.z - a.z * b.y,
		y = a.z * b.x - a.x * b.z,
		z = a.x * b.y - a.y * b.x,
	}
end
vector.multiply = function(a, s)
	return { x = a.x * s, y = a.y * s, z = a.z * s }
end
vector.dot = function(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

-- ---------------------------------------------------------------
-- PlayerMeta additions
-- ---------------------------------------------------------------
function PlayerMeta:get_look_dir()
	local d = self._look_dir
	if d then return { x = d.x, y = d.y, z = d.z } end
	return { x = 0, y = 0, z = 1 }
end
function PlayerMeta:set_look_dir(d) self._look_dir = { x = d.x, y = d.y, z = d.z } end

function PlayerMeta:get_player_velocity()
	local v = self._velocity
	return { x = v and v.x or 0, y = v and v.y or 0, z = v and v.z or 0 }
end
function PlayerMeta:set_player_velocity(v) self._velocity = { x = v.x, y = v.y, z = v.z } end
function PlayerMeta:add_player_velocity(v)
	local cur = self._velocity or { x = 0, y = 0, z = 0 }
	self._velocity = { x = cur.x + v.x, y = cur.y + v.y, z = cur.z + v.z }
end
PlayerMeta.add_to_velocity = PlayerMeta.add_player_velocity
function PlayerMeta:set_velocity(v) self._velocity = { x = v.x, y = v.y, z = v.z } end
function PlayerMeta:get_armor_groups() return self._armor or {} end
function PlayerMeta:get_wielded_item() return ItemStack(self._wielded or "") end
function PlayerMeta:set_wielded_item(s) self._wielded = (type(s) == "table") and s:to_string() or tostring(s or "") end

local function player_get_meta(p)
	if not p._meta_data then
		p._meta_data = setmetatable({ _d = {} }, {
			__index = {
				get_string = function(self, k) return self._d[k] or "" end,
				set_string = function(self, k, v) self._d[k] = tostring(v) end,
				get_int = function(self, k) return tonumber(self._d[k]) or 0 end,
				set_int = function(self, k, v) self._d[k] = tostring(math.floor(v)) end,
			},
		})
	end
	return p._meta_data
end
PlayerMeta.get_meta = function(self) return player_get_meta(self) end

local function sum_punch_damage(tool_capabilities, armor_groups, time_from_last_punch)
	local caps = tool_capabilities or {}
	local armor = armor_groups or {}
	if (armor.immortal or 0) > 0 then return 0 end
	-- Engine semantics (lua_api / modding book): armor group values are
	-- the percentage of damage TAKEN (vulnerability). A damage group not
	-- present in armor_groups deals nothing. fleshy=100 = fully damageable.
	local total = 0
	for group, amt in pairs(caps.damage_groups or {}) do
		local vuln = armor[group] or 0
		total = total + amt * vuln / 100
	end
	local fpi = caps.full_punch_interval
	if fpi and fpi > 0 then
		local t = math.min(time_from_last_punch or fpi, fpi)
		total = total * math.max(0, math.min(1, t / fpi))
	end
	return total
end

function PlayerMeta:punch(puncher, time_from_last_punch, tool_capabilities, dir)
	local damage = sum_punch_damage(tool_capabilities, self._armor or {},
		time_from_last_punch)
	local canceled = M.fire_punchplayer(self, puncher, time_from_last_punch,
		tool_capabilities, dir, damage)
	if canceled then return end
	if damage > 0 then
		self:set_hp(self._hp - damage)
	end
end

-- ---------------------------------------------------------------
-- Entities: real luaentity instances, driven from M.step
-- ---------------------------------------------------------------
local function obj_get_luaentity(self) return self._lua end

local function make_entity_object(pos, name)
	local def = minetest.registered_entities[name] or {}
	M.entity_seq = M.entity_seq + 1
	local obj = {
		_id = M.entity_seq,
		_pos = { x = pos.x, y = pos.y, z = pos.z },
		_velocity = { x = 0, y = 0, z = 0 },
		_armor = { fleshy = 100 }, -- engine default for Lua entities
		_props = { hp_max = def.hp_max or 10 },
		_hp = def.hp_max or 10,
		_removed = false,
	}
	local lua = {}
	for k, v in pairs(def) do lua[k] = v end
	lua.name = name
	lua.object = obj

	function obj:is_player() return false end
	function obj:get_pos() return { x = self._pos.x, y = self._pos.y, z = self._pos.z } end
	function obj:set_pos(p) self._pos = { x = p.x, y = p.y, z = p.z } end
	function obj:move_to(p, continuous) self:set_pos(p) end
	function obj:get_velocity() return { x = self._velocity.x, y = self._velocity.y, z = self._velocity.z } end
	function obj:set_velocity(v) self._velocity = { x = v.x, y = v.y, z = v.z } end
	function obj:set_acceleration(_) end
	function obj:get_acceleration() return { x = 0, y = 0, z = 0 } end
	function obj:get_properties() return self._props end
	function obj:set_properties(props) for k, v in pairs(props or {}) do self._props[k] = v end end
	function obj:set_armor_groups(g) self._armor = g or {} end
	function obj:get_armor_groups() return self._armor end
	function obj:get_hp() return self._hp end
	function obj:set_hp(hp)
		self._hp = hp
		if hp <= 0 and not self._dead then
			self._dead = true
			local l = self._lua
			if l and l.on_death then pcall(l.on_death, l, "punch") end
			self:remove()
		end
	end
	function obj:punch(puncher, time_from_last_punch, tool_capabilities, dir)
		local l = self._lua
		if l and l.on_punch then
			local ok, res = pcall(l.on_punch, l, puncher, time_from_last_punch, tool_capabilities, dir)
			if ok and res == true then return end -- fully handled
		end
		local damage = sum_punch_damage(tool_capabilities, self._armor)
		if damage > 0 then
			self:set_hp(self._hp - damage)
		end
	end
	function obj:rightclick(clicker)
		local l = self._lua
		if l and l.on_rightclick then
			pcall(l.on_rightclick, l, clicker)
		end
	end
	function obj:get_luaentity() return self._lua end
	function obj:remove()
		if self._removed then return end
		self._removed = true
		if M.luaentities[self._id] then
			M.luaentities[self._id] = nil
		end
	end
	obj._lua = lua
	M.luaentities[obj._id] = lua
	return obj
end

local raw_add_entity = minetest.add_entity
minetest.add_entity = function(pos, name, staticdata)
	local obj = make_entity_object(pos or { x = 0, y = 0, z = 0 }, name)
	table.insert(M.entity_spawns, { pos = pos, name = name })
	local lua = obj._lua
	if lua and lua.on_activate then
		pcall(lua.on_activate, lua, staticdata or "", 0)
	end
	return obj
end

-- Drive entity on_step after globalsteps (projectiles move & hit).
local raw_step = M.step
M.step = function(dtime)
	M.clock_us = M.clock_us + math.floor(dtime * 1000000)
	local fired = true
	while fired do
		fired = false
		for i, entry in ipairs(M.afters) do
			if entry.due <= M.clock_us then
				table.remove(M.afters, i)
				entry.fn()
				fired = true
				break
			end
		end
	end
	for _, fn in ipairs(M.globalsteps) do
		local ok, err = pcall(fn, dtime)
		if not ok then minetest.log("error", "globalstep: " .. tostring(err)) end
	end
	-- Iterate a snapshot: on_step may remove/spawn entities mid-loop
	-- (mortar explodes, corpse collapses) — the real engine tolerates
	-- that, so the stub must too.
	local step_order = {}
	for h in pairs(M.luaentities) do step_order[#step_order + 1] = h end
	for i = 1, #step_order do
		local lua = M.luaentities[step_order[i]]
		local obj = lua and lua.object
		if obj and not obj._removed and lua.on_step then
			local ok, err = pcall(lua.on_step, lua, dtime, { type = "node", collides = false })
			if not ok then minetest.log("error", "on_step(" .. tostring(lua.name) .. "): " .. tostring(err)) end
		end
	end
end

function minetest.get_objects_inside_radius(center, radius)
	local out = {}
	for _, p in ipairs(M.connected) do
		if vector.distance(p:get_pos(), center) <= radius then
			table.insert(out, p)
		end
	end
	for _, lua in pairs(M.luaentities) do
		local obj = lua.object
		if obj and not obj._removed then
			if vector.distance(obj:get_pos(), center) <= radius then
				table.insert(out, obj)
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------
-- Raycast: DDA-ish sampling over voxels + object capsule tests,
-- hits sorted by distance along the ray.
-- ---------------------------------------------------------------
local function node_solid(name)
	if not name or name == "air" then return false end
	local def = minetest.registered_nodes[name]
	if def and def.pointable == false then return false end
	return true
end

local function object_ray_radius(obj)
	if obj.is_player and obj:is_player() then return 0.45 end
	local lua = obj.get_luaentity and obj:get_luaentity()
	local def = lua and minetest.registered_entities[lua.name]
	return (def and def._stub_ray_radius) or 0.5
end

minetest.raycast = function(pos1, pos2, objects, liquids)
	local hits = {}
	local dir = vector.subtract(pos2, pos1)
	local len = vector.length and vector.length(dir) or math.sqrt(dir.x ^ 2 + dir.y ^ 2 + dir.z ^ 2)
	if len <= 0 then
		local function none() end
		return none
	end
	local ndir = vector.normalize(dir)

	if objects ~= false then
		local candidates = {}
		for _, p in ipairs(M.connected) do table.insert(candidates, p) end
		for _, lua in pairs(M.luaentities) do
			local obj = lua.object
			if obj and not obj._removed then table.insert(candidates, obj) end
		end
		for _, obj in ipairs(candidates) do
			local c = obj:get_pos()
			local hit_t = nil
			if obj.is_player and obj:is_player() then
				-- Players are tall capsules: sample the body.
				for h = 0.15, 1.7, 0.5 do
					local sc = { x = c.x, y = c.y + h, z = c.z }
					local rel = vector.subtract(sc, pos1)
					local t = vector.dot(rel, ndir)
					if t >= -0.1 and t <= len + 0.1 then
						local tc = math.max(0, math.min(len, t))
						local closest = vector.add(pos1, vector.multiply(ndir, tc))
						if vector.distance(closest, sc) <= 0.45 then
							hit_t = math.max(0, t)
							break
						end
					end
				end
			else
				local rel = vector.subtract(c, pos1)
				local t = vector.dot(rel, ndir)
				if t >= -0.5 and t <= len + 0.5 then
					local tc = math.max(0, math.min(len, t))
					local closest = vector.add(pos1, vector.multiply(ndir, tc))
					if vector.distance(closest, c) <= object_ray_radius(obj) + 0.3 then
						hit_t = math.max(0, t)
					end
				end
			end
			if hit_t then
				table.insert(hits, {
					type = "object",
					ref = obj,
					pos = vector.add(pos1, vector.multiply(ndir, hit_t)),
					t = hit_t,
				})
			end
		end
	end

	local seen_cells = {}
	local steps = math.max(1, math.ceil(len / 0.2))
	for i = 0, steps do
		local p = vector.add(pos1, vector.multiply(ndir, (i / steps) * len))
		local cell = vhash(p)
		if not seen_cells[cell] then
			local name = M.voxels[cell]
			if node_solid(name) then
				seen_cells[cell] = true
				local np = vector.round(p)
				table.insert(hits, {
					type = "node",
					pos = np,
					under = np,
					above = vector.round(vector.subtract(p, vector.multiply(ndir, 0.51))),
					node = { name = name },
					t = (i / steps) * len,
				})
			end
		end
	end

	table.sort(hits, function(a, b) return a.t < b.t end)
	local i = 0
	return function()
		i = i + 1
		return hits[i]
	end
end

return M
