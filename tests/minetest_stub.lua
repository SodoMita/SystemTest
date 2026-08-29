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
	self.sizes = self.sizes or {}
	self.sizes[list] = size
end

function InvMeta:get_stack(list, i)
	return ItemStack((self.lists[list] or {})[i] or "")
end

function InvMeta:set_stack(list, i, stack)
	self.lists[list] = self.lists[list] or {}
	local str = (type(stack) == "table") and stack:to_string() or tostring(stack or "")
	self.lists[list][i] = (str ~= "") and str or nil
	return true
end

function InvMeta:set_list(list, stacks)
	self.lists[list] = {}
	for i, s in ipairs(stacks or {}) do
		local str = (type(s) == "table") and s:to_string() or tostring(s or "")
		if str ~= "" then self.lists[list][i] = str end
	end
end

function InvMeta:get_list(list)
	local out = {}
	for i = 1, self:get_size(list) do
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
	for i = 1, self:get_size(list) do
		local it = ItemStack(self.lists[list] and self.lists[list][i] or "")
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
	for i = 1, self:get_size(list) do
		local cur = ItemStack(self.lists[list][i] or "")
		if cur:get_name() == name then
			self.lists[list][i] = name .. " " .. (cur:get_count() + count)
			return ItemStack("")
		end
	end
	for i = 1, self:get_size(list) do
		if not self.lists[list][i] then
			self.lists[list][i] = name .. " " .. count
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
			self.lists[list][i] = (left > 0) and (name .. " " .. left) or nil
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
	new = function(x, y, z)
		if type(x) == "table" then return { x = x.x, y = x.y, z = x.z } end
		return { x = x or 0, y = y or 0, z = z or 0 }
	end,
	add = function(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end,
	subtract = function(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end,
	offset = function(a, x, y, z)
		return { x = a.x + x, y = a.y + y, z = a.z + z }
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

return M
