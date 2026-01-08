const std = @import("std");
const ecs = @import("zflecs");
const math = @import("../math/math.zig");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const Entity = @import("entity.zig").Entity;

const components = @import("components/components.zig");
const TransformComponent = components.TransformComponent;
const CameraComponent = components.CameraComponent;
const MeshRendererComponent = components.MeshRendererComponent;
const LightComponent = components.LightComponent;
const FpvCameraController = components.FpvCameraController;

// Scripting component
pub const ScriptComponent = @import("../scripting/script_component.zig").ScriptComponent;
const JsComponentStorage = @import("../scripting/js_component_storage.zig").JsComponentStorage;
const ComponentSchema = @import("../scripting/js_component_storage.zig").ComponentSchema;

// Animation component
pub const AnimatorComponent = @import("../animation/animator_component.zig").AnimatorComponent;

/// Scene container that owns the Flecs world and all entities/components.
/// Provides the primary API for creating and managing the game world.
pub const Scene = struct {
    allocator: std.mem.Allocator,

    /// Flecs world handle
    world: *ecs.world_t,

    /// Currently active camera entity
    active_camera: Entity,

    /// Transform update system entity
    transform_system: ecs.entity_t,

    /// JavaScript-defined component storage
    js_components: JsComponentStorage,

    pub fn init(allocator: std.mem.Allocator) Scene {
        const world = ecs.init();

        // Register all component types and systems
        registerComponents(world);
        const transform_system = registerSystems(world);

        return .{
            .allocator = allocator,
            .world = world,
            .active_camera = Entity.invalid,
            .transform_system = transform_system,
            .js_components = JsComponentStorage.init(allocator),
        };
    }

    pub fn deinit(self: *Scene) void {
        self.js_components.deinit();
        _ = ecs.fini(self.world);
    }

    // ==================== Entity Lifecycle ====================

    /// Create a new entity in the scene.
    pub fn createEntity(self: *Scene) Entity {
        return .{ .id = ecs.new_id(self.world) };
    }

    /// Create a new entity with a name.
    pub fn createEntityNamed(self: *Scene, name: [:0]const u8) Entity {
        return .{ .id = ecs.new_entity(self.world, name.ptr) };
    }

    /// Destroy an entity and all its components.
    pub fn destroyEntity(self: *Scene, entity: Entity) void {
        if (!entity.isValid()) return;
        self.js_components.removeEntity(entity);
        ecs.delete(self.world, entity.id);
    }

    /// Check if an entity exists in the scene.
    pub fn entityExists(self: *const Scene, entity: Entity) bool {
        if (!entity.isValid()) return false;
        return ecs.is_alive(self.world, entity.id);
    }

    // ==================== Component Management ====================

    /// Add a component to an entity using comptime type dispatch.
    pub fn addComponent(self: *Scene, entity: Entity, component: anytype) void {
        const T = @TypeOf(component);
        _ = ecs.set(self.world, entity.id, T, component);
    }

    /// Remove a component from an entity.
    pub fn removeComponent(self: *Scene, comptime T: type, entity: Entity) void {
        ecs.remove(self.world, entity.id, ecs.id(T));
    }

    /// Get a mutable pointer to an entity's component.
    pub fn getComponent(self: *Scene, comptime T: type, entity: Entity) ?*T {
        return ecs.get_mut(self.world, entity.id, T);
    }

    /// Get a const pointer to an entity's component.
    pub fn getComponentConst(self: *const Scene, comptime T: type, entity: Entity) ?*const T {
        return ecs.get(self.world, entity.id, T);
    }

    /// Check if an entity has a specific component.
    pub fn hasComponent(self: *const Scene, comptime T: type, entity: Entity) bool {
        return ecs.has_id(self.world, entity.id, ecs.id(T));
    }

    // ==================== JavaScript Components ====================

    pub fn registerJsComponent(self: *Scene, type_name: []const u8, schema_json: []const u8, is_tag: bool) !void {
        try self.js_components.registerType(type_name, schema_json, is_tag);
    }

    pub fn addJsComponent(self: *Scene, entity: Entity, type_name: []const u8, data_json: []const u8) !void {
        if (!self.entityExists(entity)) return error.InvalidEntity;
        try self.js_components.addComponent(entity, type_name, data_json);
    }

    pub fn updateJsComponent(self: *Scene, entity: Entity, type_name: []const u8, data_json: []const u8) !void {
        if (!self.entityExists(entity)) return error.InvalidEntity;
        try self.js_components.updateComponent(entity, type_name, data_json);
    }

    pub fn removeJsComponent(self: *Scene, entity: Entity, type_name: []const u8) void {
        self.js_components.removeComponent(entity, type_name);
    }

    pub fn hasJsComponent(self: *const Scene, entity: Entity, type_name: []const u8) bool {
        return self.js_components.hasComponent(entity, type_name);
    }

    pub fn getJsComponent(self: *const Scene, entity: Entity, type_name: []const u8) ?[]const u8 {
        return self.js_components.getComponent(entity, type_name);
    }

    pub fn getJsComponentSchema(self: *const Scene, type_name: []const u8) ?ComponentSchema {
        return self.js_components.getSchema(type_name);
    }

    pub fn queryJsComponents(self: *const Scene, allocator: std.mem.Allocator, type_names: []const []const u8) ![]Entity {
        return self.js_components.query(allocator, type_names);
    }

    // ==================== Hierarchy Management ====================

    /// Set an entity's parent using Flecs' ChildOf relationship.
    /// Pass Entity.invalid to unparent (make it a root entity).
    pub fn setParent(self: *Scene, child: Entity, parent: Entity) void {
        if (!child.isValid()) return;

        // Remove existing parent relationship
        ecs.remove_pair(self.world, child.id, ecs.ChildOf, ecs.Wildcard);

        // Add new parent if valid
        if (parent.isValid()) {
            ecs.add_pair(self.world, child.id, ecs.ChildOf, parent.id);
        }
    }

    /// Remove an entity's parent (make it a root entity).
    pub fn removeParent(self: *Scene, child: Entity) void {
        self.setParent(child, Entity.invalid);
    }

    /// Get an entity's parent.
    pub fn getParent(self: *const Scene, entity: Entity) Entity {
        if (!entity.isValid()) return Entity.invalid;
        const parent_id = ecs.get_target(self.world, entity.id, ecs.ChildOf, 0);
        return .{ .id = parent_id };
    }

    /// Get all children of an entity (caller must free the returned slice).
    pub fn getChildren(self: *Scene, entity: Entity, allocator: std.mem.Allocator) ![]Entity {
        var children = try std.ArrayList(Entity).initCapacity(allocator, 8);
        errdefer children.deinit(allocator);

        if (!entity.isValid()) return try children.toOwnedSlice(allocator);

        // Use Flecs to iterate children via ChildOf relationship
        var it = ecs.children(self.world, entity.id);
        while (ecs.children_next(&it)) {
            var i: usize = 0;
            while (i < it.count()) : (i += 1) {
                const child_id = it.entities()[i];
                try children.append(allocator, .{ .id = child_id });
            }
        }

        return try children.toOwnedSlice(allocator);
    }

    // ==================== Camera ====================

    /// Set the active camera for rendering.
    pub fn setActiveCamera(self: *Scene, entity: Entity) void {
        self.active_camera = entity;
    }

    /// Get the active camera entity.
    pub fn getActiveCamera(self: *const Scene) Entity {
        return self.active_camera;
    }

    // ==================== Transform System ====================

    /// Update all world transforms in the hierarchy.
    /// Call this once per frame before rendering.
    pub fn updateWorldTransforms(self: *Scene) void {
        // Run the Flecs pipeline so the transform cascade system updates world matrices.
        _ = ecs.progress(self.world, 0);
    }

    /// Get the world matrix for an entity (must call updateWorldTransforms first).
    pub fn getWorldMatrix(self: *const Scene, entity: Entity) Mat4 {
        if (self.getComponentConst(TransformComponent, entity)) |transform| {
            return transform.world_matrix;
        }
        return Mat4.identity();
    }

    // ==================== Queries ====================

    /// Get entity count.
    pub fn entityCount(self: *const Scene) u32 {
        // Count all entities with any component (simplified)
        var query_desc: ecs.query_desc_t = std.mem.zeroes(ecs.query_desc_t);
        query_desc.terms[0] = .{ .id = ecs.Wildcard };

        const query = ecs.query_init(self.world, &query_desc) catch return 0;
        defer ecs.query_fini(query);

        var count: u32 = 0;
        var it = ecs.query_iter(self.world, query);
        while (ecs.query_next(&it)) {
            count += @intCast(it.count());
        }
        return count;
    }

    /// Iterate all entities with TransformComponent and MeshRendererComponent.
    /// Used by the render system.
    pub fn iterateMeshRenderers(
        self: *Scene,
        comptime callback: fn (Entity, *TransformComponent, *MeshRendererComponent, *anyopaque) void,
        userdata: *anyopaque,
    ) void {
        var query_desc: ecs.query_desc_t = std.mem.zeroes(ecs.query_desc_t);
        query_desc.terms[0] = .{ .id = ecs.id(TransformComponent) };
        query_desc.terms[1] = .{ .id = ecs.id(MeshRendererComponent) };

        const query = ecs.query_init(self.world, &query_desc) catch return;
        defer ecs.query_fini(query);

        var it = ecs.query_iter(self.world, query);
        while (ecs.query_next(&it)) {
            const transforms = ecs.field(&it, TransformComponent, 0) orelse continue;
            const renderers = ecs.field(&it, MeshRendererComponent, 1) orelse continue;

            var i: usize = 0;
            while (i < it.count()) : (i += 1) {
                const entity_id = it.entities()[i];
                callback(.{ .id = entity_id }, &transforms[i], &renderers[i], userdata);
            }
        }
    }

    /// Iterate all entities with LightComponent.
    pub fn iterateLights(
        self: *Scene,
        comptime callback: fn (Entity, *TransformComponent, *LightComponent, *anyopaque) void,
        userdata: *anyopaque,
    ) void {
        var query_desc: ecs.query_desc_t = std.mem.zeroes(ecs.query_desc_t);
        query_desc.terms[0] = .{ .id = ecs.id(TransformComponent) };
        query_desc.terms[1] = .{ .id = ecs.id(LightComponent) };

        const query = ecs.query_init(self.world, &query_desc) catch return;
        defer ecs.query_fini(query);

        var it = ecs.query_iter(self.world, query);
        while (ecs.query_next(&it)) {
            const transforms = ecs.field(&it, TransformComponent, 0) orelse continue;
            const lights = ecs.field(&it, LightComponent, 1) orelse continue;

            var i: usize = 0;
            while (i < it.count()) : (i += 1) {
                const entity_id = it.entities()[i];
                callback(.{ .id = entity_id }, &transforms[i], &lights[i], userdata);
            }
        }
    }

    /// Iterate all entities with ScriptComponent.
    pub fn iterateScripts(
        self: *Scene,
        comptime callback: fn (Entity, *ScriptComponent, *anyopaque) void,
        userdata: *anyopaque,
    ) void {
        var query_desc: ecs.query_desc_t = std.mem.zeroes(ecs.query_desc_t);
        query_desc.terms[0] = .{ .id = ecs.id(ScriptComponent) };

        const query = ecs.query_init(self.world, &query_desc) catch return;
        defer ecs.query_fini(query);

        var it = ecs.query_iter(self.world, query);
        while (ecs.query_next(&it)) {
            const scripts = ecs.field(&it, ScriptComponent, 0) orelse continue;

            var i: usize = 0;
            while (i < it.count()) : (i += 1) {
                const entity_id = it.entities()[i];
                callback(.{ .id = entity_id }, &scripts[i], userdata);
            }
        }
    }
};

