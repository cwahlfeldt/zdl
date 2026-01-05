# Flecs ECS Migration Plan

This document outlines the plan to migrate ZDL's custom ECS implementation to [Flecs](https://github.com/SanderMertens/flecs) using the [zflecs](https://github.com/zig-gamedev/zflecs) Zig bindings.

## Table of Contents

1. [Motivation](#motivation)
2. [Current Architecture Overview](#current-architecture-overview)
3. [Flecs Architecture Overview](#flecs-architecture-overview)
4. [Migration Strategy](#migration-strategy)
5. [Phase 1: Add zflecs Dependency](#phase-1-add-zflecs-dependency)
6. [Phase 2: Create Flecs World Wrapper](#phase-2-create-flecs-world-wrapper)
7. [Phase 3: Migrate Components](#phase-3-migrate-components)
8. [Phase 4: Migrate Entity Management](#phase-4-migrate-entity-management)
9. [Phase 5: Implement Hierarchy System](#phase-5-implement-hierarchy-system)
10. [Phase 6: Migrate Systems](#phase-6-migrate-systems)
11. [Phase 7: Update Engine Integration](#phase-7-update-engine-integration)
12. [Phase 8: Migrate Serialization](#phase-8-migrate-serialization)
13. [Phase 9: Update JavaScript Bindings](#phase-9-update-javascript-bindings)
14. [Phase 10: Update Examples](#phase-10-update-examples)
15. [Phase 11: Cleanup and Optimization](#phase-11-cleanup-and-optimization)
16. [Risk Assessment](#risk-assessment)
17. [Rollback Strategy](#rollback-strategy)

---

## Motivation

### Current Limitations

The existing ECS implementation has several constraints:

1. **Static Component Registration**: Components are hardcoded in the Scene struct, requiring modifications to 6+ dispatch methods when adding new component types
2. **No Query System**: Manual iteration patterns; no ability to query "all entities with Transform AND MeshRenderer"
3. **Rigid Hierarchy**: Parent-child relationships embedded in TransformComponent rather than being a first-class ECS concept
4. **Limited Scalability**: Adding new components requires touching core Scene code
5. **No System Scheduling**: Systems called explicitly with no dependency resolution

### Flecs Benefits

1. **Dynamic Component Registration**: Register any component type at runtime
2. **Powerful Query System**: Filter entities by component combinations, relationships, and more
3. **Built-in Hierarchy**: Native `ChildOf` relationship with cascade queries for transform propagation
4. **Archetype-based Storage**: Cache-friendly iteration over matching entity sets
5. **System Pipelines**: Automatic system ordering with phases (OnUpdate, PostUpdate, etc.)
6. **Relationships**: First-class support for entity relationships beyond just hierarchy
7. **Battle-tested**: Used in production games and simulations

---

## Current Architecture Overview

### Files to Migrate

```
src/ecs/
├── entity.zig              # Entity handle (32-bit index + generation)
├── component_storage.zig   # Sparse-set storage per component type
├── scene.zig               # Scene container with hardcoded component storages
└── components/
    ├── transform_component.zig   # Transform + hierarchy links
    ├── camera_component.zig      # Camera projection settings
    ├── mesh_renderer.zig         # Mesh + material references
    ├── light_component.zig       # Light properties
    └── fpv_camera_controller.zig # FPS camera controller
```

### Files That Depend on ECS

- `src/engine/engine.zig` - Game loop integration
- `src/ecs/systems/render_system.zig` - Rendering
- `src/scripting/script_component.zig` - Script component
- `src/scripting/script_system.zig` - Script system
- `src/scripting/bindings/scene_api.zig` - JS scene bindings
- `src/scripting/bindings/transform_api.zig` - JS transform bindings
- `src/animation/animator_component.zig` - Animation component
- `src/animation/animation_system.zig` - Animation system
- `src/serialization/scene_serializer.zig` - Scene save/load
- `src/assets/gltf/scene_import.zig` - glTF to scene import
- All example files in `examples/`

### Current Entity Handle

```zig
pub const Entity = struct {
    index: u32,
    generation: u32,

    pub const invalid = Entity{ .index = std.math.maxInt(u32), .generation = 0 };
};
```

### Current Component Dispatch Pattern

```zig
pub fn addComponent(self: *Scene, entity: Entity, component: anytype) !void {
    const T = @TypeOf(component);
    if (T == TransformComponent) {
        try self.transforms.add(entity, component);
    } else if (T == CameraComponent) {
        try self.cameras.add(entity, component);
    } // ... 6 more branches
}
```

---

## Flecs Architecture Overview

### Core Concepts

- **World**: Container for all ECS data
- **Entity**: 64-bit identifier (includes generation)
- **Component**: Data attached to entities (registered at runtime)
- **Tag**: Zero-size component for marking entities
- **System**: Function that processes entities matching a query
- **Query**: Filter for finding entities with specific components
- **Relationship**: Link between two entities (e.g., ChildOf, DependsOn)

### zflecs API Patterns

```zig
const ecs = @import("zflecs");

// World lifecycle
const world = ecs.init();
defer _ = ecs.fini(world);

// Component registration
ecs.COMPONENT(world, Position);
ecs.COMPONENT(world, Velocity);

// Entity creation
const entity = ecs.new_entity(world, "Player");

// Component operations
_ = ecs.set(world, entity, Position, .{ .x = 0, .y = 0 });
const pos = ecs.get(world, entity, Position);

// System registration
_ = ecs.ADD_SYSTEM(world, "move", ecs.OnUpdate, move_system);

// Run all systems
_ = ecs.progress(world, delta_time);

// Hierarchy
const child = ecs.new_w_pair(world, ecs.ChildOf, parent);
```

---

## Migration Strategy

The migration will follow an **incremental approach**:

1. Add Flecs alongside existing ECS (no breaking changes initially)
2. Create wrapper types that match current API signatures
3. Migrate components one at a time
4. Migrate systems to use Flecs queries
5. Update dependent code (serialization, scripting, examples)
6. Remove old ECS code

This allows testing at each phase and easy rollback if issues arise.

---

## Phase 1: Add zflecs Dependency

### Step 1.1: Update build.zig.zon

Add zflecs to dependencies:

```zig
.dependencies = .{
    .sdl3 = .{ ... },
    .quickjs = .{ ... },
    .zflecs = .{
        .url = "git+https://github.com/zig-gamedev/zflecs#main",
        .hash = "...",  // Run zig build to get hash
    },
},
```

### Step 1.2: Update build.zig

```zig
const zflecs = b.dependency("zflecs", .{});
exe.root_module.addImport("zflecs", zflecs.module("root"));
exe.linkLibrary(zflecs.artifact("flecs"));
```

### Step 1.3: Verify Integration

Create a minimal test to verify Flecs compiles and runs:

```zig
const ecs = @import("zflecs");

test "flecs basic" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    const entity = ecs.new_entity(world, "test");
    try std.testing.expect(ecs.is_alive(world, entity));
}
```

---

## Phase 2: Create Flecs World Wrapper

### Step 2.1: Create New World Module

Create `src/ecs/world.zig`:

```zig
const ecs = @import("zflecs");

pub const World = struct {
    handle: *ecs.world_t,

    pub fn init() World {
        return .{ .handle = ecs.init() };
    }

    pub fn deinit(self: *World) void {
        _ = ecs.fini(self.handle);
    }

    pub fn progress(self: *World, delta_time: f32) void {
        _ = ecs.progress(self.handle, delta_time);
    }
};
```

### Step 2.2: Create Entity Wrapper

Create compatibility layer for Entity handle:

```zig
pub const Entity = struct {
    id: ecs.entity_t,

    pub const invalid = Entity{ .id = 0 };

    pub fn isValid(self: Entity) bool {
        return self.id != 0;
    }

    pub fn eql(self: Entity, other: Entity) bool {
        return self.id == other.id;
    }
};
```

---

## Phase 3: Migrate Components

### Step 3.1: Create Component Registration System

Create `src/ecs/components.zig`:

```zig
const ecs = @import("zflecs");

pub fn registerComponents(world: *ecs.world_t) void {
    // Core components
    ecs.COMPONENT(world, Transform);
    ecs.COMPONENT(world, Camera);
    ecs.COMPONENT(world, MeshRenderer);
    ecs.COMPONENT(world, Light);
    ecs.COMPONENT(world, FpvCameraController);
    ecs.COMPONENT(world, Script);
    ecs.COMPONENT(world, Animator);

    // Tags
    ecs.TAG(world, ActiveCamera);
    ecs.TAG(world, Enabled);
    ecs.TAG(world, Dirty);
}
```

### Step 3.2: Refactor TransformComponent

Split hierarchy from transform data. The new Transform component stores only local transform:

```zig
pub const Transform = struct {
    position: Vec3 = Vec3.zero(),
    rotation: Quat = Quat.identity(),
    scale: Vec3 = Vec3.one(),

    // Cached world matrix (computed by transform system)
    world_matrix: Mat4 = Mat4.identity(),

    // Helper methods
    pub fn toMatrix(self: Transform) Mat4 { ... }
    pub fn forward(self: Transform) Vec3 { ... }
    pub fn right(self: Transform) Vec3 { ... }
    pub fn up(self: Transform) Vec3 { ... }
};
```

Hierarchy is now handled by Flecs' built-in `ChildOf` relationship:

```zig
// Set parent (replaces scene.setParent)
ecs.add_pair(world, child, ecs.ChildOf, parent);

// Get parent
const parent = ecs.get_target(world, child, ecs.ChildOf, 0);

// Remove parent (move to root)
ecs.remove_pair(world, child, ecs.ChildOf, ecs.Wildcard);
```

### Step 3.3: Migrate Other Components

Update remaining components to be pure data structs without hierarchy:

**Camera:**
```zig
pub const Camera = struct {
    fov: f32 = std.math.degreesToRadians(60.0),
    near: f32 = 0.1,
    far: f32 = 1000.0,
};
```

**MeshRenderer:**
```zig
pub const MeshRenderer = struct {
    mesh: *Mesh,
    texture: ?*const Texture = null,
    material: ?Material = null,
    enabled: bool = true,
};
```

**Light:**
```zig
pub const Light = struct {
    light_type: LightType,
    color: Vec3,
    intensity: f32,
    range: f32 = 10.0,
    inner_angle: f32 = 0.0,
    outer_angle: f32 = 0.0,
};
```

---

## Phase 4: Migrate Entity Management

### Step 4.1: Update Scene to Use Flecs World

Refactor Scene to wrap Flecs world:

```zig
pub const Scene = struct {
    allocator: std.mem.Allocator,
    world: *ecs.world_t,
    active_camera: Entity,

    pub fn init(allocator: std.mem.Allocator) Scene {
        const world = ecs.init();
        registerComponents(world);
        registerSystems(world);

        return .{
            .allocator = allocator,
            .world = world,
            .active_camera = Entity.invalid,
        };
    }

    pub fn deinit(self: *Scene) void {
        _ = ecs.fini(self.world);
    }
};
```

### Step 4.2: Implement Entity Operations

```zig
pub fn createEntity(self: *Scene) Entity {
    return .{ .id = ecs.new(self.world) };
}

pub fn createEntityNamed(self: *Scene, name: [:0]const u8) Entity {
    return .{ .id = ecs.new_entity(self.world, name) };
}

pub fn destroyEntity(self: *Scene, entity: Entity) void {
    ecs.delete(self.world, entity.id);
}

pub fn entityExists(self: *Scene, entity: Entity) bool {
    return ecs.is_alive(self.world, entity.id);
}
```

### Step 4.3: Implement Component Operations

Replace type-dispatch with generic Flecs operations:

```zig
pub fn addComponent(self: *Scene, entity: Entity, comptime T: type, component: T) void {
    _ = ecs.set(self.world, entity.id, T, component);
}

pub fn getComponent(self: *Scene, entity: Entity, comptime T: type) ?*T {
    return ecs.get_mut(self.world, entity.id, T);
}

pub fn getComponentConst(self: *Scene, entity: Entity, comptime T: type) ?*const T {
    return ecs.get(self.world, entity.id, T);
}

pub fn removeComponent(self: *Scene, entity: Entity, comptime T: type) void {
    ecs.remove(self.world, entity.id, T);
}

pub fn hasComponent(self: *Scene, entity: Entity, comptime T: type) bool {
    return ecs.has(self.world, entity.id, ecs.id(T));
}
```

---

## Phase 5: Implement Hierarchy System

### Step 5.1: Parent-Child Operations

```zig
pub fn setParent(self: *Scene, child: Entity, parent: Entity) void {
    if (parent.isValid()) {
        ecs.add_pair(self.world, child.id, ecs.ChildOf, parent.id);
    } else {
        // Unparent - move to root
        ecs.remove_pair(self.world, child.id, ecs.ChildOf, ecs.Wildcard);
    }
}

pub fn getParent(self: *Scene, entity: Entity) Entity {
    const parent_id = ecs.get_target(self.world, entity.id, ecs.ChildOf, 0);
    return .{ .id = parent_id };
}
```

### Step 5.2: Transform Propagation System

Create a system that computes world matrices using Flecs' cascade query:

```zig
fn transformSystem(it: *ecs.iter_t) void {
    const transforms = ecs.field(it, Transform, 0);
    const parent_transforms = ecs.field(it, Transform, 1); // From parent via cascade

    for (0..it.count()) |i| {
        const local_matrix = transforms[i].toMatrix();

        if (parent_transforms) |pt| {
            transforms[i].world_matrix = pt[i].world_matrix.mul(local_matrix);
        } else {
            transforms[i].world_matrix = local_matrix;
        }
    }
}

pub fn registerTransformSystem(world: *ecs.world_t) void {
    var desc = ecs.system_desc_t{};
    desc.callback = transformSystem;
    desc.query.terms[0] = .{ .id = ecs.id(world, Transform) };
    desc.query.terms[1] = .{
        .id = ecs.id(world, Transform),
        .src = .{ .id = ecs.Cascade },  // Traverse ChildOf in breadth-first order
        .trav = ecs.ChildOf,
    };
    _ = ecs.system_init(world, &desc);
}
```

---

## Phase 6: Migrate Systems

### Step 6.1: Render System

Convert to Flecs query-based iteration:

```zig
pub const RenderSystem = struct {
    query: ecs.query_t,

    pub fn init(world: *ecs.world_t) RenderSystem {
        var desc = ecs.query_desc_t{};
        desc.terms[0] = .{ .id = ecs.id(world, Transform) };
        desc.terms[1] = .{ .id = ecs.id(world, MeshRenderer) };

        return .{ .query = ecs.query_init(world, &desc) };
    }

    pub fn render(self: *RenderSystem, world: *ecs.world_t, frame: *Frame) void {
        var it = ecs.query_iter(world, self.query);
        while (ecs.query_next(&it)) {
            const transforms = ecs.field(&it, Transform, 0);
            const renderers = ecs.field(&it, MeshRenderer, 1);

            for (0..it.count) |i| {
                if (!renderers[i].enabled) continue;
                // Render mesh with world transform...
            }
        }
    }
};
```

### Step 6.2: Script System

```zig
pub const ScriptSystem = struct {
    query: ecs.query_t,

    pub fn init(world: *ecs.world_t) ScriptSystem {
        var desc = ecs.query_desc_t{};
        desc.terms[0] = .{ .id = ecs.id(world, Script) };
        desc.terms[1] = .{ .id = ecs.id(world, Transform), .oper = .Optional };

        return .{ .query = ecs.query_init(world, &desc) };
    }

    pub fn update(self: *ScriptSystem, world: *ecs.world_t, delta_time: f32) void {
        var it = ecs.query_iter(world, self.query);
        while (ecs.query_next(&it)) {
            const scripts = ecs.field(&it, Script, 0);
            const transforms = ecs.field(&it, Transform, 1);

            for (0..it.count) |i| {
                if (!scripts[i].started) {
                    scripts[i].callStart();
                    scripts[i].started = true;
                }
                scripts[i].callUpdate(delta_time, transforms);
            }
        }
    }
};
```

### Step 6.3: Animation System

```zig
pub fn animationSystem(it: *ecs.iter_t) void {
    const animators = ecs.field(it, Animator, 0);
    const delta_time = it.delta_time;

    for (0..it.count) |i| {
        animators[i].update(delta_time);
    }
}
```

---

## Phase 7: Update Engine Integration

### Step 7.1: Modify Engine.runScene

Update the game loop to use Flecs' progress:

```zig
pub fn runScene(
    self: *Engine,
    scene: *Scene,
    update_fn: ?UpdateFn,
) !void {
    while (self.running) {
        // Input processing
        self.input.update();
        self.processEvents();

        // User update callback (before ECS systems)
        if (update_fn) |callback| {
            try callback(self, scene, &self.input, self.delta_time);
        }

        // Run all Flecs systems (transform propagation, scripts, etc.)
        _ = ecs.progress(scene.world, self.delta_time);

        // Render (can be a Flecs system or called separately)
        self.render_system.render(scene.world, &frame);

        // Present frame
        self.present();
    }
}
```

### Step 7.2: Register System Pipeline

```zig
pub fn registerSystems(world: *ecs.world_t) void {
    // Transform propagation (must run before rendering)
    _ = ecs.ADD_SYSTEM(world, "TransformSystem", ecs.PreUpdate, transformSystem);

    // Script updates
    _ = ecs.ADD_SYSTEM(world, "ScriptSystem", ecs.OnUpdate, scriptSystem);

    // Animation updates
    _ = ecs.ADD_SYSTEM(world, "AnimationSystem", ecs.OnUpdate, animationSystem);

    // FPV camera controller
    _ = ecs.ADD_SYSTEM(world, "FpvCameraSystem", ecs.OnUpdate, fpvCameraSystem);
}
```

---

## Phase 8: Migrate Serialization

### Step 8.1: Update Scene Serializer

Refactor to iterate entities dynamically:

```zig
pub fn serializeScene(self: *SceneSerializer, scene: *Scene) !SerializedScene {
    var entities = std.ArrayList(SerializedEntity).init(self.allocator);

    // Query all entities with any of our components
    var it = ecs.each(scene.world);
    while (ecs.each_next(&it)) {
        const entity_id = ecs.each_entity(&it);

        var serialized = SerializedEntity{
            .id = entity_id,
            .name = ecs.get_name(scene.world, entity_id),
            .parent_id = ecs.get_target(scene.world, entity_id, ecs.ChildOf, 0),
        };

        // Serialize each component if present
        if (ecs.get(scene.world, entity_id, Transform)) |t| {
            serialized.transform = serializeTransform(t);
        }
        if (ecs.get(scene.world, entity_id, Camera)) |c| {
            serialized.camera = serializeCamera(c);
        }
        // ... etc

        try entities.append(serialized);
    }

    return .{ .entities = entities.toOwnedSlice() };
}
```

### Step 8.2: Update Deserialization

```zig
pub fn deserializeScene(self: *SceneSerializer, data: SerializedScene) !*Scene {
    var scene = try self.allocator.create(Scene);
    scene.* = Scene.init(self.allocator);

    // First pass: create all entities
    var entity_map = std.AutoHashMap(u64, Entity).init(self.allocator);
    defer entity_map.deinit();

    for (data.entities) |serialized| {
        const entity = if (serialized.name) |name|
            scene.createEntityNamed(name)
        else
            scene.createEntity();

        try entity_map.put(serialized.id, entity);

        // Add components
        if (serialized.transform) |t| {
            scene.addComponent(entity, Transform, deserializeTransform(t));
        }
        // ... etc
    }

    // Second pass: set up hierarchy
    for (data.entities) |serialized| {
        if (serialized.parent_id != 0) {
            const child = entity_map.get(serialized.id).?;
            const parent = entity_map.get(serialized.parent_id).?;
            scene.setParent(child, parent);
        }
    }

    return scene;
}
```

---

## Phase 9: Update JavaScript Bindings

### Step 9.1: Update Scene API

Modify `src/scripting/bindings/scene_api.zig`:

```zig
fn createEntity(ctx: *js.Context) js.Value {
    const scene = getScene(ctx);
    const entity = scene.createEntity();
    return js.newNumber(ctx, @intCast(entity.id));
}

fn destroyEntity(ctx: *js.Context, entity_id: js.Value) js.Value {
    const scene = getScene(ctx);
    const id = js.toNumber(entity_id);
    scene.destroyEntity(.{ .id = @intCast(id) });
    return js.undefined;
}

fn setParent(ctx: *js.Context, child_id: js.Value, parent_id: js.Value) js.Value {
    const scene = getScene(ctx);
    const child = Entity{ .id = @intCast(js.toNumber(child_id)) };
    const parent = Entity{ .id = @intCast(js.toNumber(parent_id)) };
    scene.setParent(child, parent);
    return js.undefined;
}
```

### Step 9.2: Update Transform API

Entity lookup now uses Flecs:

```zig
fn getTransform(ctx: *js.Context, entity_id: js.Value) js.Value {
    const scene = getScene(ctx);
    const entity = Entity{ .id = @intCast(js.toNumber(entity_id)) };

    if (scene.getComponent(entity, Transform)) |transform| {
        return wrapTransform(ctx, transform);
    }
    return js.undefined;
}
```

---

## Phase 10: Update Examples

### Step 10.1: Update cube3d Example

```zig
pub fn main() !void {
    var eng = try Engine.init(allocator, .{ .window_title = "Cube3D" });
    defer eng.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create camera
    const camera = scene.createEntity();
    scene.addComponent(camera, Transform, .{ .position = Vec3.init(0, 2, 5) });
    scene.addComponent(camera, Camera, .{ .fov = std.math.degreesToRadians(60.0) });
    scene.setActiveCamera(camera);

    // Create cube
    const cube = scene.createEntity();
    scene.addComponent(cube, Transform, .{});
    scene.addComponent(cube, MeshRenderer, .{ .mesh = &cube_mesh });

    try eng.runScene(&scene, update);
}
```

### Step 10.2: Update scene_demo Example

Hierarchy now uses Flecs relationships:

```zig
// Create hierarchy
const parent = scene.createEntity();
scene.addComponent(parent, Transform, .{});

const child = scene.createEntity();
scene.addComponent(child, Transform, .{ .position = Vec3.init(2, 0, 0) });
scene.setParent(child, parent);  // Uses ChildOf relationship
```

---

## Phase 11: Cleanup and Optimization

### Step 11.1: Remove Old ECS Code

After all migrations are complete and tested:

- Delete `src/ecs/entity.zig` (old Entity type)
- Delete `src/ecs/component_storage.zig` (sparse-set storage)
- Remove hardcoded component storages from Scene
- Update module exports in `src/ecs/ecs.zig`

### Step 11.2: Performance Optimization

- Profile query performance
- Consider using `ecs.query_changed()` for dirty checking
- Use system ordering dependencies where needed
- Consider prefabs for entity templates

### Step 11.3: Documentation Update

- Update CLAUDE.md with new API patterns
- Update example READMEs
- Add Flecs-specific documentation for custom components/systems

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| API incompatibility with zflecs | Medium | High | Test early, maintain compatibility layer |
| Performance regression | Low | Medium | Benchmark before/after, profile queries |
| Serialization format change | High | Medium | Version scene files, provide migration tool |
| JavaScript binding breakage | Medium | High | Comprehensive testing, maintain stable API |
| Build system issues | Medium | Low | Isolate zflecs integration early |

---

## Rollback Strategy

1. **Git branching**: Create `feature/flecs-migration` branch
2. **Incremental commits**: One commit per phase for easy revert
3. **Compatibility layer**: Keep old Scene API signatures working during migration
4. **Feature flag**: Consider `use_flecs: bool` in Engine config during transition
5. **Example preservation**: Keep one example using old ECS as reference

---

## Success Criteria

- [ ] All existing examples compile and run correctly
- [ ] Scene serialization/deserialization works with existing scene files
- [ ] JavaScript scripting API maintains compatibility
- [ ] No performance regression in render loop (measure FPS)
- [ ] New components can be added without modifying core Scene code
- [ ] Hierarchy queries work correctly (transform propagation)
- [ ] Animation system integrates with Flecs pipeline

---

## References

- [Flecs Documentation](https://www.flecs.dev/flecs/)
- [Flecs Relationships](https://www.flecs.dev/flecs/md_docs_2Relationships.html)
- [Flecs Queries](https://www.flecs.dev/flecs/md_docs_2Queries.html)
- [zflecs GitHub](https://github.com/zig-gamedev/zflecs)
- [Flecs GitHub](https://github.com/SanderMertens/flecs)
