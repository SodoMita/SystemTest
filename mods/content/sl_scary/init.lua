
local function random_vector(min, max)
  local x = min + (max - min) * math.random()
  local y = min + (max - min) * math.random()
  local z = min + (max - min) * math.random()
  return {x = x, y = y, z = z}
end

-- Register the scary mob
-- ================================================================
-- Lobby safety (owner directive 2026-08): monsters must never attack
-- players during the lobby stage (match not active). Damage sites and
-- target acquisition below are gated through this helper. Without
-- game_mode present (standalone use), behavior is unchanged.
-- ================================================================
local function attacks_allowed()
    local gm = rawget(_G, "game_mode")
    if gm and gm.state then
        return gm.state.match_active == true
    end
    return true
end

minetest.register_entity("sl_scary:mob", {
    initial_properties = {
        physical = true, -- The mob can physically interact with the world
        collide_with_objects = false, -- Can move through nodes/players
        collisionbox = {-0.2, -0.2, -0.2, 0.2, 0.2, 0.2},
        visual = "mesh",
--         mesh = "scary_mob.glb",
--         mesh = "female_zombie.glb",
        mesh = "Codop.glb",
--         textures = {"scary_mob_texture.png"},
        pointable = true,
        static_save = false, -- Save this entity between server restarts
        visual_size = {x=1,y=1,z=1},
        node_box = {
            type = "fixed",
                fixed = {
                    {-2, -2, -2, 2, 2, 2} -- Adjust these values for scaling
                }
        },
--         glow = 2,
    },

    -- Custom properties
    target_player = nil, -- Target player
    timer = 0, -- Movement and animation timer
    attack_timer = 0, -- Timer for attack intervals
    attack_time = 2, -- Attack interval
    drag_timer = 0, -- Timer for dragging process
    drag_time = 0.05, -- How long it will drag target body
    damage = 5, -- Damage dealt to the player
    range = 15, -- Detection range
    speed = 2, -- Base movement speed
    inside_node_speed = 0.2, -- Movement speed when inside a node (10x slower)
    player_move_speed = 30,
    attack_distance = 0.4, -- Distance at which the mob will attack
    stop_distance = 0.6, -- Distance at which the mob will stop
    digging_animation_playing = true, -- Whether the dig animation is playing
    dragging = false,
    anim_mul = 1,
    was_dragging = false, -- internal flag to restore camera after drag
    -- Steering avoidance config
    avoid_radius = 1.8,      -- scan radius for nearby entities
    avoid_weight = 1.8,      -- how strongly to steer away

    -- Function called when the mob is activated
    on_activate = function(self, staticdata, dtime_s)
        self.object:set_animation({x = 0, y = 1}, 1.0, 0, true) -- Default animation (idle)
        self.anim_mul = math.random(0.1,2.0)
        mobpop = mobpop + 1
    end,

    -- Function called every server tick
    on_step = function(self, dtime)
        self.timer = self.timer + dtime

        -- Locate the nearest player (never during the lobby stage)
        if not attacks_allowed() then
            self.target_player = nil
        elseif not self.target_player or not self.target_player:is_player() then
            local players = minetest.get_connected_players()
            local pos = self.object:get_pos()

            -- Find the closest player within range
            for _, player in ipairs(players) do
                if player and player:is_player() then
                    local player_pos = player:get_pos()
                    if player_pos and vector.distance(pos, player_pos) <= self.range then
                        self.target_player = player
                        break
                    end
                end
            end
        end

        -- If no player is found, do nothing
        if not self.target_player then
            return
        end

        -- Get positions
        local pos = self.object:get_pos()
        if not pos then return end
        
        local target_pos = self.target_player:get_pos()
        if not target_pos then return end
        target_pos.y=target_pos.y+1

        -- Calculate direction toward the player
        local dir = vector.normalize(vector.subtract(target_pos, pos))

        -- Simple steering to avoid other entities
        local move_dir = dir
        do
            local avoid_vec = {x = 0, y = 0, z = 0}
            local objs = minetest.get_objects_inside_radius(pos, self.avoid_radius) or {}
            for _, obj in ipairs(objs) do
                if obj ~= self.object then
                    -- Skip the target player; avoid everything else (players and entities)
                    if not (self.target_player and obj == self.target_player) then
                        local o_pos = obj:get_pos()
                        if o_pos then
                            local away = vector.subtract(pos, o_pos)
                            local dist = vector.length(away)
                            if dist and dist > 0 then
                                local norm_away = vector.divide(away, dist)
                                -- Stronger repulsion when closer (linear falloff)
                                local strength = math.max(0, (self.avoid_radius - dist) / self.avoid_radius)
                                avoid_vec = vector.add(avoid_vec, vector.multiply(norm_away, strength))
                            end
                        end
                    end
                end
            end
            if avoid_vec.x ~= 0 or avoid_vec.y ~= 0 or avoid_vec.z ~= 0 then
                local steered = vector.add(dir, vector.multiply(avoid_vec, self.avoid_weight))
                if steered.x ~= 0 or steered.y ~= 0 or steered.z ~= 0 then
                    move_dir = vector.normalize(steered)
                end
            end
        end

        -- Check if the mob is inside a diggable node
        local node = minetest.get_node(pos)
        local is_inside_node = minetest.registered_nodes[node.name] and minetest.registered_nodes[node.name].walkable

        -- Adjust speed based on environment
        local current_speed = self.speed
        if is_inside_node then
            current_speed = self.inside_node_speed -- Slow down when inside nodes
            if not self.digging_animation_playing then
                -- Play dig animation
                self.object:set_animation({x = 0, y = 1.6}, self.anim_mul, 0, true) -- Digging animation
                self.digging_animation_playing = true
            end
        else
            if self.digging_animation_playing then
                -- Stop dig animation
                self.object:set_animation({x = 1.666, y = 3}, self.anim_mul, 0, true) -- Walk animation
                self.digging_animation_playing = false
            end
        end
        local distance = vector.distance(pos, target_pos)

        -- Check if the mob is within attack range
        self.attack_timer = self.attack_timer + dtime
        if self.attack_timer >= self.attack_time and distance <= self.attack_distance then
            -- Attack the player (never during the lobby stage)
            if attacks_allowed() and self.target_player:is_player() then
                local hp = self.target_player:get_hp()
                if hp then
                    self.target_player:set_hp(hp - self.damage)
                end
            end
            self.attack_timer = 0

            -- Set attack animation
            self.object:set_animation({x = 3, y = 4}, 1, 0, true)


            -- Optional: Play an attack sound
            minetest.sound_play("scary_attack", {pos = pos, gain = 1.0, max_hear_distance = 10})
        end
        if distance <= self.stop_distance then
            current_speed = 0
        end
        if distance <= self.attack_distance*2 and self.attack_timer >= self.attack_time*0.2 and math.random() < 0.6 and self.drag_timer <= 0 then
            self.drag_timer = self.drag_time
        end
        if self.drag_timer > 0 then
            if distance > self.attack_distance*3 then
                self.drag_timer = 0
            end

            -- Drag the player
            local direction = vector.direction(target_pos, pos+random_vector(-3,3)) -- Direction to random point near self
            direction = vector.normalize(direction)
            direction = direction * self.player_move_speed * math.random() * (self.drag_timer/self.drag_time)

            self.target_player:add_velocity(direction)

            -- Push player's camera toward the mob and force look at the mob while dragging
            do
                local player = self.target_player
                if player and player:is_player() then
                    -- Compute look direction to the mob from player's eye position
                    local ppos = player:get_pos()
                    if ppos then
                        local eye_pos = {x = ppos.x, y = ppos.y + 1.4, z = ppos.z}
                        local to_mob = vector.direction(eye_pos, pos)
                        if to_mob and (to_mob.x ~= 0 or to_mob.y ~= 0 or to_mob.z ~= 0) then
                            -- Horizontal look (yaw)
                            local yaw = minetest.dir_to_yaw({x = to_mob.x, y = 0, z = to_mob.z})
                            if yaw then player:set_look_horizontal(yaw) end
                            -- Vertical look (pitch): negative to look upward, positive to look downward
                            local horiz_len = math.sqrt(to_mob.x * to_mob.x + to_mob.z * to_mob.z)
                            local pitch = -math.atan2(to_mob.y, horiz_len)
                            if pitch then player:set_look_vertical(pitch) end
                            -- Eye offset forward to "push" camera toward the mob
                            -- Use a small, clamped forward push so it feels like a pull-in
                            local push_strength = 2 -- nodes forward in view direction
                            player:set_eye_offset({x = 0, y = 0, z = -push_strength}, {x = 0, y = 0, z = -push_strength})
                            self.was_dragging = true
                        end
                    end
                end
            end

            self.drag_timer = self.drag_timer - dtime
        else
            -- Restore camera when drag ends
            if self.was_dragging and self.target_player and self.target_player:is_player() then
                self.target_player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
            end
            self.was_dragging = false
        end

        -- Move the mob toward the player, steering around other entities
        local new_pos = vector.add(pos, vector.multiply(move_dir, current_speed * dtime))
        self.object:set_pos(new_pos)
        self.object:set_rotation(vector.dir_to_rotation(move_dir))

    end,
})
mobpop = 0
maxmobpop = 10
-- Spawn the mob naturally on certain nodes
minetest.register_abm({
    label = "Spawn scary mob",
    nodenames = {"uliza:ground"},
    interval = 30, -- Check every 30 seconds
    chance = 100, -- 1 in 100 chance to spawn
    action = function(pos, node)
        if minetest.settings:get_bool("creative_mode") then
            return
        end
        if #minetest.get_connected_players() > 0 and mobpop < maxmobpop then
            local mob_pos = vector.add(pos, {x = 0, y = 1, z = 0})
            minetest.add_entity(mob_pos, "sl_scary:mob")
        end
    end,
})

