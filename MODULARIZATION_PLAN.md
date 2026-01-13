# ZDL Engine Modularization Plan

This document outlines a plan to decouple the ZDL engine into independent, testable subsystems. The goal is to enable:

1. **Unit testing** of subsystems in isolation
2. **Clear module boundaries** with explicit dependencies
3. **Independent development** of each subsystem
4. **Reduced coupling** between engine components

**Note:** SDL remains the platform layer throughout. This plan focuses on decoupling *our* subsystems from each other, not abstracting SDL away.

---

## Current Architecture Problems

### 1. Circular Dependencies
```
Engine → ScriptSystem → Scene → RenderSystem → Engine
```
The render system directly accesses `Engine` internals. Script system needs Scene which needs Engine context.

### 2. Engine is a God Object
`engine.zig` does too much:
- Window management
- GPU device ownership
- Pipeline creation (main, PBR, skybox, IBL)
- Game loop
- Input processing
- Audio initialization
- Scripting initialization
- Mouse capture state

### 3. RenderSystem Tightly Coupled to Engine
`RenderSystem.render()` takes a `RenderFrame` that contains an `engine` pointer. It directly accesses:
- `frame.engine.hasPBR()`
- `frame.engine.pbr_pipeline`
- `frame.engine.light_uniforms`
- `frame.engine.default_texture`

### 4. Scattered Pipeline/Shader Management
Pipelines are created in multiple places:
- `engine.zig` (main, PBR, skybox, skinned)
- `debug_draw.zig`
- `ui_renderer.zig`
- `ibl.zig`

### 5. No Clear Module Boundaries
Files import freely across the codebase with no layering. For example:
- `gltf/scene_import.zig` imports `Scene` and `Entity`
- `scripting/bindings/*` import from `engine`, `ecs`, `input`, `resources`

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Application Layer                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                       Game / Examples                        │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Engine Coordinator                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Engine (thin coordinator)                   │   │
│  │  - Owns subsystems                                           │   │
│  │  - Runs main loop                                            │   │
│  │  - Passes context between subsystems                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
        ┌─────────────┬───────────┼───────────┬─────────────┐
        ▼             ▼           ▼           ▼             ▼
┌───────────┐  ┌───────────┐  ┌───────┐  ┌─────────┐  ┌──────────┐
│  Window   │  │  Render   │  │  ECS  │  │  Input  │  │  Audio   │
│  Manager  │  │  Manager  │  │ Scene │  │ Manager │  │  Manager │
└───────────┘  └───────────┘  └───────┘  └─────────┘  └──────────┘
      │              │             │           │             │
      └──────────────┴─────────────┴───────────┴─────────────┘
                                  │
                                  ▼
                          ┌───────────────┐
                          │  SDL3 + Flecs │
                          │   + QuickJS   │
                          └───────────────┘
