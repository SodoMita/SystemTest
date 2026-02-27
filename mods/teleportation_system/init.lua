-- Teleportation Wonderland Mod Nyaa~ (ฅ^･ω･^ ฅ)

local teleportationInterval = 2
local offset = 1000  -- Adjust this value as needed

-- Function to teleport with velocity preservation Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
local function teleportWithVelocity(entity, pos, velocity)
    entity:set_pos(pos)
    entity:set_velocity(velocity)
end

-- Function to check if we've reached the teleportation limit, UwU~ (ฅ^•ﻌ•^ฅ)
local function isBeyondTeleportationLimit(value)
    local limit = 29900
    return math.abs(value) > limit
end

-- Function to get a slightly closer position Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
local function getAdjustedPosition(pos)
    local center = 0

    if isBeyondTeleportationLimit(pos.x) then
        pos.x = -pos.x
        pos.x = pos.x > center and (pos.x - offset) or (pos.x + offset)
    end

    if isBeyondTeleportationLimit(pos.y) then
        pos.y = -pos.y
        pos.y = pos.y > center and (pos.y - offset) or (pos.y + offset)
    end

    if isBeyondTeleportationLimit(pos.z) then
        pos.z = -pos.z
        pos.z = pos.z > center and (pos.z - offset) or (pos.z + offset)
    end

    return pos
end

-- Function to handle teleportation Nyaa~ (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)
local function handleTeleportation(entity)
    local pos = entity:get_pos()
    local velocity = entity:get_velocity()

    pos = getAdjustedPosition(pos)
    teleportWithVelocity(entity, pos, velocity)
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

