-- Trigger manager for simple named and area triggers.
-- API:
--   triggers.register_named(name, cb(ctx))
--   triggers.fire(name, ctx)
--   triggers.add_area(name, pos1, pos2, opts={once=true}, cb(ctx, player))
--   triggers.clear()
-- On enter detection (pos in aabb) per-player.

local M = {}

local named = {}
local areas = {}
local next_area_id = 1

function M.clear()
  named = {}
  areas = {}
  next_area_id = 1
end

function M.register_named(name, cb)
  if not name or name == "" then return end
  named[name] = named[name] or {}
  table.insert(named[name], cb)
end

function M.fire(name, ctx)
  local list = named[name]
  if not list then return end
  for _, cb in ipairs(list) do
    local ok, err = pcall(cb, ctx)
    if not ok then
      minetest.log("error", string.format("[dialogue] trigger '%s' handler error: %s", name, tostring(err)))
    end
  end
end

local function norm_pos(p)
  return {x=math.min(p.x, p.x), y=math.min(p.y, p.y), z=math.min(p.z, p.z)}
end

local function aabb_from(pos1, pos2)
  local minp = {x=math.min(pos1.x,pos2.x), y=math.min(pos1.y,pos2.y), z=math.min(pos1.z,pos2.z)}
  local maxp = {x=math.max(pos1.x,pos2.x), y=math.max(pos1.y,pos2.y), z=math.max(pos1.z,pos2.z)}
  return {min=minp, max=maxp}
end

local function aabb_contains(aabb, p)
  return p.x>=aabb.min.x and p.x<=aabb.max.x and p.y>=aabb.min.y and p.y<=aabb.max.y and p.z>=aabb.min.z and p.z<=aabb.max.z
end

function M.add_area(name, pos1, pos2, opts, cb)
  local id = next_area_id; next_area_id = next_area_id + 1
  areas[id] = {
    id = id,
    name = name,
    aabb = aabb_from(pos1, pos2),
    once = (opts and opts.once) or false,
    cb = cb,
    fired_players = {},
  }
  return id
end

local timer = 0
minetest.register_globalstep(function(dtime)
  timer = timer + dtime
  if timer < 0.25 then return end
  timer = 0
  for id, ar in pairs(areas) do
    for _, player in ipairs(minetest.get_connected_players() or {}) do
      local name = player:get_player_name()
      if ar.once and ar.fired_players[name] then
        goto continue_player
      end
      local pos = player:get_pos()
      if aabb_contains(ar.aabb, pos) then
        if ar.cb then
          local ok, err = pcall(ar.cb, {name=ar.name, player_name=name, area_id=id}, player)
          if not ok then
            minetest.log("error", string.format("[dialogue] area trigger error: %s", tostring(err)))
          end
        end
        if ar.once then ar.fired_players[name] = true end
      end
      ::continue_player::
    end
  end
end)

return M
