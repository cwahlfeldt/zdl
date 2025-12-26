# ZDL - Zig 3D Game Engine

A lightweight 3D game engine built with Zig and SDL3. Features an Entity Component System, perspective rendering, mesh management, and a modern GPU pipeline.

## Quick Start

```bash
# Build and run the 3D cube demo
zig build run

# Run the ECS scene demo
zig build run-scene
```

## Features

- **Entity Component System** - Scene graph with entities, components, and parent-child hierarchies
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
│   ├── ecs/               # Entity Component System
│   │   ├── scene.zig      # Scene container
│   │   ├── entity.zig     # Entity handles
│   │   ├── components/    # Transform, Camera, MeshRenderer, Light
│   │   └── systems/       # Render system
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
│   ├── cube3d/            # 3D rotating cube (Application interface)
│   └── scene_demo/        # ECS scene with parent-child entities
│
└── build.zig              # Build configuration
```

## Two Ways to Build Games

### Option 1: ECS/Scene Approach (Recommended)

Simpler setup with automatic rendering and parent-child hierarchies:

```zig
const engine = @import("engine");
const Scene = engine.Scene;
const TransformComponent = engine.TransformComponent;
const MeshRendererComponent = engine.MeshRendererComponent;

// Create scene and entities
var scene = Scene.init(allocator);
const cube = try scene.createEntity();
try scene.addComponent(cube, TransformComponent.init());
try scene.addComponent(cube, MeshRendererComponent.init(&mesh));

// Run with update callback
try eng.runScene(&scene, myUpdateFn);
```

### Option 2: Application Interface

Full control over rendering for custom pipelines:

```zig
pub fn init(self: *MyGame, ctx: *Context) !void
pub fn deinit(self: *MyGame, ctx: *Context) void
pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void
pub fn render(self: *MyGame, ctx: *Context) !void
```

## Examples

### Cube3D (`zig build run`)
Traditional Application interface with manual rendering:
- Creating and uploading meshes to GPU
- 3D camera with WASD movement
- Transform rotation with quaternions
- Per-object Model-View-Projection uniforms

### Scene Demo (`zig build run-scene`)
ECS approach with automatic rendering:
- Scene and Entity management
- Parent-child entity hierarchies (child cube orbits parent)
- Component-based architecture
- Simplified update loop

**Controls (both):**
- WASD/Arrow Keys: Move camera
- Q/E: Move up/down
- F3: Toggle FPS counter
- ESC: Quit

## Creating a New Game

Create `examples/my_game/main.zig`:

```zig
const std = @import("std");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Vec3 = engine.Vec3;
const Input = engine.Input;
const primitives = engine.primitives;
const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;

var mesh: engine.Mesh = undefined;

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

    // Create and upload mesh
    mesh = try primitives.createCube(allocator);
    defer mesh.deinit(&eng.device);
    try mesh.upload(&eng.device);

    // Setup scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Camera
    const camera = try scene.createEntity();
    try scene.addComponent(camera, CameraComponent.init());
    var cam_transform = TransformComponent.withPosition(Vec3.init(0, 2, 5));
    cam_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    try scene.addComponent(camera, cam_transform);
    scene.setActiveCamera(camera);

    // Game object
    const cube = try scene.createEntity();
    try scene.addComponent(cube, TransformComponent.init());
    try scene.addComponent(cube, MeshRendererComponent.init(&mesh));

    try eng.runScene(&scene, update);
}

fn update(scene: *Scene, input: *Input, delta_time: f32) !void {
    _ = scene;
    _ = input;
    _ = delta_time;
    // Your game logic here
}
```

Add to `build.zig` and run with `zig build run-my-game`

See [examples/README.md](examples/README.md) for the Application interface approach and detailed setup

## Engine API

### Scene & Entities (ECS)

```zig
var scene = Scene.init(allocator);
const entity = try scene.createEntity();

// Add components
try scene.addComponent(entity, TransformComponent.init());
try scene.addComponent(entity, MeshRendererComponent.init(&mesh));

// Parent-child relationships
scene.setParent(child, parent);

// Get/modify components
if (scene.getComponent(TransformComponent, entity)) |transform| {
    transform.setRotationEuler(0, rotation, 0);
}
```

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

## Requirements

- Zig 0.15.2
- SDL3 (automatically fetched)
- glslangValidator (for shader compilation)

## Building

```bash
zig build             # Build all
zig build run         # Run cube3d example
zig build run-scene   # Run scene demo
rm -rf zig-out .zig-cache  # Clean
```

## License

MIT License

## Credits

Built with:
- [Zig](https://ziglang.org/)
- [SDL3](https://github.com/libsdl-org/SDL)
- [zig-sdl3](https://codeberg.org/7Games/zig-sdl3)
