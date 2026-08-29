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
}

W.fab_jobs = {} -- [phash] = { pos, recipe, done_at, user }

local function recipe_lines(recipe_id)
	local r = W.FAB_RECIPES[recipe_id]
	local out = {}
	for _, m in ipairs(r.mats) do
		local def = minetest.registered_items[m[1]]
		table.insert(out, string.format("  • %s ×%d",
			(def and def.description or m[1]), m[2]))
	end
	return table.concat(out, "\n")
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
	local fs = "formspec_version[4]size[9,8]bgcolor[#10141aff;true]" ..
		"label[0.4,0.6;" .. minetest.formspec_escape(status) .. "]" ..
		"label[0.4,1.6;" .. S("Grapple Lash") .. "]" ..
		"textarea[0.4,2.0;4.0,2.2;;;" .. minetest.formspec_escape(recipe_lines("lash")) .. "]" ..
		"button[0.4,4.4;3.4,1.0;make_lash;" .. S("Fabricate") .. "]" ..
		"label[4.9,1.6;" .. S("Sentry Kit") .. "]" ..
		"textarea[4.9,2.0;4.0,2.2;;;" .. minetest.formspec_escape(recipe_lines("sentry_kit")) .. "]" ..
		"button[4.9,4.4;3.4,1.0;make_sentry_kit;" .. S("Fabricate") .. "]" ..
		"label[0.4,5.8;" .. S("Jobs take 10 s. The machine hums.") .. "]" ..
		"label[0.4,6.2;" .. minetest.formspec_escape(S("Operator: @1", name)) .. "]"
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
		if pl and pl.phase ~= "alive" then
			minetest.chat_send_player(name, S("The dead order nothing built."))
			return
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
	if fields.make_lash then start_job(pos, "lash", player) end
	if fields.make_sentry_kit then start_job(pos, "sentry_kit", player) end
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
				player:get_inventory():add_item("main", ItemStack(recipe.item .. " 1"))
				minetest.chat_send_player(job.user,
					S("Fabrication complete: @1", recipe.label))
			else
				minetest.add_item(job.pos, ItemStack(recipe.item .. " 1"))
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
