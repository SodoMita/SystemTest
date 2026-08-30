-- ================================================================
-- sl_solo/crew.lua — crew roster, designations, chatter, reflexes
-- ================================================================
-- * Roster + designations: crew (operator's team) vs rivals, radio
--   handles (UNIT-A.. / UNIT-X..) so the operator can track and refer
--   to individuals. Faces cannot help — everyone is the same boxman.
-- * Badge scan: right-click a nearby unit body to prox-scan its
--   designation (QoL for tracking; reveals nothing about loyalty).
-- * Chatter: idle radio lines + deflections. Pure flavor — with one
--   deliberate exception: sabotage witness lines are real evidence.
-- * Combat reflex: bots punch hostiles that reach melee range (2.5 m)
--   with a per-bot cooldown, using the real engine punch path.
-- * Damage bridge: mode monsters punch bots through p:punch, which a
--   FakePlayer ref would silently drop. The bridge routes that damage
--   through botmatch.external_punch so waves can actually kill AI
--   crew through the real death pipeline.
-- ================================================================

-- ---------------------------------------------------------------
-- Roster & designations
-- ---------------------------------------------------------------
function sl_solo.build_roster(human)
	local st = sl_solo.state
	local b = rawget(_G, "botmatch")
	local crew, rivals, designations = {}, {}, {}

	-- Crew first (alphabetical bot order), then rivals; designations
	-- follow team roster order, not bot names, so nothing about the
	-- assignment leaks through the handle.
	local crew_names, rival_names = {}, {}
	if b then
		for _, botname in ipairs(b.bot_order) do
			local team = game_mode.get_player_state(botname).team
			if team == (game_mode.get_player_state(human).team or "beacon_a") then
				table.insert(crew_names, botname)
				crew[botname] = true
			else
				table.insert(rival_names, botname)
				rivals[botname] = true
			end
		end
	end

	local crew_letters = { "A", "B", "C", "D", "E", "F" }
	local rival_letters = { "X", "Y", "Z", "W", "V", "U" }
	for i, botname in ipairs(crew_names) do
		designations[botname] = "UNIT-" .. (crew_letters[i] or tostring(i))
	end
	for i, botname in ipairs(rival_names) do
		designations[botname] = "UNIT-" .. (rival_letters[i] or tostring(i))
	end
	return crew, rivals, designations
end

-- ---------------------------------------------------------------
-- Radio chatter
-- ---------------------------------------------------------------
local CHATTER = {
	crew = {
		"core holding. for now.",
		"if you are not on the manifest, bleed proof.",
		"salvage tally climbing. keep your hands where I can see them.",
		"heard scraping in the walls again. maintenance swears the sector is empty.",
		"watch the corridors. the last crew trusted the corridors.",
		"anyone counting waves? I stopped at despair.",
	},
	rival = {
		"CORE B is ours. come and beg for it.",
		"your core sounds sick from over here. a coincidence, surely.",
		"the simulation talks to us too, you know. it says nothing nice about you.",
		"another wave. bring it.",
	},
	deflect = {
		"maybe check your own people before you stare at me.",
		"I was salvaging. you would know that if you watched the paths.",
		"the machines did this. not us. never us.",
		"funny how corruption always starts near someone ELSE's post.",
	},
	monster = {
		"contact! horde on the floor, converge!",
		"they are inside the ring again. punch, do not talk.",
		"fall in — protect the cores!",
	},
}

function sl_solo.say(botname, line)
	local st = sl_solo.state
	local desig = st.designations[botname] or "UNIT-?"
	minetest.chat_send_all(minetest.colorize("#8fd7ff", "<" .. desig .. "> " .. line))
end

function sl_solo.chatter_step(dtime)
	local st = sl_solo.state
	local now = game_mode.now()
	if now < st.chatter_at then return end
	st.chatter_at = now + 25 + math.random(0, 30)

	local b = rawget(_G, "botmatch")
	if not b then return end
	local living = {}
	for _, botname in ipairs(b.bot_order) do
		local bot = b.bots[botname]
		local pl = game_mode.get_player_state(botname)
		if bot and not bot.dead and pl.phase == "alive" and not pl.eliminated then
			table.insert(living, botname)
		end
	end
	if #living == 0 then return end
	local speaker = living[math.random(1, #living)]

	local pool
	if st.rivals[speaker] then
		pool = CHATTER.rival
	elseif speaker == st.traitor and math.random() < 0.45 then
		pool = CHATTER.deflect
	else
		pool = sl_solo.count_monsters() > 2 and CHATTER.monster or CHATTER.crew
	end
	sl_solo.say(speaker, pool[math.random(1, #pool)])
end

-- ---------------------------------------------------------------
-- Badge scan: right-click a unit body to read its designation.
-- Wraps the harness mob entity's on_rightclick (empty by default) at
-- runtime — no edits to the harness itself.
-- ---------------------------------------------------------------
function sl_solo.install_badge_scan()
	local b = rawget(_G, "botmatch")
	if not b or not b.mobs then return end
	local def = minetest.registered_entities["aaa_botmatch:player_mob"]
	if not def or def.sl_solo_badge then return end
	local orig_rc = def.on_rightclick
	def.on_rightclick = function(self, clicker, ...)
		if orig_rc then orig_rc(self, clicker, ...) end
		if not sl_solo.cfg.badge_scan or not sl_solo.state.active then return end
		if not clicker or not clicker.is_player or not clicker:is_player() then return end
		local clicker_name = clicker:get_player_name()
		if botmatch.bots[clicker_name] then return end -- AI cannot scan AI
		local st = sl_solo.state
		local desig = st.designations[self.bot_name or ""]
		if not desig then return end
		-- Prox-scan: only works within 6 m of the operator.
		local ppos = clicker:get_pos()
		local opos = self.object and self.object.get_pos and self.object:get_pos()
		if ppos and opos and vector.distance(ppos, opos) > 6 then return end
		minetest.chat_send_player(clicker_name, minetest.colorize("#8fd7ff",
			"PROX-SCAN: " .. desig .. " (" .. (st.rivals[self.bot_name] and "rival crew" or "your crew") .. ")"))
	end
	def.sl_solo_badge = true
	sl_solo.log("badge scan installed on mob bodies")
end

-- ---------------------------------------------------------------
-- Combat reflex: any living bot punches a hostile in melee range.
-- Uses the engine punch path so entity on_punch (and for the shared
-- monster, its hp handling) stays authoritative.
-- ---------------------------------------------------------------
function sl_solo.combat_reflex(name)
	local st = sl_solo.state
	local b = rawget(_G, "botmatch")
	local bot = b and b.bots[name]
	if not bot or bot.dead then return end
	local pl = game_mode.get_player_state(name)
	if pl.phase ~= "alive" or pl.eliminated then return end
	if name == st.traitor then return end -- the Echo flees instead (traitor_tick)

	local now = game_mode.now()
	if now < (bot.bm.next_monster_punch or 0) then return end

	local monster, md = sl_solo.nearest_monster(bot:get_pos(), 2.5)
	if not monster then return end
	bot.bm.next_monster_punch = now + 1.6
	if monster.punch then
		pcall(monster.punch, monster, bot, 1.0, {
			full_punch_interval = 1.0,
			damage_groups = { fleshy = 4 },
		}, nil)
	end
end

-- ---------------------------------------------------------------
-- Damage bridge: monsters punch bots through ObjectRef:punch, which
-- FakePlayer would silently no-op. Route that damage through the
-- harness pipeline so waves can kill AI crew via the real death
-- chain (dieplayer handlers, cloud cage, eliminations — all real).
-- Installed lazily on every bot ref; rawset overrides the metatable
-- fallback without touching harness code.
-- ---------------------------------------------------------------
function sl_solo.install_punch_bridges()
	local b = rawget(_G, "botmatch")
	if not b then return end
	for _, bot in pairs(b.bots) do
		if not bot.sl_solo_bridge then
			bot.sl_solo_bridge = true
			rawset(bot, "punch", function(self, puncher, time_from_last_punch, tool_capabilities, dir)
				if not puncher or not puncher.get_luaentity then return end
				local ok, le = pcall(puncher.get_luaentity, puncher)
				if not ok or not le or not le.name or not sl_solo.monster_names[le.name] then
					return -- not a hostile: keep the original inert behavior
				end
				local dmg = 4
				if tool_capabilities and tool_capabilities.damage_groups
						and tool_capabilities.damage_groups.fleshy then
					dmg = tool_capabilities.damage_groups.fleshy
				end
				if game_mode.state.match_active and not self.dead then
					b.external_punch(self:get_player_name(), nil, dmg)
				end
			end)
		end
	end
end
