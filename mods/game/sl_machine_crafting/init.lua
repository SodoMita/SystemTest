-- ================================================================
-- System Looting — Machine crafting
-- ================================================================
-- Design ruling (MASTER_DESIGN_FULL §6.5 / §6.10, MATCH_LOOP_SPEC
-- "Crafting model"):
--
--   Placeable, structural, deployable or world-affecting outputs are
--   NEVER produced by personal inventory crafting. They come from a
--   machine: the machine owns the recipe, the input slots, the
--   processing time and the risk.
--
-- The inventory crafting UI (sl_gui/crafting_system.lua) enforces its
-- half of that rule by refusing any recipe whose output is a
-- registered NODE. This mod is the other half: the Objective Forge
-- runs exactly those recipes — the same predicate, so the two sides
-- can never drift apart and no recipe is ever declared twice.
--
-- THE OBJECTIVE FORGE (§6.10 B: "1 per map, neutral, loud")
--   * one per arena, placed by the map system at the `forge` anchor
--     (neutral ground — both teams have to walk to it);
--   * it is LOUD: starting a job announces the job and the forge's
--     position to every player, so the run is contestable;
--   * processing time (sl_machine.forge_time, default 20 s) and a
--     single job at a time: the queue is the contention;
--   * risk: the charge is consumed up front. A job abandoned by the
--     end of the match, or a forge taken over by an evil ghost,
--     loses the charge.
--   * only beacon-team crew may operate it, and only during a match.
--
-- The Forge is deliberately ONE station in this turn, not the full
-- five-station plan of §6.10 B. The two-station split
-- (Assembly Station -> core_frame -> Objective Forge -> objective_core)
-- needs an intermediate item set (metal_ingot / circuit_board /
-- energy_crystal / hardened_plate / reinforced_glass) that does not
-- exist as content yet; until it does, every machine-gated recipe
-- runs here. See docs/INTEGRATION.md §4 (deferred list).
-- ================================================================

local S = minetest.get_translator("sl_machine_crafting")

-- Machine crafting registry (global so other mods and tests can read
-- the resolved machine recipe list).
sl_machine = rawget(_G, "sl_machine") or {}
_G.sl_machine = sl_machine

sl_machine.modname = "sl_machine_crafting"
sl_machine.FORGE_NAME = "sl_machine_crafting:objective_forge"

-- Node-timer tick. The job clock is stored in node meta so a server
-- restart mid-job degrades to "the charge is lost" rather than to a
-- phantom timer.
local TICK = 1.0
local DEFAULT_FORGE_TIME = 20

local function setting_int(key, default)
	local n = tonumber(minetest.settings and minetest.settings:get(key))
	if not n then return default end
	return math.max(0, math.floor(n))
end

-- Processing time of one forge run, in seconds.
function sl_machine.forge_time()
	return math.max(1, setting_int("sl_machine.forge_time", DEFAULT_FORGE_TIME))
end

-- ----------------------------------------------------------------
-- Recipe source of truth
-- ----------------------------------------------------------------
-- Machine-eligible = every registered crafting recipe whose output is
-- a registered NODE — byte-for-byte the predicate the inventory UI
-- uses to refuse a craft. One rule, two sides, no duplication.
local function is_node_item(name)
	return minetest.registered_nodes[name] ~= nil
end
sl_machine.is_machine_output = is_node_item

function sl_machine.get_recipes()
	local out = {}
	local all = (type(get_crafting_recipes) == "function") and get_crafting_recipes() or nil
	if not all then return out end
	for id, recipe in ipairs(all) do
		if recipe and recipe.output and is_node_item(recipe.output) then
			table.insert(out, { id = id, recipe = recipe })
		end
	end
	return out
end

local function recipe_by_id(id)
	for _, entry in ipairs(sl_machine.get_recipes()) do
		if entry.id == id then return entry end
	end
	return nil
end

local function ingredients_text(recipe)
	local parts = {}
	for item, count in pairs(recipe.ingredients) do
		local def = minetest.registered_items[item]
		parts[#parts + 1] = string.format("%s x%d",
			(def and def.description) or item, count)
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- ----------------------------------------------------------------
-- Job state (node meta)
-- ----------------------------------------------------------------
--   job_output : itemstring of the running job, "" when idle
--   job_count  : output count
--   job_desc   : human-readable description (for the HUD/broadcast)
--   job_left   : seconds remaining (float, stored as a string)
--   job_total  : seconds the run takes
--   job_by     : player who started it
local function job_running(meta)
	return meta:get_string("job_output") ~= ""
end

