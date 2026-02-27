-- Dialogue UI styled like a HUD overlay using formspecs
-- Typewriter text, name banner, minimal buttons; no portrait.

local dlg = nil

local M = {
  formname = "dialogue:ui",
}

local state = {}

local function get_dlg()
  if not dlg then dlg = assert(rawget(_G, "dialogue")).dialogue end
  return dlg
end

local function esc(s)
  return minetest.formspec_escape(s or "")
end

local function line_for(player_name)
  local rt = get_dlg().get_runtime(player_name)
  if not rt or not rt.scene then return nil end
  return rt.scene.lines[rt.index], rt
end

local function ensure_state(name)
  state[name] = state[name] or { typing=false, shown_len=0, timer=nil, full_text="" }
  return state[name]
end

local function stop_timer(name)
  local st = state[name]
  if st and st.timer then st.timer:cancel() st.timer=nil end
end

local function start_typing(name)
  local ln = select(1, line_for(name))
  if not ln then return end
  local st = ensure_state(name)
  -- stop prior timers and sounds
  if st.advance_timer then st.advance_timer:cancel(); st.advance_timer=nil end
  stop_timer(name)
  if st.sound_handle then minetest.sound_stop(st.sound_handle); st.sound_handle=nil end
  st.full_text = tostring(ln.text or "")
  st.shown_len = 0
  if #st.full_text > 0 then st.shown_len = 1 end
  st.typing = true
  -- play voice, if provided
  if ln.sound and ln.sound ~= "" then
    st.sound_handle = minetest.sound_play(ln.sound, {to_player=name, gain=1.0})
  end
  local function schedule_auto()
    -- Auto-advance if no options
    if ln.options and #ln.options > 0 then return end
    local per_char = 0.03 -- matches tick
    local base = math.max(1.0, (#st.full_text)*per_char*0.5)
    local wait = base
    if ln.duration and type(ln.duration) == 'number' then
      wait = math.max(wait, ln.duration)
    end
    st.advance_timer = minetest.after(wait, function()
      st.advance_timer=nil
      M.on_next(name)
    end)
  end
  local function step()
    local speed = 1  -- chars per tick (~33cps)
    st.shown_len = math.min(#st.full_text, st.shown_len + speed)
    if st.shown_len >= #st.full_text then
      st.typing = false
      st.timer = nil
      -- refresh and schedule auto-advance
      minetest.after(0, function()
        M.show(name)
        schedule_auto()
      end)
    else
      -- update UI while typing
      minetest.after(0, function() M.show(name) end)
      st.timer = minetest.after(0.03, step)
    end
  end
  st.timer = minetest.after(0.03, step)
end

local function current_text(name)
  local st = ensure_state(name)
  if not st.full_text or st.full_text == "" then return "" end
  local n = math.max(0, math.min(#st.full_text, st.shown_len))
  return string.sub(st.full_text, 1, n)
end

local function build_formspec_for(player_name)
  local line, rt = line_for(player_name)
  if not rt or not line then
    return "formspec_version[6]size[8,3]label[0.5,1;No dialogue]button[3,2;2,0.8;close;Close]"
  end

  local st = ensure_state(player_name)
  -- Background panel at bottom
  local fs = {}
  table.insert(fs, "formspec_version[6]size[14,9]")
  table.insert(fs, "box[0.3,5.0;13.4,3.5;#101218D0]")
  -- Name banner
  local speaker = esc(line.speaker or "")
  if speaker ~= "" then
    table.insert(fs, "box[0.6,4.6;3.6,0.6;#2e7dd8EE]")
    table.insert(fs, string.format("label[0.8,4.75;%s]", speaker))
  end
  -- Text area (fallback for older versions, wraps reasonably)
  local shown = esc(current_text(player_name))
  table.insert(fs, string.format("textarea[0.6,5.2;13.0,2.6;dlgtext;;%s]", shown))

  local y = 8.1
  if line.options and #line.options > 0 and not st.typing then
    -- Render options as buttons stacked
    local x = 0.6
    for i, opt in ipairs(line.options) do
      local label = esc(opt.choice or ("Option "..i))
      table.insert(fs, string.format("button[%0.2f,%0.2f;6.3,0.8;opt_%d;%s]", x, y-2.9, i-1, label))
      x = x + 6.5
      if x + 6.3 > 13.6 then x = 0.6; y = y + 0.9 end
    end
  else
    -- Next/Skip button with icons
    if st.typing then
      table.insert(fs, string.format("image_button[11.6,%0.2f;2.0,0.8;gui_button_skip.png;skip;Skip]", y-2.9))
    else
      table.insert(fs, string.format("image_button[11.6,%0.2f;2.0,0.8;gui_button_next.png;next;Next]", y-2.9))
    end
  end

  return table.concat(fs)
end

function M.show(player_name)
  minetest.show_formspec(player_name, M.formname, build_formspec_for(player_name))
end

function M.on_next(player_name)
  local ln = select(1, line_for(player_name))
  local st = ensure_state(player_name)
  if st.advance_timer then st.advance_timer:cancel(); st.advance_timer=nil end
  if not ln then return end
  if st.typing then
    -- finish typing immediately
    stop_timer(player_name)
    st.shown_len = #(st.full_text or "")
    st.typing = false
    M.show(player_name)
    return
  end
  -- stop any playing voice
  if st.sound_handle then minetest.sound_stop(st.sound_handle); st.sound_handle=nil end
  get_dlg().advance(player_name)
  if get_dlg().is_active(player_name) then
    start_typing(player_name)
    M.show(player_name)
  else
    stop_timer(player_name)
  end
end

function M.on_choice(player_name, idx)
  local st = ensure_state(player_name)
  if st.advance_timer then st.advance_timer:cancel(); st.advance_timer=nil end
  stop_timer(player_name)
  if st.sound_handle then minetest.sound_stop(st.sound_handle); st.sound_handle=nil end
  get_dlg().select_choice(player_name, idx)
  if get_dlg().is_active(player_name) then
    start_typing(player_name)
    M.show(player_name)
  end
end

-- Cleanup when dialogue stops
function M.cleanup(player_name)
  local st = state[player_name]
  if not st then return end
  if st.timer then st.timer:cancel(); st.timer=nil end
  if st.advance_timer then st.advance_timer:cancel(); st.advance_timer=nil end
  if st.sound_handle then minetest.sound_stop(st.sound_handle); st.sound_handle=nil end
  st.typing=false
end

-- Hook from dialogue.start_for_player via ui.show()
local orig_show = M.show
function M.show(player_name)
  -- ensure typing state matches current line
  local ln = select(1, line_for(player_name))
  if ln then
    start_typing(player_name)
  end
  orig_show(player_name)
end

return M
