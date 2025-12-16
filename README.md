# ZDL - Zig + SDL3 Game Engine

A lightweight, beginner-friendly 2D game engine built with Zig and SDL3. Focus on making games, not wrestling with GPU APIs.

## Quick Start

```bash
# Run Pong example
zig build run

# Run Platformer example
zig build run-platformer
```

## Project Structure

```
zdl/
├── src/                    # Engine source code
│   ├── engine/            # Core engine (SDL3, GPU, game loop)
│   ├── input/             # Input system
│   ├── renderer/          # Sprite batching and rendering
│   ├── math/              # Math library (Vec2, Mat4, etc.)
│   ├── camera.zig         # 2D camera system
│   └── engine.zig         # Engine module root
│
├── examples/              # Example games
│   ├── pong/             # Classic Pong
│   └── platformer/       # Platformer with physics
│
├── ENGINE_README.md       # Complete API documentation
├── QUICKSTART.md          # 5-minute tutorial
└── MIGRATION_GUIDE.md     # Architecture evolution
```

## Philosophy

**Engine = src/** - Handles all the complex SDL3/GPU stuff you don't want to think about

**Examples = examples/** - Shows you how to make games using the engine

You work with a simple 4-method interface:
```zig
pub fn init(self: *MyGame, ctx: *Context) !void
pub fn deinit(self: *MyGame, ctx: *Context) void
pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void
pub fn render(self: *MyGame, ctx: *Context) !void
```

That's it. The engine handles everything else.

## What You Get

✅ **Window & SDL3** - Automatic initialization and cleanup
✅ **GPU Rendering** - Shader compilation, buffers, pipelines
✅ **Input System** - Keyboard state tracking (down, just pressed, released)
✅ **2D Camera** - Orthographic projection with coordinate conversion
✅ **Sprite Batch** - Efficient rendering of colored quads
✅ **Frame Timing** - Delta time for smooth, framerate-independent movement
✅ **Math Library** - Vec2, Mat4 with all the operations you need

## Create Your First Game (30 seconds)

```zig
const std = @import("std");
const zdl = @import("engine");

pub const MyGame = struct {
    x: f32 = 0,

    pub fn init(self: *MyGame, ctx: *zdl.Context) !void { _ = ctx; _ = self; }
    pub fn deinit(self: *MyGame, ctx: *zdl.Context) void { _ = ctx; _ = self; }

    pub fn update(self: *MyGame, ctx: *zdl.Context, delta_time: f32) !void {
        if (ctx.input.isKeyDown(.d)) self.x += 200 * delta_time;
    }

    pub fn render(self: *MyGame, ctx: *zdl.Context) !void {
        try ctx.sprite_batch.addQuad(self.x, 0, 50, 50, zdl.Color.red());
    }
};
```

See [QUICKSTART.md](QUICKSTART.md) for a complete walkthrough.

## Examples

### Pong (~150 lines)
Two-player classic with ball physics and scoring.
```bash
zig build run
```

### Platformer (~165 lines)
Jump on platforms with gravity and collision detection.
```bash
zig build run-platformer
```

See [examples/README.md](examples/README.md) for details.

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Make your first game in 5 minutes
- **[ENGINE_README.md](ENGINE_README.md)** - Complete API reference
- **[examples/README.md](examples/README.md)** - Example games walkthrough
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)** - See how the architecture evolved
- **[CLAUDE.md](CLAUDE.md)** - Project guide for AI assistants

## Requirements

- Zig 0.15.2
- SDL3 (automatically fetched via build system)
- macOS, Linux, or Windows

## Building

```bash
# Build all examples
zig build

# Run pong (default)
zig build run

# Run platformer
zig build run-platformer

# Clean
rm -rf zig-out .zig-cache
```

## Engine Architecture

The engine is cleanly separated from game code:

**Engine Layer** (`src/`):
- Handles SDL3 initialization, GPU setup, shaders
- Manages game loop, timing, events
- Provides high-level systems (input, camera, sprite rendering)

**Game Layer** (`examples/`):
- Your game logic in 4 simple methods
- No need to touch engine internals
- Just import `"engine"` and start coding

## Contributing

Contributions welcome! Areas of interest:
- New example games
- Bug fixes
- Documentation improvements
- New engine features (texture loading, audio, etc.)

## License

MIT License - see LICENSE file for details

## Credits

Built with:
- [Zig](https://ziglang.org/) - Fast, safe systems programming
- [SDL3](https://github.com/libsdl-org/SDL) - Cross-platform multimedia library
- [zig-sdl3](https://codeberg.org/7Games/zig-sdl3) - Zig bindings for SDL3

---

**Ready to make games?** Check out [QUICKSTART.md](QUICKSTART.md)!
