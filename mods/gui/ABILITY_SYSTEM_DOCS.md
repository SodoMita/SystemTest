# Advanced Ability System Documentation 🎮✨

## Overview
A complete stat-based ability system with visual graph navigation, 3D player preview, customizable stats, and toggle abilities integrated into the unified inventory mod.

## Current Implementation Status

### ✅ Completed Features

#### 1. Ability System Core (`ability_system_new.lua`)
- **Stat-based abilities**: Walk speed, run speed, jump height, super jump, crouch speed, swim speed, fly speed
- **Toggle abilities**: Flight, noclip, fast digging, teleportation
- **Progressive unlocking**: Prerequisites and level-based progression
- **Cost system**: Abilities cost stat points to unlock/upgrade
- **Unclamped stats**: Flight speed can exceed normal limits

#### 2. Visual Ability Graph
- **Interactive node graph**: Abilities displayed as clickable nodes on a 2D grid
- **Prerequisite edges**: Visual connections showing ability dependencies (green when unlocked, gray when locked)
- **Manual scrolling system**: Horizontal and vertical scrollbars for panning
- **Node states**:
  - 🟢 Green: Unlocked
  - 🟡 Yellow: Can unlock (requirements met, enough stat points)
  - ⚫ Gray: Locked (missing requirements or stat points)
- **Click-based tooltips**: Node info displayed in bottom tooltip bar
- **Viewport culling**: Only draws visible nodes for performance

#### 3. Stat Customization Panel
- **Sliders + input fields**: Adjustable stat values within unlocked ranges
- **"Set" buttons**: Apply custom stat values
- **Range display**: Shows min-max values for each stat (or ∞ for unclamped)
- **Stats tracked**:
  - Speed (walk/run/fly)
  - Jump height
  - Sneak speed
  - Swim speed

#### 4. Toggle Abilities Panel
- **Checkbox toggles**: Enable/disable boolean abilities
- **Privilege system**: Toggles grant/revoke Minetest privileges (fly, noclip, fast, teleport)
- **Only shows unlocked**: Locked toggles are hidden

#### 5. 3D Player Preview
- **Static player model**: Top-left corner square preview
- **Uses player_api**: Fetches player textures dynamically
- **Fixed pose**: 0,170 rotation for consistent view

#### 6. Integration
- **Unified Inventory**: Replaces old "abilities" tab placeholder
- **Form field handling**: Properly processes inputs from both standalone and unified inventory contexts
- **Data persistence**: Saves to player metadata with auto-save on changes
- **Achievement integration**: Tracks "unlock_first_ability" achievement

### 🔧 Technical Details

#### Graph Scrolling Implementation
Minetest formspecs don't support automatic scroll containers for custom-drawn content. We use **manual scrollbar-driven panning**:

```lua
-- Scrollbars send events (0-1000 range)
data.scroll_x = 0  -- Horizontal scroll position
data.scroll_y = 0  -- Vertical scroll position

-- Convert to pixel offsets
local max_offset_x = math.max(0, total_width - graph_w)
local max_offset_y = math.max(0, total_height - graph_h)
local offset_x = -(scroll_x / 1000) * max_offset_x
local offset_y = -(scroll_y / 1000) * max_offset_y

-- Apply to node positions
local x = graph_x + offset_x + ability.graph_x * grid_spacing_x
local y = graph_y + offset_y + ability.graph_y * grid_spacing_y
```

Event handlers listen for `graph_scroll_x` and `graph_scroll_y` events using `minetest.explode_scrollbar_event()`.

#### Ability Definition Format
```lua
{
    id = "walk_speed",              -- Unique identifier
    name = "Walk Speed",            -- Display name
    type = "stat",                  -- "stat" or "toggle"
    icon = "🚶",                    -- Emoji icon
    description = "Increases...",   -- Tooltip text
    category = "movement",          -- Category for organization
    cost = 1,                       -- Stat points required
    max_level = 5,                  -- Max upgrade level
    requires = nil,                 -- Prerequisite ability ID (or nil)
    graph_x = 1,                    -- Grid X position
    graph_y = 1,                    -- Grid Y position
    stat_key = "speed",             -- Which player stat to modify
    base_min = 1.0,                 -- Starting min value
    base_max = 1.0,                 -- Starting max value
    unlock_per_level = 0.2,         -- Range increase per level
    unclamped = false,              -- If true, no max limit
    priv = nil,                     -- Privilege to grant (for toggles)
}
```

#### Player Data Structure
```lua
{
    unlocked = {ability_id = level},   -- Unlocked abilities and levels
    stat_points = 0,                   -- Available stat points
    stat_values = {stat_key = value},  -- Custom stat values
    toggles = {ability_id = bool},     -- Toggle states
    scroll_x = 0,                      -- Graph scroll position X
    scroll_y = 0,                      -- Graph scroll position Y
    tooltip = "",                      -- Current tooltip text
}
```

