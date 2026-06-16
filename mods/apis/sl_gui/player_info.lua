-- =============================================================
-- System Looting — Player Info Tab
-- =============================================================
-- Shows team assignment, role, lives, match status, and stats.
-- Integrates with sl_modebase (game_mode global).
-- =============================================================

function get_player_info_formspec(player)
    local name = player:get_player_name()
    local meta = player:get_meta()

    -- Experience / level
    local exp   = tonumber(meta:get_string("experience")) or 0
    local level = math.floor(exp / 100) + 1
    local current_xp   = exp - ((level - 1) * 100)
    local next_level_xp = 100

    -- Player model
    local player_textures = (player_api and player_api.get_textures
        and player_api.get_textures(player)) or {"character.png"}

    local formspec = {
        "formspec_version[4]",
        "size[12,11.8]",
        "bgcolor[#1a1a1aff;true]",

        -- 3D preview
        "box[0.2,0.3;1.5,1.5;#1a1a1aff]",
        string.format(
            "model[0.3,0.4;1.3,1.3;player_preview;character.b3d;%s;0,170;false;false;0,0]",
            table.concat(player_textures, ",")),
        "image_button[0.3,0.4;1.3,1.3;;open_outfit;]",

        -- Header
        "box[0.2,1.9;11.6,0.6;#2a2a2aff]",
        "label[0.5,2.2;Player Info]",
    }

    -- ---- Player identity -----------------------------------------
    table.insert(formspec, "box[0.3,2.7;5.3,3.5;#151515ff]")
    table.insert(formspec, string.format("label[0.5,3.0;Name: %s]", minetest.formspec_escape(name)))
    table.insert(formspec, string.format("label[0.5,3.4;Level: %d]", level))
    table.insert(formspec, string.format("label[0.5,3.8;XP: %d / %d]", current_xp, next_level_xp))

    -- XP progress bar
    local pct = current_xp / next_level_xp
    table.insert(formspec, "box[0.5,4.1;4.5,0.3;#2a2a2aff]")
    table.insert(formspec, string.format("box[0.5,4.1;%f,0.3;#4a9a4aff]", 4.5 * pct))
    table.insert(formspec, string.format("label[2.5,4.15;%.0f%%]", pct * 100))

    -- Health
    local hp     = player:get_hp()
    local hp_max = player:get_properties().hp_max or 20
    table.insert(formspec, string.format("label[0.5,4.7;HP: %d / %d]", hp, hp_max))

    -- Breath
    local breath     = player:get_breath()
    local breath_max = player:get_properties().breath_max or 10
    table.insert(formspec, string.format("label[0.5,5.1;Breath: %d / %d]", breath, breath_max))

    -- Sprint stamina (from running_system)
    if get_player_sprint_stamina then
        local stam, stam_max = get_player_sprint_stamina(player)
        table.insert(formspec, string.format("label[0.5,5.5;Stamina: %d / %d]",
            math.floor(stam), stam_max))
    end

    -- ---- Team / Match info ---------------------------------------
    table.insert(formspec, "box[5.8,2.7;5.8,3.5;#151515ff]")

    if rawget(_G, "game_mode") and game_mode.state then
        local state = game_mode.state
        local pl    = game_mode.get_player_state(name)

        -- Role
        local role_label = "Player"
        if pl.role == "monster_master" then role_label = "Monster Master" end
        table.insert(formspec, string.format("label[6.0,3.0;Role: %s]", role_label))

        -- Team
        if pl.team then
            local team_label = game_mode.get_team_label(pl.team)
            local team_color = game_mode.get_team_color(pl.team)
            table.insert(formspec, string.format("label[6.0,3.4;Team: %s]",
                minetest.colorize(team_color, team_label)))
        else
            table.insert(formspec, "label[6.0,3.4;Team: None]")
        end

        -- Lives
        table.insert(formspec, string.format("label[6.0,3.8;Lives: %d]", pl.lives or 0))
        if pl.eliminated then
            table.insert(formspec, "label[6.0,4.2;Status: ELIMINATED]")
        else
            table.insert(formspec, "label[6.0,4.2;Status: Active]")
        end

        -- Match
        if state.match_active then
            table.insert(formspec, string.format(
                "label[6.0,4.6;Match #%d — In Progress]", state.match_count or 0))
        else
            table.insert(formspec, "label[6.0,4.6;No active match]")
        end

        -- Team roster
        table.insert(formspec, "label[6.0,5.1;Team Roster:]")
        local roster_y = 5.4
        if pl.team then
            for pname, pdata in pairs(state.players) do
                if pdata.team == pl.team then
                    local status = pdata.eliminated and " (OUT)" or ""
                    local c = pdata.eliminated and "#777777" or "#cccccc"
                    table.insert(formspec, string.format("label[6.2,%f;%s]",
                        roster_y, minetest.colorize(c, pname .. status)))
                    roster_y = roster_y + 0.3
                    if roster_y > 6.0 then break end
                end
            end
        end
    else
        table.insert(formspec, "label[6.0,3.0;Game mode not loaded]")
    end

    -- ---- Ability summary -----------------------------------------
    table.insert(formspec, "box[0.3,6.5;11.3,4.8;#151515ff]")
    table.insert(formspec, "label[0.5,6.8;Active Abilities:]")

    local ab_meta_str = meta:get_string("abilities_v2")
    if ab_meta_str ~= "" then
        local ab_data = minetest.deserialize(ab_meta_str) or {}
        local ab_y = 7.2
        local col = 0
        if ab_data.unlocked then
            for ab_id, lvl in pairs(ab_data.unlocked) do
                if lvl > 0 then
                    local x_off = (col % 2 == 0) and 0.5 or 6.0
                    table.insert(formspec, string.format("label[%f,%f;• %s Lv%d]",
                        x_off, ab_y, ab_id, lvl))
                    if col % 2 == 1 then ab_y = ab_y + 0.35 end
                    col = col + 1
                    if ab_y > 10.8 then break end
                end
            end
        end
        if col == 0 then
            table.insert(formspec, "label[0.5,7.2;No abilities unlocked yet.]")
        end

        -- Stat points remaining
        table.insert(formspec, string.format("label[0.5,11.0;Stat Points Available: %d]",
            ab_data.stat_points or 0))
    else
        table.insert(formspec, "label[0.5,7.2;No abilities unlocked yet.]")
    end

    return table.concat(formspec, "")
end

minetest.log("action", "[player_info] Player Info tab loaded.")
