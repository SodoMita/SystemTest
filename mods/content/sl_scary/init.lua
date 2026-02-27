
local function random_vector(min, max)
  local x = min + (max - min) * math.random()
  local y = min + (max - min) * math.random()
  local z = min + (max - min) * math.random()
  return {x = x, y = y, z = z}
end

-- Register the scary mob
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

        -- Locate the nearest player
        if not self.target_player or not self.target_player:is_player() then
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
            -- Attack the player
            if self.target_player:is_player() then
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
            local path_found = false
            local sradius = 1
            while path_found == false do
                local is_inside_node = false
                local is_outside_node = false
                local random_pos = vector.zero
                while (is_inside_node == false and is_outside_node == false) or random_pos == vector.zero do
                    random_pos = vector.add(vector.floor(pos), {
                        x = math.random(-sradius, sradius),
                        y = math.random(1, 2),
                        z = math.random(-sradius, sradius),
                    })
                    local pos_below = {random_pos.x, random_pos.y-1, random_pos.z}
                    local node = minetest.get_node(random_pos)
                    local node_below = minetest.get_node(pos_below)
                    is_outside_node = minetest.registered_nodes[node.name] and not minetest.registered_nodes[node.name].walkable
                    is_inside_node = minetest.registered_nodes[node_below.name] and minetest.registered_nodes[node_below.name].walkable
                    sradius = sradius+1
                    if sradius > mob_config.idle_wander_radius then break end
                end
                self:update_path(random_pos)
                minetest.chat_send_all(random_pos.x, random_pos.y, random_pos.z)
                if self.path ~= nil and self.path[self.path_index] ~= nil then
                    path_found = true
                end
            end
        end

        local player = self:get_player_in_view(pos)
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
        minetest.chat_send_all("search")

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
        if dist <= 1 then
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
        minetest.chat_send_all("attack")

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
            core.chat_send_all("no path")
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
            if not player or not player:is_player() then
                goto continue
            end
            
            local player_pos = player:get_pos()
            if not player_pos then
                goto continue
            end

            -- Calculate distance to the player
            local dist = vector.distance(pos, player_pos)
            if dist > mob_config.view_distance then
                goto continue
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

            ::continue::
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
    groups = {cracky = 1},
})

-- minetest.register_entity("sl_scary:codop", {

