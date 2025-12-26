# QuickJS Integration Plan for ZDL

This document outlines the plan for integrating QuickJS as an embedded JavaScript scripting language into the ZDL game engine to simplify game development.

## Goals

### Primary Goals

1. **Simplify Game Development** - Allow game logic to be written in JavaScript instead of Zig, lowering the barrier to entry for developers unfamiliar with systems programming.

2. **Hot Reloading** - Enable live script reloading during development without recompiling the engine, dramatically improving iteration speed.

3. **Rapid Prototyping** - Provide a high-level scripting environment for quickly testing gameplay ideas before optimizing in Zig.

4. **Moddability** - Allow end-users to create mods and custom content using JavaScript without needing Zig toolchain.

### Secondary Goals

1. **Performance-Critical Code in Zig** - Keep rendering, physics, and other performance-sensitive systems in Zig while scripting handles game logic.

2. **Type-Safe Bindings** - Provide clear, documented JavaScript APIs that map cleanly to the underlying ECS.

3. **Minimal Overhead** - QuickJS's small footprint (~210KB) and fast startup (<300μs) aligns well with game engine requirements.

## Why QuickJS

| Feature | Benefit for ZDL |
|---------|-----------------|
| Small footprint (210KB x86) | Minimal impact on binary size |
| Fast startup (<300μs) | No noticeable delay when loading scripts |
| ES2023 support | Modern JavaScript with async/await, modules |
| No external dependencies | Simplifies build integration |
| Reference counting + GC | Predictable memory behavior |
| MIT license | Compatible with any game distribution |
| C API | Direct integration with Zig via `@cImport` |
| Bytecode compilation | Optional pre-compilation for release builds |

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Game Scripts (JS)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  player.js  │  │  enemy.js   │  │   game.js   │  ...        │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      JavaScript Bindings                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Scene API   │  │ Entity API  │  │  Input API  │  ...        │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Script Runtime (Zig)                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  src/scripting/                                              ││
│  │  ├── runtime.zig      (JSRuntime/JSContext management)      ││
│  │  ├── bindings.zig     (C function exports to JS)            ││
│  │  ├── script_component.zig  (ECS component for scripts)      ││
│  │  └── script_system.zig     (System to execute scripts)      ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ZDL Core Engine (Zig)                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │  Engine  │  │   ECS    │  │  Input   │  │   GPU    │  ...   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
src/
├── scripting/
│   ├── runtime.zig           # QuickJS runtime wrapper
│   ├── bindings/
│   │   ├── bindings.zig      # Main binding exports
│   │   ├── scene_bindings.zig
│   │   ├── entity_bindings.zig
│   │   ├── transform_bindings.zig
│   │   ├── input_bindings.zig
│   │   ├── math_bindings.zig
│   │   └── time_bindings.zig
│   ├── script_component.zig  # Component that holds script references
│   └── script_system.zig     # System that executes script callbacks
├── ecs/
│   └── components/
│       └── script_component.zig  # (or add to existing components)
```

### New Dependencies

Add to `build.zig.zon`:
```zig
.quickjs = .{
    .url = "git+https://github.com/AequoreaVictoria/zig-quickjs#<commit>",
    // OR build from source via:
    // .url = "git+https://github.com/quickjs-ng/quickjs#<commit>",
}
```

Alternatively, vendor QuickJS source directly and compile via Zig's build system using `@cImport`.

## JavaScript API Design

### Core Classes

```javascript
// Entity creation and component management
const player = Scene.createEntity();
player.addComponent("Transform", { position: [0, 1, 0] });
player.addComponent("MeshRenderer", { mesh: "cube" });

// Component access
const transform = player.getComponent("Transform");
transform.position.y += 1;
transform.setRotation(0, Math.PI / 4, 0);

// Hierarchy
const weapon = Scene.createEntity();
weapon.setParent(player);

