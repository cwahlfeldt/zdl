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
├── serialization/    # Scene serialization
│   ├── serialization.zig    # Module exports
│   └── scene_serializer.zig # JSON scene save/load
├── debug/            # Debug and profiling tools
│   ├── debug.zig         # Module exports
│   ├── profiler.zig      # Frame timing and CPU zone profiling
│   ├── debug_draw.zig    # Visual debug rendering (lines, boxes, spheres)
│   └── stats_overlay.zig # FPS, memory, draw call statistics
├── assets/           # Asset management
│   ├── asset_manager.zig    # Runtime asset loading/caching
│   └── gltf/                # glTF loader
│       ├── gltf.zig         # Module exports, GLTFLoader
│       ├── parser.zig       # JSON/GLB parsing
│       ├── animation_loader.zig # Skeleton/animation loading
│       └── types.zig        # Data types
├── animation/        # Animation system
│   ├── animation.zig        # Module exports
│   ├── skeleton.zig         # Bone hierarchy
│   ├── animation_clip.zig   # Keyframe data
│   ├── animator.zig         # Playback/blending
│   ├── animator_component.zig # ECS component
│   ├── animation_system.zig # ECS system
│   └── skinned_mesh.zig     # GPU skinning support
├── input/            # Input system
├── math/             # Vec2, Vec3, Vec4, Mat4, Quat
├── resources/        # Mesh, Texture, Primitives
├── gpu/              # GPU uniforms
├── shaders/          # GLSL vertex/fragment shaders
├── audio/            # Audio system
└── engine.zig        # Module exports

tools/
└── asset_pipeline/   # Asset build tool (zdl-assets)

assets/
├── scenes/           # Example scene files
└── shaders/          # GPU shaders (including skinned_vertex.vert)

examples/
├── cube3d/           # Simple 3D cube demo
├── scene_demo/       # FPS camera with scene hierarchy
├── debug_demo/       # Debug visualization and profiling demo
├── gltf_demo/        # glTF model loading demo
├── animation_demo/   # Skeletal animation demo
└── pbr_demo/         # PBR rendering with materials and lights
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
- Optional PBR Material for physically-based rendering
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

### Scene Serialization

Save and load scenes to/from JSON files:

```zig
const SceneSerializer = @import("engine").SceneSerializer;

// Save a scene
var serializer = SceneSerializer.initWithAssets(allocator, &asset_manager);
try serializer.saveToFile(&scene, "my_scene.json");

// Load a scene
const loaded_scene = try serializer.loadFromFile("my_scene.json", null);
defer {
    loaded_scene.deinit();
    allocator.destroy(loaded_scene);
}
```

Scene files are JSON with the following structure:
- `version`: Format version string
- `active_camera_id`: Entity ID of active camera
- `entities`: Array of serialized entities with components

Supported components: Transform, Camera, MeshRenderer, Light, FpvCameraController.

Example scene file: `assets/scenes/example.scene.json`

### Debug and Profiling

The debug module provides tools for development:

**Profiler** - Frame timing and CPU zone profiling:
```zig
const Profiler = engine.Profiler;
const scopedZone = engine.scopedZone;

var profiler = try Profiler.init(allocator);
defer profiler.deinit();

// In game loop:
profiler.beginFrame();
defer profiler.endFrame();

// Profile a code section:
{
    const zone = scopedZone(&profiler, "Physics");
    defer zone.end();
    // ... physics code ...
}

// Query stats:
const fps = profiler.getFps();
const frame_ms = profiler.getFrameTime();
```

**DebugDraw** - Visual debug primitives:
```zig
const DebugDraw = engine.DebugDraw;

var debug_draw = DebugDraw.init(allocator);
defer debug_draw.deinit(&eng.device);

// Initialize GPU resources (after engine init):
try debug_draw.initGpu(&eng.device, swapchain_format);

// Draw debug shapes:
debug_draw.line(from, to, Color.init(1, 0, 0, 1));
debug_draw.wireBox(center, size, Color.init(0, 1, 0, 1));
debug_draw.wireSphere(center, radius, Color.init(0, 0, 1, 1));
debug_draw.axes(position, size);
debug_draw.grid(center, size, divisions, color);
debug_draw.arrow(from, to, color);

// Render (in render pass):
debug_draw.uploadVertexData(&eng.device);
debug_draw.render(&eng.device, cmd, pass, view_proj);
debug_draw.clear();
```

**StatsOverlay** - Performance statistics:
```zig
const StatsOverlay = engine.StatsOverlay;

var stats = StatsOverlay.init(&profiler);
stats.updateEntityCount(scene.entityCount());
stats.recordDrawCall(vertex_count, index_count);

// Get formatted stats:
var buffer: [256]u8 = undefined;
const text = stats.formatTitleString(&buffer);
```

