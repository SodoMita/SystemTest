-- Register a callback for when a player joins the game
minetest.register_on_joinplayer(function(player)
    -- Set a monochrome and creepy sky for the player
	local sky = {
        base_color = "#000000",  -- Base color for a dark, creepy effect
        type = "regular",
        sky_color = {
            -- Using shades of a single color for a monochrome effect
            day_sky = "#222222",
            day_horizon = "#333333",
            dawn_sky = "#111111",
            dawn_horizon = "#222222",
            night_sky = "#000000",
            night_horizon = "#000000",
            indoors = "#000000",  -- Darker indoors for creepy effect
            -- Adjusting fog tints for a ghostly, eerie look
            fog_sun_tint = "#000000",
            fog_moon_tint = "#000000",
            fog_tint_type = "custom"
        }
    }
    
    -- Apply the sky settings to the player
    player:set_sky(sky)
    player:set_stars({
        count = 3
    })

    -- Play a looping creepy ambient sound
    -- minetest.sound_play("creepy_ambient", {
    --     to_player = player:get_player_name(),
    --     gain = 0.5,  -- Volume of the sound
    --     loop = true  -- Loop the sound
    -- })

	player:set_sun({visible = true, sunrise_visible = true, texture = "round_sun.png"})


    -- Send the player a spooky message when they join
    minetest.chat_send_player(player:get_player_name(), "You feel an unsettling chill in the air...")
end)

