-- ================================================================
-- sl_weapons — the Precision Fabricator (spec §10.1 "The pilgrimage")
-- The station is the treasure: bolted down, uncraftable, unmoving —
-- digging one destroys it. The recipe is deliberately mundane; the
-- gate was never the shopping list. The job takes ten full seconds
-- of machine hum audible 12 m, which is an eternity in the cubes.
-- ================================================================

local W = sl_weapons
local S = W.S

local JOB_TIME = 10

-- Deliberately mundane materials (spec §10.1): existing salvage and
-- components only. Nothing exotic — the trip is the cost.
W.FAB_RECIPES = {
	lash = {
		label = S("Grapple Lash"),
		item = W.modname .. ":grapple",
		mats = {
			{ "sl_modebase:metal_ingot", 2 },
			{ "sl_modebase:circuit_board", 2 },
			{ "sl_modebase:energy_crystal", 2 },
			{ "sl_modebase:plastic_scrap", 1 },
		},
	},
	sentry_kit = {
		label = S("Sentry Kit"),
		item = W.modname .. ":sentry_kit",
		mats = {
			{ "sl_modebase:metal_ingot", 3 },
			{ "sl_modebase:circuit_board", 1 },
			{ "sl_modebase:energy_crystal", 1 },
		},
	},
	-- The arsenal itself (team directive 2026-08-29): pads are map
	-- furniture and mapgen places none, so every weapon must also be
	-- fabricable from monster spoils. Pads stay the fast lane during a
	-- match; the Fabricator is the floor under the whole arsenal.
	chatter = {
		label = S("Chatter SMG"),
		item = W.modname .. ":chatter",
		mats = {
			{ "sl_modebase:metal_ingot", 2 },
			{ "sl_modebase:circuit_board", 1 },
			{ "sl_modebase:plastic_scrap", 1 },
		},
	},
	scatter = {
		label = S("Riot Scatter"),
		item = W.modname .. ":scatter",
		mats = {
			{ "sl_modebase:metal_ingot", 3 },
			{ "sl_modebase:energy_crystal", 1 },
		},
	},
	driver = {
		label = S("Pulse Driver"),
		item = W.modname .. ":driver",
		mats = {
			{ "sl_modebase:energy_crystal", 2 },
			{ "sl_modebase:circuit_board", 2 },
			{ "sl_modebase:metal_ingot", 1 },
		},
	},
	lance = {
		label = S("Arc Lance"),
		item = W.modname .. ":lance",
		mats = {
			{ "sl_modebase:energy_crystal", 3 },
			{ "sl_modebase:circuit_board", 2 },
		},
	},
	mortar = {
		label = S("Fusion Mortar"),
		item = W.modname .. ":mortar",
		mats = {
			{ "sl_modebase:metal_ingot", 4 },
			{ "sl_modebase:circuit_board", 2 },
			{ "sl_modebase:energy_crystal", 2 },
		},
	},
	neon_six = {
		label = S("Neon Six"),
		item = W.modname .. ":neon_six",
		mats = {
			{ "sl_modebase:metal_ingot", 2 },
			{ "sl_modebase:energy_crystal", 2 },
			{ "sl_modebase:plastic_scrap", 1 },
		},
	},
	neon_repeater = {
		label = S("Neon Repeater"),
		item = W.modname .. ":neon_repeater",
		mats = {
			{ "sl_modebase:metal_ingot", 3 },
			{ "sl_modebase:energy_crystal", 2 },
			{ "sl_modebase:circuit_board", 1 },
		},
	},
	-- The executioner's receipt: one guaranteed kill, priced so the
	-- buyer means it (team directive 2026-08-29).
	severance = {
		label = S("Severance (single use)"),
		item = W.modname .. ":severance",
		mats = {
			{ "sl_modebase:metal_ingot", 3 },
			{ "sl_modebase:energy_crystal", 2 },
		},
	},
}

W.fab_jobs = {} -- [phash] = { pos, recipe, done_at, user }

-- Stable catalog order for the formspec (lash first: the pilgrimage
-- stays the headline; the arsenal follows).
local FAB_ORDER = {
	"lash", "sentry_kit", "chatter", "scatter", "driver",
	"lance", "mortar", "neon_six", "neon_repeater", "severance",
}

local function recipe_line(id)
	local r = W.FAB_RECIPES[id]
	local parts = {}
	for _, m in ipairs(r.mats) do
		local def = minetest.registered_items[m[1]]
		table.insert(parts, string.format("%s ×%d",
			(def and def.description or m[1]), m[2]))
	end
	return r.label .. " — " .. table.concat(parts, ", ")
end

