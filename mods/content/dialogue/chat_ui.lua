-- Chat-based dialogue UI: prints subtitles in chat, plays voice, auto-advances.

local M = {
  formname = nil, -- not used
}

local function esc(s) return tostring(s or "") end

local state = {}

local function st(name)
  state[name] = state[name] or { timer=nil, sound_handle=nil }
  return state[name]
end

local function print_line(name, line)
  local speaker = line.speaker and ("["..line.speaker.."] ") or ""
  minetest.chat_send_player(name, speaker .. esc(line.text))
end

local function play_voice(name, line)
  local S = st(name)
  if S.sound_handle then minetest.sound_stop(S.sound_handle); S.sound_handle=nil end
  if line.sound and line.sound ~= "" then
    S.sound_handle = minetest.sound_play(line.sound, {to_player=name, gain=1.0})
  end
end

local function schedule_advance(name, line)
  local d = 0
  if line.duration and type(line.duration)=='number' then d = line.duration
  else
    local cps = 20
    d = math.max(1.0, (line.text and #tostring(line.text) or 0)/cps)
  end
  local S = st(name)
  if S.timer then S.timer:cancel(); S.timer=nil end
  S.timer = minetest.after(d, function()
    S.timer=nil
    M.on_next(name)
  end)
end

local function current_line(player_name)
  local rt = dialogue.dialogue.get_runtime(player_name)
  if not rt or not rt.scene then return nil end
  return rt.scene.lines[rt.index]
end

function M.show(player_name)
  local ln = current_line(player_name)
  if not ln then return end
  print_line(player_name, ln)
  play_voice(player_name, ln)
  if not (ln.options and #ln.options > 0) then
    schedule_advance(player_name, ln)
  else
    -- list options
    local opts = {}
    for i, o in ipairs(ln.options) do opts[i] = string.format("%d) %s", i, esc(o.choice or ("Option "..i))) end
    minetest.chat_send_player(player_name, table.concat(opts, "  "))
    minetest.chat_send_player(player_name, "Type /dlg_pick <n>")
  end
end

function M.on_next(player_name)
  local ln = current_line(player_name)
  local S = st(player_name)
  if S.timer then S.timer:cancel(); S.timer=nil end
  if S.sound_handle then minetest.sound_stop(S.sound_handle); S.sound_handle=nil end
  dialogue.dialogue.advance(player_name)
  if dialogue.dialogue.is_active(player_name) then
    M.show(player_name)
  end
end

function M.on_choice(player_name, idx)
  local S = st(player_name)
  if S.timer then S.timer:cancel(); S.timer=nil end
  if S.sound_handle then minetest.sound_stop(S.sound_handle); S.sound_handle=nil end
  dialogue.dialogue.select_choice(player_name, idx)
  if dialogue.dialogue.is_active(player_name) then
    M.show(player_name)
  end
end

function M.cleanup(player_name)
  local S = state[player_name]
  if not S then return end
  if S.timer then S.timer:cancel(); S.timer=nil end
  if S.sound_handle then minetest.sound_stop(S.sound_handle); S.sound_handle=nil end
end

return M