local function clear_job(meta)
	meta:set_string("job_output", "")
	meta:set_string("job_count", "")
	meta:set_string("job_desc", "")
	meta:set_string("job_left", "")
	meta:set_string("job_total", "")
	meta:set_string("job_by", "")
end

local function infotext(meta)
	if job_running(meta) then
		return S("Objective Forge — running: @1 (@2s left)",
			meta:get_string("job_desc"), tostring(math.ceil(tonumber(meta:get_string("job_left")) or 0)))
	end
	return S("Objective Forge — idle")
end

local function refresh_infotext(pos, meta)
	meta = meta or minetest.get_meta(pos)
	meta:set_string("infotext", infotext(meta))
end

-- Machine crafting is match-bound: outside a match the forge is inert
-- and any in-flight charge is forfeit (the risk half of the design).
local function match_live()
	return game_mode and game_mode.state and game_mode.state.match_active
end

-- Who may run the forge: living crew on a beacon team, during a
-- match. The Monster Master and ghosts are explicitly refused.
local function can_operate(name)
	if not game_mode then return false, S("Machine crafting is unavailable.") end
	if not match_live() then return false, S("The forge is cold. There is no active match.") end
	local st = game_mode.state.players and game_mode.state.players[name]
	if not st then return false, S("You are not in this match.") end
	if not game_mode.is_beacon_team(st.team) then
		return false, S("Only beacon-team crew can run the Objective Forge.")
	end
	return true
end

local function stack_max_of(name)
	local def = minetest.registered_items[name] or minetest.registered_nodes[name]
	local n = def and tonumber(def.stack_max)
	if n and n > 0 then return n end
	return 99
end

-- Capacity of the output list for one item type.
local function output_room(inv, name, smax)
	local room = 0
	for i = 1, inv:get_size("dst") do
		local s = inv:get_stack("dst", i)
		if s:is_empty() then
			room = room + smax
		elseif s:get_name() == name then
			room = room + math.max(0, smax - s:get_count())
		end
	end
	return room
end

-- Pay out into the output slot, spilling whatever does not fit at the
-- foot of the machine. The capacity is computed HERE rather than read
-- off add_item's return value: the headless stub's add_item always
-- succeeds, and "silently deleted" is the one failure mode a
-- win-condition item must never have.
local function put_or_spill(pos, inv, stack)
	local name, count = stack:get_name(), stack:get_count()
	if name == "" or count <= 0 then return 0 end
	local smax = stack_max_of(name)
	local fits = math.min(count, output_room(inv, name, smax))
	if fits > 0 then
		inv:add_item("dst", ItemStack(name .. " " .. fits))
	end
	local spill = count - fits
	if spill > 0 then
		minetest.add_item({ x = pos.x, y = pos.y + 1, z = pos.z },
			ItemStack(name .. " " .. spill))
	end
	return spill
end
sl_machine.put_or_spill = put_or_spill

local function finish_job(pos, meta)
	meta = meta or minetest.get_meta(pos)
	local output = meta:get_string("job_output")
	if output == "" then return end
	local count = math.max(1, math.floor(tonumber(meta:get_string("job_count")) or 1))
	local desc = meta:get_string("job_desc")
	local by = meta:get_string("job_by")
	clear_job(meta)

	local inv = meta:get_inventory()
	inv:set_size("src", 8)
	inv:set_size("dst", 4)
	local spilled = put_or_spill(pos, inv, ItemStack(output .. " " .. count))

	-- Essence ruling §13.3 rule 2: named crafts credit the MM pool on
	-- completion (the Objective Core is the named +3 craft). The hook
	-- scales with the output count and is inert without sl_modebase.
	if game_mode and game_mode.on_craft_essence then
		game_mode.on_craft_essence(output, count)
	end

	-- LOUD: the run finishing is public too.
	if game_mode and game_mode.broadcast then
		game_mode.broadcast(S("The Objective Forge finishes: @1.", desc ~= "" and desc or output))
	end
	if by ~= "" then
		minetest.chat_send_player(by,
			S("Your forge run is done — collect it from the output slot."))
	end

	-- Output slot full: the work is not lost, it is spilled at the
	-- forge for anyone to grab (more drama, never a silent delete).
	if spilled and spilled > 0 then
		if game_mode and game_mode.broadcast then
			game_mode.broadcast(S("The forge output is full — @1 spills onto the floor.",
				(desc ~= "" and desc) or output))
		end
	end

	refresh_infotext(pos, meta)
end

