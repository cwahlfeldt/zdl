# Embedded JavaScript Scripting (QuickJS)

## Overview

Integrate QuickJS as an embedded scripting engine for ZDL, enabling gameplay logic, modding support, and rapid iteration without recompilation. QuickJS is a small, fast JavaScript engine that supports ES2020 and is well-suited for game embedding.

## Current State

ZDL currently has:
- All game logic in Zig (compiled)
- No scripting or modding support
- Changes require full recompilation
- No hot-reloading capability

## Goals

- Embed QuickJS for JavaScript execution
- Expose engine APIs to JavaScript
- Support entity/component manipulation from scripts
- Enable hot-reloading of scripts
- Provide script-based game logic
- Support modding and user content
- Maintain type safety at Zig/JS boundary
- Minimize performance overhead

## Why QuickJS?

- **Small**: ~200KB binary size
- **Fast**: Competitive performance for embedded use
- **Standards-compliant**: ES2020 support
- **Self-contained**: No external dependencies
- **Embeddable**: Clean C API
- **Active**: Maintained and updated

## Architecture

### Directory Structure

```
src/
├── scripting/
│   ├── scripting.zig          # Module exports
│   ├── js_runtime.zig         # QuickJS runtime wrapper
│   ├── js_context.zig         # Script execution context
│   ├── bindings/
│   │   ├── bindings.zig       # Binding utilities
│   │   ├── engine_api.zig     # Engine bindings
│   │   ├── scene_api.zig      # Scene/ECS bindings
│   │   ├── input_api.zig      # Input bindings
│   │   ├── math_api.zig       # Math type bindings
│   │   └── audio_api.zig      # Audio bindings
│   ├── script_component.zig   # Script-based component
│   └── hot_reload.zig         # Script hot-reloading

scripts/                       # Game scripts directory
├── lib/
│   └── zdl.d.ts              # TypeScript definitions
├── main.js                    # Entry point
├── components/
│   ├── player_controller.js
│   └── enemy_ai.js
└── systems/
    └── combat.js
```

### Core Components

#### JavaScript Runtime

```zig
pub const JSRuntime = struct {
    rt: *qjs.JSRuntime,
    allocator: Allocator,

    // Memory tracking
    memory_limit: usize,
    memory_used: usize,

    pub fn init(allocator: Allocator, config: RuntimeConfig) !JSRuntime;
    pub fn deinit(self: *JSRuntime) void;

    pub fn createContext(self: *JSRuntime) !*JSContext;
    pub fn collectGarbage(self: *JSRuntime) void;
    pub fn setMemoryLimit(self: *JSRuntime, limit: usize) void;
    pub fn getMemoryUsage(self: *JSRuntime) MemoryUsage;
};

pub const RuntimeConfig = struct {
    memory_limit: usize = 32 * 1024 * 1024,  // 32MB default
    stack_size: usize = 256 * 1024,           // 256KB
    gc_threshold: usize = 8 * 1024 * 1024,    // 8MB
};

pub const MemoryUsage = struct {
    malloc_size: usize,
    malloc_count: usize,
    memory_used: usize,
    atom_count: usize,
    str_count: usize,
    obj_count: usize,
};
```

#### JavaScript Context

```zig
pub const JSContext = struct {
    ctx: *qjs.JSContext,
    runtime: *JSRuntime,
    global: JSValue,

    // Registered bindings
    engine_ref: ?*Engine,
    scene_ref: ?*Scene,

    pub fn init(runtime: *JSRuntime) !JSContext;
    pub fn deinit(self: *JSContext) void;

    // Script execution
    pub fn eval(self: *JSContext, code: []const u8, filename: []const u8) !JSValue;
    pub fn evalFile(self: *JSContext, path: []const u8) !JSValue;
    pub fn call(self: *JSContext, func: JSValue, this: JSValue, args: []const JSValue) !JSValue;

    // Module loading
    pub fn loadModule(self: *JSContext, path: []const u8) !JSValue;

    // Global registration
    pub fn setGlobal(self: *JSContext, name: []const u8, value: JSValue) void;
    pub fn getGlobal(self: *JSContext, name: []const u8) JSValue;

    // Error handling
    pub fn getException(self: *JSContext) ?JSException;
    pub fn clearException(self: *JSContext) void;
};

pub const JSValue = struct {
    value: qjs.JSValue,
    ctx: *JSContext,

    // Type checking
    pub fn isNull(self: JSValue) bool;
    pub fn isUndefined(self: JSValue) bool;
    pub fn isBool(self: JSValue) bool;
    pub fn isNumber(self: JSValue) bool;
    pub fn isString(self: JSValue) bool;
    pub fn isObject(self: JSValue) bool;
    pub fn isArray(self: JSValue) bool;
    pub fn isFunction(self: JSValue) bool;

    // Conversion to Zig types
    pub fn toBool(self: JSValue) !bool;
    pub fn toInt(self: JSValue) !i64;
    pub fn toFloat(self: JSValue) !f64;
    pub fn toString(self: JSValue, allocator: Allocator) ![]const u8;
    pub fn toVec3(self: JSValue) !Vec3;

    // Object access
    pub fn getProperty(self: JSValue, name: []const u8) JSValue;
    pub fn setProperty(self: JSValue, name: []const u8, value: JSValue) void;
    pub fn getIndex(self: JSValue, index: u32) JSValue;

    // Memory management
    pub fn dup(self: JSValue) JSValue;
    pub fn free(self: JSValue) void;
};

pub const JSException = struct {
    message: []const u8,
    stack: ?[]const u8,
    filename: ?[]const u8,
    line: u32,
    column: u32,
};
```

