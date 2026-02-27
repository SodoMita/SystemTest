# Running System Implementation Summary

## What Was Added

### New Files
1. **`running_system.lua`** - Main sprint/running mechanics
   - Aux1 key detection for sprinting
   - Stamina system with drain and regeneration
   - Physics override for sprint speed and jump
   - FOV effect while sprinting
   - HUD display for stamina bar
   - Integration with ability system

2. **`RUNNING_SYSTEM_README.md`** - User documentation
   - How to use the sprint system
   - Ability descriptions
   - Configuration options
   - Tips and restrictions

### Modified Files
1. **`ability_system_new.lua`** - Added sprint-related abilities:
   - `sprint_stamina` - Increases max stamina (5 levels, +20 per level)
   - `sprint_efficiency` - Reduces stamina drain (3 levels, -15% per level)
   - `sprint_hud` - Toggle for HUD visibility (free, 0 cost)
   - `move_dash` - Modified description to indicate infinite sprint stamina

2. **`init.lua`** - Added loading of running_system.lua

## How It Works

### Sprint Activation
- Player holds **Aux1** key (default: E) while moving
- System checks if sprint is allowed (stamina, movement, not in water)
- Physics override applied: speed × 1.5, jump × 1.2, FOV × 1.1

### Stamina System
- Base: 100 stamina, drains at 0.5/sec, regenerates at 1.0/sec
- Abilities can increase max stamina and reduce drain
- Dash ability provides infinite stamina when toggled

### Ability Integration
The system reads from `abilities_v2` player metadata:
- `run_speed` level → +10% sprint speed per level
- `sprint_stamina` level → +20 max stamina per level
- `sprint_efficiency` level → -15% drain multiplier per level
- `move_dash` toggle → infinite stamina flag
- `sprint_hud` toggle → show/hide HUD

### HUD Display
- Shows as colored text bar at bottom of screen
- Green (>60%), Yellow (30-60%), Red (<30%)
- Updates every 0.1 seconds for performance
- Can be toggled off via ability system

## Key Features

✅ **Aux1 Key Support** - Sprint by holding E key  
✅ **Stamina System** - Balanced drain/regen mechanics  
✅ **Ability Integration** - Works with existing ability tree  
✅ **Visual Feedback** - HUD bar and FOV effect  
✅ **Progressive Upgrades** - Multiple abilities to unlock  
✅ **Toggle Options** - HUD visibility and infinite sprint  
✅ **Physics Safe** - Respects base stats from ability system  

## Testing Checklist

- [ ] Sprint activates when holding Aux1 while moving
- [ ] Stamina drains while sprinting
- [ ] Stamina regenerates when not sprinting
- [ ] Cannot sprint with 0 stamina
- [ ] Cannot sprint in water
- [ ] HUD displays correctly
- [ ] Sprint speed stacks with Walk Speed ability
- [ ] Sprint Stamina ability increases max stamina
- [ ] Sprint Efficiency reduces drain rate
- [ ] Dash ability provides infinite stamina
- [ ] Sprint HUD toggle works correctly
- [ ] Physics restore correctly on logout/login

## Configuration

Edit these constants in `running_system.lua`:
```lua
SPRINT_SPEED_MULTIPLIER = 1.5  -- Base sprint speed
SPRINT_JUMP_MULTIPLIER = 1.2   -- Jump boost while sprinting
SPRINT_FOV_MULTIPLIER = 1.1    -- FOV increase
SPRINT_STAMINA_DRAIN = 0.5     -- Drain per second
```

## Future Enhancements (Optional)

- Sprint particle effects (dust clouds)
- Sound effects for sprint start/stop
- Sprint achievements (distance sprinted, etc.)
- Water sprinting with swim abilities
- Sprint energy system instead of/in addition to stamina
- Sprint animations (if custom models support it)
- Sprint cooldown option
- Sprint while sneaking (parkour mode)
