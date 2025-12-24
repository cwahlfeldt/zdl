# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZDL is a 3D game engine built with Zig and SDL3. The engine provides a clean, modular architecture for building 3D applications with perspective rendering, mesh management, and modern GPU pipeline support.

**Architecture Principles:**
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
│   ├── engine.zig    # Main engine, GPU setup, game loop
│   └── application.zig # Application interface
├── input/            # Input system
├── math/             # Vec2, Vec3, Vec4, Mat4, Quat
├── resources/        # Mesh, Texture, Primitives
├── gpu/              # GPU uniforms
├── shaders/          # GLSL vertex/fragment shaders
├── audio/            # Audio system
├── camera.zig        # 3D perspective camera
├── transform.zig     # 3D transform (position, rotation, scale)
└── engine.zig        # Module exports

examples/
└── cube3d/           # 3D cube demo
```

### Core Components

**Engine** ([src/engine/engine.zig](src/engine/engine.zig)):
- SDL3 initialization and GPU device management
- 3D graphics pipeline with depth testing
- Game loop with delta timing and FPS counter

**Camera** ([src/camera.zig](src/camera.zig)):
- Perspective projection (fov, aspect, near/far planes)
- View matrix (position, target, up vector)
- Movement: moveForward, moveRight, moveUp, orbit

**Transform** ([src/transform.zig](src/transform.zig)):
- Position (Vec3), Rotation (Quaternion), Scale (Vec3)
- TRS matrix generation
- Direction helpers: forward, right, up

**Mesh** ([src/resources/mesh.zig](src/resources/mesh.zig)):
- Vertex3D format: position, normal, UV, color
- GPU buffer upload
- Index buffer support

**Primitives** ([src/resources/primitives.zig](src/resources/primitives.zig)):
- createCube, createPlane, createQuad, createSphere

### Application Interface

Games implement four methods:
```zig
pub fn init(self: *MyGame, ctx: *Context) !void
pub fn deinit(self: *MyGame, ctx: *Context) void
pub fn update(self: *MyGame, ctx: *Context, delta_time: f32) !void
pub fn render(self: *MyGame, ctx: *Context) !void
```

Context provides access to:
- `ctx.allocator` - Memory allocator
- `ctx.input` - Keyboard input
- `ctx.camera` - 3D camera (engine-managed)
- `ctx.audio` - Audio system
- `ctx.device` - GPU device
- `ctx.pipeline` - Graphics pipeline
- `ctx.depth_texture` - Depth buffer
- `ctx.white_texture`, `ctx.sampler` - Default texture/sampler

### Rendering

Games handle their own rendering using the graphics context:
```zig
const cmd = try ctx.device.acquireCommandBuffer();
// ... setup render pass with depth target
pass.bindGraphicsPipeline(ctx.pipeline.*);
// ... push uniforms, bind mesh, draw
```

Uniforms use Model-View-Projection matrices:
```zig
const uniforms = Uniforms.init(
    transform.getMatrix(),    // Model
    camera.getViewMatrix(),   // View
    camera.getProjectionMatrix(), // Projection
);
```

## Creating a New Game

1. Create `examples/my_game/my_game.zig` implementing the Application interface
2. Create `examples/my_game/main.zig` with engine initialization
3. Add the executable to `build.zig`
4. Build and run with `zig build run-my-game`

See `examples/cube3d/` for a complete example.