local mob_config = {
    attack_range = 2,
    view_distance = 20,
    view_angle = 180,
    max_speed = 20,                  -- Maximum speed (blocks per second)
    acceleration = 120,               -- Acceleration (blocks per second^2)
    deceleration = 50,               -- Deceleration (blocks per second^2)
    max_search_distance = 15,
    max_jump = 6,
    max_drop = 20,
    search_radius = 5,
    search_wait_time = 0.5,
    idle_random_select_time = 1,
    idle_wander_radius = 3,
    -- Hard bound on wander candidates per idle tick. See handle_idle: an
    -- unbounded retry loop here is a server-thread hang the moment
    -- find_path returns nil.
    idle_wander_attempts = 4,

    animations = {
        idle = {start = 0, stop = 20, speed = 15},
        walk = {start = 21, stop = 40, speed = 20},
        run = {start = 41, stop = 60, speed = 30},
        attack = {start = 61, stop = 80, speed = 30},
    },

    sounds = {
        idle = "mob_idle",
        walk = "A_A",
        run = "A_A1",
        attack = "A_A",
        hurt = "default_dig_metal",
        death = "mob_death",
    },
}

-- Register the mob entity
minetest.register_entity("sl_scary:nerobot", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.35, -0.5, -0.35, 0.35, 0.5, 0.35},
        visual = "mesh",
        mesh = "polytest.glb",
        textures = {"scary_mob_texture.png"},
        hp_max = 32767,
    },

    -- Mob state variables
    state = "idle",
    target_player = nil,
    last_seen_pos = nil,
    search_spots = nil,
    current_search_index = nil,
    timer = 0,
    snd_timer = 0,
    last_direction = nil, -- Stores the previous movement direction for dynamic speed adjustment
    sound_handle = nil,

    -- Play animation
    set_animation = function(self, anim)
        if not anim or not mob_config.animations[anim] then return end
        local a = mob_config.animations[anim]
        self.object:set_animation({x = a.start, y = a.stop}, a.speed, 0)
    end,

    -- Play sound
    play_sound = function(self, sound)
        if not sound or not mob_config.sounds[sound]
           or self.snd_timer >= 0 then
           return
        end
        if self.sound_handle ~= nil then
            core.sound_stop(self.sound_handle)
        end

        self.sound_handle = minetest.sound_play(mob_config.sounds[sound], {
            object = self.object,
            max_hear_distance = 15,
            fade = 0.9,
            loop = true,
        })
        self.snd_timer = 2
    end,


    -- Mob on_step function
    on_step = function(self, dtime)
        self.dtime = dtime -- Store delta time for use in acceleration
        local pos = self.object:get_pos()
        if not pos then return end

        self.timer = self.timer + dtime
        self.snd_timer = self.snd_timer - dtime

        if self.state == "idle" then
            self:handle_idle(pos)
        elseif self.state == "chasing" then
            self:handle_chasing(pos)
        elseif self.state == "searching" then
            self:handle_searching(pos)
        elseif self.state == "attacking" then
            self:handle_attacking(pos)
        end
    end,

    -- Adjust speed dynamically
    adjust_speed = function(self, dir)
        if not self.last_direction then
            self.last_direction = dir
            return mob_config.base_speed
        end

        -- Calculate the angle difference between the current and last direction
        local dot = vector.dot(vector.normalize(self.last_direction), vector.normalize(dir))
        local angle_diff = math.acos(dot) -- Angle in radians

        if angle_diff > math.pi / 4 then
            -- Slow down at corners
            self.last_direction = dir
            return mob_config.base_speed * mob_config.corner_slowdown_factor
        else
            -- Accelerate on straight paths
            self.last_direction = dir
            return mob_config.base_speed * mob_config.straight_acceleration_factor
        end
    end,

    -- Update the mob's path to a target position
    update_path = function(self, target_pos)
        local pos = self.object:get_pos()
        if not pos or not target_pos then return end

        -- Find a path to the target position using Minetest's pathfinding
        local path = minetest.find_path(
            pos,
            target_pos,
            mob_config.max_search_distance,
            mob_config.max_jump,
            mob_config.max_drop,
            "A*"
        )
        self.path = path
        self.path_index = 1 -- Start from the first waypoint
    end,

    -- Handle idle state
    handle_idle = function(self, pos)
        self:set_animation("idle")
        self.play_sound(self, "idle")

        if self.timer > mob_config.idle_random_select_time then
            self.timer = 0
            -- Both loops here are BOUNDED, and that is load-bearing.
            --
            -- This used to be `while path_found == false do ... end` with no
            -- attempt counter. `update_path` assigns self.path from
            -- minetest.find_path, which returns NIL whenever no route exists
            -- inside max_search_distance -- a mob that is walled in, standing
            -- in the void, or whose random candidate is simply unreachable.
            -- path_found then never becomes true, sradius is never reset (so
            -- from the second pass the inner loop breaks immediately and the
            -- candidate never changes), and the server thread spins here
            -- forever. Measured in the headless harness: 200,000 find_path
            -- calls and 200,009 chat_send_all broadcasts INSIDE ONE on_step.
            -- A tick that does not return is a frozen server, and any player
            -- can wall a mob in with ordinary digging and building.
            --
            -- Bounded instead: try a few candidates, and if none is reachable
            -- the mob stays put and tries again on the next idle tick -- which
            -- is what an idle mob is supposed to do anyway.
            for _ = 1, (mob_config.idle_wander_attempts or 4) do
                local random_pos = vector.zero
                local is_inside_node, is_outside_node = false, false
                local sradius = 1
                -- A wander target needs BOTH: somewhere to stand (the target
                -- node is not walkable) and ground to stand on (the node below
                -- is). The old condition accepted a candidate when either one
                -- held, i.e. it happily picked a spot inside a wall or in mid
                -- air and then asked for a path to it.
                while sradius <= mob_config.idle_wander_radius
                        and not (is_inside_node and is_outside_node) do
                    random_pos = vector.add(vector.floor(pos), {
                        x = math.random(-sradius, sradius),
                        y = math.random(1, 2),
                        z = math.random(-sradius, sradius),
                    })
                    -- BUGFIX: this was `{random_pos.x, random_pos.y-1,
                    -- random_pos.z}` -- array-style, so .x/.y/.z were all nil.
                    -- The engine reads positions with readV3F, which turns a
                    -- missing component into 0 instead of erroring, so the
                    -- "is there floor below me" test was silently reading the
                    -- node at the world origin for every candidate.
                    local pos_below = {
                        x = random_pos.x, y = random_pos.y - 1, z = random_pos.z,
                    }
                    local node = minetest.get_node(random_pos)
                    local node_below = minetest.get_node(pos_below)
                    local ndef = minetest.registered_nodes[node.name]
                    local below_def = minetest.registered_nodes[node_below.name]
                    is_outside_node = ndef and not ndef.walkable
                    is_inside_node = below_def and below_def.walkable
                    sradius = sradius + 1
                end
                if is_inside_node and is_outside_node then
                    self:update_path(random_pos)
                    if self.path ~= nil and self.path[self.path_index] ~= nil then
                        break
                    end
                end
            end
        end

        local player = attacks_allowed() and self:get_player_in_view(pos) or nil
        if player then
            self.state = "chasing"
            self.target_player = player
            self.last_seen_pos = player:get_pos()
        end
        self:move_to()
    end,

    -- Handle chasing state
    handle_chasing = function(self, pos)
        self:play_sound("run")
        -- Recalculate the path not too frequently
        if not self.path_timer then self.path_timer = 0 end
        self.path_timer = self.path_timer + self.dtime
        if self.path_timer > mob_config.search_wait_time then
            self.path_timer = 0
                if self.target_player and self.target_player:is_player() then
                    local player_pos = self.target_player:get_pos()
                    if player_pos then
                        self:update_path(player_pos)
                    end
                end
        end

        -- Follow the current path
        self:move_to()
    end,

    -- Handle searching state
    handle_searching = function(self, pos)
        self:set_animation("walk")
        self:play_sound("walk")

        if not self.search_spots then
            self.search_spots = minetest.find_nodes_in_area(
                vector.subtract(self.last_seen_pos, mob_config.search_radius),
                vector.add(self.last_seen_pos, mob_config.search_radius),
                {"mymod:hide_spot"}
            )
            self.current_search_index = 1
        end

        if not self.search_spots or #self.search_spots == 0 then
            self.state = "idle"
            return
        end

        local target_spot = self.search_spots[self.current_search_index]
        if not target_spot then
            self.state = "idle"
            return
        end

        local dist = vector.distance(pos, target_spot)
        if dist <= 1 and attacks_allowed() then
            if self.timer > mob_config.search_wait_time then
                self.timer = 0
                local objs = minetest.get_objects_inside_radius(target_spot, 1)
                for _, obj in ipairs(objs) do
                    if obj:is_player() then
                        self.state = "chasing"
                        self.target_player = obj
                        self.search_spots = nil
                        return
                    end
                end

                self.current_search_index = self.current_search_index + 1
            end
        else
            self:move_to(target_spot)
        end
    end,

    -- Handle attacking state
    handle_attacking = function(self, pos)
        self:set_animation("attack")
        self:play_sound("attack")

        if not self.target_player or not self.target_player:is_player() then
            self.state = "idle"
            return
        end

        local player_pos = self.target_player:get_pos()
        if not player_pos then
            self.state = "searching"
            return
        end

        local dist = vector.distance(pos, player_pos)
        if dist > mob_config.attack_range then
            self.state = "chasing"
            return
        end

        if not attacks_allowed() then return end -- lobby safety
        self.target_player:punch(self.object, 1.0, {
            full_punch_interval = 1.0,
            damage_groups = {fleshy = 2},
        }, nil)
    end,

    calculate_acceleration = function(self, current, target, acceleration, deceleration)
        if math.abs(target - current) < 0.01 then
            return target -- Close enough, snap to target
        end

        if target > current then
            -- Accelerate toward the target
            return math.min(current + acceleration * self.dtime, target)
        elseif target < current then
            -- Decelerate toward the target
            return math.max(current - deceleration * self.dtime, target)
        else
            return current -- No change
        end
    end,

    move_to = function(self)
        local pos = self.object:get_pos()
        if not self.target_player or not self.target_player:is_player() then
            self.state = "idle"
        else
            local player_pos = self.target_player:get_pos()
            if player_pos and vector.distance(pos, player_pos) < mob_config.attack_range then
                self.state = "attacking"
                self.snd_timer = -1
            end
        end

        if not self.path or not self.path[self.path_index] then
            -- No valid path or reached the end of the path
