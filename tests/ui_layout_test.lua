-- ================================================================
-- tests/ui_layout_test.lua
-- Headless layout checks for the System Looting formspecs.
--
-- Every formspec in this game is built by string concatenation, so geometry
-- mistakes (an element drawn past the frame, two widgets painted on top of
-- each other, a `model[]` element using a stale parameter layout) never fail
-- at load time — they only show up as a broken window in game.
--
-- This harness generates the real formspecs under the engine stub, parses them
-- the way the engine does, and asserts the layout invariants:
--   * nothing is drawn outside the `size[]` frame (so nothing is clipped)
--   * the character preview is not covered by the tab strip
--   * the preview's click target is transparent (so it cannot hide the mesh)
--   * `model[]` elements use the parameter layout documented for the engine
--     this game ships against (see doc/lua_api.md)
--
-- Run from the repo root:  luajit tests/ui_layout_test.lua
-- ================================================================

local H = dofile("tests/minetest_stub.lua")

local pass_count, fail_count = 0, 0
-- Returns the verdict so a caller can skip the checks that depend on it.
local function check(cond, label)
	local ok = cond and true or false
	if ok then
		pass_count = pass_count + 1
		print("  [PASS] " .. label)
	else
		fail_count = fail_count + 1
		print("  [FAIL] " .. label)
	end
	return ok
end

local function section(title)
	print("== " .. title)
end

-- ---------------------------------------------------------------
-- Stub extensions: the shared stub covers the match loop, not the GUI.
-- ---------------------------------------------------------------
local modpaths = {
	sl_modebase = "mods/game/sl_modebase",
	sl_gui = "mods/apis/sl_gui",
	player_api = "mods/player_api",
	sl_characters = "mods/content/sl_characters",
}
function minetest.get_modpath(name)
	return modpaths[name] or "mods/game/sl_modebase"
end
function minetest.close_formspec() end
-- The achievement popup throws confetti through the particle spawner API.
function minetest.add_particlespawner() return 1 end
function minetest.delete_particlespawner() end

-- sl_gui hooks into engine callbacks the stub does not implement; stub them so
-- the formspec builders (the thing under test) can be reached.
setmetatable(minetest, { __index = function(t, k)
	if type(k) == "string" and k:match("^register_") then
		local noop = function() return true end
		rawset(t, k, noop)
		return noop
	end
	return nil
end })

local probe = H.new_player("__probe")
local PlayerMeta = getmetatable(probe)
H.remove_player("__probe")

local ObjMeta = { __index = {
	get_string = function(s, k) return s._d[k] or "" end,
	set_string = function(s, k, v) s._d[k] = v end,
	get_int = function(s, k) return tonumber(s._d[k]) or 0 end,
	set_int = function(s, k, v) s._d[k] = tostring(v) end,
	get_float = function(s, k) return tonumber(s._d[k]) or 0 end,
	set_float = function(s, k, v) s._d[k] = tostring(v) end,
	to_table = function(s) return { fields = s._d } end,
} }
function PlayerMeta:get_meta()
	if not self._meta then self._meta = setmetatable({ _d = {} }, ObjMeta) end
	return self._meta
end
function PlayerMeta:set_inventory_formspec(fs) self._inv_fs = fs end
function PlayerMeta:get_inventory_formspec() return self._inv_fs or "" end
function PlayerMeta:get_breath() return 10 end

local pm_index = PlayerMeta.__index
PlayerMeta.__index = function(t, k)
	local v
	if type(pm_index) == "table" then
		v = pm_index[k]
	elseif type(pm_index) == "function" then
		v = pm_index(t, k)
	end
	if v ~= nil then return v end
	if type(k) == "string" and (k:match("^set_") or k:match("^get_") or k:match("^wield")) then
		local noop = function() return nil end
		rawset(t, k, noop)
		return noop
	end
	return nil
end

-- player_api's globalstep reads the control state to work out which animation
-- the player is in, and that is what the preview's frame loop has to follow.
-- The auto-noop above returns nil for get_*, which the globalstep then indexes.
function PlayerMeta:get_player_control()
	return self._controls or {
		sneak = false, zoom = false, up = false, down = false,
		left = false, right = false, LMB = false, RMB = false,
	}
