# Migration Guide: Old vs New Architecture

This document shows the transformation from the monolithic demo to the engine-game separation.

## Before: Monolithic Structure

**Old [src/main.zig](src/main_old.zig)** (~475 lines):
```zig
pub fn main() !void {
    // SDL initialization
    try sdl.init(.{ .video = true });
    defer sdl.quit(.{ .video = true });

    // Window creation
    const window = try sdl.video.Window.init(...);
    defer window.deinit();

    // GPU device setup
    const device = try sdl.gpu.Device.init(...);
    defer device.deinit();

    // Shader loading and compilation
    const vertex_code = try std.fs.cwd().readFileAlloc(...);
    // ... 100+ lines of GPU setup ...

    // Game entities mixed with engine code
    const Player = struct { ... };
    var player = Player.init();

    const platforms = [_]AABB{ ... };

    // Game loop mixed with rendering code
    while (running) {
        // Input handling
        while (sdl.events.poll()) |event| { ... }

        // Game update
        player.update(&input, delta_time, &platforms);

        // Rendering (50+ lines of GPU commands)
        const cmd = try device.acquireCommandBuffer();
        // ... complex rendering code ...
    }
}
```

**Problems with this approach:**
- 475 lines of mixed engine and game code
- Hard to understand where engine ends and game begins
- Difficult to create a new game without copying everything
- Can't focus on gameplay without understanding GPU APIs
- No reusability - every game starts from scratch

## After: Engine-Game Separation

### New [src/main.zig](src/main.zig) (~30 lines):

```zig
const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const Application = @import("engine/application.zig");
const PlatformerGame = @import("game/platformer.zig").PlatformerGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator, .{
        .window_title = "Platformer Demo - ZDL Engine",
        .window_width = 960,
        .window_height = 540,
    });
    defer engine.deinit();

    var game = PlatformerGame{
        .player = undefined,
        .platforms = undefined,
    };

    const app = Application.createApplication(PlatformerGame, &game);
    try engine.run(app);
}
```

### Game Code [src/game/platformer.zig](src/game/platformer.zig) (~165 lines):

```zig
pub const PlatformerGame = struct {
    player: Player,
    platforms: [6]AABB,

    pub fn init(self: *PlatformerGame, ctx: *Context) !void {
        self.* = .{
            .player = Player.init(),
            .platforms = [_]AABB{ ... },
        };
    }

    pub fn deinit(self: *PlatformerGame, ctx: *Context) void {}

    pub fn update(self: *PlatformerGame, ctx: *Context, delta_time: f32) !void {
        self.player.update(ctx.input, delta_time, &self.platforms);
    }

    pub fn render(self: *PlatformerGame, ctx: *Context) !void {
        // Draw platforms
        for (self.platforms) |platform| {
            try ctx.sprite_batch.addQuad(
                platform.x + platform.width / 2.0,
                platform.y + platform.height / 2.0,
                platform.width,
                platform.height,
                Color.blue(),
            );
        }

        // Draw player
        try ctx.sprite_batch.addQuad(
            self.player.position.x,
            self.player.position.y,
            self.player.width,
            self.player.height,
            Color.red(),
        );
    }
};
```

### Engine Code [src/engine/engine.zig](src/engine/engine.zig) (~350 lines):

All the complex SDL3 and GPU setup code is now in the engine, completely hidden from game developers.

## Key Improvements

### 1. Separation of Concerns

**Before**: Everything in one file
**After**:
- Engine handles SDL3, GPU, window, events, rendering
- Game focuses on gameplay logic only

### 2. Reusability

**Before**: Copy 475 lines to start a new game
**After**: Create a new struct with 4 methods, ~50 lines for a simple game

Example - creating Pong took only ~150 lines in [src/game/pong.zig](src/game/pong.zig)!

### 3. Simple API

**Before**: Need to understand:
- SDL3 GPU API
- Shader compilation
- Buffer management
- Pipeline creation
- Command buffers
- Transfer buffers

**After**: Only need to know:
```zig
// Input
ctx.input.isKeyDown(.w)

// Rendering
ctx.sprite_batch.addQuad(x, y, width, height, color)

// Camera
ctx.camera.position.x = player_x
```

### 4. Clean Entry Point

**Before**: 475 lines of setup and game loop
**After**:
- 30 lines in main.zig
- Engine initialization with simple config
- Clean separation between engine lifecycle and game

## Creating a New Game

### Before:
1. Copy all 475 lines of main.zig
2. Find and modify the game logic parts
3. Hope you don't break the engine parts
4. Debug GPU errors

### After:
1. Create `src/game/my_game.zig`
2. Implement 4 methods: `init`, `deinit`, `update`, `render`
3. Update main.zig to run your game (2 lines changed)
4. Focus on gameplay!

Example:
```zig
pub const MyGame = struct {
    // Your game state
    score: u32,

    pub fn init(self: *MyGame, ctx: *Context) !void {
        self.score = 0;
    }

    pub fn deinit(self: *MyGame, ctx: *Context) void {}

    pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void {
        if (ctx.input.isKeyJustPressed(.space)) {
            self.score += 1;
        }
    }

    pub fn render(self: *MyGame, ctx: *Context) !void {
        // Draw something!
        try ctx.sprite_batch.addQuad(0, 0, 100, 100, Color.red());
    }
};
```

## File Organization

### Before:
```
src/
├── main.zig (475 lines - everything!)
├── input/
├── renderer/
├── math/
└── camera.zig
```

### After:
```
src/
├── main.zig (30 lines - entry point only)
├── engine/
│   ├── engine.zig (350 lines - all engine complexity)
│   └── application.zig (85 lines - interface definition)
├── game/
│   ├── platformer.zig (165 lines - gameplay only)
│   └── pong.zig (150 lines - another example)
├── input/
├── renderer/
├── math/
└── camera.zig
```

## Benefits for Developers

1. **Learning Curve**: Start making games immediately without learning GPU APIs
2. **Productivity**: Focus 100% on gameplay, not engine internals
3. **Experimentation**: Try new game ideas quickly
4. **Maintainability**: Game bugs won't affect the engine, engine improvements help all games
5. **Collaboration**: Game developers and engine developers can work independently

## Next Steps

See [ENGINE_README.md](ENGINE_README.md) for the complete API documentation and examples!
