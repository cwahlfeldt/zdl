# Quick Start Guide

Get started making games with ZDL in 5 minutes!

## Run the Examples

### Platformer Demo
```bash
zig build run
```

Controls:
- **WASD** or **Arrow Keys**: Move left/right
- **Space**, **W**, or **Up**: Jump
- **ESC**: Quit

### Pong Demo

Edit [src/main.zig](src/main.zig) and change the import:

```zig
// Change this line:
const PlatformerGame = @import("game/platformer.zig").PlatformerGame;

// To this:
const PongGame = @import("game/pong.zig").PongGame;

// And change these lines:
var game = PlatformerGame{ ... };
const app = Application.createApplication(PlatformerGame, &game);

// To:
var game = PongGame{ ... };
const app = Application.createApplication(PongGame, &game);
```

Then run:
```bash
zig build run
```

Controls:
- **Left Player**: W/S keys
- **Right Player**: Up/Down arrow keys
- **ESC**: Quit

## Create Your First Game

### Step 1: Create the game file

Create `src/game/my_first_game.zig`:

```zig
const std = @import("std");
const Application = @import("../engine/application.zig");
const Context = Application.Context;
const sprite = @import("../renderer/sprite.zig");
const Color = sprite.Color;

pub const MyFirstGame = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn init(self: *MyFirstGame, ctx: *Context) !void {
        _ = ctx;
        self.x = 0;
        self.y = 0;
    }

    pub fn deinit(self: *MyFirstGame, ctx: *Context) void {
        _ = self;
        _ = ctx;
    }

    pub fn update(self: *MyFirstGame, ctx: *Context, delta_time: f32) !void {
        const speed: f32 = 200.0;

        // Get input
        const wasd = ctx.input.getWASD();

        // Move the square
        self.x += wasd.x * speed * delta_time;
        self.y += wasd.y * speed * delta_time;
    }

    pub fn render(self: *MyFirstGame, ctx: *Context) !void {
        // Draw a red square
        try ctx.sprite_batch.addQuad(
            self.x,
            self.y,
            50,    // width
            50,    // height
            Color.red(),
        );
    }
};
```

### Step 2: Update main.zig

Edit [src/main.zig](src/main.zig):

```zig
const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const EngineConfig = @import("engine/engine.zig").EngineConfig;
const Application = @import("engine/application.zig");
const MyFirstGame = @import("game/my_first_game.zig").MyFirstGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator, .{
        .window_title = "My First Game!",
        .window_width = 960,
        .window_height = 540,
    });
    defer engine.deinit();

    var game = MyFirstGame{};

    const app = Application.createApplication(MyFirstGame, &game);
    try engine.run(app);
}
```

### Step 3: Run it!

```bash
zig build run
```

You should see a red square that you can move with WASD!

## What Just Happened?

You created a complete game in ~40 lines of code! The engine handled:
- Window creation
- SDL3 initialization
- GPU setup and shaders
- Event handling
- Frame timing
- Sprite rendering
- Input management

You only had to think about:
- Your game state (`x` and `y` position)
- How to update it (moving with keyboard)
- How to draw it (red square)

## Next Steps

### Add More Features

Try adding to your game:

1. **Multiple objects**: Add more squares with different colors
2. **Collision**: Make squares bounce off each other
3. **Scoring**: Track and display a score
4. **Boundaries**: Keep the square from going off-screen

### Learn from Examples

Study the example games:
- [src/game/platformer.zig](src/game/platformer.zig) - Shows physics, collision, jumping
- [src/game/pong.zig](src/game/pong.zig) - Shows two-player input, scoring, ball physics

### Read the Docs

- [ENGINE_README.md](ENGINE_README.md) - Complete API reference
- [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - See how the engine evolved

## Common Patterns

### Check if a key is held down
```zig
if (ctx.input.isKeyDown(.space)) {
    // Do something continuously while space is held
}
```

### Check if a key was just pressed
```zig
if (ctx.input.isKeyJustPressed(.space)) {
    // Do something once when space is pressed
}
```

### Draw colored shapes
```zig
// Predefined colors
try ctx.sprite_batch.addQuad(x, y, w, h, Color.red());
try ctx.sprite_batch.addQuad(x, y, w, h, Color.blue());
try ctx.sprite_batch.addQuad(x, y, w, h, Color.green());

// Custom color (RGBA, 0.0 to 1.0)
const purple = Color{ .r = 0.5, .g = 0.0, .b = 0.5, .a = 1.0 };
try ctx.sprite_batch.addQuad(x, y, w, h, purple);
```

### Move objects smoothly
```zig
// Always multiply by delta_time for frame-independent movement
const speed = 100.0; // pixels per second
self.x += speed * delta_time;
```

### Keep objects on screen
```zig
// Screen coordinates range from about -480 to 480 in X, -270 to 270 in Y
// (for a 960x540 window)
if (self.x < -480) self.x = -480;
if (self.x > 480) self.x = 480;
if (self.y < -270) self.y = -270;
if (self.y > 270) self.y = 270;
```

## Tips

1. **Coordinate System**: (0, 0) is the center of the screen
   - Positive X goes right
   - Positive Y goes down

2. **Delta Time**: Always use `delta_time` for movement to keep things smooth regardless of frame rate

3. **Sprite Position**: The position you give to `addQuad()` is the **center** of the sprite

4. **Colors**: RGBA values range from 0.0 to 1.0

5. **Memory**: Use `ctx.allocator` if you need to allocate memory

## Happy Game Making!

You now have everything you need to start creating games. The engine handles the boring parts, you focus on making it fun!