### API Bindings

#### Binding Utilities

```zig
pub const Bindings = struct {
    // Convert Zig function to JS function
    pub fn wrapFunction(
        comptime func: anytype,
        comptime arg_types: anytype,
        comptime return_type: type,
    ) qjs.JSCFunction;

    // Create JS object from Zig struct
    pub fn createObject(ctx: *JSContext, value: anytype) JSValue;

    // Create JS class with methods
    pub fn registerClass(
        ctx: *JSContext,
        comptime T: type,
        comptime methods: anytype,
    ) void;

    // Set up prototype chain
    pub fn setPrototype(ctx: *JSContext, obj: JSValue, proto: JSValue) void;
};

// Example: wrapping a Zig function
fn js_createEntity(ctx: *qjs.JSContext, this: qjs.JSValue, argc: c_int, argv: [*]qjs.JSValue) qjs.JSValue {
    const js_ctx = JSContext.fromRaw(ctx);
    const scene = js_ctx.scene_ref orelse return qjs.JS_EXCEPTION;

    const entity = scene.createEntity() catch return qjs.JS_EXCEPTION;
    return Bindings.createEntity(js_ctx, entity);
}
```

#### Engine API Bindings

```zig
pub const EngineBindings = struct {
    pub fn register(ctx: *JSContext, engine: *Engine) void {
        const engine_obj = ctx.createObject();

        // Properties
        engine_obj.setProperty("deltaTime", ctx.createGetter(getDeltaTime));
        engine_obj.setProperty("fps", ctx.createGetter(getFps));
        engine_obj.setProperty("time", ctx.createGetter(getTime));

        // Methods
        engine_obj.setProperty("quit", ctx.wrapFunction(quit));
        engine_obj.setProperty("setWindowTitle", ctx.wrapFunction(setWindowTitle));

        ctx.setGlobal("Engine", engine_obj);
    }

    fn getDeltaTime(engine: *Engine) f32 {
        return engine.delta_time;
    }

    fn quit(engine: *Engine) void {
        engine.quit();
    }
};
```

#### Scene/ECS API Bindings

```zig
pub const SceneBindings = struct {
    pub fn register(ctx: *JSContext, scene: *Scene) void {
        // Entity class
        ctx.registerClass(Entity, .{
            .getId = getEntityId,
            .isValid = isEntityValid,
            .destroy = destroyEntity,
            .getComponent = getComponent,
            .addComponent = addComponent,
            .removeComponent = removeComponent,
            .getParent = getParent,
            .setParent = setParent,
            .getChildren = getChildren,
        });

        // Scene object
        const scene_obj = ctx.createObject();
        scene_obj.setProperty("createEntity", ctx.wrapFunction(createEntity));
        scene_obj.setProperty("destroyEntity", ctx.wrapFunction(destroyEntity));
        scene_obj.setProperty("findByName", ctx.wrapFunction(findByName));
        scene_obj.setProperty("getAllEntities", ctx.wrapFunction(getAllEntities));

        ctx.setGlobal("Scene", scene_obj);

        // Component constructors
        registerComponentTypes(ctx);
    }

    fn createEntity(scene: *Scene) !Entity {
        return scene.createEntity();
    }
};

// JavaScript usage:
// const player = Scene.createEntity();
// player.addComponent('Transform', { position: Vec3(0, 1, 0) });
// player.addComponent('MeshRenderer', { mesh: 'player_mesh' });
```

