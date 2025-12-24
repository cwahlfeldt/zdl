# ZDL - Zig 3D Game Engine

A lightweight 3D game engine built with Zig and SDL3. Features perspective rendering, mesh management, and a modern GPU pipeline.

## Quick Start

```bash
# Build and run the 3D cube demo
zig build run
```

## Features

- **3D Graphics Pipeline** - Perspective projection, depth testing, backface culling
- **Mesh System** - Vertex3D format with normals, UVs, colors; GPU buffer upload
- **Primitives** - Built-in cube, plane, quad, sphere generators
- **Transform System** - Position, rotation (quaternion), scale with TRS matrix
- **3D Camera** - Perspective projection, view matrix, movement controls
- **Input System** - Keyboard state tracking
- **Audio System** - WAV loading and playback
- **Math Library** - Vec2, Vec3, Vec4, Mat4, Quat

## Project Structure

```
zdl/
├── src/                    # Engine source code
│   ├── engine/            # Core engine (SDL3, GPU, game loop)
│   ├── input/             # Input system
│   ├── resources/         # Mesh, Texture, Primitives
│   ├── math/              # Math library
│   ├── gpu/               # GPU uniforms
│   ├── shaders/           # GLSL shaders
│   ├── audio/             # Audio system
│   ├── camera.zig         # 3D camera
│   ├── transform.zig      # 3D transform
│   └── engine.zig         # Module exports
│
├── examples/
│   └── cube3d/            # 3D rotating cube demo
│
└── build.zig              # Build configuration
```

## Application Interface

Games implement four simple methods:

```zig
pub fn init(self: *MyGame, ctx: *Context) !void
pub fn deinit(self: *MyGame, ctx: *Context) void
pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void
pub fn render(self: *MyGame, ctx: *Context) !void
```

## Example: 3D Cube Demo

The cube3d example demonstrates:
- Creating and uploading meshes to GPU
- 3D camera with WASD movement
- Transform rotation with quaternions
- Per-object Model-View-Projection uniforms
- Depth-tested rendering

Controls:
- WASD/Arrow Keys: Move camera
- Q/E: Move up/down
- F3: Toggle FPS counter
- ESC: Quit

## Creating a New Game

1. Create your game file in `examples/my_game/`:

```zig
// my_game.zig
const std = @import("std");
const engine = @import("engine");

pub const MyGame = struct {
    // Your game state here

    pub fn init(self: *MyGame, ctx: *engine.Context) !void {
        // Initialize meshes, camera, etc.
    }

    pub fn deinit(self: *MyGame, ctx: *engine.Context) void {
        // Cleanup
    }

    pub fn update(self: *MyGame, ctx: *engine.Context, delta_time: f32) !void {
        // Game logic, input handling
    }

    pub fn render(self: *MyGame, ctx: *engine.Context) !void {
        // Render your scene
    }
};
```

2. Create `main.zig`:

```zig
const std = @import("std");
const engine = @import("engine");
const MyGame = @import("my_game.zig").MyGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var eng = try engine.Engine.init(gpa.allocator(), .{
        .window_title = "My Game",
        .window_width = 1280,
        .window_height = 720,
    });
    defer eng.deinit();

    var game: MyGame = .{};
    const app = engine.Application.createApplication(MyGame, &game);
    try eng.run(app);
}
```

3. Add to `build.zig` and run with `zig build run-my-game`

## Engine API

### Camera

```zig
var camera = Camera.init(width, height);
camera.position = Vec3.init(0, 2, 5);
camera.target = Vec3.init(0, 0, 0);
camera.moveForward(distance);
camera.moveRight(distance);
camera.orbit(yaw, pitch);
```

### Transform

```zig
var transform = Transform.withPosition(Vec3.init(0, 0, 0));
transform.scale = Vec3.init(2, 2, 2);
transform.setRotationEuler(pitch, yaw, roll);
const model_matrix = transform.getMatrix();
```

### Mesh

```zig
var mesh = try primitives.createCube(allocator);
try mesh.upload(device);
defer mesh.deinit(device);
```

### Uniforms

```zig
const uniforms = Uniforms.init(
    transform.getMatrix(),
    camera.getViewMatrix(),
    camera.getProjectionMatrix(),
);
cmd.pushVertexUniformData(1, std.mem.asBytes(&uniforms));
```

## Requirements

- Zig 0.15.2
- SDL3 (automatically fetched)
- glslangValidator (for shader compilation)

## Building

```bash
zig build           # Build all
zig build run       # Run cube3d example
rm -rf zig-out .zig-cache  # Clean
```

## License

MIT License

## Credits

Built with:
- [Zig](https://ziglang.org/)
- [SDL3](https://github.com/libsdl-org/SDL)
- [zig-sdl3](https://codeberg.org/7Games/zig-sdl3)