--             self.object:set_velocity({x = 0, y = 0, z = 0})
            self:set_animation("idle")
            return
        end



        local start_index = self.path_index
        local best_index = start_index
        local best_y_diff = math.huge

        -- Function to check if there's a direct path
        local function can_reach_directly(from, to)
            local ray = minetest.raycast(from, vector.add(to, {x=0, y=1, z=0}), false, false) -- Add y=1 to avoid ground collision
            for pointed_thing in ray do
                if pointed_thing.type == "node" then
                    return false
                end
            end
            return true
        end

        -- Loop to find the best reachable waypoint on the same Y level or closest to it
        for i = start_index, #self.path do
            local waypoint = self.path[i]

            -- Stop if we've reached a waypoint with a different Y level
            if math.abs(waypoint.y - pos.y) > 0.5 then
                break
            end

            if can_reach_directly(pos, waypoint) then
                best_index = i
            else
                -- If this point isn't reachable, stop looking further
                break
            end
        end

        self.path_index = best_index
        local target_pos = self.path[self.path_index]

        -- Check if the mob has reached the current waypoint
        if vector.distance(pos, target_pos) < 0.5 then
            self.path_index = self.path_index + 1 -- Move to the next waypoint
            if not self.path[self.path_index] then
                -- Reached the final waypoint, push into player
                if self.target_player and self.target_player:is_player() then
                    target_pos = self.target_player:get_pos()
                end
                -- Or start attacking
