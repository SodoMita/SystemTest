-- Dialogue runtime and registry
-- Scenes are loaded from YAML: { scene/title, lines=[ {id,speaker,text,trigger,options=[{choice,next}], next_scene} ] }

local triggers = nil -- set on first require via global

local M = {}

local scenes = {}
local per_player = {}

local function get_triggers()
  if not triggers then
    triggers = assert(rawget(_G, "dialogue")).triggers
  end
  return triggers
end

local function normalize_scene(name, data)
  local scene = { name = name, lines = {} }
  local src_lines = data.lines or {}
  for i, ln in ipairs(src_lines) do
    local item = {
      id = ln.id,
      speaker = ln.speaker,
      text = ln.text,
      sprite = ln.sprite,
      sound = ln.sound,
      animation = ln.animation,
      cutscene = ln.cutscene,
      trigger = ln.trigger,
      quest_id = ln.quest_id,
      next_scene = ln.next_scene,
      options = ln.options or nil,
    }
    table.insert(scene.lines, item)
  end
  return scene
end

function M.register_scene(name, data)
  scenes[name] = normalize_scene(name, data)
end

function M.get_scene(name) return scenes[name] end

local function start_runtime(player_name, scene)
  per_player[player_name] = {
    scene = scene,
    index = 1,
    fired = {}, -- fired triggers per index
  }
end

local function current_line(state)
  if not state or not state.scene then return nil end
  return state.scene.lines[state.index]
end

local function fire_trigger_if_any(state, player_name)
  local ln = current_line(state)
  if not ln then return end
  if ln.trigger and not state.fired[state.index] then
    get_triggers().fire(ln.trigger, { player_name = player_name, scene = state.scene.name, index = state.index })
    state.fired[state.index] = true
  end
end

function M.start_for_player(player_name, scene_name)
  local sc = scenes[scene_name]
  if not sc then return false end
  start_runtime(player_name, sc)
  fire_trigger_if_any(per_player[player_name], player_name)
  -- show UI
  local ui = rawget(_G, "dialogue").ui
  ui.show(player_name)
  return true
end

function M.stop_for_player(player_name)
  -- cleanup UI side-effects
  local ui = rawget(_G, "dialogue").ui
  if ui and ui.cleanup then ui.cleanup(player_name) end
  per_player[player_name] = nil
  -- close UI (if using formspec UI)
  local formname = ui and ui.formname
  if type(formname) == "string" and formname ~= "" then
    minetest.close_formspec(player_name, formname)
  end
end

function M.is_active(player_name)
  return per_player[player_name] ~= nil
end

function M.get_runtime(player_name)
  return per_player[player_name]
end

function M.advance(player_name)
  local st = per_player[player_name]; if not st then return end
  local cur = current_line(st)
  if not cur then return end
  -- if current has options, don't auto-advance; UI should select option
  if cur.options and #cur.options > 0 then return end
  st.index = st.index + 1
  local next_line = current_line(st)
  if not next_line then
    -- end of scene; maybe jump to next_scene if set on last line
    if cur and cur.next_scene and scenes[cur.next_scene] then
      start_runtime(player_name, scenes[cur.next_scene])
      fire_trigger_if_any(per_player[player_name], player_name)
      return current_line(per_player[player_name])
    else
      M.stop_for_player(player_name)
      return nil
    end
  end
  fire_trigger_if_any(st, player_name)
  return next_line
end

function M.select_choice(player_name, idx)
  local st = per_player[player_name]; if not st then return end
  local cur = current_line(st); if not cur then return end
  if not cur.options or not cur.options[idx+1] then return end
  local opt = cur.options[idx+1]
  -- If option specifies next, first try jump within current scene by id
  if opt.next then
    local target_index = nil
    for i, ln in ipairs(st.scene.lines) do
      if ln.id == opt.next then target_index = i; break end
    end
    if target_index then
      st.index = target_index
      fire_trigger_if_any(st, player_name)
      return current_line(st)
    elseif scenes[opt.next] then
      -- fallback: treat as scene name
      start_runtime(player_name, scenes[opt.next])
      fire_trigger_if_any(per_player[player_name], player_name)
      return current_line(per_player[player_name])
    end
  end
  return M.advance(player_name)
end

return M
