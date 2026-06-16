-- DISABLED: Broken GUI that prevents inventory access
-- TODO: Implement proper urban-themed GUI later

--[[
minetest.register_on_joinplayer(function(player)
    local player_name = player:get_player_name()
    -- Initialize player attributes only
    player:set_attribute("experience", 0)
end)
--]]

-- Example: Increase experience when player digs and play a sound
minetest.register_on_dignode(function(pos, oldnode, digger)
    local player_name = digger:get_player_name()
    local experience = digger:get_attribute("experience") or 0

    -- Increase experience
    experience = experience + 1
    digger:set_attribute("experience", experience)

    -- Play a sound when the player digs
    local sound_spec = {name = "level_up_sound", gain = 1.0, pitch = 1.0, fade = 0.0}
    local sound_params = {gain = 1.0, pitch = 1.0, fade = 0.0}
    minetest.sound_play(sound_spec, sound_params)

    -- Check if player leveled up
    if experience % 100 == 0 then
        local player_level = experience / 100
        digger:set_attribute("experience", 0)
        digger:set_hp(20)  -- Reset health on level up (adjust as needed)

        -- Show level up message
        minetest.chat_send_player(player_name, "Congratulations! You leveled up to level " .. player_level)
    end
end)
