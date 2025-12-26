# ZDL Engine Examples

This directory contains example applications built with the ZDL 3D engine.

## Running Examples

### 3D Cube Demo (Default)

```bash
zig build run
```

### Scene Demo (ECS)

```bash
zig build run-scene
```

**Controls (both examples):**
- WASD/Arrow Keys: Move camera forward/back/left/right
- Q/E: Move camera up/down
- F3: Toggle FPS counter
- ESC: Quit

## Example Structure

```
examples/
├── cube3d/
│   ├── main.zig        # Entry point
│   └── cube3d.zig      # Game implementation (Application interface)
└── scene_demo/
    └── main.zig        # ECS-based scene with parent-child entities
```

## What the Examples Demonstrate

### Cube3D (`examples/cube3d/`)

Traditional Application interface approach with manual rendering.

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
- Transform system
- GPU resource management
- Manual render pass setup

### Scene Demo (`examples/scene_demo/`)

Entity Component System (ECS) approach with automatic rendering.

**Features:**
- Scene and Entity management
- Component-based architecture (TransformComponent, CameraComponent, MeshRendererComponent)
- Parent-child entity hierarchies
- Automatic world transform calculation
- Simplified update loop with callback function
- Engine-managed rendering

**Good for learning:**
- ECS architecture patterns
- Scene graph hierarchies
- Component composition
- Simplified game loop structure

## Creating Your Own Example

Choose between two approaches:

### Option A: ECS/Scene Approach (Recommended)

Simpler setup with automatic rendering. Best for most games.

1. Create `examples/my_game/main.zig`:
```zig
const std = @import("std");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Vec3 = engine.Vec3;
const Input = engine.Input;
const Mesh = engine.Mesh;
const primitives = engine.primitives;
const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;

var cube_mesh: Mesh = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "My Game",
        .window_width = 1280,
        .window_height = 720,
    });
    defer eng.deinit();

    // Create mesh
    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    // Create scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create camera
    const camera = try scene.createEntity();
    try scene.addComponent(camera, CameraComponent.init());
    var cam_transform = TransformComponent.withPosition(Vec3.init(0, 2, 5));
    cam_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    try scene.addComponent(camera, cam_transform);
    scene.setActiveCamera(camera);

    // Create cube entity
    const cube = try scene.createEntity();
    try scene.addComponent(cube, TransformComponent.init());
    try scene.addComponent(cube, MeshRendererComponent.init(&cube_mesh));

    try eng.runScene(&scene, update);
}

fn update(scene: *Scene, input: *Input, delta_time: f32) !void {
    // Your game logic here
    _ = scene;
    _ = input;
    _ = delta_time;
}
```

### Option B: Application Interface Approach

Full control over rendering. Best for custom render pipelines.

1. Create `examples/my_game/main.zig`:
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

2. Create `examples/my_game/my_game.zig`:
```zig
const std = @import("std");
const engine = @import("engine");
const Context = engine.Context;
const Camera = engine.Camera;
const Transform = engine.Transform;
const Vec3 = engine.Vec3;
const Mesh = engine.Mesh;
const primitives = engine.primitives;

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

### Adding to build.zig

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

Build and run:
```bash
zig build run-my-game
```

## Engine Imports

All examples import the engine:
```zig
const engine = @import("engine");
```

**Core:**
- `engine.Engine` - The engine core
- `engine.Application` - Application interface (for manual rendering)
- `engine.Context` - Runtime context

**ECS (Entity Component System):**
- `engine.Scene` - Scene container for entities
- `engine.Entity` - Entity handle
- `engine.TransformComponent` - Position, rotation, scale component
- `engine.CameraComponent` - Camera component
- `engine.MeshRendererComponent` - Mesh rendering component
- `engine.LightComponent`, `engine.LightType` - Lighting components

**3D Graphics:**
- `engine.Camera` - 3D perspective camera (standalone)
- `engine.Transform` - 3D transform (standalone)
- `engine.Mesh`, `engine.Vertex3D` - Mesh system
- `engine.primitives` - Cube, plane, sphere generators
- `engine.Uniforms` - GPU uniform data
- `engine.Texture` - Texture loading

**Input/Audio:**
- `engine.Input` - Keyboard input
- `engine.Audio`, `engine.Sound` - Audio system

**Math:**
- `engine.Vec2`, `engine.Vec3`, `engine.Vec4` - Vector types
- `engine.Mat4` - 4x4 matrix
- `engine.Quat` - Quaternion

See [../CLAUDE.md](../CLAUDE.md) for complete API documentation.