local function fab_formspec(pos, name)
	local meta = minetest.get_meta(pos)
	local job = W.fab_jobs[W.phash(pos)]
	local status
	if job then
		local left = math.max(0, math.ceil(job.done_at - W.now()))
		status = S("FABRICATING: @1 — @2 s", W.FAB_RECIPES[job.recipe].label, tostring(left))
	else
		status = S("PRECISION FABRICATOR — ready")
	end
	local fs = "formspec_version[4]size[9,10.4]bgcolor[#10141aff;true]" ..
		"label[0.4,0.6;" .. minetest.formspec_escape(status) .. "]" ..
		"label[0.4,1.2;" .. S("Catalog — every job takes 10 s. The machine hums.") .. "]"
	-- Catalog buttons: five rows, two columns
	local col_x = { [0] = 0.4, 4.9 }
	for i, id in ipairs(FAB_ORDER) do
		local r = W.FAB_RECIPES[id]
		if r then
			local col = (i <= 5) and 0 or 1
			local row = (i - 1) % 5
			fs = fs .. "button[" .. col_x[col] .. "," .. (1.8 + row * 0.9) ..
				";4.2,0.75;make_" .. id .. ";" .. minetest.formspec_escape(r.label) .. "]"
		end
	end
	-- One compact bill of materials under the buttons
	local bill = {}
	for _, id in ipairs(FAB_ORDER) do
		if W.FAB_RECIPES[id] then table.insert(bill, recipe_line(id)) end
	end
	fs = fs .. "textarea[0.4,6.6;8.2,3.0;;;" .. minetest.formspec_escape(table.concat(bill, "\n")) .. "]" ..
		"label[0.4,9.9;" .. minetest.formspec_escape(S("Operator: @1", name)) .. "]"
	return fs
end

minetest.register_node(W.modname .. ":fabricator", {
	description = S("Precision Fabricator"),
	tiles = { "sl_weapons_fabricator_top.png", "sl_weapons_fabricator_base.png",
		"sl_weapons_fabricator_side.png" },
	paramtype2 = "facedir",
	light_source = 6,
	-- Digging destroys the station: nobody carries the monopoly home.
	groups = { cracky = 1, level = 2 },
	is_ground_content = false,
	drop = "",

	can_dig = function(pos)
		return W.fab_jobs[W.phash(pos)] == nil
	end,

	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker.is_player or not clicker:is_player() then return end
		if game_mode and game_mode.refuse_if_possessed
			and game_mode.refuse_if_possessed(pos, clicker) then
			return
		end
		if game_mode and game_mode.refuse_if_sabotaged
			and game_mode.refuse_if_sabotaged(pos, clicker) then
			return
		end
		minetest.show_formspec(clicker:get_player_name(),
			W.modname .. ":fabricator_" .. W.phash(pos), fab_formspec(pos, clicker:get_player_name()))
	end,
})

local function start_job(pos, recipe_id, clicker)
	local name = clicker:get_player_name()
	local h = W.phash(pos)
	if W.fab_jobs[h] then
		minetest.chat_send_player(name, S("The machine is busy."))
		return
	end
	if game_mode then
		local pl = game_mode.get_player_state(name)
		if pl and pl.role == "monster_master" then
			minetest.chat_send_player(name, minetest.colorize("#ff8844",
				S("Your hands are the doctrine.")))
			return
		end
		if pl then
			-- Inside a match only the living build; outside it the
			-- machine runs for testers (the open range, v1.3.3).
			local dead = (game_mode.state and game_mode.state.match_active
				and pl.phase ~= "alive")
				or pl.phase == "ghost" or pl.phase == "evil_ghost"
			if dead then
				minetest.chat_send_player(name, S("The dead order nothing built."))
				return
			end
		end
	end
	local inv = clicker:get_inventory()
	if not inv then return end
	local r = W.FAB_RECIPES[recipe_id]
	for _, m in ipairs(r.mats) do
		if not inv:contains_item("main", ItemStack(m[1] .. " " .. m[2])) then
			minetest.chat_send_player(name, S("Missing materials."))
			return
		end
	end
	for _, m in ipairs(r.mats) do
		inv:remove_item("main", ItemStack(m[1] .. " " .. m[2]))
	end
	W.fab_jobs[h] = { pos = vector.round(pos), recipe = recipe_id, done_at = W.now() + JOB_TIME, user = name }
	minetest.sound_play("sl_weapons_fab_start", {
		pos = pos, gain = 0.9, max_hear_distance = 12,
	})
	minetest.chat_send_player(name, S("Fabrication started. Stand and sing."))
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname:sub(1, #(W.modname .. ":fabricator_")) ~= W.modname .. ":fabricator_" then
		return
	end
	if not player then return end
	local pos_str = formname:sub(#(W.modname .. ":fabricator_") + 1)
	local x, y, z = pos_str:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
	if not x then return end
	local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
	for id in pairs(W.FAB_RECIPES) do
		if fields["make_" .. id] then start_job(pos, id, player) end
	end
end)

local fab_accum = 0
minetest.register_globalstep(function(dtime)
	fab_accum = fab_accum + dtime
	if fab_accum < 1.0 then return end
	fab_accum = 0
	local now = W.now()
	for h, job in pairs(W.fab_jobs) do
		if now >= job.done_at then
			W.fab_jobs[h] = nil
			local recipe = W.FAB_RECIPES[job.recipe]
			local player = minetest.get_player_by_name(job.user)
			if player then
				player:get_inventory():add_item("main", W.loaded_stack(recipe.item))
				minetest.chat_send_player(job.user,
					S("Fabrication complete: @1", recipe.label))
			else
				minetest.add_item(job.pos, W.loaded_stack(recipe.item))
			end
			minetest.sound_play("sl_weapons_fab_done", {
				pos = job.pos, gain = 0.8, max_hear_distance = 16,
			})
		else
			-- Ten seconds of machine hum, audible 12 m.
			minetest.sound_play("sl_weapons_fab_hum", {
				pos = job.pos, gain = 0.6, max_hear_distance = 12,
			})
		end
	end
end)
