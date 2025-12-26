# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZDL is a 3D game engine built with Zig and SDL3. The engine uses an Entity Component System (ECS) architecture for building 3D applications with perspective rendering, mesh management, and modern GPU pipeline support.

**Architecture Principles:**
- Entity Component System (ECS) for game object management
- Clean separation between engine and game code
- 3D-focused with perspective projection and depth testing
- Modern GPU pipeline with SPIR-V shaders (Metal on macOS)

## Build System

- Zig version: 0.15.2
- Build system: Zig's standard build system (`build.zig`)
- Dependencies managed via `build.zig.zon`

### Common Commands

```bash
# Build the project
zig build

# Run the cube3d example
zig build run

# Clean build artifacts
rm -rf zig-out .zig-cache
```

## Dependencies

The project uses `zig-sdl3` from Codeberg (7Games/zig-sdl3) for SDL3 bindings. Shaders are compiled from GLSL to SPIR-V using `glslangValidator`.

## Architecture

### Directory Structure

```
src/
├── engine/           # Core engine
│   └── engine.zig    # Main engine, GPU setup, game loop
├── ecs/              # Entity Component System
│   ├── entity.zig    # Entity handles with generational indexing
│   ├── scene.zig     # Scene container with hierarchy support
│   ├── component_storage.zig # Sparse-set component storage
│   ├── components/   # Component definitions
│   │   ├── transform_component.zig  # Transform + TransformComponent
│   │   ├── camera_component.zig
│   │   └── mesh_renderer.zig
│   └── systems/      # ECS systems
│       └── render_system.zig
├── input/            # Input system
├── math/             # Vec2, Vec3, Vec4, Mat4, Quat
├── resources/        # Mesh, Texture, Primitives
├── gpu/              # GPU uniforms
├── shaders/          # GLSL vertex/fragment shaders
├── audio/            # Audio system
└── engine.zig        # Module exports

examples/
├── cube3d/           # Simple 3D cube demo
└── scene_demo/       # FPS camera with scene hierarchy
```

### Core Components

**Engine** ([src/engine/engine.zig](src/engine/engine.zig)):
- SDL3 initialization and GPU device management
- 3D graphics pipeline with depth testing
- Game loop with delta timing and FPS counter
- Scene-based rendering via `runScene()`

**Scene** ([src/ecs/scene.zig](src/ecs/scene.zig)):
- Entity creation and destruction
- Component management (add, remove, get)
- Parent-child hierarchy with world transform propagation
- Active camera management

**TransformComponent** ([src/ecs/components/transform_component.zig](src/ecs/components/transform_component.zig)):
- Local transform (position, rotation, scale)
- Cached world matrix for hierarchy
- Parent/child/sibling entity links

**CameraComponent** ([src/ecs/components/camera_component.zig](src/ecs/components/camera_component.zig)):
- Perspective projection settings (fov, near, far)
- View matrix computed from entity's world transform

**MeshRendererComponent** ([src/ecs/components/mesh_renderer.zig](src/ecs/components/mesh_renderer.zig)):
- Mesh and optional texture references
- Enabled flag for visibility control

**Mesh** ([src/resources/mesh.zig](src/resources/mesh.zig)):
- Vertex3D format: position, normal, UV, color
- GPU buffer upload
- Index buffer support

**Primitives** ([src/resources/primitives.zig](src/resources/primitives.zig)):
- createCube, createPlane, createQuad, createSphere

### Game Loop Pattern

Games provide an update callback to `Engine.runScene()`:

```zig
fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    // Update game logic here
}

pub fn main() !void {
    var eng = try Engine.init(allocator, .{ .window_title = "My Game" });
    defer eng.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create entities and components...

    try eng.runScene(&scene, update);
}
```

### Creating Entities

```zig
// Create camera
const camera = try scene.createEntity();
try scene.addComponent(camera, CameraComponent.init());
try scene.addComponent(camera, TransformComponent.withPosition(Vec3.init(0, 2, 5)));
scene.setActiveCamera(camera);

// Create renderable object
const cube = try scene.createEntity();
try scene.addComponent(cube, TransformComponent.init());
try scene.addComponent(cube, MeshRendererComponent.init(&cube_mesh));

// Create hierarchy
const child = try scene.createEntity();
try scene.addComponent(child, TransformComponent.withPosition(Vec3.init(2, 0, 0)));
scene.setParent(child, cube);  // child now orbits with cube
```

### Rendering

The `RenderSystem` automatically renders all `MeshRendererComponent` entities using the active camera. World transforms are computed from the scene hierarchy.

## Creating a New Game

1. Create `examples/my_game/main.zig`
2. Initialize engine and scene
3. Create entities with components
4. Call `eng.runScene(&scene, update_fn)`
5. Add the executable to `build.zig`
6. Build and run with `zig build run-my-game`

See `examples/cube3d/` for a simple example and `examples/scene_demo/` for FPS camera controls.