-- Abandon a running job without paying out. Called when the match
-- ends (or the world forgets the forge) — the charge is forfeit.
local function abandon_job(pos, meta, reason)
	meta = meta or minetest.get_meta(pos)
	if not job_running(meta) then return end
	local desc = meta:get_string("job_desc")
	clear_job(meta)
	if minetest.get_node_timer then
		minetest.get_node_timer(pos):stop()
	end
	refresh_infotext(pos, meta)
	if game_mode and game_mode.broadcast and reason then
		game_mode.broadcast(reason)
	end
	return desc
end
sl_machine.abandon_job = abandon_job

local function start_job(pos, entry, name)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("src", 8)
	inv:set_size("dst", 4)

	if not entry or not entry.recipe then
		return false, S("The forge does not know that recipe.")
	end
	if job_running(meta) then
		return false, S("The forge is already running @1.", meta:get_string("job_desc"))
	end
	for item, count in pairs(entry.recipe.ingredients) do
		if not inv:contains_item("src", ItemStack(item .. " " .. count)) then
			return false, S("Not enough charge in the input slots for @1.",
				entry.recipe.description or entry.recipe.output)
		end
	end
	-- The charge is consumed up front — that is the risk.
	for item, count in pairs(entry.recipe.ingredients) do
		inv:remove_item("src", ItemStack(item .. " " .. count))
	end

	local total = sl_machine.forge_time()
	local desc = entry.recipe.description or entry.recipe.output
	meta:set_string("job_output", entry.recipe.output)
	meta:set_string("job_count", tostring(entry.recipe.output_count or 1))
	meta:set_string("job_desc", desc)
	meta:set_string("job_total", tostring(total))
	meta:set_string("job_left", tostring(total))
	meta:set_string("job_by", name or "")
	if minetest.get_node_timer then
		minetest.get_node_timer(pos):start(TICK)
	end
	refresh_infotext(pos, meta)

	-- LOUD (§6.10 B): everyone learns what is being made and where.
	if game_mode and game_mode.broadcast then
		game_mode.broadcast(S("@1 runs the Objective Forge at @2: @3 (@4s).",
			name or S("Someone"), minetest.pos_to_string(pos), desc, tostring(total)))
	end
	minetest.sound_play("alert", { pos = pos, gain = 0.8, max_hear_distance = 32 })
	return true
end
sl_machine.start_job = start_job

-- ----------------------------------------------------------------
-- Formspec
-- ----------------------------------------------------------------
local function forge_formspec(pos, meta)
	meta = meta or minetest.get_meta(pos)
	local fs = {
		"formspec_version[4]",
		"size[11.5,12.2]",
		"bgcolor[#141018ff;true]",
		"label[0.3,0.3;OBJECTIVE FORGE]",
		"label[0.3,0.75;Placeables are made here — never in your inventory.]",

		"label[0.3,1.3;INPUT]",
		"list[context;src;0.3,1.6;4,2;]",
		"label[5.0,1.3;OUTPUT]",
		"list[context;dst;5.0,1.6;2,2;]",
	}

	if job_running(meta) then
		local left = math.ceil(tonumber(meta:get_string("job_left")) or 0)
		local total = tonumber(meta:get_string("job_total")) or 1
		local done = total > 0 and math.max(0, math.min(1, (total - left) / total)) or 0
		table.insert(fs, "label[7.8,1.3;RUNNING]")
		table.insert(fs, string.format("box[7.8,1.7;3.4,0.5;#333333ff]"))
		table.insert(fs, string.format("box[7.8,1.7;%f,0.5;#ff9c2aff]", 3.4 * done))
		table.insert(fs, string.format("label[7.9,1.95;%s]",
			minetest.formspec_escape(S("@1 — @2s left", meta:get_string("job_desc"), tostring(left)))))
	else
		table.insert(fs, "label[7.8,1.3;IDLE]")
	end

	table.insert(fs, "label[0.3,3.9;MACHINE RECIPES]")

	local y = 4.3
	for _, entry in ipairs(sl_machine.get_recipes()) do
		local recipe = entry.recipe
		local inv = meta:get_inventory()
		inv:set_size("src", 8)
		local afford = true
		for item, count in pairs(recipe.ingredients) do
			if not inv:contains_item("src", ItemStack(item .. " " .. count)) then
				afford = false
				break
			end
		end
		local color = afford and "#2f5d3aff" or "#3a3a3aff"
		table.insert(fs, string.format("box[0.3,%f;7.3,0.62;%s]", y, color))
		table.insert(fs, string.format("label[0.45,%f;%s x%d]", y + 0.31,
			minetest.formspec_escape(recipe.description or recipe.output),
			recipe.output_count or 1))
		table.insert(fs, string.format("label[4.6,%f;%s]", y + 0.31,
			minetest.formspec_escape(ingredients_text(recipe))))
		table.insert(fs, string.format("button[8.0,%f;3.2,0.62;forge_%d;FORGE]", y, entry.id))
		y = y + 0.68
	end

	table.insert(fs, string.format("label[0.3,%f;Run time: %d s — one job at a time, announced to everyone.]",
		y + 0.1, sl_machine.forge_time()))

	table.insert(fs, "label[0.3,10.1;INVENTORY]")
	table.insert(fs, "list[current_player;main;0.3,10.4;8,1;]")
	table.insert(fs, "listring[context;src]")
	table.insert(fs, "listring[current_player;main]")
	table.insert(fs, "listring[context;dst]")
	table.insert(fs, "listring[current_player;main]")
	return table.concat(fs, "")