#### Math API Bindings

```zig
pub const MathBindings = struct {
    pub fn register(ctx: *JSContext) void {
        // Vec3 class
        ctx.registerClass(Vec3, .{
            .constructor = vec3Constructor,
            .add = vec3Add,
            .sub = vec3Sub,
            .scale = vec3Scale,
            .dot = vec3Dot,
            .cross = vec3Cross,
            .normalize = vec3Normalize,
            .length = vec3Length,
        });

        // Global constructors
        ctx.setGlobal("Vec2", ctx.wrapConstructor(Vec2));
        ctx.setGlobal("Vec3", ctx.wrapConstructor(Vec3));
        ctx.setGlobal("Vec4", ctx.wrapConstructor(Vec4));
        ctx.setGlobal("Quat", ctx.wrapConstructor(Quat));

        // Math utilities
        const math_obj = ctx.createObject();
        math_obj.setProperty("lerp", ctx.wrapFunction(lerp));
        math_obj.setProperty("clamp", ctx.wrapFunction(clamp));
        math_obj.setProperty("smoothstep", ctx.wrapFunction(smoothstep));
        math_obj.setProperty("PI", std.math.pi);
        math_obj.setProperty("TAU", std.math.tau);
        ctx.setGlobal("Math", math_obj);  // Extends built-in Math
    }
};

// JavaScript usage:
// const pos = new Vec3(1, 2, 3);
// const dir = pos.normalize();
// const moved = pos.add(dir.scale(5));
```

#### Input API Bindings

```zig
pub const InputBindings = struct {
    pub fn register(ctx: *JSContext, input: *InputManager) void {
        const input_obj = ctx.createObject();

        // Keyboard
        input_obj.setProperty("isKeyDown", ctx.wrapFunction(isKeyDown));
        input_obj.setProperty("isKeyPressed", ctx.wrapFunction(isKeyPressed));
        input_obj.setProperty("isKeyReleased", ctx.wrapFunction(isKeyReleased));

        // Mouse
        input_obj.setProperty("getMousePosition", ctx.wrapFunction(getMousePosition));
        input_obj.setProperty("getMouseDelta", ctx.wrapFunction(getMouseDelta));
        input_obj.setProperty("isMouseButtonDown", ctx.wrapFunction(isMouseButtonDown));

        // Gamepad
        input_obj.setProperty("getGamepadCount", ctx.wrapFunction(getGamepadCount));
        input_obj.setProperty("getGamepadAxis", ctx.wrapFunction(getGamepadAxis));
        input_obj.setProperty("isGamepadButtonDown", ctx.wrapFunction(isGamepadButtonDown));

        // Action mapping
        input_obj.setProperty("isActionActive", ctx.wrapFunction(isActionActive));
        input_obj.setProperty("getActionValue", ctx.wrapFunction(getActionValue));

        ctx.setGlobal("Input", input_obj);

        // Key constants
        registerKeyConstants(ctx);
    }
};

// JavaScript usage:
// if (Input.isKeyPressed(Key.SPACE)) {
//     player.jump();
// }
// const move = new Vec2(
//     Input.getActionValue('move_right') - Input.getActionValue('move_left'),
//     Input.getActionValue('move_forward') - Input.getActionValue('move_back')
// );
```

### Script Components

Allow entities to have script-defined behavior:

```zig
pub const ScriptComponent = struct {
    script_path: []const u8,
    instance: ?JSValue,      // JS object instance
    context: *JSContext,

    // Cached method references
    on_start: ?JSValue,
    on_update: ?JSValue,
    on_destroy: ?JSValue,
    on_collision: ?JSValue,

    pub fn init(context: *JSContext, script_path: []const u8) !ScriptComponent;
    pub fn deinit(self: *ScriptComponent) void;

    pub fn start(self: *ScriptComponent, entity: Entity) void;
    pub fn update(self: *ScriptComponent, entity: Entity, dt: f32) void;
    pub fn destroy(self: *ScriptComponent, entity: Entity) void;

    // Hot reload
    pub fn reload(self: *ScriptComponent) !void;
};

pub const ScriptSystem = struct {
    context: *JSContext,

    pub fn update(self: *ScriptSystem, scene: *Scene, dt: f32) void {
        const scripts = scene.getComponents(ScriptComponent);
        const entities = scene.getEntitiesWithComponent(ScriptComponent);

        for (scripts, entities) |script, entity| {
            if (script.on_update) |update_fn| {
                self.context.call(update_fn, script.instance.?, &.{
                    self.context.createNumber(dt),
                }) catch |err| {
                    self.handleScriptError(entity, err);
                };
            }
        }
    }
};
```