```

---

## Module Definitions

### Core Modules (Foundation Layer)

These have minimal dependencies and provide foundational types:

| Module | Location | Dependencies | Purpose |
|--------|----------|--------------|---------|
| `math` | `src/math/` | std only | Vec2, Vec3, Vec4, Mat4, Quat |
| `core` | `src/core/` | std only | Common types, allocators, handles |

### Platform Layer

SDL-based systems that interface with the OS:

| Module | Location | Dependencies | Purpose |
|--------|----------|--------------|---------|
| `window` | `src/window/` | SDL, core | Window creation, event polling |
| `gpu` | `src/gpu/` | SDL, core, math | GPU device, buffers, textures, pipelines |
| `input` | `src/input/` | SDL, core, math | Keyboard, mouse, gamepad state |
| `audio` | `src/audio/` | SDL, core | Sound loading and playback |

### Resource Layer

Asset types that can be loaded/saved:

| Module | Location | Dependencies | Purpose |
|--------|----------|--------------|---------|
| `resources` | `src/resources/` | gpu, math | Mesh, Texture, Material, Primitives |
| `assets` | `src/assets/` | resources, gpu | AssetManager, glTF loader |

### ECS Layer

Entity-Component-System architecture:

| Module | Location | Dependencies | Purpose |
|--------|----------|--------------|---------|
| `ecs` | `src/ecs/` | Flecs, math, resources | Scene, Entity, Components |

### Systems Layer

Systems that operate on ECS and resources:

| Module | Location | Dependencies | Purpose |
|--------|----------|--------------|---------|
| `render` | `src/render/` | gpu, ecs, resources | RenderManager, pipelines |
| `animation` | `src/animation/` | ecs, math | Skeleton, Animator, AnimationClip |
| `scripting` | `src/scripting/` | QuickJS, ecs, input | JS runtime, script components |
| `debug` | `src/debug/` | gpu, math | Profiler, DebugDraw, StatsOverlay |
| `ui` | `src/ui/` | gpu, input | UI rendering, widgets |

### Serialization Layer

Scene and component persistence:

| Module | Location | Dependencies | Purpose |
|--------|----------|--------------|---------|
| `serialization` | `src/serialization/` | ecs, math, assets/handles | Scene import/export |

### Engine Layer

Top-level coordinator:

| Module | Location | Dependencies | Purpose |
|--------|----------|--------------|---------|
| `engine` | `src/engine/` | All above | Engine struct, main loop |

---

## Dependency Map and Allowed Imports (Target)

Layering stays shallow and explicit:

```
Layer 0: core, math
Layer 1: window, gpu, input, audio
Layer 2: resources, assets
Layer 3: ecs
Layer 4: render, animation, scripting, debug, ui, serialization
Layer 5: engine
```

Concrete boundaries (enforce in review):

| Module | Allowed imports (besides std) | Must not import |
|--------|-------------------------------|----------------|
| `core` | - | sdl3, quickjs, zflecs, engine |
| `math` | - | sdl3, quickjs, zflecs, engine |
| `window` | core, sdl3 | render, ecs, assets, engine |
| `gpu` | core, math, sdl3 | ecs, assets, engine |
| `input` | core, math, sdl3 | ecs, render, engine |
| `audio` | core, sdl3 | ecs, render, engine |
| `resources` | core, math, gpu | ecs, render, engine |
| `assets` | core, resources, gpu | ecs (no scene import), render, engine |
| `ecs` | core, math, zflecs, assets/handles | render, input, audio, engine |
| `render` | core, math, gpu, ecs, resources | window, assets, engine |
| `animation` | core, math, ecs | render, engine |
| `scripting` | core, ecs, input, quickjs | engine, render |
| `debug` | core, math, gpu, render | engine |
| `ui` | core, math, gpu, input, resources | engine |
| `serialization` | core, ecs, math, assets/handles | render, engine |
| `engine` | all modules | - |

Notes:
- `assets/handles` should be dependency-free (or move to `core/handles`) so ECS can use handles without importing `AssetManager`.
- Cross-module imports should go through each module's `*.zig` entry point (no deep imports across module boundaries).
- Same-layer imports are allowed only when they are not bidirectional.

Current boundary violations to resolve (tracked):
- `src/debug/debug_draw.zig` and `src/ui/ui_renderer.zig` import `Color` from `src/engine/engine.zig`; move `Color` to `render` or `core`.
- `src/resources/texture.zig` imports `Color` from `src/engine/engine.zig`; same fix as above.
- `src/assets/asset_manager.zig` imports ECS to `importGLTFScene`; move scene import to ECS importer or a separate integration module.
- `src/serialization/scene_serializer.zig` depends on `AssetManager`; replace with an `AssetResolver` interface or handle-based IDs.

---

## Implementation Phases

### Phase 1: Extract Window Manager

**Goal:** Move window creation and event polling out of Engine.

**Create:** `src/window/window_manager.zig`

```zig
const sdl = @import("sdl3");

pub const WindowManager = struct {
    window: *sdl.video.Window,
    width: u32,
    height: u32,

    pub fn init(config: WindowConfig) !WindowManager { ... }
    pub fn deinit(self: *WindowManager) void { ... }

    /// Poll SDL events and return them. Does NOT process them.
    pub fn pollEvents(self: *WindowManager, buffer: []Event) []Event { ... }

    pub fn setTitle(self: *WindowManager, title: [:0]const u8) void { ... }
    pub fn getSize(self: *WindowManager) struct { width: u32, height: u32 } { ... }
};

