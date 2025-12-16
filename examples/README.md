# ZDL Engine Examples

This directory contains example games built with the ZDL engine, showcasing what you can build and how to use the engine's features.

## Running the Examples

### Pong (Default)
```bash
zig build run
```

**Controls:**
- Left Player: W (up), S (down)
- Right Player: Arrow Up, Arrow Down
- ESC to quit

### Platformer
```bash
zig build run-platformer
```

**Controls:**
- WASD or Arrow Keys: Move left/right
- Space, W, or Up: Jump
- ESC to quit

## Example Structure

Each example is organized in its own directory:

```
examples/
├── pong/
│   ├── main.zig        # Entry point
│   └── pong.zig        # Game implementation
└── platformer/
    ├── main.zig        # Entry point
    └── platformer.zig  # Game implementation
```

## What Each Example Demonstrates

### Pong (`examples/pong/`)
**Complexity:** Simple (~150 lines)
**Features:**
- Two-player input handling
- Ball physics (velocity and bouncing)
- Paddle collision detection
- Score tracking
- Clean game state management

**Good for learning:**
- Basic game structure
- Input handling for multiple players
- Simple physics
- Drawing with sprite batch

### Platformer (`examples/platformer/`)
**Complexity:** Intermediate (~165 lines)
**Features:**
- Player movement and physics
- Gravity and jumping mechanics
- Platform collision detection (AABB)
- Separate X and Y collision handling
- Multiple input methods (WASD + Arrows)

**Good for learning:**
- Physics-based movement
- Collision detection
- Delta time usage for smooth movement
- Separating collision axes

## Creating Your Own Example

1. Create a new directory: `examples/my_game/`
2. Create `main.zig`:
```zig
const std = @import("std");
const zdl = @import("engine");
const MyGame = @import("my_game.zig").MyGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try zdl.Engine.init(allocator, .{
        .window_title = "My Game",
        .window_width = 960,
        .window_height = 540,
    });
    defer engine.deinit();

    var game = MyGame{};
    const app = zdl.Application.createApplication(MyGame, &game);
    try engine.run(app);
}
```

3. Create `my_game.zig`:
```zig
const std = @import("std");
const zdl = @import("engine");

pub const MyGame = struct {
    // Your game state

    pub fn init(self: *MyGame, ctx: *zdl.Context) !void {
        // Initialize
    }

    pub fn deinit(self: *MyGame, ctx: *zdl.Context) void {
        // Cleanup
    }

    pub fn update(self: *MyGame, ctx: *zdl.Context, delta_time: f32) !void {
        // Update logic
    }

    pub fn render(self: *MyGame, ctx: *zdl.Context) !void {
        // Draw your game
    }
};
```

4. Add to `build.zig`:
```zig
// In the build() function, add:
const my_game = b.addExecutable(.{
    .name = "my_game",
    .root_module = b.createModule(.{
        .root_source_file = b.path("examples/my_game/main.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
my_game.root_module.addImport("sdl3", sdl3.module("sdl3"));
my_game.root_module.addImport("engine", engine_module);
b.installArtifact(my_game);

const run_my_game = b.addRunArtifact(my_game);
run_my_game.step.dependOn(b.getInstallStep());
const run_my_game_step = b.step("run-my-game", "Run My Game");
run_my_game_step.dependOn(&run_my_game.step);
```

5. Build and run:
```bash
zig build run-my-game
```

## Engine Import

All examples import the engine using:
```zig
const zdl = @import("engine");
```

This gives you access to:
- `zdl.Engine` - The engine itself
- `zdl.Application` - Application interface
- `zdl.Context` - Context passed to your game
- `zdl.Input` - Input system
- `zdl.Camera2D` - 2D camera
- `zdl.SpriteBatch` - Sprite renderer
- `zdl.Color` - Color helpers
- `zdl.Vec2`, `zdl.Mat4` - Math types

See [../ENGINE_README.md](../ENGINE_README.md) for complete API documentation.

## Tips

- Keep your game logic in a separate `.zig` file (like `pong.zig`)
- Use `main.zig` only for engine initialization
- Study the existing examples to see patterns
- Start simple - get something on screen first, then add features
- Use delta_time for all movement to keep it smooth

## Contributing Examples

If you create a cool example game, consider contributing it! Good examples:
- Demonstrate a specific feature or technique
- Are well-commented
- Include a description of what they showcase
- Are simple enough to understand but interesting enough to be useful