--                 self.object:set_velocity({x = 0, y = 0, z = 0})
--                 self:set_animation("idle")
--                 return
            end
            target_pos = self.path[self.path_index]
        end
        if target_pos == nil then return end

        -- Calculate direction to the next waypoint
        local dir = vector.direction(pos, target_pos)

        -- Calculate target velocity based on direction
        local target_velocity = {
            x = dir.x * mob_config.max_speed,
            y = dir.y * mob_config.max_speed,
            z = dir.z * mob_config.max_speed,
        }

        -- Current velocity
        local current_velocity = self.object:get_velocity() or {x = 0, y = 0, z = 0}

        -- Apply acceleration/deceleration to each axis
        local new_velocity = {
            x = self:calculate_acceleration(current_velocity.x, target_velocity.x, mob_config.acceleration, mob_config.deceleration),
            y = self:calculate_acceleration(current_velocity.y, target_velocity.y, mob_config.acceleration, mob_config.deceleration),
            z = self:calculate_acceleration(current_velocity.z, target_velocity.z, mob_config.acceleration, mob_config.deceleration),
        }

        -- Set the new velocity
        self.object:set_velocity(new_velocity)

        -- Adjust yaw to face the next waypoint
        local yaw = math.atan(dir.z, dir.x) - math.pi / 2
        self.object:set_yaw(yaw)

        -- Determine animation based on current speed
        local speed = vector.length(new_velocity)
        if speed > mob_config.max_speed * 0.5 then
            self:set_animation("run")
        elseif speed > 0 then
            self:set_animation("walk")
        else
            self:set_animation("idle")
        end
    end,

    get_player_in_view = function(self, pos)
        local players = minetest.get_connected_players()
        for _, player in ipairs(players) do
            -- Lua 5.1 "continue" idiom: repeat..until true + break (goto removed
            -- for strict-Lua-5.1 compatibility; see issue #1).
            repeat
            if not player or not player:is_player() then
                break
            end
            
            local player_pos = player:get_pos()
            if not player_pos then
                break
            end

            -- Calculate distance to the player
            local dist = vector.distance(pos, player_pos)
            if dist > mob_config.view_distance then
                break
            end

            -- Calculate direction and angle between mob's yaw and player
            local dir = vector.direction(pos, player_pos)
            local yaw = self.object:get_yaw()
            local mob_dir = {x = math.cos(yaw), y = 0, z = math.sin(yaw)}
            local angle = math.deg(math.acos(vector.dot(vector.normalize(dir), mob_dir)))

            -- Check if the player is within the view cone
            if angle <= mob_config.view_angle then
                return player
            end
            until true
        end
        return nil
    end,
    on_punch = function(self, hitter, time_from_last_punch, tool_capabilities, dir)
        self:play_sound("hurt")
        -- Optional: Apply knockback or other effects
    end,
    on_death = function(self, killer)
        self:play_sound("death")
        -- Optional: Spawn loot or particles here
    end,
})

