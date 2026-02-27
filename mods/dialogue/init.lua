-- Dialogue mod entry point
local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

local yaml = dofile(modpath .. "/yaml.lua")
local triggers = dofile(modpath .. "/trigger_manager.lua")
local dlg = dofile(modpath .. "/dialogue_manager.lua")
local ui = dofile(modpath .. "/chat_ui.lua")

-- Expose API
local M = {
  yaml = yaml,
  triggers = triggers,
  dialogue = dlg,
  ui = ui,
}
rawset(_G, "dialogue", M) -- optional global for other mods

-- Auto-load dialogues from this mod's dialogues/ folder
local dialogues_dir = modpath .. "/dialogues"
local function load_dialogues_from_dir(dir)
  local files = minetest.get_dir_list(dir, false) or {}
  for _, fname in ipairs(files) do
    local lower = fname:lower()
    local is_yaml = (lower:sub(-5) == ".yaml") or (lower:sub(-4) == ".yml")
    if is_yaml then
      local ok, data = pcall(yaml.load_file, dir .. "/" .. fname)
      if ok and type(data) == "table" then
        local base = fname
        if lower:sub(-5) == ".yaml" then base = base:sub(1, -6) end
        if lower:sub(-4) == ".yml" then base = base:sub(1, -5) end
        local scene_name = data.scene or data.title or base
        dlg.register_scene(scene_name, data)
      else
        minetest.log("error", string.format("[dialogue] Failed to load %s: %s", fname, tostring(data)))
      end
    end
  end
end

-- Always attempt to load; get_dir_list returns empty if missing
load_dialogues_from_dir(dialogues_dir)

-- Chat commands to control dialogues
minetest.register_chatcommand("dlg_start", {
  params = "<scene>",
  description = "Start a dialogue scene",
  func = function(name, param)
    param = param:match("^%s*(.-)%s*$")
    if param == "" then return false, "Usage: /dlg_start <scene>" end
    if not dlg.start_for_player(name, param) then
      return false, "Scene not found: " .. param
    end
    return true, "Started scene: " .. param
  end,
})

minetest.register_chatcommand("dlg_stop", {
  description = "Stop the active dialogue",
  func = function(name)
    dlg.stop_for_player(name)
    return true, "Dialogue closed"
  end,
})


-- Optional: example trigger to demonstrate
-- triggers.register_named("unlock_car_jump", function(ctx)
--   minetest.log("action", "[dialogue] Trigger unlock_car_jump fired for " .. (ctx.player_name or "?"))
-- end)

-- Choice selection via chat
minetest.register_chatcommand("dlg_pick", {
  params = "<index>",
  description = "Pick a dialogue choice by number",
  func = function(name, param)
    local idx = tonumber(param)
    if not idx then return false, "Usage: /dlg_pick <index>" end
    ui.on_choice(name, idx-1)
    return true, "Picked "..idx
  end,
})

minetest.register_chatcommand("dlg_next", {
  description = "Force advance dialogue",
  func = function(name)
    ui.on_next(name)
    return true, "Next"
  end,
})

return M