// Camera
Scene.setActiveCamera(cameraEntity);
```

### Script Component Pattern

```javascript
// scripts/player_controller.js
export default class PlayerController {
    // Called when component is added
    onStart(entity) {
        this.speed = 5.0;
        this.transform = entity.getComponent("Transform");
    }

    // Called every frame
    onUpdate(entity, deltaTime) {
        const input = Input.getAxis("horizontal");
        this.transform.position.x += input * this.speed * deltaTime;

        if (Input.isKeyPressed("Space")) {
            this.jump();
        }
    }

    jump() {
        // Jump logic
    }

    // Called when entity is destroyed
    onDestroy(entity) {
        // Cleanup
    }
}
```

### Input API

```javascript
// Keyboard
if (Input.isKeyDown("W")) { /* held */ }
if (Input.isKeyPressed("Space")) { /* just pressed */ }
if (Input.isKeyReleased("Escape")) { /* just released */ }

// Mouse
const [mx, my] = Input.getMousePosition();
const [dx, dy] = Input.getMouseDelta();
if (Input.isMouseButtonDown(0)) { /* left click held */ }

// Gamepad (future)
const axis = Input.getAxis("horizontal"); // -1 to 1
```

### Math Utilities

```javascript
// Vectors
const v1 = new Vec3(1, 2, 3);
const v2 = v1.add(new Vec3(4, 5, 6));
const len = v1.length();
const normalized = v1.normalize();
const dot = v1.dot(v2);

// Quaternions
const q = Quat.fromEuler(0, Math.PI / 2, 0);
const rotated = q.rotate(v1);

// Matrices
const m = Mat4.identity();
const translated = Mat4.translation(1, 2, 3);
```

### Resource Loading

```javascript
// Load meshes
const mesh = await Resources.loadMesh("assets/models/character.obj");

// Primitives
const cube = Primitives.createCube();
const sphere = Primitives.createSphere(1.0, 32, 32);

// Textures (future)
const texture = await Resources.loadTexture("assets/textures/diffuse.png");
```

## Integration Steps

### Phase 1: Core Runtime

1. **Add QuickJS dependency** - Either use existing Zig bindings or vendor the C source
2. **Create `runtime.zig`** - Wrapper managing JSRuntime and JSContext lifecycle
3. **Basic evaluation** - Load and execute JavaScript strings/files
4. **Error handling** - Capture JS exceptions and report them meaningfully
5. **Memory limits** - Configure appropriate memory constraints

### Phase 2: Basic Bindings

1. **Console API** - `console.log()`, `console.warn()`, `console.error()`
2. **Time API** - `Time.deltaTime`, `Time.elapsed`, `Time.frameCount`
3. **Math bindings** - Vec3, Vec4, Quat, Mat4 as JS classes
4. **Input bindings** - Keyboard and mouse state queries

### Phase 3: ECS Integration

1. **Entity bindings** - Create, destroy, check validity
2. **Scene bindings** - Entity queries, active camera, hierarchy
3. **Transform bindings** - Position, rotation, scale access
4. **Component bindings** - Generic add/remove/get interface
5. **ScriptComponent** - New ECS component type holding script references

### Phase 4: Script System

1. **ScriptSystem** - Iterates entities with ScriptComponent
2. **Lifecycle callbacks** - `onStart()`, `onUpdate()`, `onDestroy()`
3. **Script loading** - Load `.js` files from assets directory
4. **Script caching** - Compile once, instantiate per-entity

### Phase 5: Developer Experience

1. **Hot reloading** - Watch script files and reload on change
2. **Debug output** - Source maps or line number preservation
3. **REPL** - Optional runtime console for debugging
4. **Documentation** - API reference and examples

### Phase 6: Advanced Features

1. **Async support** - `async/await` for resource loading
2. **ES modules** - `import`/`export` between scripts
3. **Bytecode compilation** - Pre-compile scripts for release builds
4. **TypeScript definitions** - `.d.ts` files for editor support

## Implementation Details

### Runtime Wrapper

```zig
// src/scripting/runtime.zig
const c = @cImport({
    @cInclude("quickjs.h");
});