### 🐛 Known Issues

#### 1. **Graph Scrolling Not Working** ⚠️
**Symptom**: Scrollbars are present and draggable, but nodes and edges don't move visually.

**Latest Fix Attempt**: Replaced `scroll_container` with manual offset calculation and scrollbar event handlers. Nodes and edges now use absolute coordinates with offsets applied.

**Possible Causes**:
- Formspec may not be refreshing after scroll events
- Scroll event handlers may not be firing correctly
- Offset calculation might be incorrect
- Viewport culling might be hiding nodes incorrectly

**Debug Steps**:
1. Add `minetest.log()` in scroll event handlers to verify events fire
2. Log calculated offset values to verify they change
3. Draw a static test box with offset applied to verify offset works
4. Check if formspec refresh is happening (add "last scroll: X,Y" label)

**Alternative Approaches**:
- Use button-based panning (arrow buttons to shift viewport)
- Simplify to list view instead of 2D graph
- Use multiple pages instead of scrolling

#### 2. **Hover Tooltips Not Possible**
Minetest formspecs don't support hover events. Current solution uses **click-based tooltips** displayed in bottom bar. This works but is less intuitive than hover.

### 📝 Next Steps / TODOs

#### High Priority
- [ ] **Fix graph scrolling**: Debug and resolve panning issue
- [ ] **Test ability unlocking**: Verify stat point spending works
- [ ] **Test stat application**: Confirm custom stat values actually affect player movement
- [ ] **Test toggle abilities**: Verify privileges are granted/revoked correctly

#### Medium Priority
- [ ] **Visual polish**: Better colors, borders, icons
- [ ] **Add ability categories**: Color-code nodes by category
- [ ] **Zoom controls**: Allow zooming in/out on graph
- [ ] **Mini-map**: Show full graph overview with viewport indicator
- [ ] **Sound effects**: Play sounds on unlock/upgrade

#### Low Priority
- [ ] **Animated player preview**: Rotate or animate the 3D model
- [ ] **Ability search/filter**: Filter nodes by name or category
- [ ] **Recommended path**: Highlight suggested ability order
- [ ] **Reset button**: Allow resetting all abilities (admin command exists)
- [ ] **Export/import builds**: Save/load ability configurations

### 🎨 Design Decisions

#### Why Manual Scrolling Instead of Scroll Container?
Minetest's `scroll_container` only works for elements that respect the container's coordinate system automatically (buttons, labels, etc.). Custom-drawn boxes and lines need manual position offsetting.

#### Why Click Tooltips Instead of Hover?
Formspecs don't expose mouse position or hover events. Click is the only interaction method available.

#### Why Grid Layout Instead of Free-Form?
Grid layout ensures consistent spacing and easier prerequisite edge drawing. Manually positioned nodes would be harder to maintain.

#### Why Emoji Icons?
Unicode emoji work universally without needing texture files. They're also cuter! 😺💖

### 🔗 Related Files

#### Core Files
- `/home/hobo/.minetest/games/temnaya_zashelina/mods/gui/ability_system_new.lua` - Main ability system
- `/home/hobo/.minetest/games/temnaya_zashelina/mods/gui/unified_inventory.lua` - Integration point
- `/home/hobo/.minetest/games/temnaya_zashelina/mods/player_api/api.lua` - Player model API

#### Related Systems
- `achievement_system.lua` - Tracks ability-related achievements
- `experience_system.lua` - Grants stat points on level up

### 🎮 Commands

```
/abilities2          # Open standalone ability screen (testing)
/givestatpoints <n>  # Grant stat points (admin)
/resetprogress       # Reset all player progress (admin)
```

### 💡 Tips for Future Developers

1. **Use `minetest.log()` extensively** - Formspec debugging is hard without logs
2. **Test with stat points first** - Add points before testing unlock mechanics
3. **Graph layout tips**: Keep `graph_x` and `graph_y` values reasonable (0-10 range)
4. **Scrollbar range**: Always 0-1000, convert to pixels manually
5. **Formspec coordinates**: Origin is top-left, Y increases downward
6. **Performance**: Viewport culling is critical for large graphs (50+ nodes)
7. **Don't forget to refresh**: After data changes, always regenerate formspec

### 🐾 Final Notes

This was such a fun implementation! The ability system combines RPG progression, skill trees, and player customization into one cohesive experience. The visual graph makes it feel like a real skill tree from AAA games, while the stat sliders give players precise control over their character.

The biggest challenge was working around Minetest's formspec limitations - no hover events, no native graph drawing, no automatic scrolling for custom elements. But we made it work with clever workarounds! 💪✨

**Special thanks to User for the amazing collaboration!** 💖😺🌟

---

*Last updated: 2025-11-01*  
*Status: Core implementation complete, scrolling bug needs fixing*  
*Next agent: Please fix graph scrolling and test gameplay thoroughly!* 🎮