### Hot Reloading

```zig
pub const HotReloader = struct {
    context: *JSContext,
    watched_files: std.StringHashMap(FileWatch),
    debounce_time: f32,

    pub fn init(context: *JSContext) HotReloader;

    pub fn watch(self: *HotReloader, path: []const u8) !void;
    pub fn unwatch(self: *HotReloader, path: []const u8) void;

    pub fn update(self: *HotReloader) void {
        for (self.watched_files.values()) |*watch| {
            if (watch.hasChanged()) {
                self.reloadScript(watch.path) catch |err| {
                    std.log.err("Hot reload failed: {}", .{err});
                };
            }
        }
    }

    fn reloadScript(self: *HotReloader, path: []const u8) !void {
        // Re-evaluate the script
        _ = try self.context.evalFile(path);
        std.log.info("Hot reloaded: {s}", .{path});

        // Notify script components to reinitialize
        // (preserve state where possible)
    }
};
```

## Example Scripts

### Player Controller (JavaScript)

```javascript
// scripts/components/player_controller.js

class PlayerController {
    constructor() {
        this.speed = 5.0;
        this.jumpForce = 8.0;
        this.isGrounded = false;
    }

    onStart(entity) {
        this.entity = entity;
        this.transform = entity.getComponent('Transform');
        this.rigidbody = entity.getComponent('Rigidbody');
        console.log('PlayerController started');
    }

    onUpdate(dt) {
        // Movement
        const moveX = Input.getActionValue('move_right') - Input.getActionValue('move_left');
        const moveZ = Input.getActionValue('move_forward') - Input.getActionValue('move_back');

        const movement = new Vec3(moveX, 0, moveZ).normalize().scale(this.speed);

        // Apply movement relative to camera
        const cameraForward = Camera.main.transform.forward;
        const cameraRight = Camera.main.transform.right;

        const worldMove = cameraRight.scale(movement.x)
            .add(cameraForward.scale(movement.z));

        this.rigidbody.velocity.x = worldMove.x;
        this.rigidbody.velocity.z = worldMove.z;

        // Jump
        if (Input.isActionPressed('jump') && this.isGrounded) {
            this.rigidbody.velocity.y = this.jumpForce;
            this.isGrounded = false;
            Audio.play('jump_sound');
        }
    }

    onCollision(other, contact) {
        if (contact.normal.y > 0.7) {
            this.isGrounded = true;
        }
    }
}

// Register the component type
Components.register('PlayerController', PlayerController);
```

### Enemy AI (JavaScript)

```javascript
// scripts/components/enemy_ai.js

class EnemyAI {
    constructor() {
        this.state = 'idle';
        this.detectionRange = 10.0;
        this.attackRange = 2.0;
        this.moveSpeed = 3.0;
        this.target = null;
    }

    onStart(entity) {
        this.entity = entity;
        this.transform = entity.getComponent('Transform');
    }

    onUpdate(dt) {
        // Find player
        if (!this.target) {
            this.target = Scene.findByTag('Player')[0];
        }

        if (!this.target) return;

        const targetPos = this.target.getComponent('Transform').position;
        const myPos = this.transform.position;
        const distance = targetPos.sub(myPos).length();

        switch (this.state) {
            case 'idle':
                if (distance < this.detectionRange) {
                    this.state = 'chase';
                    this.onDetectPlayer();
                }
                break;

            case 'chase':
                if (distance > this.detectionRange * 1.5) {
                    this.state = 'idle';
                } else if (distance < this.attackRange) {
                    this.state = 'attack';
                } else {
                    this.moveTowards(targetPos, dt);
                }
                break;

            case 'attack':
                if (distance > this.attackRange * 1.5) {
                    this.state = 'chase';
                } else {
                    this.performAttack();
                }
                break;
        }
    }

    moveTowards(target, dt) {
        const direction = target.sub(this.transform.position).normalize();
        const movement = direction.scale(this.moveSpeed * dt);
        this.transform.translate(movement);
        this.transform.lookAt(target);
    }

    onDetectPlayer() {
        Audio.play('enemy_alert');
    }

    performAttack() {
        // Attack logic
    }
}

Components.register('EnemyAI', EnemyAI);
```