pub const ScriptRuntime = struct {
    rt: *c.JSRuntime,
    ctx: *c.JSContext,

    pub fn init() !ScriptRuntime {
        const rt = c.JS_NewRuntime() orelse return error.RuntimeCreationFailed;
        const ctx = c.JS_NewContext(rt) orelse {
            c.JS_FreeRuntime(rt);
            return error.ContextCreationFailed;
        };

        // Set memory limit (e.g., 32MB)
        c.JS_SetMemoryLimit(rt, 32 * 1024 * 1024);

        return .{ .rt = rt, .ctx = ctx };
    }

    pub fn deinit(self: *ScriptRuntime) void {
        c.JS_FreeContext(self.ctx);
        c.JS_FreeRuntime(self.rt);
    }

    pub fn eval(self: *ScriptRuntime, code: []const u8, filename: []const u8) !void {
        const result = c.JS_Eval(
            self.ctx,
            code.ptr,
            code.len,
            filename.ptr,
            c.JS_EVAL_TYPE_GLOBAL
        );

        if (c.JS_IsException(result)) {
            // Handle exception
            const exception = c.JS_GetException(self.ctx);
            defer c.JS_FreeValue(self.ctx, exception);
            // Log error...
            return error.ScriptException;
        }

        c.JS_FreeValue(self.ctx, result);
    }
};
```

### Binding Example

```zig
// src/scripting/bindings/transform_bindings.zig
fn js_transform_set_position(
    ctx: *c.JSContext,
    this_val: c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.C) c.JSValue {
    if (argc < 3) {
        return c.JS_ThrowTypeError(ctx, "setPosition requires 3 arguments");
    }

    // Get entity from 'this'
    const entity = getEntityFromThis(ctx, this_val) orelse {
        return c.JS_ThrowReferenceError(ctx, "Invalid entity");
    };

    // Parse arguments
    var x: f64 = undefined;
    var y: f64 = undefined;
    var z: f64 = undefined;
    _ = c.JS_ToFloat64(ctx, &x, argv[0]);
    _ = c.JS_ToFloat64(ctx, &y, argv[1]);
    _ = c.JS_ToFloat64(ctx, &z, argv[2]);

    // Update transform
    if (scene.getComponent(TransformComponent, entity)) |transform| {
        transform.local.position = Vec3.init(@floatCast(x), @floatCast(y), @floatCast(z));
    }

    return c.JS_UNDEFINED;
}
```

### Script Component

```zig
// src/ecs/components/script_component.zig
pub const ScriptComponent = struct {
    /// Path to the JavaScript file
    script_path: []const u8,

    /// Compiled bytecode (cached)
    bytecode: ?[]const u8 = null,

    /// JS object instance for this entity
    js_instance: ?c.JSValue = null,

    /// Whether onStart has been called
    started: bool = false,

    pub fn init(path: []const u8) ScriptComponent {
        return .{ .script_path = path };
    }
};
```

## Potential Challenges

### 1. Memory Management

**Challenge**: QuickJS uses reference counting with cycle detection. Mixing with Zig's manual memory management requires care.

**Mitigation**:
- Use `JS_DupValue()` and `JS_FreeValue()` consistently
- Set memory limits via `JS_SetMemoryLimit()`
- Run GC explicitly at frame boundaries if needed
- Use weak references for entity handles to avoid preventing entity destruction

### 2. Type Safety

**Challenge**: JavaScript is dynamically typed; Zig is statically typed. Incorrect API usage may only fail at runtime.

**Mitigation**:
- Validate arguments in every binding function
- Provide TypeScript definition files for editor support
- Return meaningful error messages
- Consider JSDoc annotations for documentation

### 3. Performance

**Challenge**: JavaScript is slower than Zig. Heavy use of scripts could impact frame rate.

**Mitigation**:
- Keep performance-critical code in Zig (rendering, physics)
- Batch script callbacks to reduce JS↔Zig transitions
- Profile and optimize hot paths
- Use bytecode compilation for release builds
- Consider throttling script execution for background entities

### 4. Hot Reloading State

**Challenge**: Reloading scripts may lose runtime state (entity positions, health, etc.).

**Mitigation**:
- Preserve component data separately from scripts
- Scripts should read state from components, not store it internally
- Provide `onHotReload()` callback for scripts to reinitialize
- Consider serialization of script state

### 5. Debugging

**Challenge**: Stack traces point to bytecode, not source lines. Debugging JS inside a game is non-trivial.

**Mitigation**:
- Preserve source locations in eval calls
- Implement `console.log()` with timestamps
- Consider runtime REPL for live debugging
- Export source maps if using a bundler

### 6. Threading

**Challenge**: QuickJS is not thread-safe. Each runtime must be used from a single thread.

**Mitigation**:
- Run scripts on main thread only
- Use Zig for any parallel workloads
- Consider message-passing if async operations are needed

### 7. Build System Integration

**Challenge**: Integrating QuickJS C source with Zig's build system.

**Mitigation**:
- Use `@cImport` to include QuickJS headers
- Add QuickJS `.c` files to build via `addCSourceFiles`
- Alternatively, use pre-built static library

### 8. API Surface

**Challenge**: Exposing too much or too little API. Too much creates maintenance burden; too little limits usefulness.

**Mitigation**:
- Start minimal (entities, transforms, input)
- Add APIs based on actual game needs
- Document what's available vs. what requires Zig
- Version the scripting API separately from engine

## Example Game in JavaScript

```javascript
// game.js
import PlayerController from './player_controller.js';
import EnemyAI from './enemy_ai.js';