pub const WindowConfig = struct {
    title: [:0]const u8 = "ZDL",
    width: u32 = 1280,
    height: u32 = 720,
    resizable: bool = true,
    fullscreen: bool = false,
};
```

**Changes to Engine:**
- Engine owns a `WindowManager` instead of raw SDL window
- Event polling delegated to WindowManager

---

### Phase 2: Extract Render Manager

**Goal:** Consolidate all rendering concerns into a dedicated manager.

**Create:** `src/render/render_manager.zig`

```zig
pub const RenderManager = struct {
    device: *sdl.gpu.Device,
    allocator: Allocator,

    // Pipelines
    main_pipeline: *sdl.gpu.GraphicsPipeline,
    pbr_pipeline: ?*sdl.gpu.GraphicsPipeline,
    skinned_pipeline: ?*sdl.gpu.GraphicsPipeline,
    skybox_pipeline: ?*sdl.gpu.GraphicsPipeline,

    // Shared resources
    default_sampler: *sdl.gpu.Sampler,
    default_texture: *Texture,
    depth_texture: *sdl.gpu.Texture,

    // Light uniforms (shared state for rendering)
    light_uniforms: LightUniforms,

    pub fn init(allocator: Allocator, window: *sdl.video.Window) !RenderManager { ... }
    pub fn deinit(self: *RenderManager) void { ... }

    /// Initialize PBR pipeline (call after init if PBR is needed)
    pub fn initPBR(self: *RenderManager) !void { ... }

    /// Initialize skybox pipeline
    pub fn initSkybox(self: *RenderManager) !void { ... }

    /// Begin a frame - acquire command buffer and swapchain texture
    pub fn beginFrame(self: *RenderManager) !RenderFrame { ... }

    /// End a frame - submit command buffer
    pub fn endFrame(self: *RenderManager, frame: *RenderFrame) void { ... }

    /// Render a scene using the appropriate pipeline
    pub fn renderScene(self: *RenderManager, frame: *RenderFrame, scene: *Scene) void { ... }

    // Query methods
    pub fn hasPBR(self: *RenderManager) bool { ... }
    pub fn hasSkybox(self: *RenderManager) bool { ... }
    pub fn getDevice(self: *RenderManager) *sdl.gpu.Device { ... }
};

pub const RenderFrame = struct {
    command_buffer: *sdl.gpu.CommandBuffer,
    swapchain_texture: *sdl.gpu.Texture,
    render_pass: *sdl.gpu.RenderPass,

    // Reference to manager for pipeline access (NOT engine!)
    manager: *RenderManager,
};
```

**Changes to Engine:**
- Engine owns a `RenderManager`
- All pipeline creation moves to RenderManager
- RenderSystem receives `RenderFrame` with manager reference (not engine)

**Changes to RenderSystem:**
```zig
// Before:
pub fn render(frame: *RenderFrame, scene: *Scene) void {
    if (frame.engine.hasPBR()) { ... }  // BAD: accesses engine
}