minetest.register_node("sl_scary:hide_spot", {
    description = "Hiding Spot",
    drawtype = "nodebox",
-- 	drawtype = "airlike",
	walkable = false,
    node_box = {
        type = "fixed",
        fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}
    },
--     tiles = {"hide_spot_top.png", "hide_spot_bottom.png", "hide_spot_side.png"},
    -- sl_essence_value = 2: hideout price paid to the MM pool when a
    -- crew-placed Shadow Hideout is destroyed (essence ruling §13.3).
    groups = {cracky = 1, sl_essence_value = 2},
})

-- minetest.register_entity("sl_scary:codop", {


-- ============================================================
-- NEW MOBS (high-tech horror, agency-first design)
-- ============================================================
-- Principles from EVENT IDEAS.md:
--   "No random surrealism. Everything has a cause."
--   "Lore is archaeology. Players dig up what went wrong."
--   "Responsibility is horror. The scariest thing is 'I caused this.'"
-- ============================================================

-- Sprite strip frame layout (144×16, 9 frames of 16×16):
--   Frames 0-2  (x: 0-48):   idle   (3 frames, ~2 fps loop)
--   Frames 3-5  (x: 48-96):  walk   (3 frames, ~4 fps loop)
--   Frames 6-7  (x: 96-128): attack (2 frames, ~6 fps loop)
--   Frame 8     (x: 128-144): death  (1 frame, no loop)

local sprite_animations = {
    idle   = {x = 0,   y = 48},
    walk   = {x = 48,  y = 96},
    attack = {x = 96,  y = 128},
    death  = {x = 128, y = 144},
}
local sprite_fps = {
    idle = 2,
    walk = 4,
    attack = 6,
    death = 6,
}

-- Helper: find a player within a cubic range (matches existing codebase API)
local function find_player_in_range(pos, range)
    local players = minetest.get_connected_players()
    for _, player in ipairs(players) do
        if player and player:is_player() then
            local ppos = player:get_pos()
            if ppos and vector.distance(pos, ppos) <= range then
                return player
            end
        end
    end
    return nil
end

-- Helper: find nearest player (returns player + distance)
local function find_nearest_player(pos, range)
    if not attacks_allowed() then return nil, range end
    local players = minetest.get_connected_players()
    local nearest = nil
    local nearest_dist = range
    for _, player in ipairs(players) do
        if player and player:is_player() then
            local ppos = player:get_pos()
            if ppos then
                local d = vector.distance(pos, ppos)
                if d <= nearest_dist then
                    nearest = player
                    nearest_dist = d
                end
            end
        end
    end
    return nearest, nearest_dist
end

-- Helper: set animation state on a sprite entity (changes frames if state changed)
local function set_sprite_anim(self, state)
    if self.last_anim_state == state then return end
    self.last_anim_state = state
    local anim = sprite_animations[state]
    local fps = sprite_fps[state]
    if anim then
        self.object:set_animation(anim, fps, state ~= "death" and -1 or 0)
    end
end

-- ---------------------------------------------------------
-- DREDGER  (sl_scary:dredger)
-- "Used to be Maintenance Tech Kowalski."
-- Patrols its old route. Stops to "fix" nearby interactable
-- nodes. Attacks when you interrupt the routine.
-- ---------------------------------------------------------

minetest.register_entity("sl_scary:dredger", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.4, -0.5, -0.4, 0.4, 0.5, 0.4},
        visual = "sprite",
        textures = {"sl_scary_dredger_strip.png"},
        visual_size = {x=1.8, y=1.8, z=1.8},
        static_save = false,
        glow = 4,
        pointable = true,
        hp_max = 40,
        makes_footstep_sound = false,
        automatic_rotate = 0, -- degrees per second; 0 = no rotation (number, not bool)
        automatic_face_movement_dir = false,
    },

    -- Configuration
    patrol_radius = 20,
    patrol_speed = 1.2,
    chase_speed = 3.0,
    detection_range = 12,
    attack_range = 1.2,
    attack_damage = 4,
    attack_cooldown = 1.5,
    distraction_chance = 0.35,
    interactable_nodes = {
        "sl_scary:hide_spot",
        "group:terminal",
        "group:machine",
    },

    -- State
    state = "patrol",
    anim_state = "idle",
    patrol_target = nil,
    patrol_origin = nil,
    target_player = nil,
    timer = 0,
    attack_timer = 0,
    idle_timer = 0,
    was_patrolling_pos = nil,

    on_activate = function(self, staticdata, dtime_s)
        self.state = "patrol"
        local pos = self.object:get_pos()
        if pos then
            self.patrol_origin = {x = pos.x, y = pos.y, z = pos.z}
        end
        self:select_patrol_target()
        set_sprite_anim(self, "idle")
    end,

    select_patrol_target = function(self)
        local origin = self.patrol_origin or self.object:get_pos()
        if not origin then return end
        local angle = math.random() * math.pi * 2
        local dist = math.random(5, self.patrol_radius)
        self.patrol_target = {
            x = origin.x + math.cos(angle) * dist,
            y = origin.y,
            z = origin.z + math.sin(angle) * dist,
        }
    end,

    find_nearby_interactable = function(self, pos)
        local nodes = minetest.find_nodes_in_area(
            vector.subtract(pos, 4),
            vector.add(pos, 4),
            self.interactable_nodes
        )
        if nodes and #nodes > 0 then
            return nodes[math.random(1, #nodes)]
        end
        return nil
    end,

    move_toward = function(self, target_pos, speed, dtime)
        local pos = self.object:get_pos()
        if not pos or not target_pos then return false end
        local dir = vector.subtract(target_pos, pos)
        dir.y = 0
        local dist = vector.length(dir)
        if dist < 0.3 then return true end
        dir = vector.normalize(dir)
        local step = math.min(speed * dtime, dist)
        local new_pos = vector.add(pos, vector.multiply(dir, step))
        new_pos.y = pos.y
        self.object:set_pos(new_pos)
        -- Rotate to face movement direction
        local yaw = math.atan2(dir.z, dir.x) - math.pi / 2
        self.object:set_yaw(yaw)
        return false
    end,

    do_attack = function(self, player, dtime)
        if not attacks_allowed() then return end -- lobby safety
        self.attack_timer = self.attack_timer - dtime
        if self.attack_timer > 0 then return end
        local pos = self.object:get_pos()
        local player_pos = player:get_pos()
        if not pos or not player_pos then return end
        local dist = vector.distance(pos, player_pos)
        if dist > self.attack_range then return end
        local hp = player:get_hp()
        if hp then
            player:set_hp(hp - self.attack_damage)
            minetest.sound_play("scary_attack", {pos = pos, gain = 0.7, max_hear_distance = 16})
        end
        self.attack_timer = self.attack_cooldown
    end,

    on_step = function(self, dtime)
        self.timer = self.timer + dtime
        self.attack_timer = self.attack_timer - dtime
        local pos = self.object:get_pos()
        if not pos then return end

        if self.state == "patrol" then
            set_sprite_anim(self, "idle")
            local arrived = self:move_toward(self.patrol_target, self.patrol_speed, dtime)
            -- Distraction check: pause to "fix" nearby interactable
            if self.timer > 2.0 then
                self.timer = 0
                local interactable = self:find_nearby_interactable(pos)
                if interactable and math.random() < self.distraction_chance then
                    self.state = "working"
                    self.idle_timer = 2.0 + math.random() * 3.0
                    self.work_target = interactable
                    return
                end
            end
            if arrived then
                self.idle_timer = 1.0 + math.random() * 2.0
                self.state = "idle"
                self:select_patrol_target()
            end
            -- Player detection
            local player = find_player_in_range(pos, self.detection_range)
            if player then
                self.state = "chase"
                self.target_player = player
                self.was_patrolling_pos = self.patrol_target
            end

        elseif self.state == "idle" then
            set_sprite_anim(self, "idle")
            self.idle_timer = self.idle_timer - dtime
            if self.idle_timer <= 0 then
                self.state = "patrol"
            end

        elseif self.state == "working" then
            set_sprite_anim(self, "idle")
            self.idle_timer = self.idle_timer - dtime
            if self.idle_timer <= 0 then
                self.state = "patrol"
                self.work_target = nil
            end
            -- If player gets close while working, aggro (interrupted routine)
            local player = find_player_in_range(pos, 3)
            if player then
                self.state = "chase"
                self.target_player = player
                self.work_target = nil
            end

        elseif self.state == "chase" then
            set_sprite_anim(self, "walk")
            if not self.target_player or not self.target_player:is_player() then
                self.state = "patrol"
                self.target_player = nil
                if self.was_patrolling_pos then
                    self.patrol_target = self.was_patrolling_pos
                end
                return
            end
            local player_pos = self.target_player:get_pos()
            local dist = player_pos and vector.distance(pos, player_pos) or 999
            -- Lose target if too far
            if dist > self.detection_range * 2 then
                self.state = "patrol"
                self.target_player = nil
                if self.was_patrolling_pos then
                    self.patrol_target = self.was_patrolling_pos
                end
                return
            end
            -- Attack or chase
            if dist <= self.attack_range then
                set_sprite_anim(self, "attack")
                self:do_attack(self.target_player, dtime)
            else
                self:move_toward(player_pos, self.chase_speed, dtime)
            end
        end
    end,

    on_punch = function(self, hitter, time_from_last_punch, tool_capabilities, dir)
        if hitter and hitter:is_player() then
            self.state = "chase"
            self.target_player = hitter
        end
    end,

    on_death = function(self, killer)
        set_sprite_anim(self, "death")
        local pos = self.object:get_pos()
        if pos then
            minetest.add_item(pos, "sl_scary:dredger_badge")
            minetest.sound_play("mob_death", {pos = pos, gain = 0.8, max_hear_distance = 16})
        end
    end,
})

minetest.register_craftitem("sl_scary:dredger_badge", {
    description = "Dredger ID Badge — 'KOWALSKI, F. — Maintenance Tech'\n" ..
                  "Overtime log: 96h continuous before incident.\n" ..
                  "'Exposed to hydraulic fluid. Personality changes noted.'",
    inventory_image = "sl_scary_dredger_strip.png^[resize:16x16",
    stack_max = 1,
})

minetest.register_abm({
    label = "Spawn Dredger",
    nodenames = {"group:metal_floor", "default:steelblock"},
    interval = 60,
    chance = 80,
    action = function(pos)
        if minetest.settings:get_bool("creative_mode") then return end
        if #minetest.get_connected_players() == 0 then return end
        if mobpop >= maxmobpop then return end
        minetest.add_entity(vector.add(pos, {x=0, y=1, z=0}), "sl_scary:dredger")
    end,
})

-- ---------------------------------------------------------
-- CONTAINMENT HORROR  (sl_scary:containment)
-- "They sealed it in Section 12. The logs say noise is
--  still reported inside the sealed section."
-- Massive, slow, devastating. Dormant until you get close.
-- Vulnerable after each attack (stun window).
-- ---------------------------------------------------------

minetest.register_entity("sl_scary:containment", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.8, -1.0, -0.8, 0.8, 1.0, 0.8},
        visual = "sprite",
        textures = {"sl_scary_containment_strip.png"},
        visual_size = {x=3.0, y=3.0, z=3.0},
        static_save = false,
        glow = 6,
        pointable = true,
        hp_max = 80,
        makes_footstep_sound = true,
        automatic_rotate = 0, -- degrees per second; 0 = no rotation (number, not bool)
        automatic_face_movement_dir = false,
    },

    detection_range = 25,
    chase_speed = 1.0,
    attack_range = 2.0,
    attack_damage = 10,
    attack_cooldown = 3.0,
    stun_after_attack = 2.5,

    state = "dormant",
    anim_state = "idle",
    target_player = nil,
    timer = 0,
    attack_timer = 0,
    stun_timer = 0,

    on_activate = function(self, staticdata, dtime_s)
        self.state = "dormant"
        set_sprite_anim(self, "idle")
    end,

    on_step = function(self, dtime)
        self.timer = self.timer + dtime
        self.attack_timer = self.attack_timer - dtime
        self.stun_timer = self.stun_timer - dtime
        local pos = self.object:get_pos()
        if not pos then return end

        if self.state == "dormant" then
            set_sprite_anim(self, "idle")
            -- Wake only when player is very close (you chose to enter)
            local player = find_player_in_range(pos, 5)
            if player then
                self.state = "chasing"
                self.target_player = player
                minetest.sound_play("scary_attack", {pos = pos, gain = 1.0, max_hear_distance = 32})
            end

        elseif self.state == "stunned" then
            if self.stun_timer <= 0 then
                self.state = "chasing"
            end

        elseif self.state == "chasing" then
            if not self.target_player or not self.target_player:is_player() then
                self.state = "dormant"
                self.target_player = nil
                return
            end
            local player_pos = self.target_player:get_pos()
            if not player_pos then return end
            local dist = vector.distance(pos, player_pos)
            if dist > self.detection_range * 2 then
                self.state = "dormant"
                self.target_player = nil
                return
            end
            if self.stun_timer > 0 then
                set_sprite_anim(self, "idle")
                return
            end
            if attacks_allowed() and dist <= self.attack_range and self.attack_timer <= 0 then
                set_sprite_anim(self, "attack")
                local hp = self.target_player:get_hp()
                if hp then
                    self.target_player:set_hp(hp - self.attack_damage)
                    minetest.sound_play("scary_attack", {pos = pos, gain = 1.0, max_hear_distance = 24})
                end
                self.attack_timer = self.attack_cooldown
                self.stun_timer = self.stun_after_attack
                return
            end
            set_sprite_anim(self, "walk")
            local dir = vector.normalize(vector.subtract(player_pos, pos))
            local new_pos = vector.add(pos, vector.multiply(dir, self.chase_speed * dtime))
            self.object:set_pos(new_pos)
            local yaw = math.atan2(dir.z, dir.x) - math.pi / 2
            self.object:set_yaw(yaw)
        end
    end,

    on_punch = function(self, hitter, time_from_last_punch, tool_capabilities, dir)
        if self.state == "dormant" then
            self.state = "chasing"
            if hitter and hitter:is_player() then
                self.target_player = hitter
            end
        end
    end,

    on_death = function(self, killer)
        set_sprite_anim(self, "death")
        local pos = self.object:get_pos()
        if pos then
            minetest.add_item(pos, "sl_scary:containment_shard")
            minetest.sound_play("mob_death", {pos = pos, gain = 1.0, max_hear_distance = 32})
        end
    end,
})

