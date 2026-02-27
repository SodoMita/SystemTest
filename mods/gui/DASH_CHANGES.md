# Dash Ability - Updated Mechanics

## Change Summary
The Dash ability has been changed from infinite stamina to a high-risk, high-reward burst ability.

## Old Behavior (Before)
- **Effect**: Infinite stamina while sprinting
- **Use Case**: Unlimited sprint for exploration
- **HUD**: Showed "∞ (Infinite)"

## New Behavior (After)
- **Effect**: 10x speed multiplier with 500x stamina drain
- **Use Case**: Very short emergency bursts of extreme speed
- **HUD**: Shows "💨 DASH MODE [bar] X/Y" in orange color

## Detailed Mechanics

### Speed Calculation
When Dash is toggled ON:
- Base sprint multiplier: 1.5x
- Run Speed ability: +0.1x per level (up to +0.5x at level 5)
- **Dash bonus**: +9.0x additional
- **Total with max Run Speed**: 1.5 + 0.5 + 9.0 = **11x base walking speed**

### Stamina Drain Calculation
When Dash is toggled ON:
- Base drain: 0.5 stamina/second
- Sprint Efficiency reduction: -15% per level (up to -45% at level 3)
- **Dash multiplier**: 500x
- **Example drains**:
  - No efficiency: 0.5 × 500 = **250 stamina/sec** (~0.4 seconds with 100 stamina)
  - Max efficiency (L3): 0.275 × 500 = **137.5 stamina/sec** (~0.73 seconds with 100 stamina)
  - Max efficiency + max stamina: 137.5/sec with 200 stamina = **~1.45 seconds**

### Practical Usage Times

| Build | Max Stamina | Drain Rate | Dash Duration |
|-------|-------------|------------|---------------|
| Base (no abilities) | 100 | 250/sec | **~0.4 seconds** |
| Sprint Stamina L5 | 200 | 250/sec | **~0.8 seconds** |
| Sprint Efficiency L3 | 100 | 137.5/sec | **~0.73 seconds** |
| **Optimized** (Both maxed) | 200 | 137.5/sec | **~1.45 seconds** |

## Strategic Considerations

### When to Use Dash
✅ **Good Uses**:
- Escaping dangerous situations
- Quick travel across short distances
- Chasing fast-moving targets
- Parkour jumps requiring extreme speed
- Emergency repositioning in combat

❌ **Bad Uses**:
- Long-distance travel (use normal sprint instead)
- Exploration (stamina will deplete too fast)
- When stamina is low (will stop abruptly)
- In narrow spaces (too fast to control)

### Recommended Build Order
1. **First**: Max Sprint Stamina (L5) - More time in dash mode
2. **Second**: Max Sprint Efficiency (L3) - Reduces drain significantly
3. **Third**: Unlock Dash - Now you have ~14 seconds of burst
4. **Optional**: Max Run Speed (L5) - For even faster dash (11x speed)

### Tips
- Toggle Dash OFF when not needed to conserve stamina
- Build up max stamina and efficiency before relying on Dash
- Watch the HUD bar carefully - Dash empties it fast!
- Practice short bursts rather than continuous use
- Combine with Jump Height for aerial maneuvers
- Sprint normally most of the time, Dash only when needed

## Technical Details

### Code Changes
```lua
-- Added to modifiers when Dash is toggled ON:
modifiers.dash_active = true
modifiers.sprint_speed_bonus = sprint_speed_bonus + 9.0  -- +9.0 for 10x total
modifiers.stamina_drain_multiplier = stamina_drain_multiplier * 500  -- 500x drain!
```

### HUD Display
- Normal Sprint: Green/Yellow/Red stamina bar
- Dash Mode: Orange "💨 DASH MODE" indicator
- Low stamina warning: Prevents dash when stamina < 5

### Safety Features
- Cannot activate dash with less than 5 stamina
- Automatically disables when stamina reaches 0
- Visual warning with orange HUD color
- Sprint stops cleanly when stamina depletes

## Balance Reasoning

The change from infinite stamina to burst speed was made to:
1. Create more strategic depth (resource management)
2. Reward investment in stamina-related abilities
3. Provide a high-skill, high-reward option
4. Prevent trivializing exploration/travel
5. Make the ability more exciting (10x speed!)
6. Encourage tactical decision-making

The extreme speed comes at a steep cost, making it a powerful tool that requires planning and skill to use effectively.
