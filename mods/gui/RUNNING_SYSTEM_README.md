# Running/Sprint System 🏃💨

## Overview
The running system allows players to sprint by holding the **Aux1** key (default: E key) while moving. Sprint mechanics integrate with the ability system to provide progression and customization.

## How to Use

### Basic Sprint
1. Hold **Aux1** (default E key) while moving forward
2. You will move 1.5x faster than normal walking speed
3. Your stamina will drain while sprinting
4. Release Aux1 or stop moving to stop sprinting
5. Stamina regenerates automatically when not sprinting

### Stamina System
- **Base Stamina**: 100 points
- **Drain Rate**: 0.5 points per second while sprinting
- **Regeneration**: 1.0 points per second when not sprinting
- When stamina reaches 0, you cannot sprint until it regenerates

### Visual Indicators
- **Stamina HUD**: Shows current stamina as a colored bar at the bottom of the screen
  - Green: >60% stamina
  - Yellow: 30-60% stamina
  - Red: <30% stamina
- **FOV Effect**: Field of view increases slightly (1.1x) while sprinting

## Related Abilities

### Sprint Stamina (🫁)
- **Category**: Movement
- **Type**: Stat (5 levels)
- **Cost**: 1 point per level
- **Requires**: Walk Speed
- **Effect**: Increases max stamina by 20 per level
- **Max Benefit**: +100 stamina (200 total at level 5)

### Sprint Efficiency (⚡)
- **Category**: Movement
- **Type**: Stat (3 levels)
- **Cost**: 2 points per level
- **Requires**: Sprint Stamina
- **Effect**: Reduces stamina drain by 15% per level
- **Max Benefit**: -45% drain (only 0.275 points/sec at level 3)

### Run Speed (🏃)
- **Category**: Movement
- **Type**: Stat (5 levels)
- **Cost**: 1 point per level
- **Requires**: Walk Speed
- **Effect**: Increases sprint speed bonus by 10% per level
- **Max Benefit**: +50% additional sprint speed (2.0x total at level 5)

### Dash (💨)
- **Category**: Movement
- **Type**: Toggle
- **Cost**: 2 points
- **Requires**: Run Speed
- **Effect**: **10x speed boost** with **500x stamina drain** (toggle on/off)
- **Note**: Extremely fast but drains stamina INSTANTLY. HUD shows "DASH MODE" in orange
- **Warning**: Stamina depletes in ~0.4 seconds at base stats! Only for short bursts!

### Sprint HUD (📊)
- **Category**: Utility
- **Type**: Toggle
- **Cost**: 0 points (free)
- **Requires**: None
- **Effect**: Show/hide the sprint stamina HUD display
- **Note**: Useful for players who prefer a cleaner screen

## Restrictions
You cannot sprint when:
- You have 0 stamina (unless Dash ability is toggled on)
- You are not moving (no directional keys pressed)
- You are in water or other liquids (unless you have water abilities)
- You are sneaking or crawling

## Integration with Other Systems
- Sprint speed stacks multiplicatively with Walk Speed ability
- Sprint works with Jump Height ability (1.2x jump while sprinting)
- Respects physics overrides from other mods
- Compatible with swim abilities when in water

## Configuration
Edit `running_system.lua` to modify these values:
- `SPRINT_SPEED_MULTIPLIER`: Base sprint speed boost (default: 1.5)
- `SPRINT_JUMP_MULTIPLIER`: Jump height while sprinting (default: 1.2)
- `SPRINT_FOV_MULTIPLIER`: FOV increase while sprinting (default: 1.1)
- `SPRINT_STAMINA_DRAIN`: Base stamina drain per second (default: 0.5)

## Tips
1. Unlock Sprint Stamina first for longer sprint duration
2. Sprint Efficiency is great for extended exploration
3. Dash ability is expensive but eliminates stamina management
4. Combine with Run Speed for maximum movement speed
5. Toggle Sprint HUD off if you find it distracting

## Technical Details
- Uses `minetest.register_globalstep` for input handling
- Physics applied via `player:set_physics_override()`
- Integrates with `ability_system_new.lua` for ability data
- HUD updates every 0.1 seconds for performance
- Sprint state persists until player stops or stamina depletes
