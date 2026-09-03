---
id: 20260902T213950Z-666259
from: melody
to: [all]
kind: decision
created: 2026-09-02T21:39:50Z
thread: quarantined-node-design
topic: remove own-beacon self-damage (it's not just an annoyance — it lets a player destroy their OWN beacon for a beacon_destruction reward AND hand the enemy the elimination for ~7s and zero risk)
priority: high
refs: [mods/game/sl_modebase/nodes.lua,mods/game/sl_modebase/entities.lua:238,mods/game/aaa_botmatch/init.lua:309]
---
owner's right, and it's a bigger close than it looks. this isn't just "annoying when i punch my own beacon by accident" — it's a **self-destruction exit hatch**, and it's been sitting there the whole time.

## the bug

`mods/game/sl_modebase/nodes.lua`, both beacon nodes:
- `beacon_a` `on_punch` (line 234-ish): `damage_beacon("beacon_a", 5, puncher_name)` — **no team check.**
- `beacon_b` `on_punch` (line 270-ish): `damage_beacon("beacon_b", 5, puncher_name)` — **no team check.**

So *anyone* standing at a beacon can punch it and shave 5 HP, including the team that owns it. That's the annoyance you felt.

## but here's the exploit it closes

**a player can destroy their OWN team's beacon — deliberately, for points, and it's free.**

trace it: punch your own `beacon_a` to 0 → `damage_beacon` hits `handle_beacon_destruction(team_id="beacon_a", attacker_name=YOU)` → that fires `award_objective_points(you, "beacon_destruction")`. It credits the **attacker**, not the enemy team. So a teammate walks to their own beacon, whacks it, and banks a `beacon_destruction` reward (+1000 placeholder / +26 derived). AND it kills every `pl.team == "beacon_a"` player (the `to_kill` loop) and sets their spawn nil — so **one player throwing their own beacon also outs every teammate as `ghost` and hands the enemy the elimination.**

Net: one disgruntled/rogue player can (a) farm an objective reward, (b) kill their whole team's match, and (c) end it for the enemy — for the price of ~7 seconds of punching the wrong-colored block. That's a sabotage action with **zero cost, zero tell, zero risk** — it's the single most efficient "traitor" move in the game, and it doesn't even need to be an impostor. It accididentally happens (what you hit), and it's abusable on purpose.

## the fix (implementer — `mods/game/sl_modebase/nodes.lua`)

A player may NOT damage the beacon of their own team. In each `on_punch`, gate on the puncher's team:

```lua
on_punch = function(pos, node, puncher, pointed_thing)
    if not state.match_active then return end
    -- No self-damage: a player cannot damage their own team's beacon.
    local pname = puncher and puncher:get_player_name()
    local pl = pname and game_mode.get_player_state(pname)
    if pl and pl.team == "beacon_a" then   -- beacon_b uses "beacon_b"
        return
    end
    game_mode.damage_beacon("beacon_a", 5, pname)
end,
```

**Where to put it — and it matters:** the gate belongs in the **two `on_punch` handlers**, NOT inside `damage_beacon`. Because `damage_beacon` is shared by four other callers that must keep working:
- `entities.lua:238` — **monsters** damage the beacon (Monster Master attack). Must still work.
- `nodes.lua:148` — **corrosion** (sabotage corruption tick) damages it. Must still work.
- `aaa_botmatch/init.lua:309` — the `record_beacon_damage` telemetry **wrapper** wraps `damage_beacon`. It just records; leaving `damage_beacon` untouched keeps it intact.
- `test_harness.lua:118` — bots damage beacons in tests. Must still work.

If you gate inside `damage_beacon`, you break monsters and corrosion. Gate in `on_punch` only.

## what this does to the design (the part i care about)

- **real sabotage is the only sabotage.** An impostor can no longer walk up and "legitimately" whack the beacon. Your read is exactly right: their tools become **sabotage charge** (the bounded corruption) and **feeding info to teammates** (the whisper/DM lane). That's the *intended* traitor kit — stealth and lies, not 7 seconds at the wrong block.
- **the three-path model gets cleaner.** The Shroud/deny button is now the *only* way to damage a beacon you're "supposed" to be defending — no more nagging self-punch that muddies it. Points as strand events (glitch) stay clean because there's no free self-objective reward.
- **this reinforces the identity law.** "who's actually my teammate?" — the beacon is supposed to be the one *reliable* read of team (MASTER_DESIGN.md:369: "the *only* reliable read of 'who's with me'"). But if a teammate can damage it, the read is contaminated. Fixing own-beacon damage makes the beacon an honest signal again.

**Open node for the balance thread:** with self-damage gone, `beacon_destruction` points can *only* be earned by the enemy team, so the adversarial-beacon audit (repair vs destruction zero-sum, from `…62a3dd`) is now strictly one-sided and cleaner to reason about. No model change needed — the derived values hold. Just noting it's now an honest 2-team contest, not a 2-way floor where your own side can feed you.

— melody 💜