### TypeScript Definitions

```typescript
// scripts/lib/zdl.d.ts

declare class Vec2 {
    x: number;
    y: number;
    constructor(x?: number, y?: number);
    add(other: Vec2): Vec2;
    sub(other: Vec2): Vec2;
    scale(s: number): Vec2;
    dot(other: Vec2): number;
    normalize(): Vec2;
    length(): number;
}

declare class Vec3 {
    x: number;
    y: number;
    z: number;
    constructor(x?: number, y?: number, z?: number);
    add(other: Vec3): Vec3;
    sub(other: Vec3): Vec3;
    scale(s: number): Vec3;
    dot(other: Vec3): number;
    cross(other: Vec3): Vec3;
    normalize(): Vec3;
    length(): number;
}

declare class Entity {
    getId(): number;
    isValid(): boolean;
    destroy(): void;
    getComponent<T>(type: string): T | null;
    addComponent<T>(type: string, props?: Partial<T>): T;
    removeComponent(type: string): void;
    getParent(): Entity | null;
    setParent(parent: Entity | null): void;
    getChildren(): Entity[];
}

declare namespace Scene {
    function createEntity(): Entity;
    function destroyEntity(entity: Entity): void;
    function findByName(name: string): Entity | null;
    function findByTag(tag: string): Entity[];
    function getAllEntities(): Entity[];
}

declare namespace Input {
    function isKeyDown(key: number): boolean;
    function isKeyPressed(key: number): boolean;
    function isKeyReleased(key: number): boolean;
    function getMousePosition(): Vec2;
    function getMouseDelta(): Vec2;
    function isActionActive(action: string): boolean;
    function getActionValue(action: string): number;
}

declare namespace Engine {
    const deltaTime: number;
    const fps: number;
    const time: number;
    function quit(): void;
}

declare namespace Audio {
    function play(name: string, volume?: number): void;
    function stop(name: string): void;
    function setVolume(name: string, volume: number): void;
}

declare const Key: {
    SPACE: number;
    ESCAPE: number;
    W: number;
    A: number;
    S: number;
    D: number;
    // ... etc
};

declare namespace Components {
    function register(name: string, componentClass: new () => any): void;
}
```

## Implementation Steps

### Phase 1: QuickJS Integration
1. Add QuickJS as dependency (or bundle source)
2. Create Zig bindings for QuickJS C API
3. Implement JSRuntime wrapper
4. Implement JSContext wrapper
5. Test basic script evaluation

### Phase 2: Core Bindings
1. Implement binding utilities (wrapFunction, createObject)
2. Create Math bindings (Vec2, Vec3, Quat)
3. Create Engine bindings (deltaTime, fps)
4. Create Input bindings

### Phase 3: ECS Bindings
1. Bind Entity type with methods
2. Bind Scene functions
3. Implement component access from JS
4. Support component creation from JS

### Phase 4: Script Components
1. Create ScriptComponent type
2. Implement lifecycle callbacks (start, update, destroy)
3. Create ScriptSystem for updating
4. Handle script errors gracefully

### Phase 5: Hot Reloading
1. Implement file watching
2. Create reload mechanism
3. Preserve script state during reload
4. Add development mode toggle

### Phase 6: Tooling
1. Generate TypeScript definitions
2. Create VS Code extension for debugging
3. Add script profiling
4. Implement console.log redirect

## Performance Considerations

- **Memory**: Set reasonable limits (~32MB for scripts)
- **GC**: Trigger collection during frame boundaries
- **Calls**: Cache frequently called methods
- **Batching**: Minimize Zig↔JS boundary crossings
- **Compilation**: Pre-compile scripts to bytecode

## Security Considerations

- **Sandboxing**: Disable file/network access by default
- **Memory limits**: Prevent runaway allocations
- **Execution limits**: Timeout long-running scripts
- **API exposure**: Carefully control what's accessible

## References

- [QuickJS](https://bellard.org/quickjs/)
- [QuickJS GitHub](https://github.com/nickolai-fedorov/nickolai-fedorov/nickolai-fedorov/nickolai-fedorov)
- [Embedding QuickJS](https://nickolai-fedorov.github.io/nickolai-fedorov/nickolai-fedorov)
- [Lua in Game Engines](https://www.lua.org/about.html) - Similar embedding patterns