end
sl_machine.forge_formspec = forge_formspec

local FORMEXPR = "^sl_machine_crafting:forge:([-]?%d+),([-]?%d+),([-]?%d+)$"

-- ----------------------------------------------------------------
-- The node
-- ----------------------------------------------------------------
minetest.register_node(sl_machine.FORGE_NAME, {
	description = S("Objective Forge"),
	tiles = { sl_texgen.texture("terminal_texture.png") },
	paramtype = "light",
	light_source = 12,
	-- A forge placed by the map never pays essence when destroyed
	-- (ruling rule 1 only prices crew-placed nodes). A crew-built one
	-- would be priced 4, like the spawner unit.
	groups = {
		cracky = 2,
		oddly_breakable_by_hand = 1,
		sl_essence_value = 4,
		not_in_creative_inventory = 1,
		possessable = 1,
	},
	is_ground_content = false,

	-- Map-placed and match-owned: it cannot be mined away mid-match
	-- (griefing the economy is not a mechanic; losing the CHARGE is).
	can_dig = function(pos, player)
		if game_mode and game_mode.state and game_mode.state.match_active then
			return false
		end
		return true
	end,

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:get_inventory():set_size("src", 8)
		meta:get_inventory():set_size("dst", 4)
		clear_job(meta)
		meta:set_string("infotext", S("Objective Forge — idle"))
	end,

	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker or not clicker:is_player() then return itemstack end
		local name = clicker:get_player_name()
		if game_mode and game_mode.refuse_if_sabotaged and game_mode.refuse_if_sabotaged(pos, clicker) then
			return itemstack
		end
		local ok, why = can_operate(name)
		if not ok then
			minetest.chat_send_player(name, why)
			return itemstack
		end
		minetest.show_formspec(name,
			"sl_machine_crafting:forge:" .. (game_mode.pos_hash
				and game_mode.pos_hash(pos)
				or (pos.x .. "," .. pos.y .. "," .. pos.z)),
			forge_formspec(pos, minetest.get_meta(pos)))
		return itemstack
	end,

	on_timer = function(pos, elapsed)
		local meta = minetest.get_meta(pos)
		if not job_running(meta) then return false end
		-- The forge is match-bound: when the match ends mid-run the
		-- charge is forfeit (design: the machine owns the risk).
		if not match_live() then
			abandon_job(pos, meta, S("The match ended mid-run — the forge charge is lost."))
			return false
		end
		local left = tonumber(meta:get_string("job_left")) or 0
		left = left - (tonumber(elapsed) or TICK)
		if left > 0 then
			meta:set_string("job_left", tostring(left))
			refresh_infotext(pos, meta)
			return true
		end
		finish_job(pos, meta)
		return false
	end,

	on_destruct = function(pos)
		local meta = minetest.get_meta(pos)
		if job_running(meta) then
			abandon_job(pos, meta, S("The Objective Forge is destroyed — the charge is lost."))
		end
	end,

	-- Dropping the charge is the point: a destroyed forge leaves
	-- nothing behind but the input it was fed.
	-- The charge is physical: whatever sits in the input slots is
	-- spilled on the floor rather than deleted with the machine.
	-- can_dig is a Lua-level convention (the engine calls on_dig
	-- regardless), so it is checked HERE, first: otherwise a refused
	-- dig would still empty the slots and the crew would lose the
	-- charge to a punch that did nothing.
	on_dig = function(pos, node, digger)
		local def = minetest.registered_nodes[node.name]
		local may_dig = true
		if def and def.can_dig then
			may_dig = def.can_dig(pos, digger) ~= false
		end
		if may_dig then
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			if inv then
				for _, listname in ipairs({ "src", "dst" }) do
					for _, stack in ipairs(inv:get_list(listname) or {}) do
						if not stack:is_empty() then
							minetest.add_item(pos, stack)
						end
					end
					inv:set_list(listname, {})
				end
			end
		end
		if minetest.node_dig then return minetest.node_dig(pos, node, digger) end
		if not may_dig then return false end
		minetest.remove_node(pos)
		return true
	end,

	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		-- Inputs are locked while a job runs: no swapping the charge
		-- out from under a run that was already announced, and no
		-- topping it up either (both directions, or the lock leaks).
		if job_running(minetest.get_meta(pos))
			and (from_list == "src" or to_list == "src") then
			return 0
		end
		return count
	end,

	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname ~= "src" and listname ~= "dst" then return 0 end
		if listname == "src" and job_running(minetest.get_meta(pos)) then return 0 end
		return stack:get_count()
	end,

})

