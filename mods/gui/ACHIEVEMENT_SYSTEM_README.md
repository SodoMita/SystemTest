# Achievement System 🏆✨

A complete achievement tracking and progression system for your Luanti urban game!

## Features

### 🎯 Core Achievement System
- **Achievement Registration**: Easy-to-use API for creating achievements
- **Progress Tracking**: Track incremental progress toward goals (e.g., "Break 100 blocks")
- **Prerequisites**: Chain achievements together with requirement dependencies
- **Hidden Achievements**: Secret achievements that only appear when requirements are met
- **Rewards**: Grant XP and items upon completion
- **Tier System**: Automatic tier classification (Common, Uncommon, Rare, Epic, Legendary) based on XP rewards

### 📊 Visual Interface
- **Category Organization**: Achievements grouped by category (Getting Started, Exploration, Crafting, Abilities, Challenge, Secret)
- **Progress Bars**: Visual indicators for multi-step achievements
- **Color Coding**:
  - 🟢 Green: Unlocked achievements
  - 🟡 Yellow: Available to unlock
  - ⚫ Dark gray: Locked (requirements not met)
- **Unlock Counter**: Shows X/Y achievements unlocked
- **Scrollable List**: Clean scrollable interface for viewing all achievements

### 🎉 Epic Celebration System
When you unlock an achievement, get ready for an amazing celebration!

**Tier-Based Effects**:
- **Common** (Gray): 10 particles, subtle sound
- **Uncommon** (Green): 25 particles, enhanced sound
- **Rare** (Blue): 50 particles, brighter effects
- **Epic** (Purple): 100 particles, dramatic sound
- **Legendary** (Gold): 200 particles, epic fanfare!

**Visual Effects**:
- 🎪 **HUD Popup**: Giant achievement notification at top of screen with colored background and black border
- 🎊 **2D GUI Confetti**: Animated particles fall down across the entire screen (2x particle count!) with realistic acceleration physics
  - Spread across full screen width and height
  - Accelerate as they fall for dramatic effect
  - Visible even in menus - you can't miss them!
- 🎇 **3D Particle Shower**: Colored particles continuously spawn around you for 2 full seconds
  - Huge Y-axis spread (-5 to +20 blocks)
  - Stronger gravity for more dramatic falls
  - Creates a spectacular ongoing fountain effect
- 🎵 **Dynamic Sound**: Pitch and volume scale with achievement importance
- ⏱️ **10-Second Display**: All effects automatically disappear after 10 seconds

**Smart Queue System**:
- Multiple achievements unlocked at once? No problem!
- Achievements display **sequentially** from least to most valuable
- Each achievement gets its full 10 seconds of glory
- Watch the celebration escalate as you go from common to legendary!

The more valuable the achievement, the more spectacular the celebration! 🎆

### 🔄 Automatic Tracking
The system automatically tracks:
- **Block Breaking**: Tracks dig counts for mining achievements
- **Block Placing**: Tracks placement for building achievements
- **Leveling**: Detects when player reaches milestone levels
- **Crafting**: Tracks items crafted and categories used
- **Ability Unlocking**: Tracks ability tree progression
- **Exploration**: Monitors position for travel/location achievements
  - Floating island visits (Y > 100)
  - City exploration (Y -10 to 50)
  - Secret depths (Y < -100)
  - Distance traveled from spawn

### 📦 Files Created

1. **achievement_system.lua**: Core achievement framework
   - `register_achievement(def)` - Register new achievements
   - `achievement_progress(player, id, amount)` - Add progress
   - `check_achievement(player, id)` - Check and unlock if conditions met
   - `get_achievement_formspec(player)` - Generate GUI

2. **achievement_definitions.lua**: 27 pre-defined achievements across 6 categories
   - Getting Started (4 achievements)
   - Exploration (4 achievements)
   - Crafting (5 achievements)
   - Abilities (4 achievements)
   - Challenge (6 achievements)
   - Secret (2 hidden achievements)