minetest.register_craftitem("sl_scary:containment_shard", {
    description = "Containment Shard\n" ..
                  "Bio-mechanical tissue fused with corroded plating.\n" ..
                  "Security Log 0433: 'Noise reported inside Section 12. Sealed.'\n" ..
                  "Security Log 0420: 'Sealed.'\n" ..
                  "Security Log 0352: 'Section 12 sealed.'",
    inventory_image = "sl_scary_containment_strip.png^[resize:16x16",
    stack_max = 3,
})

minetest.register_abm({
    label = "Spawn Containment Horror",
    nodenames = {"group:containment_floor", "default:stone"},
    interval = 180,
    chance = 300,
    action = function(pos)
        if minetest.settings:get_bool("creative_mode") then return end
        if #minetest.get_connected_players() == 0 then return end
        if mobpop >= maxmobpop then return end
        minetest.add_entity(vector.add(pos, {x=0, y=1, z=0}), "sl_scary:containment")
    end,
})

-- ---------------------------------------------------------
-- SIGNAL WRAITH  (sl_scary:signal_wraith)
-- "Ghost data trapped in the signal processing layer."
-- Non-physical (phases through walls). Glitch-teleports.
-- Emits corrupted data fragments on hit/death.
-- ---------------------------------------------------------

minetest.register_entity("sl_scary:signal_wraith", {
    initial_properties = {
        physical = false,
        collide_with_objects = false,
        collisionbox = {-0.3, -0.6, -0.3, 0.3, 0.6, 0.3},
        visual = "sprite",
        textures = {"sl_scary_wraith_strip.png"},
        visual_size = {x=2.0, y=2.0, z=2.0},
        static_save = false,
        glow = 8,
        pointable = true,
        hp_max = 20,
        makes_footstep_sound = false,
        automatic_rotate = 0, -- degrees per second; 0 = no rotation (number, not bool)
        automatic_face_movement_dir = false,
    },

    detection_range = 16,
    chase_speed = 2.5,
    idle_speed = 0.8,
    attack_range = 1.0,
    attack_damage = 3,
    attack_cooldown = 2.0,
    glitch_timer = 0,
    glitch_interval = 3.0,

    state = "idle",
    target_player = nil,
    timer = 0,
    attack_timer = 0,
    drift_target = nil,

    on_activate = function(self, staticdata, dtime_s)
        self.state = "idle"
        self.last_anim_state = nil
        set_sprite_anim(self, "idle")
        self:select_drift_target()
    end,

    select_drift_target = function(self)
        local pos = self.object:get_pos()
        if not pos then return end
        local angle = math.random() * math.pi * 2
        local dist = math.random(3, 8)
        self.drift_target = {
            x = pos.x + math.cos(angle) * dist,
            y = pos.y + (math.random() - 0.5) * 2,
            z = pos.z + math.sin(angle) * dist,
        }
    end,

    on_step = function(self, dtime)
        self.timer = self.timer + dtime
        self.glitch_timer = self.glitch_timer - dtime
        self.attack_timer = self.attack_timer - dtime
        local pos = self.object:get_pos()
        if not pos then return end

        if self.state == "idle" then
            set_sprite_anim(self, "idle")
            if self.drift_target then
                local dist = vector.distance(pos, self.drift_target)
                if dist < 1.0 then
                    self:select_drift_target()
                else
                    local dir = vector.normalize(vector.subtract(self.drift_target, pos))
                    self.object:set_pos(vector.add(pos, vector.multiply(dir, self.idle_speed * dtime)))
                end
            end
            -- Glitch teleport
            if self.glitch_timer <= 0 then
                self.glitch_timer = self.glitch_interval
                local offset = {
                    x = (math.random() - 0.5) * 6,
                    y = (math.random() - 0.5) * 3,
                    z = (math.random() - 0.5) * 6,
                }
                self.object:set_pos(vector.add(pos, offset))
            end
            -- Detect
            local player = find_player_in_range(pos, self.detection_range)
            if player then
                self.state = "chase"
                self.target_player = player
            end

        elseif self.state == "chase" then
            if not self.target_player or not self.target_player:is_player() then
                self.state = "idle"
                self.target_player = nil
                return
            end
            local player_pos = self.target_player:get_pos()
            if not player_pos then return end
            local dist = vector.distance(pos, player_pos)

            if attacks_allowed() and dist <= self.attack_range then
                set_sprite_anim(self, "attack")
                if self.attack_timer <= 0 then
                    local hp = self.target_player:get_hp()
                    if hp then
                        self.target_player:set_hp(hp - self.attack_damage)
                        -- Brief screen distortion (signal corruption)
                        self.target_player:set_eye_offset(
                            {x=(math.random()-0.5)*0.3, y=0, z=(math.random()-0.5)*0.3},
                            {x=(math.random()-0.5)*0.3, y=0, z=(math.random()-0.5)*0.3}
                        )
                        local p = self.target_player
                        minetest.after(0.3, function()
                            if p and p:is_player() then
                                p:set_eye_offset({x=0,y=0,z=0}, {x=0,y=0,z=0})
                            end
                        end)
                    end
                    self.attack_timer = self.attack_cooldown
                end
            else
                set_sprite_anim(self, "walk")
                local dir = vector.normalize(vector.subtract(player_pos, pos))
                self.object:set_pos(vector.add(pos, vector.multiply(dir, self.chase_speed * dtime)))
            end
            -- Glitch during chase
            if self.glitch_timer <= 0 and dist > 3 then
                self.glitch_timer = self.glitch_interval
                local offset = {
                    x = (math.random() - 0.5) * 4,
                    y = (math.random() - 0.5) * 2,
                    z = (math.random() - 0.5) * 4,
                }
                self.object:set_pos(vector.add(pos, offset))
            end
            if dist > self.detection_range * 1.5 then
                self.state = "idle"
                self.target_player = nil
            end
        end
    end,

    on_punch = function(self, hitter, time_from_last_punch, tool_capabilities, dir)
        if math.random() < 0.5 then
            local pos = self.object:get_pos()
            if pos then
                self.object:set_pos(vector.add(pos, {
                    x=(math.random()-0.5)*8,
                    y=(math.random()-0.5)*4,
                    z=(math.random()-0.5)*8,
                }))
            end
            local pos = self.object:get_pos()
            if pos then
                minetest.add_item(pos, "sl_scary:corrupted_data")
            end
        end
    end,

    on_death = function(self, killer)
        set_sprite_anim(self, "death")
        local pos = self.object:get_pos()
        if pos then
            minetest.add_item(pos, "sl_scary:corrupted_data")
            minetest.add_item(pos, "sl_scary:corrupted_data")
            minetest.sound_play("mob_death", {pos = pos, gain = 0.6, max_hear_distance = 12})
        end
    end,
})