-- ----------------------------------------------------------------
-- Field handler
-- ----------------------------------------------------------------
minetest.register_on_player_receive_fields(function(player, formname, fields)
	-- Three captures, three variables (the spawner GUI shipped a
	-- `_, _, x, y, z` bug that shifted z into x — do not reintroduce).
	local x, y, z = formname:match(FORMEXPR)
	if not x then return end
	if not player or not player.is_player or not player:is_player() then return end
	local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
	local node = minetest.get_node_or_nil(pos)
	if not node or node.name ~= sl_machine.FORGE_NAME then return end
	local name = player:get_player_name()

	local job_id
	for field, _ in pairs(fields) do
		if field:sub(1, 6) == "forge_" then
			job_id = tonumber(field:sub(7))
		end
	end
	if not job_id then return end

	if game_mode and game_mode.refuse_if_sabotaged and game_mode.refuse_if_sabotaged(pos, player) then return end
	local ok, why = can_operate(name)
	if not ok then
		minetest.chat_send_player(name, why)
		return
	end

	local entry = recipe_by_id(job_id)
	if not entry then
		minetest.chat_send_player(name, S("That recipe is no longer available."))
		return
	end

	local started, err = start_job(pos, entry, name)
	if not started then
		minetest.chat_send_player(name, err or S("The forge refuses the charge."))
		return
	end
	minetest.show_formspec(name, "sl_machine_crafting:forge:" .. (x .. "," .. y .. "," .. z),
		forge_formspec(pos, minetest.get_meta(pos)))
end)

-- ----------------------------------------------------------------
-- Match lifecycle: the forge is match-bound state.
-- ----------------------------------------------------------------
-- Non-invasive wrap (the sl_weapons pattern): a match end abandons
-- every running job instead of letting a timer pay out into the
-- lobby. The map reset re-places the forge node anyway; this makes
-- the "charge is forfeit" rule explicit and order-independent.
if game_mode and game_mode.end_match then
	local orig_end = game_mode.end_match
	game_mode.end_match = function(...)
		local anchor = game_mode.map and game_mode.map.current
			and game_mode.map.current.anchor
		if anchor and anchor.forge then
			local pos = anchor.forge
			local meta = minetest.get_meta(pos)
			local abandoned = job_running(meta)
			if abandoned then
				abandon_job(pos, meta,
					S("The match ended mid-run — the forge charge is lost."))
			end
			-- Sweep the slots too. A rebuilt map re-places the node
			-- (on_construct resets it), but an external/adopted arena
			-- is only journal-restored — without this sweep, last
			-- match's charge would survive into the next one.
			local inv = meta:get_inventory()
			if inv then
				for _, listname in ipairs({ "src", "dst" }) do
					inv:set_list(listname, {})
				end
			end
			if minetest.get_node_timer then
				minetest.get_node_timer(pos):stop()
			end
		end
		return orig_end(...)
	end
end

-- Diagnostics for /sl_state and the test harness: what the forge is
-- doing right now, or nil when the map has no forge.
function sl_machine.status()
	local anchor = game_mode and game_mode.map and game_mode.map.current
		and game_mode.map.current.anchor
	if not anchor or not anchor.forge then return nil end
	local pos = anchor.forge
	local node = minetest.get_node_or_nil(pos)
	if not node or node.name ~= sl_machine.FORGE_NAME then
		return { pos = pos, present = false }
	end
	local meta = minetest.get_meta(pos)
	local status = { pos = pos, present = true, running = job_running(meta) }
	if status.running then
		status.output = meta:get_string("job_output")
		status.description = meta:get_string("job_desc")
		status.left = tonumber(meta:get_string("job_left")) or 0
		status.total = tonumber(meta:get_string("job_total")) or 0
		status.by = meta:get_string("job_by")
	end
	return status
end

-- (The recipe count is logged lazily: sl_gui may load after this mod,
-- and the machine list is resolved on demand, never cached at load.)
minetest.log("action", "[sl_machine_crafting] Objective Forge loaded")