3. **achievement_tracking.lua**: Automatic event tracking
   - Hooks into digging, placing, leveling, crafting, abilities
   - Periodic position checks for exploration
   - Island visit tracking system

4. **Updated Files**:
   - `init.lua` - Added achievement system loading
   - `crafting_system.lua` - Added achievement tracking to crafts
   - `ability_system.lua` - Added achievement tracking to ability unlocks
   - `unified_inventory.lua` - Integrated achievements tab

## 🎮 Usage

### For Players

**View Achievements**:
- Press `I` to open inventory
- Click the 🏆 tab on the right
- Or use `/achievements` command

**Achievement Categories**:
1. **Getting Started**: Learn the basics
2. **Exploration**: Discover the world
3. **Crafting**: Master the crafting system
4. **Abilities**: Unlock and upgrade abilities
5. **Challenge**: Long-term goals for dedication
6. **Secret**: Hidden surprises! 🎁

### For Admins

**Grant Achievement**:
```
/giveachievement <player> <achievement_id>
```

**Reset Achievements**:
```
/resetachievements <player>
```

**Reset ALL Progress** (XP, Abilities, Achievements):
```
/resetprogress <player>
```
This command will:
- Reset experience to 0
- Clear all unlocked abilities and stat points
- Wipe all achievement progress
- Reset player physics to default
- Clear achievement queue

### For Developers

**Register New Achievement**:
```lua
register_achievement({
    id = "my_achievement",
    name = "My Cool Achievement",
    description = "Do something awesome",
    icon = "🌟",
    category = "challenge",
    
    -- Progress tracking
    max_progress = 100,  -- How many times to do the thing
    
    -- Prerequisites
    requires = {"other_achievement"},
    
    -- Rewards
    reward_xp = 100,
    reward_items = {["default:diamond"] = 5},
    
    -- Hidden until unlockable?
    hidden = false,
    
    -- For future graph view
    graph_x = 0,
    graph_y = 0,
})
```

**Track Progress**:
```lua
-- Add progress to an achievement
achievement_progress(player, "my_achievement", 1)

-- Check if conditions met and unlock
check_achievement(player, "my_achievement")
```

**Custom Achievement Checks**:
```lua
register_achievement({
    id = "has_10_diamonds",
    check = function(player)
        local inv = player:get_inventory()
        return inv:contains_item("main", "default:diamond 10")
    end,
    -- ... other properties
})

-- Then call periodically:
check_achievement(player, "has_10_diamonds")
```

## 🔮 Future Enhancements

### Planned Features
- [ ] **Visual Graph View**: Node-based achievement tree with connecting lines showing prerequisites
- [ ] **3D Trophies**: Physical trophy items that can be placed in world
- [ ] **Global Leaderboards**: Compare achievement progress with other players
- [ ] **Custom Icons**: Support for texture-based icons instead of emoji
- [ ] **Achievement Points**: Separate point system from XP for bragging rights
- [ ] **Time-based Achievements**: "Complete within 1 hour" challenges
- [ ] **Cooperative Achievements**: Require multiple players working together
- [ ] **Seasonal Achievements**: Limited-time special events

### Integration Ideas
- Link achievements to story progression
- Grant special abilities or items for achievement milestones
- Create achievement-locked areas or NPCs
- Add achievement showcase in player profile
- Achievement-based cosmetic rewards (particle effects, titles, etc.)

## 📝 Technical Details

**Data Storage**:
- Player achievement data stored in player metadata as serialized table
- Format: `{unlocked = {id = true}, progress = {id = count}}`
- Persistent across sessions

**Performance**:
- Exploration checks run every 10 seconds (configurable)
- Achievement checks are event-driven for most actions
- Efficient lookup using `achievement_by_id` table

**Compatibility**:
- Works with existing XP/leveling system
- Integrates with crafting and ability systems
- Minimal conflicts with other mods

## 🏆 Achievement List

Run `/achievements` in-game to see the full list with current progress!

---

Made with 💚 by a cute catgirl AI assistant~ Enjoy your achievements! ✨🎮