minetest.register_craftitem("sl_scary:corrupted_data", {
    description = "Corrupted Data Fragment\n" ..
                  "\"...breach in sector...signal integrity compromised...\"\n" ..
                  "Reliability: UNKNOWN",
    inventory_image = "sl_scary_wraith_strip.png^[resize:16x16",
    stack_max = 5,
})

minetest.register_abm({
    label = "Spawn Signal Wraith",
    nodenames = {"group:terminal", "default:mese_post_light", "group:beacon"},
    interval = 90,
    chance = 120,
    action = function(pos)
        if minetest.settings:get_bool("creative_mode") then return end
        if #minetest.get_connected_players() == 0 then return end
        if mobpop >= maxmobpop then return end
        minetest.add_entity(vector.add(pos, {x=0, y=2, z=0}), "sl_scary:signal_wraith")
    end,
})

-- ---------------------------------------------------------
-- Dev commands (creative-only)
-- ---------------------------------------------------------

minetest.register_chatcommand("sl_spawn_dredger", {
    description = "Spawn a Dredger at your position (creative only)",
    privs = {creative = true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return end
        local pos = player:get_pos()
        if not pos then return end
        pos.y = pos.y + 1
        minetest.add_entity(pos, "sl_scary:dredger")
        return true, "Dredger spawned."
    end,
})

minetest.register_chatcommand("sl_spawn_wraith", {
    description = "Spawn a Signal Wraith at your position (creative only)",
    privs = {creative = true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return end
        local pos = player:get_pos()
        if not pos then return end
        pos.y = pos.y + 2
        minetest.add_entity(pos, "sl_scary:signal_wraith")
        return true, "Signal Wraith spawned."
    end,
})

minetest.register_chatcommand("sl_spawn_containment", {
    description = "Spawn a Containment Horror at your position (creative only)",
    privs = {creative = true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return end
        local pos = player:get_pos()
        if not pos then return end
        pos.y = pos.y + 1
        minetest.add_entity(pos, "sl_scary:containment")
        return true, "Containment Horror spawned."
    end,
})