export function init(scene) {
    // Create camera
    const camera = scene.createEntity();
    camera.addComponent("Camera", { fov: 60, near: 0.1, far: 1000 });
    camera.addComponent("Transform", { position: [0, 5, 10] });
    camera.addComponent("FpsCameraController");
    scene.setActiveCamera(camera);

    // Create player
    const player = scene.createEntity();
    player.addComponent("Transform", { position: [0, 1, 0] });
    player.addComponent("MeshRenderer", { mesh: "cube" });
    player.addComponent("Script", { class: PlayerController });

    // Create some enemies
    for (let i = 0; i < 5; i++) {
        const enemy = scene.createEntity();
        enemy.addComponent("Transform", {
            position: [Math.random() * 20 - 10, 1, Math.random() * 20 - 10]
        });
        enemy.addComponent("MeshRenderer", { mesh: "sphere" });
        enemy.addComponent("Script", { class: EnemyAI, args: { target: player } });
    }

    // Create floor
    const floor = scene.createEntity();
    floor.addComponent("Transform", { position: [0, 0, 0], scale: [20, 1, 20] });
    floor.addComponent("MeshRenderer", { mesh: "plane" });
}
```

## Success Criteria

1. **Functional**: Scripts can create entities, add components, and respond to input
2. **Performant**: Script overhead < 1ms per frame with 100 scripted entities
3. **Stable**: No memory leaks or crashes from script errors
4. **Usable**: Clear error messages, reasonable stack traces
5. **Documented**: API reference with examples for all bindings

## Resources

- [QuickJS Official Documentation](https://bellard.org/quickjs/quickjs.html)
- [QuickJS GitHub (bellard)](https://github.com/bellard/quickjs)
- [QuickJS-NG (actively maintained fork)](https://github.com/quickjs-ng/quickjs)
- [QuickJS-NG Documentation](https://quickjs-ng.github.io/quickjs/)
- [Castle Game Engine QuickJS Integration](https://castle-engine.io/wp/2020/04/02/castle-game-engine-integration-with-quickjs-javascript/)
- [Zig QuickJS Bindings (KallynGowdy/zigjs)](https://github.com/KallynGowdy/zigjs)
