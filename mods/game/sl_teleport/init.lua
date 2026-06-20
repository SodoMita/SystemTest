-- Teleportation Wonderland Mod Nyaa~ (ฅ^･ω･^ ฅ)

local teleportationInterval = 2
local offset = 1000  -- Adjust this value as needed

-- ========================================================
-- Public API — let other mods hook into teleport events Nyaa~
-- ========================================================
sl_teleport = sl_teleport or {}
sl_teleport.callbacks = sl_teleport.callbacks or {}
sl_teleport.TELEPORT_LIMIT = 29900

-- Same limit-check function used internally — exported for reuse
function sl_teleport.is_beyond_limit(value)
    return math.abs(value) > sl_teleport.TELEPORT_LIMIT
end

-- Register a callback fired when an entity is actually teleported.
-- Callback signature:  function(entity, old_pos, new_pos, looped_axes)
--   looped_axes = { x = bool, y = bool, z = bool }
function sl_teleport.register_on_teleport(func)
    table.insert(sl_teleport.callbacks, func)
end

-- Function to teleport with velocity preservation Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
local function teleportWithVelocity(entity, pos, velocity)
    entity:set_pos(pos)
    entity:set_velocity(velocity)
end

-- Function to check if we've reached the teleportation limit, UwU~ (ฅ^•ﻌ•^ฅ)
local function isBeyondTeleportationLimit(value)
    return sl_teleport.is_beyond_limit(value)
end

-- Function to get a slightly closer position Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
-- Now also returns which axes were wrapped so callers know what happened.
local function getAdjustedPosition(pos)
    local center = 0
    local looped = { x = false, y = false, z = false }

    if isBeyondTeleportationLimit(pos.x) then
        pos.x = -pos.x
        pos.x = pos.x > center and (pos.x - offset) or (pos.x + offset)
        looped.x = true
    end

    if isBeyondTeleportationLimit(pos.y) then
        pos.y = -pos.y
        pos.y = pos.y > center and (pos.y - offset) or (pos.y + offset)
        looped.y = true
    end

    if isBeyondTeleportationLimit(pos.z) then
        pos.z = -pos.z
        pos.z = pos.z > center and (pos.z - offset) or (pos.z + offset)
        looped.z = true
    end

    return pos, looped
end

-- Function to handle teleportation Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
local function handleTeleportation(entity)
    local pos     = entity:get_pos()
    local velocity = entity:get_velocity()

    local new_pos, looped = getAdjustedPosition(pos)

    -- Only teleport (and notify) if something actually wrapped
    if looped.x or looped.y or looped.z then
        teleportWithVelocity(entity, new_pos, velocity)

        -- Fire callbacks so other mods (e.g. achievements) react to the
        -- *actual* teleport event, using the same logic this mod uses.
        for _, callback in ipairs(sl_teleport.callbacks) do
            local ok, err = pcall(callback, entity, pos, new_pos, looped)
            if not ok then
                minetest.log("error",
                    "[sl_teleport] on_teleport callback failed: " .. tostring(err))
            end
        end
    end
end

-- Time accumulator Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
local timeAccumulator = 0
minetest.register_globalstep(function(dtime)
    timeAccumulator = timeAccumulator + dtime

    if timeAccumulator >= teleportationInterval then
        for _, obj in pairs(minetest.get_objects_inside_radius({x = 0, y = 0, z = 0}, 30000)) do
            handleTeleportation(obj)
        end

        -- Players teleport together Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
        for _, player in pairs(minetest.get_connected_players()) do
            handleTeleportation(player)
        end

        -- Reset the accumulator Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
        timeAccumulator = 0
    end
end)