/// Register all component types with Flecs.
fn registerComponents(world: *ecs.world_t) void {
    ecs.COMPONENT(world, TransformComponent);
    ecs.COMPONENT(world, CameraComponent);
    ecs.COMPONENT(world, MeshRendererComponent);
    ecs.COMPONENT(world, LightComponent);
    ecs.COMPONENT(world, FpvCameraController);
    ecs.COMPONENT(world, ScriptComponent);
    ecs.COMPONENT(world, AnimatorComponent);
}

fn updateWorldTransformsSystem(it: *ecs.iter_t, transforms: []TransformComponent) void {
    const world = it.world;
    for (transforms, it.entities()) |*transform, entity_id| {
        const local_matrix = transform.local.getMatrix();
        const parent_id = ecs.get_target(world, entity_id, ecs.ChildOf, 0);
        if (parent_id != 0) {
            if (ecs.get(world, parent_id, TransformComponent)) |parent_transform| {
                transform.world_matrix = parent_transform.world_matrix.mul(local_matrix);
            } else {
                transform.world_matrix = local_matrix;
            }
        } else {
            transform.world_matrix = local_matrix;
        }
    }
}

fn registerSystems(world: *ecs.world_t) ecs.entity_t {
    var desc = ecs.SYSTEM_DESC(updateWorldTransformsSystem);
    desc.query.terms[0].src.id = @intCast(ecs.Self | ecs.Cascade);
    desc.query.terms[0].trav = ecs.ChildOf;
    return ecs.SYSTEM(world, "TransformWorldUpdate", ecs.OnUpdate, &desc);
}

test "scene entity creation" {
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const e1 = scene.createEntity();
    const e2 = scene.createEntity();

    try std.testing.expect(scene.entityExists(e1));
    try std.testing.expect(scene.entityExists(e2));
}

test "scene component management" {
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const entity = scene.createEntity();
    scene.addComponent(entity, TransformComponent.withPosition(Vec3.init(1, 2, 3)));

    const transform = scene.getComponent(TransformComponent, entity);
    try std.testing.expect(transform != null);
    try std.testing.expectEqual(@as(f32, 1), transform.?.getPosition().x);
    try std.testing.expectEqual(@as(f32, 2), transform.?.getPosition().y);
    try std.testing.expectEqual(@as(f32, 3), transform.?.getPosition().z);
}

test "scene hierarchy" {
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const parent = scene.createEntity();
    const child = scene.createEntity();

    scene.setParent(child, parent);
    const retrieved_parent = scene.getParent(child);

    try std.testing.expect(retrieved_parent.eql(parent));

    scene.removeParent(child);
    const no_parent = scene.getParent(child);
    try std.testing.expect(!no_parent.isValid());
}