// After:
pub fn render(frame: *RenderFrame, scene: *Scene) void {
    if (frame.manager.hasPBR()) { ... }  // GOOD: accesses render manager
}
```

---

### Phase 3: Refactor Input Manager

**Goal:** Make Input independent and receive events from Engine.

**Current Problem:**
Input processes SDL events directly in `processEvent()`. It's also updated by Engine in the game loop.

**Solution:**
Input should expose methods to update state, Engine translates SDL events and calls Input methods.

```zig
// src/input/input.zig (refactored)
pub const Input = struct {
    keyboard: KeyboardState,
    mouse: MouseState,
    gamepads: GamepadManager,

    pub fn init() Input { ... }
    pub fn deinit(self: *Input) void { ... }

    // State update methods (called by Engine after translating SDL events)
    pub fn setKeyDown(self: *Input, scancode: Scancode, repeat: bool) void { ... }
    pub fn setKeyUp(self: *Input, scancode: Scancode) void { ... }
    pub fn setMousePosition(self: *Input, x: i32, y: i32) void { ... }
    pub fn setMouseDelta(self: *Input, dx: i32, dy: i32) void { ... }
    pub fn setMouseButton(self: *Input, button: MouseButton, down: bool) void { ... }
    pub fn setMouseWheel(self: *Input, dx: f32, dy: f32) void { ... }

    // Frame boundary
    pub fn endFrame(self: *Input) void { ... }

    // Query methods (unchanged)
    pub fn isKeyDown(self: *const Input, scancode: Scancode) bool { ... }
    pub fn isKeyPressed(self: *const Input, scancode: Scancode) bool { ... }
    pub fn getMousePosition(self: *const Input) Vec2 { ... }
    pub fn getMoveVector(self: *const Input) Vec2 { ... }
    // ... etc
};
```

**Changes to Engine:**
```zig
fn processEvents(self: *Engine) void {
    while (self.window_manager.pollEvent()) |event| {
        switch (event.type) {
            .key_down => self.input.setKeyDown(event.key.scancode, event.key.repeat),
            .key_up => self.input.setKeyUp(event.key.scancode),
            .mouse_motion => {
                self.input.setMousePosition(event.motion.x, event.motion.y);
                self.input.setMouseDelta(event.motion.xrel, event.motion.yrel);
            },
            .quit => self.running = false,
            // ... etc
        }
    }
}
```

This makes Input testable without SDL - you can directly call `setKeyDown()` in tests.

---

### Phase 4: Decouple Script System

**Goal:** Remove ScriptSystem's direct dependency on Engine.

**Current Problem:**
ScriptSystem needs Engine for delta time, FPS, window size, mouse capture, etc.

**Solution:**
Create a `ScriptContext` that Engine populates and passes to ScriptSystem.

```zig
// src/scripting/script_context.zig
pub const ScriptContext = struct {
    // Time
    delta_time: f32,
    total_time: f64,
    fps: f32,

    // Window
    window_width: u32,
    window_height: u32,

    // Mouse capture
    mouse_captured: bool,
    set_mouse_capture: *const fn(bool) void,

    // Quit callback
    request_quit: *const fn() void,
};
```

**Changes to ScriptSystem:**
```zig
pub fn update(self: *ScriptSystem, ctx: ScriptContext, scene: *Scene, input: *Input) void {
    // Use ctx.delta_time instead of engine.delta_time
    // Use ctx.set_mouse_capture instead of engine.setMouseCapture
}
```

**Changes to Engine:**
```zig
fn runLoop(self: *Engine) void {
    const ctx = ScriptContext{
        .delta_time = self.delta_time,
        .total_time = self.total_time,
        .fps = self.fps,
        .window_width = self.window_manager.width,
        .window_height = self.window_manager.height,
        .mouse_captured = self.mouse_captured,
        .set_mouse_capture = &self.setMouseCapture,
        .request_quit = &self.quit,
    };

    self.script_system.update(ctx, &self.scene, &self.input);
}
```

---

### Phase 5: Consolidate Shader/Pipeline Loading

**Goal:** Single location for all shader compilation and pipeline creation.

**Create:** `src/render/shader_library.zig`

```zig
pub const ShaderLibrary = struct {
    device: *sdl.gpu.Device,
    allocator: Allocator,

    // Cached shaders
    shaders: std.StringHashMap(*sdl.gpu.Shader),

    pub fn init(allocator: Allocator, device: *sdl.gpu.Device) ShaderLibrary { ... }
    pub fn deinit(self: *ShaderLibrary) void { ... }

    /// Load a shader from embedded bytes or file
    pub fn loadShader(self: *ShaderLibrary, name: []const u8, stage: ShaderStage, code: []const u8) !*sdl.gpu.Shader { ... }

    /// Get a previously loaded shader
    pub fn getShader(self: *ShaderLibrary, name: []const u8) ?*sdl.gpu.Shader { ... }
};
```

**Create:** `src/render/pipeline_cache.zig`

```zig
pub const PipelineCache = struct {
    device: *sdl.gpu.Device,
    allocator: Allocator,
    shader_library: *ShaderLibrary,

    // Cached pipelines
    pipelines: std.StringHashMap(*sdl.gpu.GraphicsPipeline),

    pub fn init(allocator: Allocator, device: *sdl.gpu.Device, shader_library: *ShaderLibrary) PipelineCache { ... }
    pub fn deinit(self: *PipelineCache) void { ... }

    /// Create or get a pipeline by name with given config
    pub fn getPipeline(self: *PipelineCache, name: []const u8, config: PipelineConfig) !*sdl.gpu.GraphicsPipeline { ... }

    // Pre-built pipeline configs
    pub fn getMainPipeline(self: *PipelineCache) !*sdl.gpu.GraphicsPipeline { ... }
    pub fn getPBRPipeline(self: *PipelineCache) !*sdl.gpu.GraphicsPipeline { ... }
    pub fn getSkyboxPipeline(self: *PipelineCache) !*sdl.gpu.GraphicsPipeline { ... }
    pub fn getDebugPipeline(self: *PipelineCache) !*sdl.gpu.GraphicsPipeline { ... }
    pub fn getUIPipeline(self: *PipelineCache) !*sdl.gpu.GraphicsPipeline { ... }
};
```

**Changes:**
- RenderManager uses PipelineCache
- DebugDraw uses PipelineCache (passed in init)
- UIRenderer uses PipelineCache (passed in init)
- Remove duplicate shader loading code

---

### Phase 6: Clean Up Module Exports

**Goal:** Each module has a single entry point that exports public API.

**Pattern:**
```
src/render/
├── render.zig          # Module entry: pub usingnamespace for public API
├── render_manager.zig  # Main manager struct
├── render_frame.zig    # Frame struct
├── pipeline_cache.zig  # Pipeline caching
├── shader_library.zig  # Shader management
└── internal/           # Private implementation details
```

**Example `src/render/render.zig`:**
```zig
pub const RenderManager = @import("render_manager.zig").RenderManager;
pub const RenderFrame = @import("render_frame.zig").RenderFrame;
pub const PipelineCache = @import("pipeline_cache.zig").PipelineCache;
pub const ShaderLibrary = @import("shader_library.zig").ShaderLibrary;

