# ZDL Game Engine

A lightweight 2D game engine built with Zig and SDL3, designed to let developers focus on gameplay without worrying about engine internals.

## Architecture

The engine is cleanly separated from game code:

```
src/
├── engine/              # Engine core - you don't need to modify this
│   ├── application.zig  # Application interface
│   └── engine.zig       # Engine implementation
├── game/                # Your game code goes here
│   └── platformer.zig   # Example: platformer game
├── input/               # Input system (part of engine)
├── renderer/            # Rendering systems (part of engine)
├── math/                # Math library (part of engine)
├── camera.zig           # 2D camera (part of engine)
└── main.zig             # Entry point - minimal boilerplate
```

## Quick Start

### 1. Create Your Game

Implement the `Application` interface by defining these four methods:

```zig
const Application = @import("engine/application.zig");
const Context = Application.Context;

pub const MyGame = struct {
    // Your game state here
    player_x: f32 = 0,
    player_y: f32 = 0,

    pub fn init(self: *MyGame, ctx: *Context) !void {
        // Initialize your game
        // Access: ctx.allocator, ctx.input, ctx.camera, ctx.sprite_batch
    }

    pub fn deinit(self: *MyGame, ctx: *Context) void {
        // Clean up resources
    }

    pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void {
        // Update game logic
        // Read input: ctx.input.isKeyDown(.w)
        // Update positions based on delta_time
    }

    pub fn render(self: *MyGame, ctx: *Context) !void {
        // Render your game
        // Draw sprites: try ctx.sprite_batch.addQuad(x, y, w, h, color);
    }
};
```

### 2. Set Up main.zig

```zig
const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const Application = @import("engine/application.zig");
const MyGame = @import("game/my_game.zig").MyGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the engine
    var engine = try Engine.init(allocator, .{
        .window_title = "My Awesome Game",
        .window_width = 1280,
        .window_height = 720,
    });
    defer engine.deinit();

    // Create your game
    var game = MyGame{};

    // Run the game loop
    const app = Application.createApplication(MyGame, &game);
    try engine.run(app);
}
```

### 3. Build and Run

```bash
zig build run
```

## Engine Features

### Context API

The `Context` struct provides access to all engine systems:

```zig
pub const Context = struct {
    allocator: std.mem.Allocator,    // Memory allocator
    input: *Input,                    // Input system
    camera: *Camera2D,                // 2D camera
    sprite_batch: *SpriteBatch,       // Sprite renderer
    device: *sdl.gpu.Device,          // GPU device (advanced)
    window: *sdl.video.Window,        // Window handle (advanced)
    // ... other GPU resources for advanced usage
};
```

### Input System

```zig
// Check if key is down
if (ctx.input.isKeyDown(.w)) {
    player.y -= speed * delta_time;
}

// Check if key was just pressed (useful for jumping)
if (ctx.input.isKeyJustPressed(.space)) {
    player.jump();
}

// Helper functions
const wasd = ctx.input.getWASD();     // Returns {x: f32, y: f32}
const arrows = ctx.input.getArrowKeys();
```

### Camera System

```zig
// The camera is automatically set up for you
// Coordinate system: (0, 0) is the center of the screen
// Positive X is right, positive Y is down

// Move the camera to follow the player
ctx.camera.position.x = player.x;
ctx.camera.position.y = player.y;

// Convert between screen and world coordinates
const world_pos = ctx.camera.screenToWorld(mouse_x, mouse_y);
const screen_pos = ctx.camera.worldToScreen(entity_x, entity_y);
```

### Sprite Rendering

```zig
// Draw a colored rectangle
try ctx.sprite_batch.addQuad(
    x,           // X position (center)
    y,           // Y position (center)
    width,       // Width
    height,      // Height
    Color.red(), // Color
);

// Available colors: red(), green(), blue(), yellow(), white(), black()

// Draw with custom color
const my_color = Color{ .r = 1.0, .g = 0.5, .b = 0.0, .a = 1.0 };
try ctx.sprite_batch.addQuad(x, y, w, h, my_color);

// Draw textured sprites (with UV coordinates)
try ctx.sprite_batch.addQuadUV(x, y, w, h, color, u0, v0, u1, v1);
```

## Example: Simple Platformer

See [src/game/platformer.zig](src/game/platformer.zig) for a complete example with:
- Player movement (WASD + Arrow keys)
- Gravity and jumping
- Platform collision detection
- Clean separation of game logic

## What You Don't Need to Worry About

The engine handles all of this for you:

- ✅ SDL3 initialization and cleanup
- ✅ GPU device setup and management
- ✅ Window creation and event handling
- ✅ Shader compilation and pipeline setup
- ✅ Vertex buffer management
- ✅ Render loop and frame timing
- ✅ Input state tracking
- ✅ Camera matrix calculations
- ✅ Sprite batching and rendering

## What You Focus On

As a game developer, you only need to think about:

- 🎮 Game logic in `update()`
- 🎨 Drawing in `render()`
- 📊 Your game's data structures
- 🎯 Gameplay mechanics

## Advanced Usage

If you need more control, you can access GPU resources directly through the context:

```zig
// Access GPU device
const device = ctx.device;

// Access vertex buffers
const vertex_buffer = ctx.vertex_buffer;

// Access graphics pipeline
const pipeline = ctx.pipeline;
```

## Next Steps

1. **Add textures**: Extend the engine to load and render textured sprites
2. **Add audio**: Integrate SDL3 audio for sound effects and music
3. **Add tilemap support**: Create a tilemap renderer for level design
4. **Add particle effects**: Create a particle system for visual polish
5. **Add 3D support**: Follow the ENGINE_PLAN.md to add 3D capabilities

## Design Philosophy

This engine follows the principle of **progressive disclosure**:

- Simple things are simple (draw a colored rectangle)
- Complex things are possible (direct GPU access if needed)
- Clear separation between engine and game code
- Minimal boilerplate in user code
- The engine does the heavy lifting, you do the creative work

## Contributing

When extending the engine:

1. Keep the `Application` interface simple and stable
2. Add new features as optional systems accessible through `Context`
3. Provide examples in `src/game/` for each new feature
4. Update this README with usage examples
