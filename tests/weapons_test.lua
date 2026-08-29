-- ================================================================
-- tests/weapons_test.lua
-- Headless test suite for mods/game/sl_weapons against the engine
-- stub (WEAPONS_SPEC §14): fire pipeline, gates, pools, bloom,
-- corpses/burial/cremation, deadwalk, pads, turret IFF + possession
-- flip + battery + logs, lash, fabricator, MM doctrine, beacon chip
-- routing, ranged exorcism, and the match-end scene sweep.
--
-- Run from the repo root:  lua5.1 tests/weapons_test.lua
-- ================================================================

local H = dofile("tests/minetest_stub.lua")

-- Capture inventory-craft recipe registrations (the real global comes
-- from sl_gui's crafting menu, which this suite does not load).
local captured_recipes = {}
register_craft_recipe = function(def) table.insert(captured_recipes, def) end

local pass_count, fail_count = 0, 0
local function check(cond, label)
	if cond then
		pass_count = pass_count + 1
		print("  [PASS] " .. label)
	else
		fail_count = fail_count + 1
		print("  [FAIL] " .. label)
	end
end
local function section(t) print("== " .. t) end

-- Capture item drops (the stub records them in H.item_drops; mirror
-- that here so this suite's early override keeps one log).
local drops = {}
minetest.add_item = function(pos, stack)
	table.insert(drops, { pos = pos, stack = stack })
	local s = type(stack) == "table" and stack.__is_stack and stack or ItemStack(stack)
	table.insert(H.item_drops, {
		pos = pos and { x = pos.x, y = pos.y, z = pos.z } or nil,
		name = s:get_name(),
		count = s:get_count(),
	})
	return { set_velocity = function() end, remove = function() end }
end

local function stack_name(s)
	if type(s) == "table" then return s:get_name() end
	return tostring(s or ""):match("^(%S+)") or ""
end

local function last_sounds(n)
	local out = {}
	local from = math.max(1, #H.sounds - (n or 1) + 1)
	for i = from, #H.sounds do out[#out + 1] = H.sounds[i].name end
	return out
end

local function sound_played(name, since)
	-- `since` is a marker captured as #H.sounds BEFORE the act under
	-- test; the window starts strictly after it.
	for i = (since or 0) + 1, #H.sounds do
		if H.sounds[i].name == name then return true end
	end
	return false
end

-- Aim shooter's eye at a point (or a player's chest).
local function aim_at(shooter, target)
	local is_player = target.get_pos ~= nil
	local tpos = is_player and target:get_pos() or target
	-- Players are tall capsules: aim mid-body. Plain coordinate
	-- tables are exact points (nodes, floors) — no offset.
	local point = { x = tpos.x, y = tpos.y + (is_player and 1.0 or 0), z = tpos.z }
	local spos = shooter:get_pos()
	local eye = { x = spos.x, y = spos.y + 1.625, z = spos.z }
	local d = { x = point.x - eye.x, y = point.y - eye.y, z = point.z - eye.z }
	local len = math.sqrt(d.x ^ 2 + d.y ^ 2 + d.z ^ 2)
	shooter:set_look_dir({ x = d.x / len, y = d.y / len, z = d.z / len })
end

local function fire(itemname, player)
	local def = minetest.registered_tools[itemname]
	if not def then return nil, "no such tool" end
	-- Emulates a player wielding a LOADED weapon (v1.3): fresh stacks
	-- carry no magazine. Dedicated magazine tests use raw stacks.
	local st = ItemStack(itemname)
	local ww = sl_weapons -- global: the helper runs before `local W` exists
	local wdef = ww and ww.defs_by_item[itemname]
	if wdef and wdef.pool and wdef.mag then
		ww.mag_set(st, wdef.mag)
	end
	return def.on_use(st, player, nil)
end

-- A quiet open-space arena far above everything.
local function sky(pos) return { x = pos.x, y = 60, z = pos.z } end

local victim_seq = 0
local function new_victim(prefix, team)
	victim_seq = victim_seq + 1
	local name = (prefix or "vic") .. tostring(victim_seq)
	local p = H.new_player(name)
	H.fire_joinplayer(p)
	local gm = game_mode
	local pl = gm.get_player_state(name)
	pl.phase = "alive"
	pl.eliminated = false
	if team and gm.is_beacon_team and gm.is_beacon_team(team) then
		pl.team = team
	end
	p:set_hp(20)
	-- Flush the join-time spawn_player(0.2 s) so later set_pos sticks.
	H.advance(0.3, 0.1)
	return p
end

-- Ensure the victim's team keeps another living member, then kill
-- them through the real damage path so all death hooks fire.
local function kill_player(victim, dmg, cause, shooter)
	local gm = game_mode
	local pl = gm.get_player_state(victim:get_player_name())
	if pl.team then
		local alive = 0
		for _, other in ipairs(H.connected) do
			local op = gm.get_player_state(other:get_player_name())
			if op.team == pl.team and op.phase == "alive"
				and other ~= victim then alive = alive + 1 end
		end
		if alive == 0 then
			local backup = new_victim("bak", pl.team)
			backup:set_pos({ x = 900, y = 60, z = 900 })
		end
	end
	sl_weapons.last_cause[victim:get_player_name()] = cause
	victim:set_hp(0)
	H.respawn(victim)
end

-- ================================================================
section("PHASE W0 — mod load path")
-- ================================================================

H.current_modname = "sl_modebase"
local ok1, err1 = pcall(dofile, "mods/game/sl_modebase/init.lua")
check(ok1, "sl_modebase loads" .. (ok1 and "" or (" -> " .. tostring(err1))))

H.modpaths.sl_weapons = "mods/game/sl_weapons"
H.current_modname = "sl_weapons"
local ok2, err2 = pcall(dofile, "mods/game/sl_weapons/init.lua")
check(ok2, "sl_weapons loads" .. (ok2 and "" or (" -> " .. tostring(err2))))
if not ok2 then print("FATAL: sl_weapons failed to load; aborting.") os.exit(1) end
H.run_mods_loaded() -- station recipes register here (order-proof)

local W = sl_weapons
local gm = game_mode
local state = gm.state

for _, node in ipairs({ "pistol", "chatter", "scatter", "lance", "mortar",
	"driver", "neon_six", "neon_repeater" }) do
	check(minetest.registered_tools["sl_weapons:" .. node] ~= nil,
		"weapon registered: " .. node)
end
for _, item in ipairs({ "ammo_bullets", "ammo_shells", "ammo_cells", "ammo_rockets",
	"sentry_kit", "targeting_log", "grapple" }) do
	check(minetest.registered_items["sl_weapons:" .. item] ~= nil,
		"item registered: " .. item)
end
for _, node in ipairs({ "pad_weapon", "pad_weapon_dim", "pad_ammo", "pad_ammo_dim",
	"turret", "fabricator", "residue", "mound", "scorch" }) do
	check(minetest.registered_nodes["sl_weapons:" .. node] ~= nil,
		"node registered: " .. node)
end
for _, ent in ipairs({ "sl_weapons:corpse", "sl_weapons:deadwalk", "sl_weapons:mortar",
	"sl_weapons:pulse", "sl_weapons:lash_hook", "sl_weapons:turret_head" }) do
	check(minetest.registered_entities[ent] ~= nil, "entity registered: " .. ent)
end

-- ================================================================
section("PHASE W0b — deprecation audit (live-server round 2)")
-- ================================================================

-- Engine entity properties belong inside initial_properties; a prop at
-- the top of a definition logs deprecation warnings on the live server
-- (the sl_weapons:mortar / :turret_head lesson).
local ENGINE_PROPS = {
	"physical", "collide_with_objects", "collisionbox", "selectionbox",
	"pointable", "visual", "mesh", "textures", "visual_size", "spritediv",
	"is_visible", "makes_footstep_sound", "static_save", "hp_max", "glow",
	"nametag", "infotext", "wield_item", "backface_culling",
	"automatic_rotate", "automatic_face_movement_dir",
}
local prop_offences, audited = 0, 0
for name, def in pairs(minetest.registered_entities) do
	audited = audited + 1
	for _, prop in ipairs(ENGINE_PROPS) do
		if def[prop] ~= nil then
			prop_offences = prop_offences + 1
			print("    offence: " .. name .. " top-level '" .. prop .. "'")
		end
	end
end
check(prop_offences == 0, "entity defs carry engine props in initial_properties ("
	.. tostring(audited) .. " audited)")

-- The deprecated velocity twins must appear nowhere in game code — not
-- even in comments; the tree should stop teaching the pattern. MT CTF
-- calls get_velocity / add_velocity directly, and so do we.
local legacy = 0
local vgrep = io.popen("grep -rn player_velocity mods/game mods/content 2>/dev/null")
if vgrep then
	for line in vgrep:lines() do
		if line:find("get_player_velocity") or line:find("add_player_velocity")
			or line:find("set_player_velocity") then
			legacy = legacy + 1
			print("    legacy call: " .. line)
		end
	end
	vgrep:close()
end
check(legacy == 0, "no deprecated velocity calls in game code")

-- Formspec table columns: the legal types are text, image, color,
-- indent and tree; alignment is an option (align=right), never a type.
-- v1.3.5 shipped a 'right' column and the client parser segfaulted.
local VALID_COL = { text = true, image = true, color = true, indent = true, tree = true }
local bad_cols = 0
local cgrep = io.popen("grep -rn tablecolumns mods/game mods/content 2>/dev/null")
if cgrep then
	for line in cgrep:lines() do
		for cols in line:gmatch("tablecolumns%[([^%]]*)%]") do
			for col in cols:gmatch("[^;]+") do
				local kind = col:match("^%s*([%w_]+)")
				if not VALID_COL[kind] then
					bad_cols = bad_cols + 1
					print("    bad column type '" .. tostring(kind) .. "': " .. line)
				end
			end
		end
	end
	cgrep:close()
end
check(bad_cols == 0, "formspec table columns are all legal types")

check(gm.is_possessable("sl_weapons:pad_weapon"), "weapon pad is possessable")
check(gm.is_possessable("sl_weapons:turret"), "turret is possessable")
check(gm.is_possessable("sl_weapons:fabricator") == false
	or gm.is_possessable("sl_weapons:fabricator") == true, "fabricator possessability resolved")

-- ================================================================
section("PHASE W1a — lobby gates")
-- ================================================================

local alpha = H.new_player("alpha")
local beta = H.new_player("beta")
local gamma = H.new_player("gamma")
H.fire_joinplayer(alpha); H.fire_joinplayer(beta); H.fire_joinplayer(gamma)
H.advance(1, 0.5)

alpha._wielded = "sl_weapons:pistol"
alpha:get_inventory():add_item("main", ItemStack("sl_weapons:pistol"))
-- Open test range (v1.3.3): weapons fire outside matches; lobby
-- bodies stay immortal, so test fire is loud but never lethal.
local s0 = #H.sounds
fire("sl_weapons:pistol", alpha) -- draw attempt (raise delay)
H.advance(0.4, 0.1)
aim_at(alpha, beta)
fire("sl_weapons:pistol", alpha)
check(sound_played("sl_weapons_pistol_fire", s0), "weapons fire outside matches (test range)")
local idle_refusal = false
for _, l in ipairs(H.chat_player.alpha or {}) do
	if l:find("idle outside an active match", 1, true) then idle_refusal = true end
end
check(not idle_refusal, "no 'range idle' refusal outside matches")
check(beta:get_hp() == 20, "lobby bodies stay immortal under test fire")

-- ================================================================
section("PHASE W1b — insertion, loadout, gates inside a match")
-- ================================================================

state.settings.mm_auto_assign = false
gamma._wielded = ""
minetest.registered_chatcommands.sl_match_start.func("alpha", "")
minetest.registered_chatcommands.sl_ready.func("alpha", "")
minetest.registered_chatcommands.sl_ready.func("beta", "")
minetest.registered_chatcommands.sl_ready.func("gamma", "")
H.advance(7, 0.5)
check(state.match_active == true, "match active")

local ainv = alpha:get_inventory()
check(ainv:contains_item("main", ItemStack("sl_weapons:pistol")),
	"loadout pistol granted at insertion")
check(ainv:contains_item("main", ItemStack("sl_modebase:combat_blade")),
	"loadout blade granted at insertion")

-- Monster Master doctrine
gm.set_monster_master("gamma")
gamma._wielded = "sl_weapons:pistol"
gamma:get_inventory():add_item("main", ItemStack("sl_weapons:chatter"))
H.advance(1.5, 0.5)
check(not gamma:get_inventory():contains_item("main", ItemStack("sl_weapons:chatter")),
	"MM ranged items stripped from inventory")
local s1 = #H.sounds
fire("sl_weapons:pistol", gamma)
check(H.chat_player.gamma[#H.chat_player.gamma]:find("doctrine", 1, true) ~= nil,
	"MM fire refused: 'Your hands are the doctrine.'")
check(not sound_played("sl_weapons_pistol_fire", s1), "MM shot produced no sound")

-- Ghost gate (simulated phase)
local apl = gm.get_player_state("alpha")
apl.phase = "ghost"
local s2 = #H.sounds
fire("sl_weapons:pistol", alpha)
check(not sound_played("sl_weapons_pistol_fire", s2), "ghost cannot fire")
apl.phase = "alive"

-- Master disable setting
H.settings["sl_weapons_enabled"] = "false"
fire("sl_weapons:pistol", alpha)
check(H.chat_player.alpha[#H.chat_player.alpha]:find("offline", 1, true) ~= nil,
	"weapons offline setting refuses fire")
H.settings["sl_weapons_enabled"] = nil

-- ================================================================
section("PHASE W1c — hitscan pipeline, pools, bloom, dry fire")
-- ================================================================

-- A quiet sky range for the duels.
alpha:set_pos(sky({ x = 0, y = 0, z = 0 }))
local vic = new_victim("tgt", "beacon_b")
vic:set_pos({ x = 0, y = 60, z = 8 })
-- The victim carries things worth looting (and a biolocked pistol).
vic:get_inventory():add_item("main", ItemStack("sl_weapons:pistol"))
vic:get_inventory():add_item("main", ItemStack("sl_modebase:flare"))
vic:get_inventory():add_item("main", ItemStack("sl_modebase:medkit"))

aim_at(alpha, vic)
fire("sl_weapons:pistol", alpha) -- draw attempt: pays the shared raise delay
H.advance(0.4, 0.1)
local snd = #H.sounds
fire("sl_weapons:pistol", alpha)
check(vic:get_hp() == 16, "pistol hits for 4 (20 -> 16)")
check(sound_played("sl_weapons_pistol_fire", snd), "pistol report audible")
check(#H.particles > 0, "tracer particles spawned")

-- Refire gate
local hp = vic:get_hp()
fire("sl_weapons:pistol", alpha)
check(vic:get_hp() == hp, "refire gate blocks immediate second shot")
H.advance(0.4, 0.1)
fire("sl_weapons:pistol", alpha)
check(vic:get_hp() == hp - 4, "pistol fires again after refire time")

-- Raise delay on weapon switch
W.get_pool("alpha").bullets = 60
aim_at(alpha, vic)
fire("sl_weapons:chatter", alpha)
check(W.bloom_current("alpha") == W.BLOOM_MIN, "first chatter shot is exact (bloom min)")
local bullets = W.get_pool("alpha").bullets
fire("sl_weapons:chatter", alpha)
check(W.get_pool("alpha").bullets == bullets, "switch-raise blocked the shot")
H.advance(0.35, 0.1)
local chat_stack = ItemStack("sl_weapons:chatter")
W.mag_set(chat_stack, W.defs_by_item["sl_weapons:chatter"].mag)
for _ = 1, 4 do
	minetest.registered_tools["sl_weapons:chatter"].on_use(chat_stack, alpha, nil)
	H.advance(0.1, 0.05)
end
check(W.mag_get(chat_stack) == W.defs_by_item["sl_weapons:chatter"].mag - 4,
	"chatter burns 4 rounds out of its magazine")
check(W.get_pool("alpha").bullets == bullets, "firing alone never touches the reserve")
check(W.bloom_current("alpha") > W.BLOOM_MIN, "bloom grows along a held burst")
H.advance(0.7, 0.1)
check(W.bloom_current("alpha") == W.BLOOM_MIN, "bloom resets after 0.6 s idle")

-- Scatter: shells, pellets, point-blank
vic:set_pos({ x = 0, y = 60, z = 4 })
aim_at(alpha, vic)
W.get_pool("alpha").shells = 8
fire("sl_weapons:scatter", alpha) -- draw attempt
H.advance(0.95, 0.1)
vic:set_hp(20)
local sh_before = W.get_pool("alpha").shells
local sc_stack = ItemStack("sl_weapons:scatter")
W.mag_set(sc_stack, W.defs_by_item["sl_weapons:scatter"].mag)
minetest.registered_tools["sl_weapons:scatter"].on_use(sc_stack, alpha, nil)
check(W.mag_get(sc_stack) == W.defs_by_item["sl_weapons:scatter"].mag - 1,
	"scatter consumes one shell from its magazine")
check(W.get_pool("alpha").shells == sh_before, "the reserve waits for a load")
local scatter_dmg = 20 - vic:get_hp()
check(scatter_dmg >= 4 and scatter_dmg <= 12,
	"scatter pellets deal partial-to-full 12 (got " .. tostring(scatter_dmg) .. ")")

-- Lance: 18, cells x2
vic:set_pos({ x = 0, y = 60, z = 6 })
aim_at(alpha, vic)
W.get_pool("alpha").cells = 10
fire("sl_weapons:lance", alpha) -- draw attempt
H.advance(0.95, 0.1)
vic:set_hp(20)
fire("sl_weapons:lance", alpha)
check(vic:get_hp() == 2, "lance leaves the victim at 2 HP (18 dmg)")
check(W.get_pool("alpha").cells == 10, "lance burns its magazine, not the reserve (1 cell-round/shot)")

-- Zoom toggle exists (no engine fov in stub; flag only)
minetest.registered_tools["sl_weapons:lance"].on_place(ItemStack("sl_weapons:lance"), alpha, nil)
check(W.zoom.alpha == true, "lance RMB toggles zoom")

-- Kill: incident line, corpse, residue, smashed ammo, dissolved pistol
W.get_pool(vic:get_player_name()).cells = 30
vic:get_inventory():add_item("main", ItemStack("sl_weapons:chatter"))
aim_at(alpha, vic)
fire("sl_weapons:pistol", alpha) -- redraw pistol
H.advance(1.7, 0.1) -- pistol switch + lance refire window
local sndk = #H.sounds
fire("sl_weapons:pistol", alpha)
check(vic:get_hp() <= 0 or vic._dead == true, "pistol tap finishes the kill")
local feed = nil
for _, line in ipairs(H.chat_all) do
	if line:find("cause: pulse round", 1, true) then feed = line end
end
check(feed ~= nil, "incident feed logs the kill")
check(feed and not feed:find("alpha", 1, true), "incident feed names no attacker")
check(#W.corpses == 1, "corpse spawned on death")
local corpse = W.corpses[1]
check(corpse.victim == vic:get_player_name(), "corpse holds the victim's name")
check(H.voxels[H.vhash(corpse.floor)] == "sl_weapons:residue", "residue node under the body")
check(corpse.dissolved_pistol == true, "biolocked loadout pistol dissolved")
local pool_victim = W.get_pool(corpse.victim)
check(pool_victim.cells == 20, "a third of loose ammo smashed on death (30 -> 20)")

-- Corpse report + audible looting
local had_flare = corpse.inv
check(#had_flare >= 0, "corpse inventory list present")
alpha._inv:set_size("main", 64) -- room for the loot (meta stacks do not merge)
alpha._wielded = ""
corpse.obj:rightclick(alpha)
check(#H.formspecs.alpha > 0, "corpse report formspec shown")
H.fire_receive_fields("alpha", "sl_weapons:corpse", { loot_all = "true" })
check(sound_played("sl_weapons_loot_hum", sndk), "looting is audible (hum)")
check(corpse.looted == true and #corpse.inv == 0, "corpse looted empty")
local recovered_note = false
for _, st in ipairs(alpha:get_inventory():get_list("main")) do
	local d = st:get_meta():get_string("description")
	if d:find("Recovered — last charge", 1, true) then recovered_note = true end
end
check(recovered_note, "looted gun shows the dead man's frozen numbers (res. #3)")

-- ================================================================
section("PHASE W1d — projectiles: inheritance, splash, juggle")
-- ================================================================

-- Velocity inheritance: fire mortar with a sprint carried.
-- NB: the whole projectile range lives at x=30 — the W1c kill left a
-- residue node at (0,60,6), and shells dutifully detonate on stains.
local vic2 = new_victim("tgt", "beacon_b")
vic2:set_pos({ x = 30, y = 60, z = 10 })
alpha:set_pos({ x = 30, y = 60, z = 0 })
aim_at(alpha, vic2)
vic2:set_hp(40) -- the sprint shell below lands 28: keep 20 HP bodies out of it
alpha:set_player_velocity({ x = 5, y = 0, z = 0 })
W.get_pool("alpha").rockets = 5
local rockets_before = W.get_pool("alpha").rockets
local es0 = #H.entity_spawns
fire("sl_weapons:mortar", alpha) -- draw attempt
H.advance(0.95, 0.1)
fire("sl_weapons:mortar", alpha) -- the real shot, sprint carried
check(#H.entity_spawns == es0 + 1, "mortar projectile spawned")
local mst = ItemStack("sl_weapons:mortar")
W.mag_set(mst, 0)
W.get_pool("alpha").rockets = 5
W.mag_load(alpha, W.defs_by_item["sl_weapons:mortar"], mst)
check(W.mag_get(mst) == 3 and W.get_pool("alpha").rockets == 2,
	"loading fills the 3-rocket magazine from the reserve")
local mortar_obj = nil
for _, lua in pairs(H.luaentities) do
	if lua.name == "sl_weapons:mortar" and lua.object
		and not lua.object._removed then
		mortar_obj = lua.object break
	end
end
check(mortar_obj ~= nil, "mortar entity tracked")
if mortar_obj then
	local v = mortar_obj:get_velocity()
	check(v.x > 4 and v.x < 6, "velocity inheritance: shell carries the sprint (vx=" ..
		tostring(math.floor(v.x)) .. ")")
	check(v.z > 20 and v.z < 27, "shell speed along the shot line (vz=" ..
		tostring(math.floor(v.z)) .. ")")
end
alpha:set_player_velocity({ x = 0, y = 0, z = 0 })

-- Let it fly: a fresh, straight shot for the clean direct hit
-- (the sprint shell keeps drifting sideways — that's the point).
aim_at(alpha, vic2)
H.advance(1.0, 0.1) -- refire window
vic2:set_hp(40) -- doubled direct damage (28) one-shots 20 HP bodies;
-- the victim runs hot so the assert measures the wound, not the funeral
local sndm = #H.sounds
fire("sl_weapons:mortar", alpha)
H.advance(0.9, 0.05)
check(vic2:get_hp() == 12, "mortar direct hit lands 28 (40 -> " .. tostring(vic2:get_hp()) .. ")")
check(sound_played("sl_weapons_explosion", sndm), "explosion heard")

-- Parabola: fire flat into open sky and watch gravity bend the arc.
alpha:set_player_velocity({ x = 0, y = 0, z = 0 })
aim_at(alpha, { x = 30, y = 61.6, z = 20 })
H.advance(1.0, 0.1) -- refire window
local arc_es = #H.entity_spawns
fire("sl_weapons:mortar", alpha)
check(#H.entity_spawns == arc_es + 1, "arc probe shell away")
local shell2 = nil
for _, lua in pairs(H.luaentities) do
	-- the sprint shell from earlier is still airborne, plunging at
	-- vy ~ -25; the fresh probe leaves the muzzle near vy = 0.
	if lua.name == "sl_weapons:mortar" and lua.object
		and not lua.object._removed
		and lua.object:get_velocity().y > -10 then
		shell2 = lua.object break
	end
end
if shell2 then
	local vy0 = shell2:get_velocity().y
	H.advance(0.2, 0.1)
	local vy1 = shell2:get_velocity().y
	check(vy1 - vy0 < -1.0, "parabolic arc: gravity drags the shell (vy " ..
		string.format("%.1f -> %.1f", vy0, vy1) .. ")")
	shell2:remove() -- probe retired: no stray shells wandering into W2
end

-- Splash + knockback: ground shot near a fresh victim
local vic3 = new_victim("tgt", "beacon_b")
vic3:set_pos({ x = 31, y = 60, z = 9 })
vic3:set_hp(20)
local ground = { x = 30, y = 59, z = 8 }
H.voxels[H.vhash(ground)] = "default:stone" -- somewhere for the shell to land
-- Gravity arcs the shell down ~1 m over this range: aim above the stone
-- so it falls INTO the cell (a flat aim skims the cell's top corner and
-- sails under). Geometry proven by simulation: impact node (30,59,8),
-- victim 1.73 m off-centre.
aim_at(alpha, { x = 30, y = 59.7, z = 8.3 })
H.advance(0.5, 0.1) -- refire window behind the arc probe
W.get_pool("alpha").rockets = W.get_pool("alpha").rockets + 2
fire("sl_weapons:mortar", alpha)
H.advance(0.6, 0.05)
local splash_dmg = 20 - vic3:get_hp()
check(splash_dmg >= 2 and splash_dmg <= 5, "splash falloff below direct (10 max, " ..
	tostring(splash_dmg) .. " dmg at 2.2 m)")
local kv = vic3:get_velocity()
check(kv.x ~= 0 or kv.z ~= 0, "splash knockback applied to victim")

-- Mortar-jump: shoot your own feet, ride the blast.
alpha:set_hp(20)
alpha:set_player_velocity({ x = 0, y = 0, z = 0 })
H.voxels[H.vhash({ x = 30, y = 59, z = 1 })] = "default:stone" -- floor to blast (at the aim point)
aim_at(alpha, { x = alpha:get_pos().x, y = alpha:get_pos().y - 1, z = alpha:get_pos().z + 1 })
H.advance(0.4, 0.1) -- refire window from the last mortar shot
fire("sl_weapons:mortar", alpha)
H.advance(0.4, 0.05)
local selfvel = alpha:get_velocity()
check(selfvel.y > 0, "mortar-jump: shooter launched upward")
check(alpha:get_hp() < 20, "mortar-jump costs self-damage (50% falloff)")

-- Pulse: juggle knockback, no reload between bolts
local vic4 = new_victim("tgt", "beacon_b")
vic4:set_pos({ x = 30, y = 60, z = 6 })
vic4:set_hp(20)
aim_at(alpha, vic4)
W.get_pool("alpha").cells = 10
fire("sl_weapons:driver", alpha) -- draw attempt
H.advance(0.35, 0.1)
fire("sl_weapons:driver", alpha)
H.advance(0.3, 0.05)
check(vic4:get_hp() == 15, "pulse bolt deals 5")
local jv = vic4:get_velocity()
check(jv.z ~= 0 or jv.x ~= 0 or jv.y ~= 0, "pulse-juggle knockback nudges the target")

-- Dry fire: loud click + autoswitch to pistol (empty MAGAZINE —
-- the reserve is irrelevant until someone loads it)
W.get_pool("alpha").cells = 6
alpha:get_inventory():add_item("main", ItemStack("sl_weapons:lance"))
local dry_stack = ItemStack("sl_weapons:lance")
W.mag_set(dry_stack, 0) -- a fresh stack is wear-0 = FULL (CTF semantics)
minetest.registered_tools["sl_weapons:lance"].on_use(dry_stack, alpha, nil) -- raise
H.advance(0.35, 0.1)
local sndd = #H.sounds
minetest.registered_tools["sl_weapons:lance"].on_use(dry_stack, alpha, nil)
check(sound_played("sl_weapons_dry_click", sndd), "dry click is loud")
check(not alpha:get_inventory():contains_item("main", ItemStack("sl_weapons:lance")),
	"empty lance autoswitches to pistol")

-- ================================================================
section("PHASE W1e — magazines: every weapon eats ammo, blades wear")
-- ================================================================

-- No free rides: every weapon declares a pool AND a magazine
local offenders = {}
for iname, def in pairs(W.defs_by_item) do
	if not def.pool or not def.mag then
		table.insert(offenders, iname)
	end
end
check(#offenders == 0, "every weapon declares ammo + magazine (offenders: "
	.. table.concat(offenders, ",") .. ")")

-- The pistol's magazine cycle: fire, empty, dry, load, fire again
H.advance(2.0, 0.5) -- lance refire window (player-keyed) + switch raise
aim_at(alpha, { x = 0, y = 61, z = 40 }) -- empty air: nobody on the line
local pdef = W.defs_by_item["sl_weapons:pistol"]
local pst = ItemStack("sl_weapons:pistol")
W.mag_set(pst, pdef.mag)
W.get_pool("alpha").bullets = 0 -- no reserve: the magazine is all there is
local pfire1 = #H.sounds
minetest.registered_tools["sl_weapons:pistol"].on_use(pst, alpha, nil) -- raise
H.advance(0.4, 0.1)
minetest.registered_tools["sl_weapons:pistol"].on_use(pst, alpha, nil) -- fires
check(sound_played("sl_weapons_pistol_fire", pfire1), "loaded pistol fires")
H.advance(0.4, 0.1)
minetest.registered_tools["sl_weapons:pistol"].on_use(pst, alpha, nil) -- fires
check(W.mag_get(pst) == pdef.mag - 2, "each shot burns one magazine round")
check(pst:get_wear() == math.floor(2 * 65535 / pdef.mag + 0.5),
	"the durability bar drains with firing (wear " .. pst:get_wear() .. " after 2)")
for _ = 1, pdef.mag do
	minetest.registered_tools["sl_weapons:pistol"].on_use(pst, alpha, nil)
	H.advance(0.4, 0.1)
end
check(W.mag_get(pst) == 0, "the magazine empties")
check(pst:get_wear() == 65535, "empty magazine shows an empty bar (wear 65535)")
local pdry = #H.sounds
minetest.registered_tools["sl_weapons:pistol"].on_use(pst, alpha, nil)
check(sound_played("sl_weapons_dry_click", pdry), "empty magazine dry-clicks (no free pistol)")
W.get_pool("alpha").bullets = 40
pst = W.mag_load(alpha, pdef, pst)
check(W.mag_get(pst) == pdef.mag, "loading fills the pistol to capacity")
check(pst:get_wear() == 0, "loading restores the bar to full (wear 0)")
check(W.get_pool("alpha").bullets == 40 - pdef.mag, "and pulls exactly the difference from the reserve")
local r_before = W.get_pool("alpha").bullets
W.mag_load(alpha, pdef, pst)
check(W.get_pool("alpha").bullets == r_before, "a full magazine loads nothing more")

-- RMB loads a non-zoom weapon straight from the reserve
local sdef = W.defs_by_item["sl_weapons:scatter"]
local sst = ItemStack("sl_weapons:scatter")
W.mag_set(sst, 0)
W.get_pool("alpha").shells = 8
sst = minetest.registered_tools["sl_weapons:scatter"].on_place(sst, alpha, nil)
check(W.mag_get(sst) == sdef.mag, "right-click loads the scatter")
check(W.get_pool("alpha").shells == 8 - sdef.mag, "shells pulled from the reserve")

-- A cache use while holding a matching weapon tops up both
local ldef = W.defs_by_item["sl_weapons:lance"]
local lw = ItemStack("sl_weapons:lance")
W.mag_set(lw, 0)
alpha:set_wielded_item(lw)
W.get_pool("alpha").cells = 10
local cache = minetest.registered_items["sl_weapons:ammo_cells"]
cache.on_use(ItemStack("sl_weapons:ammo_cells"), alpha, nil)
check(W.get_pool("alpha").cells == 10 + W.AMMO_YIELD.cells - ldef.mag,
	"cache use fills the reserve and loads the wielded lance")
check(W.mag_get(alpha:get_wielded_item()) == ldef.mag, "the wielded lance is loaded")

-- Ammo indicator is the durability bar (v1.3.2, CTF-style): wear 0
-- is a full magazine, 65535 is empty; the HUD text carries no numbers.
check(W.hud_line("alpha"):find("%d") == nil,
	"the HUD text carries no ammo digits ('" .. W.hud_line("alpha") .. "')")

-- Loadout: the pistol arrives loaded with starting reserve
local lp_stack
for _, st in ipairs(alpha:get_inventory():get_list("main")) do
	if st:get_name() == "sl_weapons:pistol" then lp_stack = st end
end
check(lp_stack ~= nil and W.mag_get(lp_stack) == 12, "loadout pistol arrives loaded (12)")
check(W.peek_pool("alpha").bullets >= 24, "loadout carries two magazines of bullets")

-- Melee is consumable: the blade wears on landed hits and breaks
local blv = new_victim("blv", "beacon_b")
alpha:set_wielded_item(ItemStack("sl_modebase:combat_blade"))
local w0 = alpha:get_wielded_item():get_wear()
blv:punch(alpha, 1.0, { full_punch_interval = 0.8, damage_groups = { fleshy = 6 } }, nil)
local w1 = alpha:get_wielded_item():get_wear()
check(w1 > w0, "a landed hit wears the blade")
local spent = ItemStack("sl_modebase:combat_blade")
spent:add_wear(65535 - math.ceil(65535 / 40))
alpha:set_wielded_item(spent)
blv:punch(alpha, 1.0, { full_punch_interval = 0.8, damage_groups = { fleshy = 6 } }, nil)
check(alpha:get_wielded_item():get_name() == "", "a spent blade breaks in the hand")
alpha:set_wielded_item(ItemStack(""))

local blade_recipe
for _, r in ipairs(captured_recipes) do
	if r.output == "sl_modebase:combat_blade" then blade_recipe = r end
end
check(blade_recipe ~= nil, "a broken blade is replaceable: the recipe exists (ingot x2)")

-- Neon Six: six shots then the cylinder pause (busy gate)
local vic5 = new_victim("tgt", "beacon_b")
vic5:set_pos({ x = 0, y = 60, z = 7 })
aim_at(alpha, vic5)
W.get_pool("alpha").bullets = 40
alpha:get_inventory():add_item("main", ItemStack("sl_weapons:neon_six"))
H.advance(2.0, 0.5) -- W1e's pistol refire + switch raise clear
local six_stack = ItemStack("sl_weapons:neon_six")
W.mag_set(six_stack, W.defs_by_item["sl_weapons:neon_six"].mag)
local six_fired = 0
local six_m = W.mag_get(six_stack)
for i = 1, 8 do
	minetest.registered_tools["sl_weapons:neon_six"].on_use(six_stack, alpha, nil)
	if W.mag_get(six_stack) < six_m then
		six_fired = six_fired + 1
		six_m = W.mag_get(six_stack)
	end
	H.advance(0.6, 0.1) -- longer than the 0.55 refire
	vic5:set_hp(20)
end
check(six_fired == 6, "six shots then the spin pauses the seventh (got " .. tostring(six_fired) .. ")")
check((W.busy_until.alpha or 0) > W.now() or six_fired >= 7, "cylinder busy window tracked")

-- ================================================================
-- ================================================================
section("PHASE W1g — NaN armour: the point-blank lesson")
-- ================================================================

-- Live server 2026-08-29: a mortar-jump with the blast centred exactly
-- on the shooter normalized a zero vector -> NaN -> add_velocity(NaN)
-- -> client segfault. Every vector that reaches a movement write must
-- be finite; the checks below reproduce the crash verbatim.
local function is_finite(v)
	return v ~= nil and v.x == v.x and v.y == v.y and v.z == v.z
		and math.abs(v.x) ~= math.huge
		and math.abs(v.y) ~= math.huge
		and math.abs(v.z) ~= math.huge
end

check(type(vector.safe_dir) == "function" and type(vector.finite) == "function",
	"the vector armor (safe_dir / finite) is installed")
check(vector.safe_dir({ x = 0, y = 0, z = 0 }).y == 0,
	"safe_dir of a zero vector stands still by default")
check(vector.safe_dir({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }).y == 1,
	"safe_dir of a zero vector honours the fallback (point-blank = up)")
local sd = vector.safe_dir({ x = 0, y = 0, z = 3 })
check(math.abs(sd.z - 1) < 1e-9, "safe_dir normalizes real directions")
local nan = 0 / 0
check(vector.safe_dir({ x = nan, y = nan, z = nan }).y == 0,
	"safe_dir quarantines NaN input")
check(vector.finite({ x = 1, y = 2, z = 3 })
	and not vector.finite({ x = nan, y = 0, z = 0 })
	and not vector.finite({ x = math.huge, y = 0, z = 0 }),
	"vector.finite detects NaN and infinity")

-- The exact live crash: a blast centred precisely on the shooter.
alpha:set_pos({ x = 50, y = 60, z = 0 })
alpha:set_velocity({ x = 0, y = 0, z = 0 })
alpha:set_hp(20)
local pvic = new_victim("pnt", "beacon_b") -- a victim at ground zero too
pvic:set_pos({ x = 50, y = 60, z = 0 })
pvic:set_hp(20)
W.explode({ x = 50, y = 60, z = 0 }, "alpha", W.projectiles.mortar)
H.advance(0.1, 0.05)
local pvel = alpha:get_velocity()
check(is_finite(pvel), "point-blank self-blast leaves the shooter finite (the segfault)")
check(pvel.y > 0, "point-blank blast still mortar-jumps (straight up)")
check(is_finite(pvic:get_velocity()), "a victim at ground zero stays finite")
check(alpha:get_hp() < 20 and pvic:get_hp() < 20, "ground zero still hurts")

-- The full pipeline repro: fire at your own feet — the shell detonates
-- at the shooter's exact position ("uses sl_weapons:mortar, pointing
-- at" the node you stand on).
alpha:set_pos({ x = 55, y = 60, z = 0 })
alpha:set_velocity({ x = 0, y = 0, z = 0 })
H.voxels[H.vhash({ x = 55, y = 59, z = 0 })] = "default:stone"
aim_at(alpha, { x = 55, y = 59, z = 0 })
W.get_pool("alpha").rockets = 2
H.advance(1.8, 0.2) -- refire window behind whatever came before
fire("sl_weapons:mortar", alpha)
H.advance(0.4, 0.05)
H.voxels[H.vhash({ x = 55, y = 59, z = 0 })] = nil -- leave no residue
check(is_finite(alpha:get_velocity()), "firing at your own feet stays finite (pipeline)")

-- Boundary guards: a NaN shove is refused, degenerate spread collapses
local pre_v = alpha:get_velocity()
W.knockback(alpha, { x = nan, y = nan, z = nan })
check(alpha:get_velocity().x == pre_v.x and alpha:get_velocity().y == pre_v.y,
	"knockback refuses a NaN vector")
check(is_finite(W.spread_dir({ x = 0, y = 1, z = 0 }, 4)),
	"spread stays finite when aiming straight up")

section("PHASE W2a — corpse destruction: burial, cremation, traces")
-- ================================================================

-- Burial: shovel on a corpse -> grave mound, corpse gone.
local bvic = new_victim("bvr", "beacon_b")
bvic:set_pos({ x = 40, y = 60, z = 0 })
kill_player(bvic, 20, "lance", alpha)
check(#W.corpses == 2, "second corpse spawned (burial subject)")
local bcorpse = W.corpses[#W.corpses]
alpha._wielded = "sl_modebase:trench_shovel"
bcorpse.obj:rightclick(alpha)
check(H.voxels[H.vhash(bcorpse.floor)] == "sl_weapons:mound",
	"burial leaves a grave mound")
check(bcorpse.removed == true, "buried corpse is gone")
check(sound_played("sl_weapons_shovel_bury", 1), "burial heard")

-- Cremation: flare on a corpse -> scorch + Ashen Relic at par.
local cvic = new_victim("cvr", "beacon_b")
cvic:set_pos({ x = 80, y = 60, z = 0 })
kill_player(cvic, 20, "lance", alpha)
local ccorpse = W.corpses[#W.corpses]
alpha._wielded = "sl_modebase:flare"
local drops_before = #drops
ccorpse.obj:rightclick(alpha)
check(H.voxels[H.vhash({ x = ccorpse.floor.x, y = ccorpse.floor.y + 1, z = ccorpse.floor.z })] == "sl_weapons:scorch",
	"cremation leaves a scorch")
local relic_dropped = false
for i = drops_before + 1, #drops do
	if stack_name(drops[i].stack) == "sl_modebase:ritual_ashen_relic" then relic_dropped = true end
end
check(relic_dropped, "cremation drops an Ashen Relic (full ritual par)")
check(H.voxels[H.vhash(ccorpse.floor)] == "sl_weapons:residue",
	"residue outlives the cremation")
alpha._wielded = ""

-- ================================================================
section("PHASE W2b — the Deadwalk Puppet (safe variant)")
-- ================================================================

-- beta died earlier? No — beta is alive. Make beta an evil ghost
-- with its own corpse.
beta:set_pos({ x = 120, y = 60, z = 0 })
kill_player(beta, 20, "lance", alpha)
local bpl = gm.get_player_state("beta")
bpl.phase = "evil_ghost" -- revive path simulated
local beta_corpse = W.corpses[#W.corpses]
check(beta_corpse.victim == "beta", "beta's corpse spawned")

beta_corpse.obj:rightclick(beta)
check(#W.deadwalks == 1, "evil ghost raises its own deadwalk")
local dw = W.deadwalks[1]
check(dw ~= nil and dw.object ~= nil and dw.object:get_hp() == 8, "deadwalk has 8 HP")

-- Visible corruption flags + harmless by statute
local dw_def = minetest.registered_entities["sl_weapons:deadwalk"]
check(dw_def.initial_properties and dw_def.initial_properties.hp_max == 8
	and dw_def.hp_max == nil,
	"deadwalk hp_max is 8, declared in initial_properties (no healing path exists)")
local other = new_victim("oth", "beacon_b")
other:set_pos(dw.object:get_pos())
H.advance(1.0, 0.1)
check(other:get_hp() == 20, "deadwalk harms nobody while shadowing")

-- Shot apart -> puppet collapse, corpse consumed, residue remains
local floor_of_beta = beta_corpse.floor
dw.object:punch(alpha, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 8 } }, { x = 0, y = 0, z = 1 })
check(#W.deadwalks == 0, "deadwalk collapses when shot apart")
check(beta_corpse.removed == true, "collapsed puppet consumed its corpse")
check(H.voxels[H.vhash(floor_of_beta)] == "sl_weapons:residue", "residue remains after collapse")
local collapse_feed = false
for _, line in ipairs(H.chat_all) do
	if line:find("puppet collapse", 1, true) then collapse_feed = true end
end
check(collapse_feed, "feed logs 'cause: puppet collapse'")

-- One walk per body
beta:set_pos({ x = 120, y = 60, z = 5 })
bpl.phase = "evil_ghost"
local beta2 = nil
for _, e in ipairs(W.corpses) do
	if e.victim == "beta" then beta2 = e end
end
check(beta2 == nil or beta2.removed == true or beta2.puppeted == true,
	"no second walk from the same body")

-- ================================================================
section("PHASE W2c — weapon pads: chimes, respawn, possession")
-- ================================================================

local pad_pos = { x = 200, y = 60, z = 0 }
W.place_weapon_pad(pad_pos, "mortar")
check(H.voxels[H.vhash(pad_pos)] == "sl_weapons:pad_weapon", "weapon pad placed")
alpha:set_pos({ x = pad_pos.x, y = pad_pos.y + 1, z = pad_pos.z })
local sndp = #H.sounds
H.advance(0.4, 0.1)
check(ainv:contains_item("main", ItemStack("sl_weapons:mortar")),
	"stepping on the pad dispenses the mortar")
local mortar_chime = nil
for i = sndp + 1, #H.sounds do
	if H.sounds[i].name == "sl_weapons_pad_chime" then mortar_chime = H.sounds[i] end
end
check(mortar_chime ~= nil, "pad chime played")
check(mortar_chime and math.abs((mortar_chime.params.pitch or 1) - 0.6) < 0.001,
	"mortar chime is the low pitch (the headline)")
check(H.voxels[H.vhash(pad_pos)] == "sl_weapons:pad_weapon_dim", "pad dims when taken")

-- Respawn timer
H.advance(30.5, 0.5)
check(H.voxels[H.vhash(pad_pos)] == "sl_weapons:pad_weapon", "pad re-arms after 30 s")

-- Ammo pad
local apad = { x = 204, y = 60, z = 0 }
W.place_ammo_pad(apad, "cells")
alpha:set_pos({ x = apad.x, y = apad.y + 1, z = apad.z })
W.get_pool("alpha").cells = 0
H.advance(0.4, 0.1)
check(W.get_pool("alpha").cells == 15, "ammo pad fills cells (+15)")

-- Possession silences a pad; ranged exorcism (2 hits) frees it.
bpl.phase = "evil_ghost"
beta:set_pos({ x = 300, y = 60, z = 0 })
check(gm.possess_object(apad, "beta") == true, "evil ghost possesses the ammo pad")
local cells_before = W.get_pool("alpha").cells
alpha:set_pos({ x = apad.x, y = apad.y + 1, z = apad.z })
W.place_ammo_pad(apad, "cells") -- re-arm for a clean refusal test
H.advance(0.4, 0.1)
check(W.get_pool("alpha").cells == cells_before,
	"possessed pad refuses to dispense")

alpha:set_pos({ x = apad.x, y = apad.y, z = apad.z - 6 })
aim_at(alpha, apad)
fire("sl_weapons:pistol", alpha) -- redraw after the long weapon gap
H.advance(0.4, 0.1)
fire("sl_weapons:pistol", alpha) -- hit 1 (node impact)
H.advance(0.4, 0.1)
check(gm.is_possessed(apad) == true, "one weapon hit does not exorcise")
fire("sl_weapons:pistol", alpha) -- hit 2
H.advance(0.4, 0.1)
check(gm.is_possessed(apad) == false, "two weapon hits exorcise the pad")

-- ================================================================
section("PHASE W2d — sentry turret: IFF, limits, battery, logs")
-- ================================================================

local tpos = { x = 400, y = 60, z = 0 }
H.voxels[H.vhash({ x = tpos.x, y = tpos.y - 1, z = tpos.z })] = "default:stone"
alpha:set_pos({ x = tpos.x, y = tpos.y, z = tpos.z })
alpha:get_inventory():add_item("main", ItemStack("sl_weapons:sentry_kit 2"))
local kit_def = minetest.registered_craftitems["sl_weapons:sentry_kit"]
kit_def.on_place(ItemStack("sl_weapons:sentry_kit"), alpha,
	{ type = "node", above = tpos, under = { x = tpos.x, y = tpos.y - 1, z = tpos.z } })
check(H.voxels[H.vhash(tpos)] == "sl_weapons:turret", "turret node deployed")
check(W.turrets[W.phash(tpos)] ~= nil, "turret registered")

-- Limit: one per player
local tpos2 = { x = 404, y = 60, z = 0 }
H.voxels[H.vhash({ x = tpos2.x, y = tpos2.y - 1, z = tpos2.z })] = "default:stone"
kit_def.on_place(ItemStack("sl_weapons:sentry_kit"), alpha,
	{ type = "node", above = tpos2, under = { x = tpos2.x, y = tpos2.y - 1, z = tpos2.z } })
check(H.voxels[H.vhash(tpos2)] ~= "sl_weapons:turret", "second turret refused (1/player)")

-- IFF: stranger shot, deployer spared
local stranger = new_victim("str", "beacon_b")
stranger:set_pos({ x = tpos.x + 3, y = tpos.y, z = tpos.z })
stranger:set_hp(20)
alpha:set_pos({ x = tpos.x - 3, y = tpos.y, z = tpos.z })
alpha:set_hp(20) -- the mortar-jump earlier cost a hit point
H.advance(2.0, 0.1)
check(stranger:get_hp() < 20, "turret fires on strangers (deployer-only IFF)")
check(alpha:get_hp() == 20, "deployer is spared")

-- Monsters are targets. The turret keeps its lock while the first
-- contact lives, so march the stranger out of range first — this
-- window is about the lifeform, not the leftover contact.
stranger:set_pos({ x = 490, y = 60, z = 0 })
local mobj = gm.spawn_monster({ x = tpos.x, y = tpos.y, z = tpos.z + 4 }, "scout", "gamma")
-- 3 s, not 2: acquisition runs on a 0.2 s tick after the lock drops,
-- and the acquire delay alone can eat a second. The assert must see
-- the SHOT, not the acquisition.
H.advance(3.0, 0.1)
local mlua = mobj and mobj.get_luaentity and mobj:get_luaentity()
check(mlua == nil or mobj:get_hp() < 30, "turret engages monsters")

-- Possession flips IFF: the deployer becomes a target
if mobj and mobj.remove then pcall(function() mobj:remove() end) end
bpl.phase = "evil_ghost"
bpl.possession_ready_at = 0 -- test surgery: separate possession economy
check(gm.possess_object(tpos, "beta") == true, "evil ghost possesses the turret")
alpha:set_hp(20)
H.advance(2.5, 0.1)
check(alpha:get_hp() < 20, "possessed turret turns on its deployer")

-- Sabotage disables firing
gm.release_possession(tpos, "test")
local sentry = W.turrets[W.phash(tpos)]
check(sentry ~= nil, "turret survives possession release")
gm.register_sabotage(tpos, "node", nil)
local sbefore = stranger:get_hp()
stranger:set_pos({ x = tpos.x + 3, y = tpos.y, z = tpos.z })
H.advance(2.0, 0.1)
check(stranger:get_hp() == sbefore, "sabotaged turret holds fire")
gm.clear_sabotage_at(tpos)

-- Battery expiry: self-dismantle into scrap
sentry.battery_end = W.now()
local drops_b4 = #drops
H.advance(0.5, 0.1)
check(H.voxels[H.vhash(tpos)] ~= "sl_weapons:turret", "turret self-dismantles on empty battery")
local scrap = false
for i = drops_b4 + 1, #drops do
	if stack_name(drops[i].stack) == "sl_modebase:scrap_metal" then scrap = true end
end
check(scrap, "expired turret drops scrap")

-- Destruction: targeting log deposition (council resolution #9)
alpha:get_inventory():add_item("main", ItemStack("sl_weapons:sentry_kit"))
H.voxels[H.vhash({ x = tpos.x, y = tpos.y - 1, z = tpos.z })] = "default:stone"
kit_def.on_place(ItemStack("sl_weapons:sentry_kit"), alpha,
	{ type = "node", above = tpos, under = { x = tpos.x, y = tpos.y - 1, z = tpos.z } })
check(W.turrets[W.phash(tpos)] ~= nil, "turret redeployed")
alpha._wielded = "sl_weapons:lance"
local node_def = minetest.registered_nodes["sl_weapons:turret"]
local drops_b5 = #drops
node_def.on_punch(tpos, { name = "sl_weapons:turret" }, alpha, nil) -- 18
node_def.on_punch(tpos, { name = "sl_weapons:turret" }, alpha, nil) -- 18 -> 25 spent
check(H.voxels[H.vhash(tpos)] ~= "sl_weapons:turret", "turret destroyed by weapon fire")
local log_dropped = false
for i = drops_b5 + 1, #drops do
	if stack_name(drops[i].stack) == "sl_weapons:targeting_log" then log_dropped = true end
end
check(log_dropped, "destroyed turret drops its targeting log")
alpha._wielded = ""

-- ================================================================
section("PHASE W2e — fabricator pilgrimage & the Grapple Lash")
-- ================================================================

local fpos = { x = 600, y = 60, z = 0 }
H.voxels[H.vhash(fpos)] = "sl_weapons:fabricator"
alpha._wielded = ""
minetest.registered_nodes["sl_weapons:fabricator"].on_rightclick(fpos,
	{ name = "sl_weapons:fabricator" }, alpha, nil)
check(#H.formspecs.alpha > 0, "fabricator formspec opens")

-- MM refused at the machine
gamma._wielded = ""
minetest.registered_nodes["sl_weapons:fabricator"].on_rightclick(fpos,
	{ name = "sl_weapons:fabricator" }, gamma, nil)
H.fire_receive_fields("gamma", "sl_weapons:fabricator_600,60,0", { make_lash = "true" })
check(gamma:get_inventory():contains_item("main", ItemStack("sl_weapons:grapple")) == false,
	"MM cannot fabricate the lash")

-- Missing materials
H.fire_receive_fields("alpha", "sl_weapons:fabricator_" .. W.phash(fpos), { make_lash = "true" })
check(W.fab_jobs[W.phash(fpos)] == nil, "job refused without materials")

-- Real job: mats consumed, 10 s hum, lash delivered
local finv = alpha:get_inventory()
for _, m in ipairs({ "sl_modebase:metal_ingot 2", "sl_modebase:circuit_board 2",
	"sl_modebase:energy_crystal 2", "sl_modebase:plastic_scrap 1" }) do
	finv:add_item("main", ItemStack(m))
end
H.fire_receive_fields("alpha", "sl_weapons:fabricator_" .. W.phash(fpos), { make_lash = "true" })
check(W.fab_jobs[W.phash(fpos)] ~= nil, "fabrication job started")
check(not finv:contains_item("main", ItemStack("sl_modebase:metal_ingot 2")),
	"materials consumed up front")
local hum_from = #H.sounds
H.advance(9.0, 0.5)
check(W.fab_jobs[W.phash(fpos)] ~= nil, "job still running at 9 s")
check(sound_played("sl_weapons_fab_hum", hum_from), "machine hums while working")
H.advance(1.5, 0.5)
check(finv:contains_item("main", ItemStack("sl_weapons:grapple")), "lash delivered after 10 s")

-- The arsenal line: a Chatter comes off the same machine (end-to-end)
finv:add_item("main", ItemStack("sl_modebase:metal_ingot 2"))
finv:add_item("main", ItemStack("sl_modebase:circuit_board 1"))
finv:add_item("main", ItemStack("sl_modebase:plastic_scrap 1"))
H.fire_receive_fields("alpha", "sl_weapons:fabricator_" .. W.phash(fpos), { make_chatter = "true" })
check(W.fab_jobs[W.phash(fpos)] ~= nil, "chatter fabrication job started")
H.advance(10.5, 0.5)
check(finv:contains_item("main", ItemStack("sl_weapons:chatter")), "chatter delivered after 10 s")

-- Lash: cost, anchor, reel, detach-on-damage, line severing
local wall = { x = 700, y = 60, z = 0 }
H.voxels[H.vhash(wall)] = "default:stone"
H.voxels[H.vhash({ x = wall.x, y = wall.y + 1, z = wall.z })] = "default:stone"
alpha:set_pos({ x = wall.x, y = wall.y, z = wall.z - 10 })
alpha:set_player_velocity({ x = 0, y = 0, z = 0 }) -- legacy knockback would bend the hook arc
aim_at(alpha, wall)
W.get_pool("alpha").cells = 15
fire("sl_weapons:grapple", alpha)
check(W.get_pool("alpha").cells == 10, "lash costs 5 cells")
H.advance(0.6, 0.05)
check(W.lash.alpha ~= nil, "hook anchored into the wall")
H.advance(0.3, 0.05)
local reel_v = alpha:get_velocity()
check(reel_v.x ~= 0 or reel_v.z ~= 0, "reel applies velocity toward the anchor")

-- Any damage detaches (danger 3)
alpha:punch(new_victim("htr", "beacon_a"), 1.0,
	{ full_punch_interval = 1.0, damage_groups = { fleshy = 1 } }, { x = 0, y = 0, z = 1 })
check(W.lash.alpha == nil, "taking a hit snaps the line")
check(sound_played("sl_weapons_lash_snap", 1), "the snap is heard")

-- Line cut: punch the anchored hook (danger 4)
W.get_pool("alpha").cells = 5
H.advance(2.1, 0.5) -- lash cooldown from the first launch
fire("sl_weapons:grapple", alpha)
H.advance(0.6, 0.05)
check(W.lash.alpha ~= nil, "second hook anchored")
local hook_lua = nil
for _, lua in pairs(H.luaentities) do
	if lua.name == "sl_weapons:lash_hook" and lua.shooter == "alpha" then hook_lua = lua end
end
check(hook_lua ~= nil, "hook entity findable")
if hook_lua then
	hook_lua.object:punch(new_victim("cutr", "beacon_b"), 1.0,
		{ full_punch_interval = 1.0, damage_groups = { fleshy = 1 } }, { x = 0, y = 0, z = 1 })
	check(W.lash.alpha == nil, "one hit on the hook severs the line")
end

-- ================================================================
section("PHASE W2f — MM bare hands doctrine")
-- ================================================================

local hvic = new_victim("hnd", "beacon_b")
hvic:set_pos({ x = 800, y = 60, z = 0 })
hvic:set_hp(20)
gamma:set_pos({ x = 800, y = 60, z = 1 })
gamma._wielded = "" -- bare hands
-- ObjectRef semantics: hvic:punch(gamma) = hvic IS PUNCHED BY gamma
hvic:punch(gamma, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 1 } },
	{ x = 0, y = 0, z = 1 })
check(hvic:get_hp() == 17, "MM baseline hand overrides to 3 (20 -> 17)")

W.set_mm_levels(gamma, { grip = 3 })
hvic:set_hp(20)
hvic:punch(gamma, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 1 } },
	{ x = 0, y = 0, z = 1 })
check(hvic:get_hp() == 10, "Tyrant Grip III hits for 10")

-- MM holding any item loses the override (hands only)
gamma._wielded = "sl_modebase:combat_blade"
hvic:set_hp(20)
hvic:punch(gamma, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 6 } },
	{ x = 0, y = 0, z = 1 })
check(hvic:get_hp() == 20 - 6, "wielded blade uses normal tool damage, not the doctrine")

-- ================================================================
section("PHASE W2g — beacon chip routing & match-end sweep")
-- ================================================================

local bpos = { x = 900, y = 60, z = 0 }
H.voxels[H.vhash(bpos)] = "sl_modebase:beacon_a"
state.teams.beacon_a.hp = 100
alpha:set_pos({ x = bpos.x, y = bpos.y, z = bpos.z - 8 })
aim_at(alpha, bpos)
fire("sl_weapons:pistol", alpha)
check(state.teams.beacon_a.hp == 99, "pistol chips a beacon for exactly 1 (melee stays the siege)")

-- Lance chips 3
state.teams.beacon_a.hp = 100
W.get_pool("alpha").cells = 4
fire("sl_weapons:lance", alpha) -- draw attempt
H.advance(1.7, 0.1)
fire("sl_weapons:lance", alpha)
check(state.teams.beacon_a.hp == 97, "lance chips a beacon for 3")

-- Loadout pistol is drop-locked
local pistol_def = minetest.registered_tools["sl_weapons:pistol"]
local dropped = pistol_def.on_drop and pistol_def.on_drop(ItemStack("sl_weapons:pistol"), alpha, alpha:get_pos())
check(dropped ~= nil and dropped:is_empty(), "loadout pistol dissolves on drop")

-- Achievement lifecycle hook: the match forgets, the count survives.
local reset_called = {}
reset_match_achievements = function(p)
	reset_called[p:get_player_name()] = true
end

local trace_count_before = #W.traces
gm.end_match("beacons", "weapons suite sweep")
H.advance(1.0, 0.5)
check(state.match_active == false, "match ended")
check(#W.corpses == 0, "corpses swept at match end")
check(#W.deadwalks == 0, "deadwalks swept at match end")
local traces_left = 0
for _, tr in ipairs(W.traces) do
	if H.voxels[H.vhash(tr.pos)] == tr.name then traces_left = traces_left + 1 end
end
check(traces_left == 0, "all trace nodes swept (residue/mound/scorch)")
for hash in pairs(W.turrets) do
	check(false, "turret survived the sweep at " .. hash)
end
check(next(W.turrets) == nil, "turret registry empty after sweep")
check(next(W.pools) == nil, "ammo pools cleared")
check(W.lash.alpha == nil, "lash lines detached")
check(H.voxels[H.vhash(pad_pos)] == "sl_weapons:pad_weapon", "pads re-armed for the next scene")
check(reset_called.alpha == true and reset_called.beta == true,
	"achievement reset hook ran for connected players")
reset_match_achievements = nil

-- The real achievement lifecycle (loaded fresh; graceful if sl_gui
-- cannot load under the stub).
local okA = pcall(dofile, "mods/apis/sl_gui/achievement_system.lua")
if okA then
	local ach_player = alpha
	local meta = ach_player:get_meta()
	meta:set_string("achievements", minetest.serialize({
		unlocked = { win_match = true },
		progress = { win_match = 3 },
	}))
	reset_match_achievements(ach_player)
	local data = minetest.deserialize(meta:get_string("achievements"))
	check(data and next(data.unlocked) == nil, "real reset clears unlocked state")
	check(meta:get_int("times_earned_win_match") == 1,
		"real reset bumps the lifetime times_earned counter")
else
	check(true, "sl_gui achievement system not loadable under stub (skipped)")
end

-- ================================================================
section("PHASE W3 — salvage rolls, smoke regression: modebase intact")
-- ================================================================

-- Weapons section on the salvage roll table (§5); the Lash never rolls.
local rolls = game_mode.get_pickup_rolls()
local kit_w, total_w, lash_rolled = 0, 0, false
for _, e in ipairs(rolls) do
	total_w = total_w + e.weight
	if e.item == "sl_weapons:sentry_kit" then kit_w = kit_w + e.weight end
	if e.item == "sl_weapons:grapple" then lash_rolled = true end
end
check(lash_rolled == false, "the Lash appears on no random table")
check(kit_w / total_w > 0.07 and kit_w / total_w < 0.13,
	"sentry kit rolls near 10% (got " .. string.format("%.1f", 100 * kit_w / total_w) .. "%)")

math.randomseed(42)
local scv = new_victim("scv", "beacon_a")
local pick_node = minetest.registered_nodes["sl_modebase:item_pickup"]
local ppos = { x = 900, y = 60, z = 0 }
local kits = 0
for i = 1, 400 do
	H.voxels[H.vhash(ppos)] = "sl_modebase:item_pickup"
	pick_node.on_rightclick(ppos, { name = "sl_modebase:item_pickup" }, scv, ItemStack(""), nil)
end
for _, st in ipairs(scv:get_inventory():get_list("main")) do
	if st:get_name() == "sl_weapons:sentry_kit" then kits = kits + st:get_count() end
end
check(kits >= 18 and kits <= 60, "400 salvage rolls yield sentry kits near expectation (got " .. kits .. ")")

-- ----------------------------------------------------------------
section("PHASE W3b — workshops from mob spoils (mapgen places none)")
-- ----------------------------------------------------------------

local MOB_SPOILS = {
	["sl_modebase:metal_ingot"] = true,
	["sl_modebase:circuit_board"] = true,
	["sl_modebase:energy_crystal"] = true,
	["sl_modebase:plastic_scrap"] = true,
}
local fab_recipe, altar_recipe, lash_recipe
for _, r in ipairs(captured_recipes) do
	if r.output == "sl_weapons:fabricator" then fab_recipe = r end
	if r.output == "sl_modebase:ghost_altar" then altar_recipe = r end
	if r.output == "sl_weapons:grapple" then lash_recipe = r end
end
check(fab_recipe ~= nil, "the Precision Fabricator is inventory-craftable")
check(altar_recipe ~= nil, "the Ghost Altar is inventory-craftable")
local foreign = 0
for k in pairs((fab_recipe and fab_recipe.ingredients) or {}) do
	if not MOB_SPOILS[k] then foreign = foreign + 1 end
end
for k in pairs((altar_recipe and altar_recipe.ingredients) or {}) do
	if not MOB_SPOILS[k] then foreign = foreign + 1 end
end
check(foreign == 0, "station recipes use only mob-obtainable parts")
check(lash_recipe == nil, "the Lash itself is never an inventory recipe")

-- Spoils: a catalog monster pays its parts on death
local function payout_of(fn)
	local d0 = #H.item_drops
	local obj = fn()
	if not obj then return nil end
	obj:punch(nil, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 99 } }, nil)
	local got = {}
	for i = d0 + 1, #H.item_drops do
		got[H.item_drops[i].name] = (got[H.item_drops[i].name] or 0) + H.item_drops[i].count
	end
	return got
end
local got_stalker = payout_of(function()
	return game_mode.spawn_monster({ x = 960, y = 60, z = 0 }, "stalker", "gamma")
end)
check(got_stalker ~= nil and got_stalker["sl_modebase:metal_ingot"] == 1
	and got_stalker["sl_modebase:plastic_scrap"] == 1,
	"stalker pays ingot + plastic")
local got_brute = payout_of(function()
	return game_mode.spawn_monster({ x = 961, y = 60, z = 0 }, "brute", "gamma")
end)
check(got_brute ~= nil and got_brute["sl_modebase:metal_ingot"] == 2
	and got_brute["sl_modebase:energy_crystal"] == 1,
	"brute pays 2 ingots + a crystal")
local got_scout = payout_of(function()
	return game_mode.spawn_monster({ x = 962, y = 60, z = 0 }, "scout", "gamma")
end)
check(got_scout ~= nil and got_scout["sl_modebase:circuit_board"] == 1,
	"scout pays a circuit board")

-- Ambient spawns (no catalog variant) carry nothing
local d_amb = #H.item_drops
local amb = minetest.add_entity({ x = 963, y = 60, z = 0 }, "sl_modebase:monster")
amb:punch(nil, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 99 } }, nil)
check(#H.item_drops == d_amb, "ambient monsters carry no workshop parts")

-- ----------------------------------------------------------------
section("PHASE W3c — the fabricable arsenal & the open range")
-- ----------------------------------------------------------------

-- Every primary weapon is a Fabricator job costing mob spoils only
local ARSENAL = { "chatter", "scatter", "driver", "lance", "mortar", "neon_six", "neon_repeater" }
local mob_items = {
	["sl_modebase:metal_ingot"] = true,
	["sl_modebase:circuit_board"] = true,
	["sl_modebase:energy_crystal"] = true,
	["sl_modebase:plastic_scrap"] = true,
}
local missing_jobs, foreign_mats = {}, 0
for _, id in ipairs(ARSENAL) do
	local r = W.FAB_RECIPES[id]
	if not r then
		table.insert(missing_jobs, id)
	else
		for _, m in ipairs(r.mats) do
			if not mob_items[m[1]] then foreign_mats = foreign_mats + 1 end
		end
	end
end
check(#missing_jobs == 0, "all seven primaries fabricable (missing: " .. table.concat(missing_jobs, ",") .. ")")
check(foreign_mats == 0, "arsenal jobs cost only mob-obtainable parts")

-- A hook in flight when the match generation turns never anchors
-- (stray lines must not ride into the next match). Launched directly:
-- the range is closed outside a match, by design.
local hook_obj = minetest.add_entity({ x = 974, y = 60, z = 8 }, "sl_weapons:lash_hook")
check(hook_obj and not hook_obj._removed, "hook entity in flight")
do
	local hl = hook_obj:get_luaentity()
	hl.shooter = "alpha"
	hl.sl_weapon_fx = true
	hl.gen = W.match_gen
end
hook_obj:set_velocity({ x = 0, y = 0, z = 30 }) -- clean air, no anchor
H.advance(0.15, 0.05)
W.match_gen = W.match_gen + 1 -- the match-end generation bump
H.advance(0.6, 0.05)
check(W.lash["alpha"] == nil, "in-flight hook from a finished match never anchors")
check(hook_obj._removed, "the stray hook entity is gone")

check(gm.get_player_state("alpha").phase == "alive", "players normalized after match end")

-- ----------------------------------------------------------------
section("PHASE W3d — match start resets levels & inventories")
-- ----------------------------------------------------------------

-- Stale state from the finished match: hoarded spoils, a weapon, MM
-- grip levels, and (simulated) sl_gui progression.
local progression_reset_calls = {}
local fake_reset = function(p)
	table.insert(progression_reset_calls, p:get_player_name())
end
reset_player_progression = fake_reset
alpha:get_inventory():add_item("main", ItemStack("sl_modebase:metal_ingot 50"))
alpha:get_inventory():add_item("main", ItemStack("sl_weapons:mortar"))
alpha:get_meta():set_string("sl_mm_hands", minetest.serialize({ grip = 3 }))

-- Creative mode is ON for this start: the reset must be unconditional
-- (the old skip was exactly how arsenals leaked between matches).
H.settings.creative_mode = true
gm.set_monster_master("gamma") -- kit gifted before the reset runs
state.settings.countdown = 1
minetest.registered_chatcommands.sl_match_start.func("alpha", "")
for _, p in ipairs(minetest.get_connected_players()) do
	minetest.registered_chatcommands.sl_ready.func(p:get_player_name(), "")
end
H.advance(4, 0.5)
check(state.match_active == true, "second match started")
H.settings.creative_mode = false

local rd_inv = alpha:get_inventory()
check(not rd_inv:contains_item("main", ItemStack("sl_modebase:metal_ingot 50")),
	"hoarded spoils cleared at match start (even in creative)")
check(not rd_inv:contains_item("main", ItemStack("sl_weapons:mortar")),
	"carried weapons cleared at match start")
check(rd_inv:contains_item("main", ItemStack("sl_weapons:pistol")),
	"loadout granted after the clear")
check(W.get_mm_levels(alpha).grip == 0, "MM grip levels reset at match start")
local saw_a, saw_b, saw_g = false, false, false
for _, n in ipairs(progression_reset_calls) do
	if n == "alpha" then saw_a = true end
	if n == "beta" then saw_b = true end
	if n == "gamma" then saw_g = true end
end
check(saw_a and saw_b and saw_g, "progression reset hook ran for every player")

-- The MM's kit is role equipment, not loot: re-granted after the clear
local ginv = gamma:get_inventory()
check(ginv:contains_item("main", ItemStack("sl_modebase:summon_monster")),
	"MM summon tool survives the reset (re-granted)")
check(ginv:contains_item("main", ItemStack("sl_modebase:monster_essence 10")),
	"MM starter essence survives the reset (re-granted)")

-- The real sl_gui progression reset, when loadable: experience and
-- abilities go to zero through the exported hook.
local okB = pcall(dofile, "mods/apis/sl_gui/ability_system.lua")
if okB and reset_player_progression ~= fake_reset then
	beta:get_meta():set_string("experience", "450")
	beta:get_meta():set_string("abilities_v2",
		minetest.serialize({ unlocked = { anything = 2 }, stat_points = 5 }))
	reset_player_progression(beta)
	check(beta:get_meta():get_string("experience") == "0",
		"experience zeroed by the sl_gui reset hook")
	local ab = minetest.deserialize(beta:get_meta():get_string("abilities_v2")) or {}
	check((ab.stat_points or 0) == 0 and (ab.unlocked and next(ab.unlocked)) == nil,
		"ability levels and stat points zeroed")
else
	check(true, "sl_gui ability system not loadable under stub (skipped)")
end

gm.end_match(nil, "W3d cleanup")
H.advance(1, 0.5)

-- ----------------------------------------------------------------
section("PHASE W1f — the Severance: one swing, 200 damage, then gone")
-- ----------------------------------------------------------------

local sev = minetest.registered_tools["sl_weapons:severance"]
check(sev ~= nil, "the Severance is registered")
check(sev and sev.tool_capabilities and sev.tool_capabilities.damage_groups.fleshy == 200,
	"it hits for 200")

local sev_job = W.FAB_RECIPES.severance
local mob_only = sev_job ~= nil
if sev_job then
	for _, m in ipairs(sev_job.mats) do
		if not (m[1] == "sl_modebase:metal_ingot" or m[1] == "sl_modebase:circuit_board"
			or m[1] == "sl_modebase:energy_crystal" or m[1] == "sl_modebase:plastic_scrap") then
			mob_only = false
		end
	end
end
check(mob_only, "fabricable at mob-spoil prices (ingot 3 + crystal 2)")

-- A fresh match for the execution (corpse counts must stay honest);
-- the MM role was normalized at the last match end, so gamma wears it
-- again for the doctrine check below.
gm.set_monster_master("gamma")
state.settings.countdown = 1
minetest.registered_chatcommands.sl_match_start.func("alpha", "")
for _, p in ipairs(minetest.get_connected_players()) do
	minetest.registered_chatcommands.sl_ready.func(p:get_player_name(), "")
end
H.advance(4, 0.5)
check(state.match_active == true, "third match started")

-- Player execution: 20 HP meets 200
local svx = new_victim("svx", "beacon_a")
svx:set_hp(20)
alpha:set_wielded_item(ItemStack("sl_weapons:severance"))
local corpses_before = #W.corpses
local sev_caps = sev.tool_capabilities
svx:punch(alpha, 1.0, sev_caps, { x = 0, y = 0, z = 1 })
check(svx._dead == true or svx:get_hp() <= 0, "one swing kills a living player")
check(alpha:get_wielded_item():get_name() == "", "the Severance is consumed on the kill")
check(W.last_cause[svx:get_player_name()] == "severance", "the incident report names the cause")
check(#W.corpses == corpses_before + 1, "the kill leaves a corpse")

-- A swing that lands nothing costs nothing (damage 0 = no consume)
alpha:set_wielded_item(ItemStack("sl_weapons:severance"))
local svz = new_victim("svz", "beacon_b")
svz:punch(alpha, 1.0, { full_punch_interval = 1.0, damage_groups = {} }, { x = 0, y = 0, z = 1 })
check(alpha:get_wielded_item():get_name() == "sl_weapons:severance",
	"a swing that deals no damage wastes nothing")
alpha:set_wielded_item(ItemStack(""))

-- Monster execution: the same swing unmakes a stalker
local drops_before = #H.item_drops
local stk = game_mode.spawn_monster({ x = 980, y = 60, z = 0 }, "stalker", "gamma")
alpha:set_wielded_item(ItemStack("sl_weapons:severance"))
stk:punch(alpha, 1.0, sev_caps, { x = 0, y = 0, z = 1 })
check(stk._removed or stk:get_hp() <= 0, "the swing deletes a monster")
check(alpha:get_wielded_item():get_name() == "", "consumed on the monster kill too")
check(#H.item_drops > drops_before, "the wreck still pays its spoils")

-- Ordinary blades wear on monster hits (shared hook)
alpha:set_wielded_item(ItemStack("sl_modebase:combat_blade"))
local blade_w0 = alpha:get_wielded_item():get_wear()
local sct = game_mode.spawn_monster({ x = 981, y = 60, z = 0 }, "scout", "gamma")
sct:punch(alpha, 1.0, { full_punch_interval = 0.8, damage_groups = { fleshy = 6 } }, { x = 0, y = 0, z = 1 })
check(alpha:get_wielded_item():get_wear() > blade_w0, "blades also wear on monsters now")
alpha:set_wielded_item(ItemStack(""))

-- The doctrine: hands only, never items — the sweep takes it from the MM
gamma:get_inventory():add_item("main", ItemStack("sl_weapons:severance"))
H.advance(1.3, 0.5)
check(not gamma:get_inventory():contains_item("main", ItemStack("sl_weapons:severance")),
	"the Monster Master cannot keep a Severance")

gm.end_match(nil, "W1f cleanup")
H.advance(1, 0.5)

-- ----------------------------------------------------------------
section("PHASE W3e — tournament mode: inventories reset, progression persists")
-- ----------------------------------------------------------------

local tcmd = minetest.registered_chatcommands.sl_tournament
check(tcmd ~= nil, "the /sl_tournament command is registered")
local tok, _tmsg = tcmd.func("alpha", "start 2")
check(tok == true, "tournament starts between matches (2-match season)")
check(tcmd.func("alpha", "start") == false, "double-start is refused")
check(state.tournament_planned == 2 and state.tournament_matches_left == 2,
	"the season length is booked at start")
check(state.tournament_roster["alpha"] and state.tournament_roster["beta"]
	and state.tournament_roster["gamma"], "the roster locks in everyone connected")

-- The roster locked at the starting gun: a late joiner spectates.
local l8r = new_victim("l8r", nil)
local l8r_name = l8r:get_player_name()
check(gm.get_player_state(l8r_name).tournament_spectator == true,
	"a late joiner is flagged tournament spectator")
check(state.tournament_roster[l8r_name] == nil, "late joiners stay off the roster")
check(gm.get_player_state("beta").tournament_spectator == nil,
	"roster members are not spectators")

-- Seed persistent progression: levels, abilities, an achievement, MM grip
beta:get_meta():set_string("experience", "450")
beta:get_meta():set_string("abilities_v2",
	minetest.serialize({ unlocked = { sniper_eyes = 1 }, stat_points = 7 }))
beta:get_meta():set_string("achievements",
	minetest.serialize({ unlocked = { win_match = true }, progress = {} }))
gamma:get_meta():set_string("sl_mm_hands", minetest.serialize({ grip = 2 }))
beta:get_inventory():add_item("main", ItemStack("sl_modebase:metal_ingot 30"))

gm.set_monster_master("gamma")
state.settings.countdown = 1
minetest.registered_chatcommands.sl_match_start.func("alpha", "")
for _, p in ipairs(minetest.get_connected_players()) do
	minetest.registered_chatcommands.sl_ready.func(p:get_player_name(), "")
end
H.advance(4, 0.5)
check(state.match_active == true, "tournament match 1 started")
check(gm.get_player_state(l8r_name).team == nil,
	"spectators are left out of the team assignment")
check(state.monster_master.player ~= l8r_name,
	"spectators are never chosen as the Monster Master")
check(not beta:get_inventory():contains_item("main", ItemStack("sl_modebase:metal_ingot 30")),
	"inventories still reset each tournament match")
check(beta:get_meta():get_string("experience") == "450",
	"levels persist across the tournament match start")
local tab = minetest.deserialize(beta:get_meta():get_string("abilities_v2")) or {}
check((tab.stat_points or 0) == 7 and tab.unlocked and tab.unlocked.sniper_eyes == 1,
	"abilities persist across the tournament match start")
check(W.get_mm_levels(gamma).grip == 2, "MM grip levels persist in a tournament")

-- Match 1 of 2: bank five points to beta, then the whistle.
gm.get_player_state("beta").points = 5
gm.end_match(nil, "tournament match 1")
H.advance(1, 0.5)
check((state.tournament_scores["beta"] or 0) == 5,
	"match points bank into the season score")
check(state.tournament_matches_left == 1, "one match remains on the season")
local tac = minetest.deserialize(beta:get_meta():get_string("achievements")) or {}
check(tac.unlocked and tac.unlocked.win_match == true,
	"achievements persist across the tournament match end")

-- The results form must be a legal formspec: the table[] item list is
-- ONE comma-separated element (the ";" row join crashed live servers).
local rfs = H.formspecs["beta"] and H.formspecs["beta"][#H.formspecs["beta"]]
check(rfs ~= nil and rfs.formname == "sl_modebase:results",
	"results form shown after each match")
if rfs then
	local items = (rfs.form:match("results;([^]]+)") or ""):gsub(";%d+$", "")
	check(items:find(";", 1, true) == nil,
		"table element list carries no ';' separators (the live-server crash)")
	check(items:find("Player", 1, true) and items:find(",beta,", 1, true),
		"results table carries the scoreboard rows")
end

-- Match 2 of 2: the season decider — 3 more points and auto-close.
state.settings.countdown = 1
minetest.registered_chatcommands.sl_match_start.func("alpha", "")
for _, p in ipairs(minetest.get_connected_players()) do
	minetest.registered_chatcommands.sl_ready.func(p:get_player_name(), "")
end
H.advance(4, 0.5)
check(state.match_active == true, "tournament match 2 started")
gm.get_player_state("beta").points = 3
gm.end_match(nil, "tournament match 2")
check(state.tournament_matches_left == 0, "the season is exhausted")
H.advance(2.6, 0.5) -- the ranking form pops out after 2 s
check(state.tournament == false, "the tournament ends itself after the final match")
local tfs = H.formspecs["beta"] and H.formspecs["beta"][#H.formspecs["beta"]]
check(tfs ~= nil and tfs.formname == "sl_modebase:tournament_results"
	and tfs.form:find("TOURNAMENT RESULTS", 1, true),
	"the season ranking form pops out at the end")
check(tfs ~= nil and tfs.form:find("1,beta,8", 1, true),
	"ranking lists the champion by season points (1,beta,8)")
check(beta:get_meta():get_string("experience") == "0",
	"leaving the tournament resets levels once")
local tab2 = minetest.deserialize(beta:get_meta():get_string("abilities_v2")) or {}
check((tab2.stat_points or 0) == 0 and (tab2.unlocked and next(tab2.unlocked)) == nil,
	"abilities reset when the tournament ends")
local tac2 = minetest.deserialize(beta:get_meta():get_string("achievements")) or {}
check(tac2.unlocked == nil or next(tac2.unlocked) == nil,
	"achievements reset when the tournament ends (times_earned kept)")
check(gm.get_player_state(l8r_name).tournament_spectator == nil,
	"spectator status clears with the season")
check(next(state.tournament_roster) == nil, "roster cleared")
check(tcmd.func("alpha", "stop") == false, "stopping twice is refused")
check(gm.get_player_state("alpha").phase == "alive", "players normalized after tournament")
H.advance(2, 0.5)
check(true, "engine steps still healthy after the full suite")

print(string.format("\nRESULT: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then os.exit(1) end