// Internal types not exported
```

**Update `src/engine.zig` (main module export):**
```zig
// Core
pub const math = @import("math/math.zig");
pub const Vec2 = math.Vec2;
pub const Vec3 = math.Vec3;
// ...

// Window
pub const window = @import("window/window.zig");
pub const WindowManager = window.WindowManager;

// Render
pub const render = @import("render/render.zig");
pub const RenderManager = render.RenderManager;

// ECS
pub const ecs = @import("ecs/ecs.zig");
pub const Scene = ecs.Scene;
pub const Entity = ecs.Entity;

// ... etc
```

---

## Dependency Rules

Use the "Dependency Map and Allowed Imports (Target)" section as the source of truth.
In short:
- Modules only import from the same layer or lower.
- No circular imports between modules.
- `engine` is the only module allowed to import from every layer.

---

## File Changes Summary

### New Files

| Path | Purpose |
|------|---------|
| `src/window/window_manager.zig` | Window creation/management |
| `src/window/window.zig` | Module exports |
| `src/render/render_manager.zig` | Rendering coordination |
| `src/render/render_frame.zig` | Per-frame render state |
| `src/render/pipeline_cache.zig` | Pipeline caching |
| `src/render/shader_library.zig` | Shader management |
| `src/render/render.zig` | Module exports |
| `src/scripting/script_context.zig` | Context passed to scripts |
| `src/core/core.zig` | Common types module |

### Files to Refactor

| Path | Changes |
|------|---------|
| `src/engine/engine.zig` | Extract window, render management; thin coordinator |
| `src/input/input.zig` | Add state-setting methods; remove SDL event processing |
| `src/ecs/systems/render_system.zig` | Use RenderManager instead of Engine |
| `src/scripting/script_system.zig` | Use ScriptContext instead of Engine |
| `src/debug/debug_draw.zig` | Accept PipelineCache in init |
| `src/ui/ui_renderer.zig` | Accept PipelineCache in init |

### Files to Delete (Stale Code)

Already removed:
- `lib/ultralight/` - Unused Ultralight integration
- `lib/zig-ultralight/` - Unused Ultralight bindings
- `lib/ultralight-free-sdk-*/` - Unused Ultralight SDK
- `FLECS_MIGRATION_PLAN.md` - Completed migration plan
- `my-game/` - Generated test project

---

## Testing Strategy

### Unit Tests (No SDL Required)

With proper decoupling, these can be tested:

| Module | Test Focus |
|--------|------------|
| `math/*` | Vector/matrix operations |
| `input` | State tracking with direct `setKeyDown()` calls |
| `ecs/scene` | Entity creation, component management |
| `scripting/script_context` | Context construction |

### Integration Tests (SDL Required)

| Test | Purpose |
|------|---------|
| Window creation | Verify WindowManager creates SDL window |
| Pipeline creation | Verify PipelineCache creates valid pipelines |
| Full render | End-to-end rendering test |

---

## Migration Path

### Step 1: Non-Breaking Additions
1. Create `WindowManager` (Engine uses it internally, API unchanged)
2. Create `RenderManager` (Engine uses it internally, API unchanged)
3. Add ScriptContext (Engine creates it, ScriptSystem accepts it)

### Step 2: Internal Refactoring
1. Move pipeline creation to RenderManager
2. Update RenderSystem to use `frame.manager` instead of `frame.engine`
3. Update ScriptSystem to use ScriptContext

### Step 3: Public API Cleanup
1. Expose new managers in public API
2. Update examples to use new patterns (optional)
3. Document new architecture

---

## Success Criteria

1. **RenderSystem has no Engine import**
2. **ScriptSystem receives ScriptContext, not Engine**
3. **Input can be unit tested with mock events**
4. **All pipelines created through PipelineCache**
5. **Clear layer dependencies (no upward imports)**
6. **All examples still work**
7. **No circular dependencies between modules**

---

## Out of Scope

The following are explicitly **not** goals of this modularization:

- Abstracting SDL behind interfaces (SDL is our platform layer)
- Supporting multiple rendering backends
- Removing deprecated APIs (separate task, do after modularization)
- Changing the public game API
- JavaScript-first engine direction (paused per IMPLEMENTATION_PLAN.md)