end
function PlayerMeta:get_player_control_state() return self:get_player_control() end

-- character_outfit walks the inventory and asks each stack what it is.
local StackMeta = getmetatable(ItemStack(""))
function StackMeta:get_definition()
	return minetest.registered_items[self._name] or { name = self._name }
end

-- ---------------------------------------------------------------
-- Formspec parser
-- ---------------------------------------------------------------

-- Elements whose first two fields are `x,y` and `w,h` in real coordinates.
local SIZED = {
	animated_image = true, background = true, background9 = true, box = true,
	button = true, button_exit = true, button_url = true, button_url_exit = true,
	button_key = true, checkbox = true, dropdown = true, field = true,
	hypertext = true, image = true, image_button = true, image_button_exit = true,
	item_image = true, item_image_button = true, list = true, model = true,
	pwdfield = true, scrollbar = true, scroll_container = true, table = true,
	tabheader = true, textarea = true, textlist = true, vertscrollbar = true,
}

-- Which field holds the element's field name, per element type. Everything
-- else is position 1 = "x,y", 2 = "w,h"; `list[]` is the one element that
-- starts with the inventory location instead.
local NAME_FIELD = {
	image_button = 4, image_button_exit = 4, item_image_button = 4,
	scrollbar = 4, vertscrollbar = 4,
}
local POS_FIELD = { list = 3 }

