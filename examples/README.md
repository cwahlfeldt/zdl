# ZDL Engine Examples

This directory contains example applications built with the ZDL 3D engine.

## Running Examples

### 3D Cube Demo (Default)

```bash
zig build run
```

**Controls:**
- WASD/Arrow Keys: Move camera forward/back/left/right
- Q/E: Move camera up/down
- F3: Toggle FPS counter
- ESC: Quit

## Example Structure

```
examples/
└── cube3d/
    ├── main.zig        # Entry point
    └── cube3d.zig      # Game implementation
```

## What the Example Demonstrates

### Cube3D (`examples/cube3d/`)

**Features:**
- Creating 3D meshes (cube and plane primitives)
- Uploading meshes to GPU
- 3D camera with perspective projection
- Camera movement controls
- Transform system with quaternion rotation
- Per-object Model-View-Projection uniforms
- Depth-tested rendering
- Window resize handling

**Good for learning:**
- 3D rendering basics
- Camera controls
- Transform hierarchies
- GPU resource management

## Creating Your Own Example

1. Create a new directory: `examples/my_game/`

2. Create `main.zig`:
```zig
const std = @import("std");
const engine = @import("engine");
const MyGame = @import("my_game.zig").MyGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try engine.Engine.init(allocator, .{
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

3. Create `my_game.zig`:
```zig
const std = @import("std");
const engine = @import("engine");
const Context = engine.Context;
const Camera = engine.Camera;
const Transform = engine.Transform;
const Vec3 = engine.Vec3;
const Mesh = engine.Mesh;
const primitives = engine.primitives;
const Uniforms = engine.Uniforms;

pub const MyGame = struct {
    camera: Camera = undefined,
    mesh: ?Mesh = null,
    transform: Transform = undefined,

    pub fn init(self: *MyGame, ctx: *Context) !void {
        const size = ctx.getWindowSize();
        self.camera = Camera.init(size.width, size.height);
        self.camera.position = Vec3.init(0, 2, 5);
        self.camera.target = Vec3.init(0, 0, 0);

        self.mesh = try primitives.createCube(ctx.allocator);
        try self.mesh.?.upload(ctx.device);

        self.transform = Transform.withPosition(Vec3.init(0, 0, 0));
    }

    pub fn deinit(self: *MyGame, ctx: *Context) void {
        if (self.mesh) |*m| m.deinit(ctx.device);
    }

    pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void {
        // Handle input, update game state
        _ = self;
        _ = ctx;
        _ = delta_time;
    }

    pub fn render(self: *MyGame, ctx: *Context) !void {
        // See cube3d.zig for full rendering example
        _ = self;
        _ = ctx;
    }
};
```

4. Add to `build.zig`:
```zig
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

## Engine Imports

All examples import the engine:
```zig
const engine = @import("engine");
```

Available exports:
- `engine.Engine` - The engine core
- `engine.Application` - Application interface
- `engine.Context` - Runtime context
- `engine.Camera` - 3D perspective camera
- `engine.Transform` - 3D transform (position, rotation, scale)
- `engine.Mesh`, `engine.Vertex3D` - Mesh system
- `engine.primitives` - Cube, plane, sphere generators
- `engine.Uniforms` - GPU uniform data
- `engine.Texture` - Texture loading
- `engine.Input` - Keyboard input
- `engine.Audio`, `engine.Sound` - Audio system
- `engine.Vec2`, `engine.Vec3`, `engine.Vec4` - Vector types
- `engine.Mat4` - 4x4 matrix
- `engine.Quat` - Quaternion

See [../CLAUDE.md](../CLAUDE.md) for complete API documentation.