-- Random creepy messages during gameplay
local creepy_messages = {
    -- Whispers and voices
    "You feel like something is watching you...",
    "The silence is deafening.",
    "You hear faint whispers in the distance.",
    "The air feels heavy and cold.",
    "A faint voice calls your name, then vanishes.",
    "You hear a distant scream, then silence.",
    "The wind carries an eerie tune.",
    "Soft murmurs echo around you, but no one is there.",
    "A whisper brushes past your ear, but the wind is still.",
    "You hear footsteps behind you, but no one is there.",
    "The sound of breathing grows louder, then stops.",
    "You hear someone calling for help, but it feels wrong.",
    "A faint laugh echoes in the fog.",
    "Faint cries of children drift through the air.",
    "You hear a door creaking, but there's no door nearby.",
    "A voice whispers, 'Don't turn around.'",
    "The wind carries faint but unsettling laughter.",
    "You hear faint chanting in the distance.",
    "A whisper says, 'Leave while you still can.'",
    "You hear a faint knock, but there's no door nearby.",
    
    -- Shadows and movement
    "Shadows flicker in the fog.",
    "You see something move out of the corner of your eye.",
    "A shadow darts past, just out of reach.",
    "The darkness feels alive.",
    "Your own shadow looks distorted.",
    "You think you saw something, but it’s gone now.",
    "Something is moving in the distance.",
    "You feel like the trees are watching you.",
    "You see a figure ahead, but when you blink, it's gone.",
    "A shadow crawls across the ground, but nothing casts it.",
    "You feel like you're being followed.",
    "You could swear you saw eyes glowing in the dark.",
    "Something brushes past your leg, but nothing is there.",
    "The fog seems to shift and writhe.",
    "You see footprints appear in the dirt, but no one is making them.",
    "A silhouette stands in the distance, then vanishes.",
    "You spot movement in the corner of your vision.",
    "A dark figure looms behind you in the fog... but it’s gone.",
    "You feel an invisible presence nearby.",
    "The shadows seem to stretch toward you.",

    -- Cold and physical sensations
    "A chill runs down your spine.",
    "The air feels heavy and cold.",
    "Your breath turns visible, but it's not that cold.",
    "You feel a cold hand on your shoulder, but no one is there.",
    "The ground feels colder with every step.",
    "You shiver, but there's no breeze.",
    "The temperature suddenly drops.",
    "Your limbs feel heavier, as if something is holding you back.",
    "Cold air brushes past your neck.",
    "Your hands feel numb, even though they're covered.",
    "The cold seems to seep into your bones.",
    "You suddenly feel lightheaded, as if something is draining you.",
    "Your skin prickles, as if someone is watching you.",
    "Your legs feel weak, but you don't know why.",
    "You feel a weight pressing down on your chest.",
    "Every step feels harder, as if something is pulling you back.",
    "You feel something cold brush against your face.",
    "Your heart races for no reason.",
    "Your hands tremble, but you’re not afraid... are you?",
    "You feel a sudden, sharp pain in your back, but there's nothing there.",

    -- Strange sounds
    "A distant bell tolls in the fog.",
    "You hear the faint sound of chains rattling.",
    "A low growl echoes through the air.",
    "The sound of dripping water grows louder.",
    "You hear the crunch of leaves behind you.",
    "A faint hum fills the air, but there's no source.",
    "The ground beneath you groans, as if alive.",
    "A far-off howl pierces the silence.",
    "The sound of a clock ticking grows louder, but you see no clock.",
    "The wind carries the sound of metal scraping.",
    "You hear the sound of footsteps running past you.",
    "A faint metallic clang echoes in the distance.",
    "A deep, guttural laugh rumbles somewhere nearby.",
    "The sound of a baby crying echoes, then stops abruptly.",
    "You hear whispers in a language you don't understand.",
    "The sound of creaking wood grows louder.",
    "A faint melody plays in the distance, but it’s off-key.",
    "The sound of glass breaking makes you jump, but nothing is there.",
    "The sound of heavy breathing comes from the shadows.",
    "A faint dripping sound echoes in the distance.",

    -- Unexplainable phenomena
    "The fog seems to close in around you.",
    "The ground beneath you seems to shift slightly.",
    "Your vision blurs for a moment, then clears.",
    "The trees seem to move closer when you're not looking.",
    "Your footsteps echo louder than they should.",
    "You feel like you're walking in circles.",
    "The air feels thick, as if you're underwater.",
    "The path ahead seems to stretch endlessly.",
    "You see your breath, but it's not cold.",
    "You hear a clock ticking, but there’s no clock.",
    "The sky darkens, even though it’s already night.",
    "You feel like you’re sinking, but the ground is firm.",
    "The air feels suffocatingly heavy.",
    "You feel like the world is closing in on you.",
    "The fog swirls unnaturally, forming strange shapes.",
    "You feel like you’ve been here before, but you haven’t.",
    "The shadows seem to pulse in time with your heartbeat.",
    "The ground feels soft, like it's not entirely solid.",
    "The sky seems to flicker, as if it’s not real.",
    "You feel like you're being pulled in an unknown direction.",

    -- Miscellaneous creepy details
    "You step on something soft, but there’s nothing there.",
    "You smell something rotting, but the air is clear.",
    "A strange taste fills your mouth suddenly.",
    "You feel like you're forgetting something important.",
    "Your vision dims for a moment, then returns.",
    "The trees seem to whisper to each other.",
    "You feel like the ground is watching you.",
    "You hear soft laughter, but it’s not friendly.",
    "Your footsteps sound louder than usual.",
    "The air smells faintly of sulfur.",
    "The ground feels sticky beneath your feet.",
    "You see faint, glowing symbols in the fog.",
    "The sound of a heartbeat echoes in your ears.",
    "A faint light flickers in the distance, then disappears.",
    "Your shadow seems to move on its own.",
    "The sky feels lower than it should be.",
    "You feel uncomfortably exposed, even though you're alone.",
    "The fog feels like it's clinging to your skin.",
    "You feel like something is lurking just out of sight.",
    "Your reflection in the water looks... wrong."
}

-- Send random creepy messages to players during gameplay
-- minetest.register_globalstep(function(dtime)
--     for _, player in ipairs(minetest.get_connected_players()) do
--         if math.random(1, 5000) == 1 then  -- Rare chance to send a message
--             minetest.chat_send_player(player:get_player_name(), creepy_messages[math.random(#creepy_messages)])
--         end
--     end
-- end)

-- Function to send a random creepy message to a random player
local function send_creepy_message()
    local players = minetest.get_connected_players()
    if #players > 0 then
        -- Pick a random player
        local player = players[math.random(#players)]
        -- Send a random message
        minetest.chat_send_player(player:get_player_name(), creepy_messages[math.random(#creepy_messages)])
    end

    -- Schedule the next creepy message
    minetest.after(math.random(30, 120), send_creepy_message) -- Random interval between 30 and 120 seconds
end

-- Start the creepy message loop
minetest.after(10, send_creepy_message) -- Initial delay of 10 seconds