local function split_fields(body)
	local parts, cur, depth = {}, "", 0
	for k = 1, #body do
		local c = body:sub(k, k)
		if c == "[" then depth = depth + 1
		elseif c == "]" then depth = depth - 1 end
		if c == ";" and depth == 0 then
			parts[#parts + 1] = cur
			cur = ""
		else
			cur = cur .. c
		end
	end
	parts[#parts + 1] = cur
	return parts
end

-- Split a formspec string into { name, parts } records. Brackets inside a
-- field (textlist items, textarea bodies) are tracked so they do not end the
-- element early.
local function parse_formspec(fs)
	local out = {}
	local i, n = 1, #fs
	while i <= n do
		local ws_end = select(2, fs:find("^%s*", i))
		i = ws_end + 1
		if i > n then break end

		local ns, ne = fs:find("^[%a_][%w_]*", i)
		if not ns then
			i = i + 1
		else
			local name = fs:sub(ns, ne)
			i = ne + 1
			if fs:sub(i, i) == "[" then
				local depth, j = 0, i
				while j <= n do
					local c = fs:sub(j, j)
					if c == "[" then
						depth = depth + 1
					elseif c == "]" then
						depth = depth - 1
						if depth == 0 then break end
					end
					j = j + 1
				end
				out[#out + 1] = { name = name, parts = split_fields(fs:sub(i + 1, j - 1)) }
				i = j + 1
			else
				out[#out + 1] = { name = name, parts = {} }
			end
		end
	end
	return out
end

local function xy(s)
	local a, b = tostring(s):match("^%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)")
	return tonumber(a), tonumber(b)
end

-- `list[]` is the one element whose W,H are slot counts rather than units.
-- parseList sizes the rect as (slots-1) * slot_spacing + slot_size, and in real
-- coordinates slot_size is 1 unit with slot_spacing 1.25 units, so an 8-wide
-- list is 9.75 units across, not 8.
local SLOT_GEOM = { list = true }
local SLOT_SPACING, SLOT_SIZE = 1.25, 1.0

local function geom_to_units(el_name, w, h)
	if SLOT_GEOM[el_name] then
		return (w - 1) * SLOT_SPACING + SLOT_SIZE, (h - 1) * SLOT_SPACING + SLOT_SIZE
	end
	return w, h
end

-- Resolve every element to an absolute rect, applying container/scroll offsets
-- the same way the engine does.
local function layout(fs)
	local size_w, size_h = nil, nil
	local order = {}
	local offsets = { { x = 0, y = 0, scrolling = false } }

	local function cur() return offsets[#offsets] end

	for _, el in ipairs(parse_formspec(fs)) do
		local p = el.parts
		-- `size[]` is one of the few elements that separates with commas.
		local pos_i = POS_FIELD[el.name] or 1
		local name_i = NAME_FIELD[el.name] or 3

		if el.name == "size" then
			size_w, size_h = xy(p[1])
		elseif el.name == "container" then
			local x, y = xy(p[1])
			local o = cur()
			offsets[#offsets + 1] = { x = o.x + (x or 0), y = o.y + (y or 0), scrolling = o.scrolling }
		elseif el.name == "container_end" then
			if #offsets > 1 then offsets[#offsets] = nil end
		elseif el.name == "scroll_container" then
			local x, y = xy(p[1])
			local w, h = xy(p[2])
			local o = cur()
			local ax, ay = o.x + (x or 0), o.y + (y or 0)
			order[#order + 1] = {
				name = el.name, parts = p, field = p[3],
				x = ax, y = ay, w = w or 0, h = h or 0,
				scrolling = false, depth = #offsets,
			}
			offsets[#offsets + 1] = { x = ax, y = ay, scrolling = true }
		elseif el.name == "scroll_container_end" then
			if #offsets > 1 then offsets[#offsets] = nil end
		elseif SIZED[el.name] then
			local x, y = xy(p[pos_i])
			local w, h = xy(p[pos_i + 1])
			local o = cur()
			if x and y and w and h then
				local uw, uh = geom_to_units(el.name, w, h)
				order[#order + 1] = {
					name = el.name, parts = p, field = p[name_i],
					x = o.x + x, y = o.y + y, w = uw, h = uh,
					scrolling = o.scrolling, depth = #offsets,
				}
			end
		end
	end

	return order, size_w, size_h
end

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w
		and a.y < b.y + b.h and b.y < a.y + a.h
end

local function overlap_area(a, b)
	local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if w <= 0 or h <= 0 then return 0 end
	return w * h
end

-- ---------------------------------------------------------------
-- The shared assertions
-- ---------------------------------------------------------------

-- Widgets that take input should not sit on top of each other: the engine
-- paints the later element over the earlier one, so the earlier one loses
-- visible area *and* part of its click target.
local INTERACTIVE = {
	button = true, button_exit = true, button_url = true, button_url_exit = true,
	button_key = true, image_button = true, image_button_exit = true,
	item_image_button = true, field = true, pwdfield = true, textarea = true,
	textlist = true, table = true, dropdown = true, checkbox = true,
	scrollbar = true, vertscrollbar = true, list = true, tabheader = true,
	model = true, scroll_container = true,
}

-- Overlaps that are deliberate. The 3D character preview needs an invisible
-- image_button on top of it to be clickable at all.
local ALLOWED_OVERLAP = {
	["model|image_button"] = true,
}

local function check_no_overlap(label, fs)
	local rects = layout(fs)
	local worst
	for i = 1, #rects do
		local a = rects[i]
		-- Elements inside a scroll_container are clipped to its viewport, so
		-- only compare widgets that share a coordinate space.
		if INTERACTIVE[a.name] then
			for j = i + 1, #rects do
				local b = rects[j]
				if INTERACTIVE[b.name] and a.depth == b.depth and overlaps(a, b) then
					local key = a.name .. "|" .. b.name
					if not ALLOWED_OVERLAP[key] and not ALLOWED_OVERLAP[b.name .. "|" .. a.name] then
						local ar = overlap_area(a, b)
						local small = math.min(a.w * a.h, b.w * b.h)
						if small > 0 and ar / small > 0.02 then
							local desc = string.format(
								"%s: %s[%s] (%.2f,%.2f %.2fx%.2f) overlaps %s[%s] (%.2f,%.2f %.2fx%.2f) by %.0f%% of the smaller",
								label, a.name, tostring(a.field), a.x, a.y, a.w, a.h,
								b.name, tostring(b.field), b.x, b.y, b.w, b.h, 100 * ar / small)
							if not worst or ar / small > worst.ratio then
								worst = { ratio = ar / small, desc = desc }
							end
						end
					end
				end
			end
		end
	end
	if worst then print("        " .. worst.desc) end
	check(worst == nil, label .. ": no interactive widget overlaps another")
end

-- container/container_end must balance: an unclosed container silently offsets
-- everything after it, and an extra container_end shifts the rest of the
-- window the other way.
local function check_containers(label, fs)
	local depth, worst = 0, 0
	for _, el in ipairs(parse_formspec(fs)) do
		if el.name == "container" then
			depth = depth + 1
			if depth > worst then worst = depth end
		elseif el.name == "container_end" then
			depth = depth - 1
		end
	end
	check(depth == 0, label .. ": container/container_end are balanced")
end

local function check_frame(label, fs)
	check_containers(label, fs)
	check_no_overlap(label, fs)
	local rects, w, h = layout(fs)
	if not w or not h then
		check(false, label .. ": has a size[] element")
		return
	end
	local worst
	for _, r in ipairs(rects) do
		if not r.scrolling then
			local over_r = (r.x + r.w) - w
			local over_b = (r.y + r.h) - h
			local under_l = -r.x
			local under_t = -r.y
			local worst_edge = math.max(over_r, over_b, under_l, under_t)
			if worst_edge > 1e-6 then
				local desc = string.format(
					"%s: %s[%s] reaches %.2f past the %g x %g frame (%.2f,%.2f %.2fx%.2f)",
					label, r.name, tostring(r.field), worst_edge, w, h, r.x, r.y, r.w, r.h)
				if not worst or worst_edge > worst.over then worst = { over = worst_edge, desc = desc } end
			end
		end
	end
	if worst then
		print("        " .. worst.desc)
	end
	check(worst == nil, label .. ": every element fits inside the frame")
end

-- A `model[]` element must match the parameter layout the engine documents:
--   model[X,Y;W,H;name;mesh;textures;rotation;continuous;mouse;frame loop;speed]
-- The ninth field is the animation frame loop range and the tenth the
-- animation speed. An empty ninth field means "the full range of all available
-- frames" (guiFormSpecMenu::parseModel seeds frame_loop_end with infinity),
-- which on a model that packs several animations into one track plays all of
-- them in turn. begin == end is legal and pins a single frame:
-- TrackAnimSpec::advance special-cases a zero-length range.
local function check_models(label, fs)
	local bad
	for _, el in ipairs(parse_formspec(fs)) do
		if el.name == "model" then
			local p = el.parts
			if #p < 5 or #p > 10 then
				bad = string.format("%s: model[%s] has %d fields (engine accepts 5..10)",
					label, tostring(p[3]), #p)
			else
				local loop = p[9]
				if loop and loop ~= "" then
					local b, e = xy(loop)
					if not b or not e or e < b then
						bad = string.format(
							"%s: model[%s] frame loop range is '%s' (must be begin<=end, or empty for the full range)",
							label, tostring(p[3]), tostring(loop))
					end
				end
				local speed = p[10]
				if (speed == nil or speed == "") and #p == 10 then
					bad = bad or string.format("%s: model[%s] has an empty animation speed",
						label, tostring(p[3]))
				end
				if speed and speed ~= "" and not (tonumber(speed) and tonumber(speed) > 0) then
					bad = bad or string.format("%s: model[%s] animation speed '%s' is not a positive FPS",
						label, tostring(p[3]), speed)
				end
			end
		end
	end
	if bad then print("        " .. bad) end
	check(bad == nil, label .. ": model[] elements use the documented parameter layout")
end

-- The preview is clickable via a transparent overlay button. If the engine
-- draws its default bevelled background, the overlay hides the mesh it sits on.
local function check_transparent_overlay(label, fs, field)
	local styled, has_overlay
	for _, el in ipairs(parse_formspec(fs)) do
		if el.name == "style" or el.name == "style_type" then
			local selectors = {}
			for s in tostring(el.parts[1]):gmatch("[^,]+") do selectors[s] = true end
			if selectors[field] then
				for i = 2, #el.parts do
					if el.parts[i]:match("^%s*border%s*=%s*false%s*$") then styled = true end
				end
			end
		end
		if el.name == "image_button" and el.parts[4] == field then
			has_overlay = true
			if el.parts[3] ~= "" then
				check(false, string.format("%s: overlay '%s' has an image that covers the preview", label, field))
				return
			end
		end
	end
	if has_overlay then
		check(styled, label .. ": overlay '" .. field .. "' is borderless so the mesh shows through")
	end
end

-- ---------------------------------------------------------------
-- Generate the real formspecs
-- ---------------------------------------------------------------

section("PHASE 1 — load the mods under the stub")
H.current_modname = "sl_modebase"
local ok, err = pcall(dofile, "mods/game/sl_modebase/init.lua")
check(ok, "sl_modebase loads" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then os.exit(1) end

H.current_modname = "sl_gui"
ok, err = pcall(dofile, "mods/apis/sl_gui/init.lua")
check(ok, "sl_gui loads" .. (ok and "" or (" -> " .. tostring(err))))
if not ok then os.exit(1) end

-- Publish the player model exactly as mods/content/sl_characters does at
-- runtime, so the preview takes the code path it takes in the real game.
do
	H.current_modname = "player_api"
	local pok, perr = pcall(dofile, "mods/player_api/api.lua")
	check(pok, "player_api loads" .. (pok and "" or (" -> " .. tostring(perr))))
	H.current_modname = "sl_characters"
	local mok, merr = pcall(dofile, "mods/content/sl_characters/model_boxman.lua")
	check(mok, "the boxman model loads" .. (mok and "" or (" -> " .. tostring(merr))))
	local model = sl_characters and sl_characters.default_model
	local registered = model and player_api and player_api.registered_models
		and player_api.registered_models[model]
	check(registered ~= nil and registered.animations ~= nil,
		"the boxman registered its animation ranges with player_api")
end

local player = H.new_player("alpha")
H.fire_joinplayer(player)
H.advance(1, 0.5)
player:get_meta():set_string("crafting_category", "salvage")

local TABS = { "crafting", "abilities", "achievements", "system", "comms" }

section("PHASE 2 — unified inventory: nothing is clipped by the frame")
for _, tab in ipairs(TABS) do
	player:get_meta():set_string("current_tab", tab)
	check_frame("inventory/" .. tab, get_unified_inventory(player))
end
player:get_meta():set_string("current_tab", "crafting")

section("PHASE 3 — unified inventory: the character preview is not covered")
for _, tab in ipairs(TABS) do
	player:get_meta():set_string("current_tab", tab)
	local fs = get_unified_inventory(player)
	local rects = layout(fs)

	local preview
	for _, r in ipairs(rects) do
		if r.name == "model" and r.field == "player_preview" then preview = r end
	end
	if not preview then
		check(false, "inventory/" .. tab .. ": renders a player_preview model")
	else
		local covered, covered_by = 0, nil
		for _, r in ipairs(rects) do
			if r.name == "image_button" and tostring(r.field):match("^tab_") then
				local a = overlap_area(preview, r)
				if a > covered then covered, covered_by = a, r.field end
			end
		end
		if covered > 0 then
			print(string.format("        tab '%s' covers %.3f of the %.3f preview",
				tostring(covered_by), covered, preview.w * preview.h))
		end
		check(covered == 0, "inventory/" .. tab .. ": no tab button overlaps the character preview")
	end
end
player:get_meta():set_string("current_tab", "crafting")

section("PHASE 4 — model[] elements use the current engine parameter layout")
for _, tab in ipairs(TABS) do
	player:get_meta():set_string("current_tab", tab)
	check_models("inventory/" .. tab, get_unified_inventory(player))
end
player:get_meta():set_string("current_tab", "crafting")
check_models("inventory (preview overlay)", get_unified_inventory(player))
check_transparent_overlay("inventory", get_unified_inventory(player), "open_outfit")

section("PHASE 5 — outfit / player info menu")
local outfit = get_character_outfit_formspec(player, "HEAD")
check_frame("outfit", outfit)
check_models("outfit", outfit)
do
	local rects = layout(outfit)
	local preview
	for _, r in ipairs(rects) do
		if r.name == "model" and r.field == "outfit_preview" then preview = r end
	end
	check(preview ~= nil, "outfit: renders an outfit_preview model")
	if preview then
		local covered = 0
		for _, r in ipairs(rects) do
			if r.name == "image_button" and tostring(r.field):match("^tab_") then
				covered = covered + overlap_area(preview, r)
			end
		end
		check(covered == 0, "outfit: no tab button overlaps the character preview")
	end
end

section("PHASE 6 — matchmaking terminal")
-- The START MATCH control is only drawn for admins, so test as one.
minetest.set_player_privs("alpha", { sl_admin = true, server = true, interactive = true })

local mm = minetest.registered_chatcommands.sl_matchmaking
check(mm ~= nil, "/sl_matchmaking is registered")
if mm then
	local shown_before = #(H.formspecs.alpha or {})
	local pok, perr = pcall(function() mm.func("alpha") end)
	check(pok, "/sl_matchmaking opens the terminal" .. (pok and "" or (" -> " .. tostring(perr))))
	local shown = H.formspecs.alpha or {}
	local last = shown[#shown]
	check(last ~= nil and #shown > shown_before, "the terminal formspec was sent to the player")
	if last then
		check_frame("matchmaking", last.form)

		-- The primary control must be reachable: the START MATCH button has to
		-- sit fully inside the frame, not hang off the bottom edge.
		local rects, w, h = layout(last.form)
		local start_btn
		for _, r in ipairs(rects) do
			if r.field == "start_match" or r.field == "stop_match" then start_btn = r end
		end
		check(start_btn ~= nil, "matchmaking: has a start/stop control")
		if start_btn then
			check(start_btn.y + start_btn.h <= h + 1e-6, string.format(
				"matchmaking: the start/stop control ends at %.2f, inside the %g-high frame",
				start_btn.y + start_btn.h, h))
		end
	end
end

section("PHASE 7 — node GUIs opened by right-click")
-- These carry inventory grids, the elements most likely to outgrow their
-- frame: an 8-slot-wide list is 9.75 units across, not 8.
-- The spawner unit only opens for a live Monster Master.
if game_mode and game_mode.set_monster_master then
	game_mode.set_monster_master("alpha")
end
local stack = ItemStack("")
for _, nodename in ipairs({ "sl_modebase:loot_crate", "sl_modebase:monster_spawner" }) do
	local def = minetest.registered_nodes[nodename]
	check(def ~= nil and def.on_rightclick ~= nil, nodename .. " has a right-click GUI")
	if def and def.on_rightclick then
		local shown_before = #(H.formspecs.alpha or {})
		local ok, err = pcall(function()
			def.on_rightclick({ x = 0, y = 0, z = 0 },
				{ name = nodename, param2 = 0 }, player, stack, {})
		end)
		check(ok, nodename .. " opens without error" .. (ok and "" or (" -> " .. tostring(err))))
		local shown = H.formspecs.alpha or {}
		if check(#shown > shown_before, nodename .. " sent a formspec") then
			check_frame(nodename, shown[#shown].form)
		end
	end
end

section("PHASE 8 — achievement popup HUD images do not scale with the artwork")
-- A HUD `image` is drawn at `source texture size * scale`
-- (src/client/hud.cpp: dstsize = imgsize * scale), so an icon's own pixel
-- dimensions decide how big the popup shows it. The achievement icons here run
-- from 16x16 to 512x512, so one fixed `scale` used to mean 32px for one
-- achievement and 1024px for another. Resolve each texture to a pixel size the
-- way the engine does and assert every icon lands at the same size.

-- PNG IHDR holds width/height big-endian at bytes 17..24.
local function png_size(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local head = f:read(24)
	f:close()
	if not head or head:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
	local function be(i)
		return head:byte(i) * 16777216 + head:byte(i + 1) * 65536
			+ head:byte(i + 2) * 256 + head:byte(i + 3)
	end
	return be(17), be(21)
end

local TEX_DIRS = {}
do
	local p = io.popen("find mods -type d -name textures 2>/dev/null")
	if p then
		for line in p:lines() do TEX_DIRS[#TEX_DIRS + 1] = line .. "/" end
		p:close()
	end
end

local function texture_path(name)
	for _, dir in ipairs(TEX_DIRS) do
		local f = io.open(dir .. name, "rb")
		if f then f:close() return dir .. name end
	end
	return nil
end

-- Apply the one texture modifier that changes the source size, `[resize:WxH]`,
-- exactly as the engine's texture pipeline would before measuring it.
local function resolved_size(text)
	local base = text:match("^[^%^]*")
	local path = texture_path(base)
	if not path then return nil, nil, base end
	local w, h = png_size(path)
	if not w then return nil, nil, base end
	for mw, mh in text:gmatch("%[resize:(%d+)x(%d+)%]") do
		w, h = tonumber(mw), tonumber(mh)
	end
	return w, h, base
end

-- id/icon straight from the registration data.
local ACH = {}
do
	local f = io.open("mods/apis/sl_gui/achievement_definitions.lua")
	local src = f and f:read("*a") or ""
	if f then f:close() end
	for id, icon in src:gmatch('id%s*=%s*"([^"]+)".-icon%s*=%s*"([^"]+)"') do
		ACH[#ACH + 1] = { id = id, icon = icon }
	end
end
check(#ACH >= 30, string.format(
	"read the achievement ids and icons from achievement_definitions.lua (%d)", #ACH))

if game_mode and game_mode.state then game_mode.state.match_active = true end

local drawn_sizes = {}   -- "WxH" of the icon as the engine would draw it
local native_sizes = {}  -- the icon file's own resolution, for the report
local measured = 0
for i, a in ipairs(ACH) do
	-- One throwaway player per achievement: `currently_showing` is keyed by
	-- player name, so a fresh name always gets its popup immediately, and
	-- pre-unlocking every *other* achievement satisfies this one's `requires`
	-- without going through the popup path again.
	local p = H.new_player("ach_probe_" .. i)
	local unlocked = {}
	for _, other in ipairs(ACH) do
		if other.id ~= a.id then unlocked[other.id] = true end
	end
	p:get_meta():set_string("achievements",
		minetest.serialize({ unlocked = unlocked, progress = {} }))
	p._huds = {}

	if unlock_achievement(p, a.id) then
		for _, def in pairs(p._huds) do
			if def.type == "image" and def.text
				and def.text:sub(1, #a.icon) == a.icon then
				local w, h = resolved_size(def.text)
				if w then
					measured = measured + 1
					local dw = w * (def.scale and def.scale.x or 1)
					local dh = h * (def.scale and def.scale.y or 1)
					drawn_sizes[string.format("%gx%g", dw, dh)] = true
					local nw, nh = png_size(texture_path(a.icon) or "")
					if nw then native_sizes[string.format("%dx%d", nw, nh)] = true end
				end
			end
		end
	end
	H.remove_player(p:get_player_name())
end

local natives = {}
for k in pairs(native_sizes) do natives[#natives + 1] = k end
table.sort(natives)
check(measured > 0, string.format(
	"measured the popup icon for %d achievements (native icon sizes: %s)",
	measured, table.concat(natives, ", ")))

local distinct = {}
for k in pairs(drawn_sizes) do distinct[#distinct + 1] = k end
table.sort(distinct)
check(#distinct == 1, string.format(
	"every achievement icon draws at the same size regardless of its own "
		.. "resolution (%d native resolutions -> %s)",
	#natives, table.concat(distinct, ", ")))

section("PHASE 9 — preview animation, header text, tab icons")

-- model[] carries ten fields; the ninth is the frame loop range. An empty one
-- means "the full range of all available frames", which on this model plays
-- every animation back to back.
local MODEL_FIELD_COUNT = 10

local function frame_loop_of(fs, label)
	local found
	for _, e in ipairs(parse_formspec(fs)) do
		if e.name == "model" then found = e end
	end
	if not check(found ~= nil, label .. ": renders a model[] preview") then return nil end
	check(#found.parts == MODEL_FIELD_COUNT, string.format(
		"%s: model[] carries %d fields, so the frame loop is field 9",
		label, #found.parts))
	if #found.parts ~= MODEL_FIELD_COUNT then return nil end
	return found.parts[9]
end

local preview_model = sl_characters and sl_characters.default_model
local preview_anims = preview_model and player_api
	and player_api.registered_models[preview_model]
	and player_api.registered_models[preview_model].animations
check(preview_anims ~= nil, "the preview model's animation ranges are registered")

-- Assert the preview is pinned to one named animation, and say which one.
local function expect_animation(label, anim_name, build)
	if not preview_anims then return end
	local range = preview_anims[anim_name]
	if not check(range ~= nil, string.format(
		"%s: the model defines a '%s' animation", label, anim_name)) then return end
	local loop = frame_loop_of(build(), label)
	if loop == nil then return end
	check(loop ~= "", string.format(
		"%s: frame loop is set, not the engine's full-range default", label))
	local b, e = loop:match("^([^,]*),([^,]*)$")
	local nb, ne = tonumber(b), tonumber(e)
	if not check(nb ~= nil and ne ~= nil, string.format(
		"%s: frame loop '%s' parses as begin,end", label, tostring(loop))) then return end
	check(math.abs(nb - range.x) < 1e-6 and math.abs(ne - range.y) < 1e-6,
		string.format("%s: frame loop %s == the '%s' range %g..%g, so the preview "
			.. "plays only that animation", label, loop, anim_name, range.x, range.y))
end

local IDLE = { sneak = false, zoom = false, up = false, down = false,
	left = false, right = false, LMB = false, RMB = false }
local WALKING = { sneak = false, zoom = false, up = true, down = false,
	left = false, right = false, LMB = false, RMB = false }

player._controls = IDLE
H.advance(0.3, 0.3)
expect_animation("inventory while standing", "stand", function()
	return get_unified_inventory(player)
end)

-- The point of the change: the range follows whatever the player is doing now.
player._controls = WALKING
H.advance(0.3, 0.3)
expect_animation("inventory while walking", "walk", function()
	return get_unified_inventory(player)
end)

player._controls = IDLE
H.advance(0.3, 0.3)

-- The outfit preview goes through the same helper.
expect_animation("outfit menu", "stand", function()
	return get_character_outfit_formspec(player, "HEAD")
end)

-- The header no longer carries the game's name; the tabs identify the window.
for _, tab in ipairs(TABS) do
	player:get_meta():set_string("current_tab", tab)
	local fs = get_unified_inventory(player)
	check(not fs:find("SYSTEM LOOTING", 1, true),
		"inventory/" .. tab .. ": no SYSTEM LOOTING label")
end
player:get_meta():set_string("current_tab", "crafting")

-- Each tab has its own icon, on disk, at the size the strip renders them.
local TAB_ICONS = {}
do
	local src = io.open("mods/apis/sl_gui/unified_inventory.lua"):read("*a")
	for id, icon in src:gmatch('{id = "([%w_]+)",%s*icon_img = "([^"]+)"') do
		TAB_ICONS[#TAB_ICONS + 1] = { id = id, icon = icon }
	end
end
check(#TAB_ICONS == #TABS, string.format(
	"found an icon for each of the %d tabs (%d)", #TABS, #TAB_ICONS))

local seen = {}
for _, t in ipairs(TAB_ICONS) do
	check(not seen[t.icon], string.format(
		"tab '%s' has its own icon (%s is not shared with another tab)",
		t.id, t.icon))
	seen[t.icon] = t.id
	local path = "mods/apis/sl_gui/textures/" .. t.icon
	local f = io.open(path, "rb")
	if not check(f ~= nil, "tab '" .. t.id .. "': " .. t.icon .. " exists") then
		goto continue
	end
	local head = f:read(24)
	f:close()
	local w = head:byte(17) * 16777216 + head:byte(18) * 65536
		+ head:byte(19) * 256 + head:byte(20)
	local h = head:byte(21) * 16777216 + head:byte(22) * 65536
		+ head:byte(23) * 256 + head:byte(24)
	check(w == 32 and h == 32, string.format(
		"tab '%s': %s is %dx%d", t.id, t.icon, w, h))
	::continue::
end

print("")
print(string.format("RESULT: %d passed, %d failed", pass_count, fail_count))
os.exit(fail_count == 0 and 0 or 1)