See `examples/debug_demo/` for a complete example.

### Animation System

The animation module provides skeletal animation support:

**Skeleton** - Bone hierarchy for characters:
```zig
const Skeleton = engine.Skeleton;
const NO_BONE = engine.animation.NO_BONE;

var skeleton = try Skeleton.init(allocator, 3); // 3 bones
defer skeleton.deinit();

// Set up bones: name, parent index, local transform
try skeleton.setBone(0, "root", NO_BONE, Transform.init());
try skeleton.setBone(1, "spine", 0, Transform.withPosition(Vec3.init(0, 1, 0)));
try skeleton.setBone(2, "head", 1, Transform.withPosition(Vec3.init(0, 0.5, 0)));

try skeleton.computeRootBones();
```

**AnimationClip** - Keyframe animation data:
```zig
const AnimationClip = engine.AnimationClip;
const AnimationChannel = engine.animation.AnimationChannel;

var clip = try AnimationClip.init(allocator, "walk", 1); // 1 channel
defer clip.deinit();

// Create rotation channel for bone 0
clip.channels[0] = try AnimationChannel.init(allocator, 0, .rotation, 3);
clip.channels[0].times[0] = 0.0;
clip.channels[0].times[1] = 0.5;
clip.channels[0].times[2] = 1.0;
clip.channels[0].rotation_values.?[0] = Quat.identity();
clip.channels[0].rotation_values.?[1] = Quat.fromAxisAngle(Vec3.init(0, 1, 0), 0.5);
clip.channels[0].rotation_values.?[2] = Quat.identity();

clip.computeDuration();
```

**Animator** - Animation playback and blending:
```zig
const Animator = engine.Animator;

var animator = try Animator.init(allocator, &skeleton);
defer animator.deinit();

try animator.addClip("walk", &walk_clip);
try animator.addClip("idle", &idle_clip);

// Play animation
_ = animator.play("walk");

// Crossfade to another animation
_ = animator.crossFade("idle", 0.3); // 0.3 second transition

// In update loop:
animator.update(delta_time);

// Get skinning matrices for GPU
const matrices = animator.getSkinningMatrices();
```

See `examples/animation_demo/` for a complete example.

### PBR Rendering

The engine supports Physically-Based Rendering with metallic-roughness workflow:

**Material** - PBR material properties:
```zig
const Material = engine.Material;

// Create materials with helper methods
const gold = Material.metal(1.0, 0.766, 0.336, 0.3);  // r, g, b, roughness
const plastic = Material.dielectric(0.2, 0.6, 0.9, 0.3);  // r, g, b, roughness
const emissive = Material.withEmissive(0.1, 0.1, 0.1, 2.0, 1.0, 0.5);  // base rgb, emissive rgb

// Or configure manually
var material = Material.init();
material.base_color = Vec4.init(0.9, 0.1, 0.1, 1.0);
material.metallic = 0.0;     // 0.0 = dielectric, 1.0 = metal
material.roughness = 0.5;    // 0.0 = smooth, 1.0 = rough
material.emissive = Vec3.init(0, 0, 0);

// Attach to mesh renderer
try scene.addComponent(entity, MeshRendererComponent.withMaterial(&mesh, material));
```

**Lights** - Multiple light types:
```zig
const LightComponent = engine.LightComponent;

// Directional light (sun)
try scene.addComponent(sun, LightComponent.directional(
    Vec3.init(1, 0.95, 0.9),  // color
    2.0                       // intensity
));

// Point light
try scene.addComponent(lamp, LightComponent.point(
    Vec3.init(1, 0.8, 0.6),  // color
    5.0,                      // intensity
    15.0                      // range
));

// Spot light
try scene.addComponent(flashlight, LightComponent.spot(
    Vec3.init(1, 1, 1),      // color
    10.0,                     // intensity
    20.0,                     // range
    0.9,                      // inner_cutoff (cos of angle)
    0.8                       // outer_cutoff (cos of angle)
));
```

**Initialization** - Enable PBR in your game:
```zig
var eng = try Engine.init(allocator, .{ .window_title = "PBR Demo" });
defer eng.deinit();

// Initialize PBR pipeline (required before using materials)
try eng.initPBR();

// Check if PBR is available
if (eng.hasPBR()) {
    // PBR rendering enabled
}
```

The render system automatically switches between legacy and PBR pipelines based on whether entities have materials attached.

See `examples/pbr_demo/` for a complete example.

## Creating a New Game

1. Create `examples/my_game/main.zig`
2. Initialize engine and scene
3. Create entities with components
4. Call `eng.runScene(&scene, update_fn)`
5. Add the executable to `build.zig`
6. Build and run with `zig build run-my-game`

See `examples/cube3d/` for a simple example and `examples/scene_demo/` for FPS camera controls.
