# Coin Collector - Phase 3 Demo

A simple coin collection game that showcases **all Phase 3 features** from the [ENGINE_PLAN.md](../../ENGINE_PLAN.md):
- Audio system
- Particle effects
- UI/HUD system

## How to Run

```bash
zig build run          # Default example
# or
zig build run-collector
```

## Gameplay

- **Objective**: Collect all 10 coins before time runs out!
- **Controls**: WASD or Arrow keys to move
- **Timer**: 30 seconds to collect all coins
- **Health**: Slowly decreases over time (demonstrates health bar UI)

## Features Demonstrated

### 1. Particle System
- **Gold burst particles** when collecting coins
  - 30 particles per collection
  - Upward velocity with gravity
  - Fade-out over 0.8 seconds
- **Blue trail particles** following the player
  - Continuous emission at 30 particles/second
  - Small particles with short lifetime
  - Creates smooth movement trail

### 2. UI/HUD System
- **Score display** in top-left corner
- **Timer** that changes color when low (< 10 seconds)
- **Coins collected counter** showing progress
- **Health bar** at the top with color-coded health levels:
  - Green when healthy
  - Yellow when medium
  - Red when low
- **Instructions** displayed at bottom
- **Game over messages** (win/lose) with centered text

### 3. Audio System (Infrastructure)
The game includes commented examples showing where to:
- Load WAV files in `init()`
- Play sound effects on events (coin collection, win, lose)
- Control volume per sound

To enable audio, uncomment the lines and add your own WAV files:
```zig
// In init():
try ctx.audio.loadWAV("collect", "assets/sounds/collect.wav");
try ctx.audio.loadWAV("win", "assets/sounds/win.wav");

// In update():
if (coin_collected) {
    try ctx.audio.playSound("collect", 0.6);
}
```

## Code Highlights

### Particle Configuration
```zig
const collect_config = EmitterConfig{
    .emission_rate = 200.0,
    .particle_lifetime = 0.8,
    .color = Color{ .r = 1.0, .g = 0.9, .b = 0.2, .a = 1.0 }, // Gold
    .size = 8.0,
    .velocity_min = Vec2.init(-200, -200),
    .velocity_max = Vec2.init(200, -100),
    .continuous = false, // Burst mode
};
```

### HUD Usage
```zig
// Score
try hud.drawScore(ctx.sprite_batch, score, screen_w, screen_h);

// Timer with dynamic color
try hud.drawText(
    ctx.sprite_batch,
    timer_text,
    x, y,
    if (time_remaining < 10.0)
        Color{ .r = 1.0, .g = 0.3, .b = 0.3, .a = 1.0 } // Red
    else
        Color.white(),
);

// Health bar
try hud.drawHealthBar(
    ctx.sprite_batch,
    current_health,
    max_health,
    x, y, width, height,
);
```

## Learning Points

This example demonstrates:
1. **State management** - Game over states (won/lost)
2. **Particle emitters** - Both burst and continuous modes
3. **Dynamic UI** - Color changes based on game state
4. **Input normalization** - Smooth diagonal movement
5. **Collision detection** - Circle-based coin collection
6. **Random generation** - Procedural coin placement
7. **Visual feedback** - Particles, color changes, animations

## File Structure

```
collector/
├── main.zig        # Engine initialization (20 lines)
├── collector.zig   # Game implementation (350 lines)
└── README.md       # This file
```

## Extending This Example

Try adding:
- Different particle effects (explosions, sparkles)
- More UI elements (lives, combo counter)
- Sound effects and music
- Different coin types with different scores
- Power-ups that spawn particles
- Background music with volume control
- Menu system with UI buttons
