# ZDL JavaScript API Implementation Plan

This document describes the architecture, systems, and implementation steps required to realize the ideal game development experience shown in `ideal-game-dev-experience.js`.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Target API Design](#target-api-design)
4. [Architecture Overview](#architecture-overview)
5. [Implementation Phases](#implementation-phases)
6. [Detailed Component Specifications](#detailed-component-specifications)
7. [CLI Tool Design](#cli-tool-design)
8. [Migration Path](#migration-path)

---

## Executive Summary

The goal is to transform ZDL from a Zig-first engine with JavaScript scripting support into a **JavaScript-first game engine** where:

- Games are written entirely in JavaScript
- The ECS, rendering, and all engine systems are exposed through a clean JS API
- A CLI tool (`zdl`) handles project creation, running, and building
- Hot-reload enables rapid iteration during development

### Key Differences from Current Implementation

| Aspect                | Current                       | Target                                        |
| --------------------- | ----------------------------- | --------------------------------------------- |
| Entry point           | Zig `main.zig`                | JavaScript module                             |
| Component definition  | Zig structs                   | JavaScript factory functions                  |
| System registration   | Zig code                      | JavaScript `world.addSystem()`                |
| Entity creation       | `scene.createEntity()` in Zig | `world.addEntity()` in JS with fluent API     |
| Engine initialization | Zig `Engine.init()`           | JS `zdl.createWindow()` + `zdl.createWorld()` |
| Build process         | `zig build`                   | `zdl build`                                   |

---

## Current State Analysis

### What Exists

The engine already has substantial JavaScript scripting support:

**QuickJS Integration** ([src/scripting/](src/scripting/))

- JSRuntime and JSContext wrappers
- Script loading with hot-reload support
- Garbage collection management

**JavaScript Bindings** ([src/scripting/bindings/](src/scripting/bindings/))

- `Math`, `Vec2`, `Vec3`, `Quat` - Math utilities
- `console` - Logging
- `Engine` - Delta time, FPS, window size, quit, mouse capture
- `Input` - Keyboard, mouse, gamepad with unified API
- `Scene` - Entity creation/destruction, camera, find by name/tag
- `Transform` - Position, rotation, scale manipulation
- `Component` - JS component registry + CRUD, queued into native storage
- `World` - `createWorld`, `addEntity`, `addComponents`, `getComponent`, `hasComponent`, `updateComponent`
- `Query` - `world.query` with native cache refresh + JS fallback
- `System` - `world.addSystem` with init/update/destroy phase runners

**ScriptComponent System**

- Lifecycle hooks: `onStart()`, `onUpdate(dt)`, `onDestroy()`
- Transform synchronization between Zig and JS
- Hot-reload with file modification detection

### What's Missing

1. **Top-level JS entry point** - Games still require Zig `main.zig`
2. **Module system** - No `import zdl from "zdl"`
3. **Window creation** - `zdl.createWindow()` not implemented yet
4. **World/engine coupling** - `createWorld(window)` does not create a native world handle
5. **Native system registry** - `world.addSystem` is JS-managed; no Flecs scheduling yet
6. **CLI tool** - No `zdl create/run/build` commands
7. **Built-in component access** - Native component bindings beyond Transform are still missing

---

## Target API Design

Based on `ideal-game-dev-experience.js`, the target API consists of:

### 1. Module Import

```javascript
import zdl from "zdl";
```

The `zdl` module is a global object providing:

- `zdl.createWindow(config)` - Create game window
- `zdl.createWorld(window)` - Create ECS world

### 2. Component Factories

Components are factory functions returning plain objects:

```javascript
// Tag component (no data)
const Player = () => ({
  type: "Player",
  name: "Player",
});

// Data component
const Position = (x = 0, y = 0, z = 0) => ({
  type: "Position",
  position: { x, y, z },
});

const Camera = ({ fov = 60, near = 0.1, far = 1000, active = true } = {}) => ({
  type: "Camera",
  fov,
  near,
  far,
  active,
});

const Mesh = (path = "assets/cube.glb") => ({
  type: "Mesh",
  path,
});
```

### 3. World API

```javascript
const world = zdl.createWorld(window);

// Register component types
world.addComponents([Player, Position, Camera, Mesh]);

// Create entity with fluent API
const player = world.addEntity((ctx) => ({
  description: "Main player entity",
  name: "player",
}))(Player(), Position(0, 0, 0), Mesh("assets/player.glb"));

// Register systems with lifecycle phase
world.addSystem(moveSystem, "update"); // Called every frame
world.addSystem(initSystem, "init"); // Called once at start
world.addSystem(destroySystem, "destroy"); // Called on shutdown
```

### 4. System Functions

Systems receive the world and can query/modify entities:

```javascript
function moveSystem(world) {
  const results = world.query(Player, Position);

  for (const entity of results) {
    if (world.hasComponent(entity, Position)) {
      const pos = world.getComponent(entity, Position);
      world.updateComponent(
        entity,
        Position(pos.position.x + 1, pos.position.y, pos.position.z)
      );
    }
  }
}
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────-┐
│                         JavaScript Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   Game.js   │  │ Components  │  │   Systems   │  │   Scenes    │  │
│  │  (entry)    │  │ (factories) │  │ (functions) │  │  (setup)    │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │                │         │
│  ┌──────▼────────────────▼────────────────▼────────────────▼──────┐  │
│  │                     ZDL JavaScript API                         │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐    │  │
│  │  │   zdl   │  │  World  │  │  Query  │  │ComponentRegistry│    │  │
│  │  │ module  │  │   API   │  │   API   │  │                 │    │  │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────────┬────────┘    │  │
│  └───────┼────────────┼────────────┼────────────────┼─────────────┘  │
└──────────┼────────────┼────────────┼────────────────┼───────────────-┘
           │            │            │                │
┌──────────▼────────────▼────────────▼────────────────▼───────────────-┐
│                      Native Bindings Layer                           │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    QuickJS C API Bridge                         │ │
│  │  • Window creation → SDL3                                       │ │
│  │  • World/Entity ops → Flecs ECS                                 │ │
│  │  • Component storage → JS ↔ Zig serialization                   │ │
│  │  • Query execution → Flecs queries                              │ │
│  │  • System scheduling → Phase-based execution                    │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────-┘
           │            │            │                │
┌──────────▼────────────▼────────────▼────────────────▼───────────────┐
│                         Zig Engine Core
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌───────────┐  │
│  │  SDL3   │  │  Flecs  │  │  GPU    │  │  Audio  │  │  Assets   │  │
│  │ Window  │  │   ECS   │  │Pipeline │  │ System  │  │  Loader   │  │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └───────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Components stored as JSON in Zig** - JS component data serialized to JSON and stored alongside Zig-native components. This allows arbitrary component schemas defined in JS.

2. **Query executed in Zig** - The `world.query()` call translates to Flecs queries. Results are iterator objects that lazily fetch entity data.

3. **Systems are JS functions** - Registered JS functions called by the Zig game loop at appropriate phases.

4. **Single-threaded execution** - All JS runs on main thread, interleaved with Zig systems.

---

## Implementation Phases

### Phase 1: Enhanced Component System

**Goal:** Allow component definition and manipulation in JavaScript.

#### 1.1 Component Registry

Create a registry that maps component type names to their schemas:

```javascript
// Internal registry structure
const componentRegistry = {
  Player: { schema: {}, isTag: true },
  Position: { schema: { position: { x: "number", y: "number", z: "number" } } },
  Camera: {
    schema: { fov: "number", near: "number", far: "number", active: "boolean" },
  },
  Mesh: { schema: { path: "string" } },
};
```

**Files to create/modify:**

- `src/scripting/bindings/component_api.zig` - New binding for component operations
- `src/scripting/component_registry.zig` - Zig-side registry management

**Native functions to expose:**

```javascript
__native_registerComponent(typeName, schema, isTag);
__native_addComponent(entityId, typeName, dataJson);
__native_getComponent(entityId, typeName); // Returns JSON string
__native_hasComponent(entityId, typeName);
__native_removeComponent(entityId, typeName);
__native_updateComponent(entityId, typeName, dataJson);
```

#### 1.2 JSON Component Storage

Extend Zig's component storage to handle arbitrary JSON data:

```zig
// src/ecs/components/js_component.zig
pub const JsComponent = struct {
    type_name: []const u8,
    data_json: []const u8,  // Serialized component data

    pub fn init(type_name: []const u8, json: []const u8) JsComponent { ... }
    pub fn deinit(self: *JsComponent, allocator: Allocator) void { ... }
    pub fn getData(self: *const JsComponent) []const u8 { ... }
    pub fn setData(self: *JsComponent, json: []const u8) void { ... }
};
```

**Alternative: Per-type component storage**

For better performance, use a sparse-set per component type:

```zig
// src/ecs/js_component_storage.zig
pub const JsComponentStorage = struct {
    type_name: []const u8,
    entities: std.ArrayList(Entity),
    data: std.ArrayList([]const u8),  // JSON strings
    entity_to_index: std.AutoHashMap(u64, usize),

    pub fn add(self: *JsComponentStorage, entity: Entity, json: []const u8) void { ... }
    pub fn get(self: *JsComponentStorage, entity: Entity) ?[]const u8 { ... }
    pub fn remove(self: *JsComponentStorage, entity: Entity) void { ... }
};
```

#### 1.3 Component API Binding

```zig
// src/scripting/bindings/component_api.zig
pub fn register(ctx: *JSContext) void {
    // Create Component global object
    const component_obj = ctx.createObject();

    ctx.setProperty(component_obj, "register", ctx.createFunction(registerComponent));
    ctx.setProperty(component_obj, "add", ctx.createFunction(addComponent));
    ctx.setProperty(component_obj, "get", ctx.createFunction(getComponent));
    ctx.setProperty(component_obj, "has", ctx.createFunction(hasComponent));
    ctx.setProperty(component_obj, "remove", ctx.createFunction(removeComponent));
    ctx.setProperty(component_obj, "update", ctx.createFunction(updateComponent));

    ctx.setGlobal("Component", component_obj);
}

fn addComponent(ctx: *JSContext, this: Value, argc: c_int, argv: [*]Value) Value {
    // 1. Get entity ID from argv[0]
    // 2. Get component type name from argv[1]
    // 3. Get component data object from argv[2]
    // 4. Serialize to JSON
    // 5. Store in JsComponentStorage
    // 6. Return success/failure
}
```

**Status:** Implemented JS component registry + CRUD and native JSON storage with queued processing. See `src/scripting/bindings/component_api.zig`, `src/scripting/js_component_storage.zig`, `src/ecs/scene.zig`, and `src/scripting/script_system.zig`.

---

### Phase 2: Query System

**Goal:** Implement `world.query(ComponentA, ComponentB, ...)` that returns iterable results.

#### 2.1 Query Execution

Queries translate to Flecs queries or manual iteration over JS component storage:

```javascript
// User code
const results = world.query(Player, Position);
for (const entity of results) {
  const pos = world.getComponent(entity, Position);
  // ...
}
```

**Implementation approach:**

1. **Intersection query** - Find entities that have ALL specified components
2. **Lazy iteration** - Don't materialize full result set upfront
3. **Type checking** - Validate component types exist in registry

```zig
// src/scripting/bindings/query_api.zig
fn executeQuery(ctx: *JSContext, component_types: []const []const u8) QueryIterator {
    // For each component type, get the entity set from JsComponentStorage
    // Compute intersection of all entity sets
    // Return iterator over intersection
}

pub const QueryIterator = struct {
    entities: []const Entity,
    current_index: usize,

    pub fn next(self: *QueryIterator) ?Entity {
        if (self.current_index >= self.entities.len) return null;
        defer self.current_index += 1;
        return self.entities[self.current_index];
    }
};
```

#### 2.2 Query API Binding

Expose query as a method on World:

```javascript
// JavaScript wrapper (bundled with engine)
class World {
  query(...componentFactories) {
    const typeNames = componentFactories.map((f) => f().type);
    const entityIds = __native_query(this._worldId, typeNames);
    return new QueryResult(this, entityIds);
  }
}

class QueryResult {
  constructor(world, entityIds) {
    this._world = world;
    this._entityIds = entityIds;
  }

  *[Symbol.iterator]() {
    for (const id of this._entityIds) {
      yield new Entity(this._world, id);
    }
  }
}
```

**Status:** Implemented `world.query` with JS fallback and native cache refresh. Native intersection uses `JsComponentStorage.query()` (`src/scripting/bindings/query_api.zig`, `src/scripting/js_component_storage.zig`, `src/ecs/scene.zig`).

---

### Phase 3: World and Entity API

**Goal:** Implement `zdl.createWorld()` and fluent entity creation.

#### 3.1 World Creation

```javascript
const world = zdl.createWorld(window);
```

This creates:

- A Flecs world instance
- JS component registries
- System phase lists

```zig
// src/scripting/bindings/world_api.zig
fn createWorld(ctx: *JSContext, argc: c_int, argv: [*]Value) Value {
    // 1. Get window handle from argv[0]
    // 2. Create Flecs world
    // 3. Create JsComponentStorage manager
    // 4. Create system registries for each phase
    // 5. Store in global world registry
    // 6. Return world handle (integer ID)
}
```

#### 3.2 Fluent Entity Builder

The target API uses a curried function pattern:

```javascript
const player = world.addEntity((ctx) => ({
  description: "Main player entity",
  name: "player",
}))(Player(), Position(0, 0, 0), Mesh("assets/player.glb"));
```

**JavaScript implementation:**

```javascript
// In world.js (bundled with engine)
class World {
  addEntity(metadataFn) {
    return (...components) => {
      const metadata = metadataFn({});
      const entityId = __native_createEntity(this._worldId, metadata.name);

      for (const component of components) {
        __native_addComponent(
          entityId,
          component.type,
          JSON.stringify(component)
        );
      }

      return new Entity(this, entityId);
    };
  }
}
```

#### 3.3 Component Registration

```javascript
world.addComponents([Player, Position, Camera, Mesh]);
```

**Implementation:**

```javascript
class World {
  addComponents(factories) {
    for (const factory of factories) {
      const sample = factory(); // Call with defaults to get schema
      const schema = this._inferSchema(sample);
      __native_registerComponent(
        sample.type,
        JSON.stringify(schema),
        this._isTag(sample)
      );
    }
  }

  _inferSchema(sample) {
    const schema = {};
    for (const [key, value] of Object.entries(sample)) {
      if (key === "type" || key === "name") continue;
      schema[key] =
        typeof value === "object" ? this._inferSchema(value) : typeof value;
    }
    return schema;
  }

  _isTag(sample) {
    return Object.keys(sample).every((k) => k === "type" || k === "name");
  }
}
```

**Status:** Implemented `zdl.createWorld` (JS stub), `World.addComponents`, `World.addEntity` (factory support + metadata validation), and `World.getComponent/hasComponent/updateComponent` backed by native caches. Entity creation is queued and processed in the script system (`src/scripting/bindings/world_api.zig`, `src/scripting/script_system.zig`).

---

### Phase 4: System Registration and Execution

**Goal:** Implement `world.addSystem(fn, phase)` with init/update/destroy phases.

#### 4.1 System Registry

```zig
// src/scripting/system_registry.zig
pub const SystemPhase = enum {
    init,
    update,
    destroy,
};

pub const JsSystem = struct {
    name: []const u8,
    function: quickjs.Value,  // Reference to JS function
    phase: SystemPhase,
};

pub const SystemRegistry = struct {
    init_systems: std.ArrayList(JsSystem),
    update_systems: std.ArrayList(JsSystem),
    destroy_systems: std.ArrayList(JsSystem),

    pub fn add(self: *SystemRegistry, system: JsSystem) void { ... }
    pub fn runPhase(self: *SystemRegistry, phase: SystemPhase, world: *World) void { ... }
};
```

#### 4.2 System Binding

```zig
// src/scripting/bindings/system_api.zig
fn addSystem(ctx: *JSContext, this: Value, argc: c_int, argv: [*]Value) Value {
    // argv[0] = system function
    // argv[1] = phase string ("init", "update", "destroy")

    const func = argv[0];
    const phase_str = ctx.getString(argv[1]);

    const phase = if (std.mem.eql(u8, phase_str, "init")) .init
                  else if (std.mem.eql(u8, phase_str, "update")) .update
                  else if (std.mem.eql(u8, phase_str, "destroy")) .destroy
                  else return ctx.throwError("Invalid phase");

    // Duplicate function reference to prevent GC
    const func_ref = ctx.dupValue(func);

    system_registry.add(.{
        .name = "user_system",
        .function = func_ref,
        .phase = phase,
    });

    return ctx.undefined();
}
```

#### 4.3 Game Loop Integration

Modify the engine's game loop to call JS systems:

```zig
// In engine.zig runScene()
pub fn runScene(self: *Engine, scene: *Scene, user_update: ?UpdateFn) !void {
    // Run init systems once
    if (self.script_system) |ss| {
        ss.runSystems(.init);
    }

    while (self.running) {
        // ... event handling ...

        // Run update systems
        if (self.script_system) |ss| {
            ss.runSystems(.update);
        }

        // ... rendering ...
    }

    // Run destroy systems
    if (self.script_system) |ss| {
        ss.runSystems(.destroy);
    }
}
```

**Status:** Implemented `world.addSystem` and JS-side phase runners; script system calls init/update/destroy phases each frame and on shutdown (`src/scripting/bindings/world_api.zig`, `src/scripting/script_system.zig`). Native system registry and Flecs integration remain pending.

---

### Phase 5: ZDL Module and Entry Point

**Goal:** Make JavaScript the entry point with `import zdl from "zdl"`.

#### 5.1 ZDL Global Module

Create the `zdl` global object:

```zig
// src/scripting/bindings/zdl_api.zig
pub fn register(ctx: *JSContext) void {
    const zdl = ctx.createObject();

    ctx.setProperty(zdl, "createWindow", ctx.createFunction(createWindow));
    ctx.setProperty(zdl, "createWorld", ctx.createFunction(createWorld));
    ctx.setProperty(zdl, "version", ctx.createString("0.1.0"));

    ctx.setGlobal("zdl", zdl);
}

fn createWindow(ctx: *JSContext, argc: c_int, argv: [*]Value) Value {
    // Get config from argv[0]
    const config = ctx.getObject(argv[0]);
    const size_str = ctx.getStringProperty(config, "size");
    const title = ctx.getStringProperty(config, "title");

    // Parse size "1920x1080"
    const width, const height = parseSize(size_str);

    // Create SDL window
    const window = sdl.createWindow(title, width, height);

    // Return window handle
    return ctx.createNumber(@intFromPtr(window));
}
```

#### 5.2 ES Module Support

QuickJS supports ES modules. Configure the module loader:

```zig
// src/scripting/js_runtime.zig
pub fn initModuleLoader(self: *JSRuntime) void {
    // Set module normalize function
    c.JS_SetModuleLoaderFunc(self.rt, normalizeModule, loadModule, null);
}

fn loadModule(ctx: *c.JSContext, module_name: [*:0]const u8, opaque: ?*anyopaque) c.JSModuleDef {
    const name = std.mem.span(module_name);

    if (std.mem.eql(u8, name, "zdl")) {
        // Return built-in zdl module
        return createZdlModule(ctx);
    }

    // Load from file
    const source = std.fs.cwd().readFileAlloc(allocator, name);
    defer allocator.free(source);

    return c.JS_Eval(ctx, source.ptr, source.len, module_name, c.JS_EVAL_TYPE_MODULE);
}
```

#### 5.3 JavaScript Entry Point

The CLI runs a JavaScript file as the entry point:

```javascript
// game.js - User's game file
import zdl from "zdl";

// Component definitions...
// Scene setup...
// System definitions...

export function main() {
  initialSceneMain();
}
```

The engine calls `main()` after loading:

```zig
// In CLI runner
fn runGame(game_path: []const u8) !void {
    var engine = try Engine.init(allocator, .{});
    defer engine.deinit();

    try engine.initScripting();

    // Load and evaluate game.js as module
    try engine.script_system.?.loadModule(game_path);

    // Call main()
    try engine.script_system.?.callGlobal("main", &.{});

    // Run game loop (systems handle everything)
    try engine.runJsGameLoop();
}
```

---

### Phase 6: CLI Tool

**Goal:** Create `zdl` CLI for project management.

#### 6.1 CLI Structure

```
tools/zdl-cli/
├── main.zig          # Entry point, argument parsing
├── commands/
│   ├── create.zig    # zdl create <path>
│   ├── run.zig       # zdl run [path]
│   └── build.zig     # zdl build [path]
├── templates/
│   ├── game.js       # Template game file
│   ├── project.json  # Project manifest
│   └── assets/       # Default assets
└── build.zig
```

#### 6.2 Commands

**`zdl create <path>`**

```zig
pub fn create(path: []const u8) !void {
    // 1. Create directory structure
    try std.fs.cwd().makePath(path);
    try std.fs.cwd().makePath(path ++ "/assets");
    try std.fs.cwd().makePath(path ++ "/scripts");

    // 2. Copy template files
    try copyTemplate("game.js", path ++ "/game.js");
    try copyTemplate("project.json", path ++ "/project.json");

    // 3. Print success message
    std.debug.print("Created new ZDL project at {s}\n", .{path});
}
```

**`zdl run [path]`**

```zig
pub fn run(path: ?[]const u8) !void {
    const game_path = path orelse "game.js";

    // 1. Find project root (look for project.json)
    const project_root = try findProjectRoot();

    // 2. Initialize engine
    var engine = try Engine.init(allocator, .{});
    defer engine.deinit();

    // 3. Load and run game
    try engine.initScripting();
    try engine.runGameScript(project_root ++ "/" ++ game_path);
}
```

**`zdl build [path]`**

```zig
pub fn build(path: ?[]const u8) !void {
    const project_root = path orelse ".";

    // 1. Read project.json for build config
    const config = try readProjectConfig(project_root);

    // 2. Bundle JavaScript files
    try bundleJs(project_root, config.entry);

    // 3. Process assets (textures, meshes, etc.)
    try processAssets(project_root ++ "/assets");

    // 4. Create distributable package
    try createPackage(project_root, config.output);
}
```

#### 6.3 Project Manifest

```json
{
  "name": "my-game",
  "version": "1.0.0",
  "entry": "game.js",
  "output": "dist/",
  "window": {
    "width": 1920,
    "height": 1080,
    "title": "My Game"
  },
  "assets": {
    "include": ["assets/**/*"]
  }
}
```

---

## Detailed Component Specifications

### Built-in Components

The engine should provide these built-in component types accessible from JS:

| Component    | Zig Type                | JS Factory                                         |
| ------------ | ----------------------- | -------------------------------------------------- |
| Transform    | `TransformComponent`    | `Transform({ position, rotation, scale })`         |
| Camera       | `CameraComponent`       | `Camera({ fov, near, far, active })`               |
| MeshRenderer | `MeshRendererComponent` | `Mesh(path)` or `MeshRenderer({ mesh, material })` |
| Light        | `LightComponent`        | `Light({ type, color, intensity, range })`         |
| RigidBody    | Future                  | `RigidBody({ mass, velocity, ... })`               |
| Collider     | Future                  | `Collider({ type, size, ... })`                    |

### Component Type Mapping

For built-in components, bypass JSON serialization:

```zig
fn addComponent(entity: Entity, type_name: []const u8, data: Value) !void {
    if (std.mem.eql(u8, type_name, "Transform")) {
        // Parse directly to TransformComponent
        const pos = getVec3Property(data, "position");
        const rot = getQuatProperty(data, "rotation");
        const scale = getVec3Property(data, "scale");
        try scene.addComponent(entity, TransformComponent.init(pos, rot, scale));
    } else if (std.mem.eql(u8, type_name, "Camera")) {
        // ... similar
    } else {
        // Custom component - store as JSON
        const json = serializeToJson(data);
        try js_storage.add(entity, type_name, json);
    }
}
```

---

## CLI Tool Design

### Build Integration

Add CLI to `build.zig`:

```zig
// build.zig
const zdl_cli = b.addExecutable(.{
    .name = "zdl",
    .root_source_file = b.path("tools/zdl-cli/main.zig"),
    .target = target,
    .optimize = optimize,
});

// Link with engine library
zdl_cli.linkLibrary(engine_lib);

b.installArtifact(zdl_cli);
```

### Installation

```bash
# Build CLI
zig build

# Install to path (or add zig-out/bin to PATH)
sudo cp zig-out/bin/zdl /usr/local/bin/
```

### Usage Examples

```bash
# Create new project
zdl create my-game
cd my-game

# Run in development mode (hot reload enabled)
zdl run

# Build for distribution
zdl build

# Run specific file
zdl run scenes/level1.js
```

---

## Migration Path

### For Existing Zig Games

Existing games using the Zig API continue to work. The JS API is an additional layer.

### Gradual Adoption

1. **Phase 1**: Use JS for game logic via ScriptComponent (current)
2. **Phase 2**: Define custom components in JS, mix with Zig components
3. **Phase 3**: Full JS game with CLI tooling

### Interoperability

Zig systems can query JS-defined components:

```zig
// Zig code
fn customRenderSystem(scene: *Scene) void {
    // Get JS component data
    if (js_storage.get(entity, "CustomShader")) |json| {
        const data = std.json.parse(CustomShaderData, json);
        // Use data...
    }
}
```

JS systems can access Zig components through bindings:

```javascript
// JS code
function mySystem(world) {
  const entities = world.query(Transform); // Built-in component
  for (const entity of entities) {
    const transform = world.getComponent(entity, Transform);
    // transform is already a rich object with methods
  }
}
```

---

## File Summary

### New Files to Create

| Path                                       | Purpose                                 | Status  |
| ------------------------------------------ | --------------------------------------- | ------- |
| `src/scripting/bindings/zdl_api.zig`       | ZDL module binding                      | Done    |
| `src/scripting/bindings/world_api.zig`     | World creation and methods              | Done    |
| `src/scripting/bindings/component_api.zig` | Component CRUD operations               | Done    |
| `src/scripting/bindings/query_api.zig`     | Query execution                         | Done    |
| `src/scripting/bindings/system_api.zig`    | System registration                     | Pending |
| `src/scripting/js_component_storage.zig`   | JSON component storage                  | Done    |
| `src/scripting/system_registry.zig`        | JS system management                    | Pending |
| `src/scripting/module_loader.zig`          | ES module loading                       | Done    |
| `src/tests.zig`                            | Test entry point for scripting bindings | Done    |
| `tools/zdl-cli/main.zig`                   | CLI entry point                         | Done    |
| `tools/zdl-cli/commands/create.zig`        | Create command                          | Done    |
| `tools/zdl-cli/commands/run.zig`           | Run command                             | Done    |
| `tools/zdl-cli/commands/build.zig`         | Build command                           | Pending |

### Files to Modify

| Path                                  | Changes                                   | Status                               |
| ------------------------------------- | ----------------------------------------- | ------------------------------------ |
| `src/scripting/bindings/bindings.zig` | Register new APIs                         | Done (zdl_api registered)            |
| `src/scripting/script_system.zig`     | Integrate system registry, module loader  | In progress (world systems + queues) |
| `src/engine/engine.zig`               | Add `runJsGameLoop()`, system phase calls | Pending                              |
| `src/ecs/scene.zig`                   | Add JS component storage integration      | Done                                 |
| `build.zig`                           | Add CLI executable                        | Done (zdl CLI tool added)            |

---

## Known Limitations & Future Work

### Window Creation

**Current Status**: The `zdl.createWindow()` function currently returns a configuration object but does not actually create a window. The engine window is created at initialization time via `Engine.init(config)`.

**Why**: The current engine architecture assumes a single window created at startup. Implementing dynamic window creation from JavaScript requires architectural changes.

**Future Implementation**:
1. Refactor `Engine` to support lazy window initialization
2. Pass engine context to JavaScript bindings (via opaque pointers or global registry)
3. Implement actual window creation/reconfiguration in `zdl_api.zig`:
   ```zig
   pub fn registerWithEngine(ctx: *JSContext, engine: *Engine) !void {
       // Store engine reference in JS context
       // Implement actual window manipulation
   }
   ```
4. Update `zdl.createWindow()` to call native window creation via QuickJS C function

**Workaround**: For now, configure the window via `EngineConfig` when initializing the engine in Zig, before running JavaScript code.

---

## Success Criteria

The implementation is complete when:

1. A game can be written entirely in JavaScript matching the `ideal-game-dev-experience.js` API
2. `zdl create`, `zdl run`, and `zdl build` work correctly
3. Hot-reload works for component definitions and systems
4. Performance is acceptable (< 1ms overhead per frame for JS execution)
5. Existing Zig-based games continue to work unchanged
6. Documentation and examples are updated
