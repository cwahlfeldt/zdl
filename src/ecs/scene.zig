const std = @import("std");
const math = @import("../math/math.zig");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const Entity = @import("entity.zig").Entity;
const EntityManager = @import("entity.zig").EntityManager;
const ComponentStorage = @import("component_storage.zig").ComponentStorage;

const components = @import("components/components.zig");
const TransformComponent = components.TransformComponent;
const CameraComponent = components.CameraComponent;
const MeshRendererComponent = components.MeshRendererComponent;
const LightComponent = components.LightComponent;
const FpsCameraController = components.FpsCameraController;

/// Scene container that owns all entities and components.
/// Provides the primary API for creating and managing the game world.
pub const Scene = struct {
    allocator: std.mem.Allocator,

    /// Entity lifecycle management
    entities: EntityManager,

    /// Component storages (one per component type)
    transforms: ComponentStorage(TransformComponent),
    cameras: ComponentStorage(CameraComponent),
    mesh_renderers: ComponentStorage(MeshRendererComponent),
    lights: ComponentStorage(LightComponent),
    fps_controllers: ComponentStorage(FpsCameraController),

    /// Currently active camera entity
    active_camera: Entity,

    /// Root entities (no parent) for hierarchy traversal
    root_entities: std.ArrayList(Entity) = .{},

    pub fn init(allocator: std.mem.Allocator) Scene {
        return .{
            .allocator = allocator,
            .entities = EntityManager.init(allocator),
            .transforms = ComponentStorage(TransformComponent).init(allocator),
            .cameras = ComponentStorage(CameraComponent).init(allocator),
            .mesh_renderers = ComponentStorage(MeshRendererComponent).init(allocator),
            .lights = ComponentStorage(LightComponent).init(allocator),
            .fps_controllers = ComponentStorage(FpsCameraController).init(allocator),
            .active_camera = Entity.invalid,
        };
    }

    pub fn deinit(self: *Scene) void {
        self.root_entities.deinit(self.allocator);
        self.fps_controllers.deinit();
        self.lights.deinit();
        self.mesh_renderers.deinit();
        self.cameras.deinit();
        self.transforms.deinit();
        self.entities.deinit();
    }

    // ==================== Entity Lifecycle ====================

    /// Create a new entity in the scene.
    pub fn createEntity(self: *Scene) !Entity {
        const entity = try self.entities.create();
        // Add to root entities by default (no parent)
        try self.root_entities.append(self.allocator, entity);
        return entity;
    }

    /// Destroy an entity and all its components.
    pub fn destroyEntity(self: *Scene, entity: Entity) !void {
        if (!self.entities.isAlive(entity)) return;

        // Remove from parent's children list if parented
        if (self.transforms.get(entity)) |transform| {
            if (transform.parent.isValid()) {
                self.unlinkFromParent(entity, transform);
            } else {
                // Remove from root entities
                self.removeFromRootEntities(entity);
            }

            // Destroy all children recursively
            var child = transform.first_child;
            while (child.isValid()) {
                const next = if (self.transforms.get(child)) |ct| ct.next_sibling else Entity.invalid;
                try self.destroyEntity(child);
                child = next;
            }
        }

        // Remove all components
        _ = self.transforms.remove(entity);
        _ = self.cameras.remove(entity);
        _ = self.mesh_renderers.remove(entity);
        _ = self.lights.remove(entity);
        _ = self.fps_controllers.remove(entity);

        // Clear active camera if destroyed
        if (self.active_camera.eql(entity)) {
            self.active_camera = Entity.invalid;
        }

        try self.entities.destroy(entity);
    }

    /// Check if an entity exists in the scene.
    pub fn entityExists(self: *const Scene, entity: Entity) bool {
        return self.entities.isAlive(entity);
    }

    // ==================== Component Management ====================

    /// Add a component to an entity using comptime type dispatch.
    pub fn addComponent(self: *Scene, entity: Entity, component: anytype) !void {
        const T = @TypeOf(component);

        if (T == TransformComponent) {
            try self.transforms.add(entity, component);
        } else if (T == CameraComponent) {
            try self.cameras.add(entity, component);
        } else if (T == MeshRendererComponent) {
            try self.mesh_renderers.add(entity, component);
        } else if (T == LightComponent) {
            try self.lights.add(entity, component);
        } else if (T == FpsCameraController) {
            try self.fps_controllers.add(entity, component);
        } else {
            @compileError("Unknown component type: " ++ @typeName(T));
        }
    }

    /// Remove a component from an entity.
    pub fn removeComponent(self: *Scene, comptime T: type, entity: Entity) ?T {
        if (T == TransformComponent) {
            // Handle hierarchy cleanup before removing transform
            if (self.transforms.get(entity)) |transform| {
                if (transform.parent.isValid()) {
                    self.unlinkFromParent(entity, transform);
                    self.root_entities.append(self.allocator, entity) catch {};
                }
            }
            return self.transforms.remove(entity);
        } else if (T == CameraComponent) {
            return self.cameras.remove(entity);
        } else if (T == MeshRendererComponent) {
            return self.mesh_renderers.remove(entity);
        } else if (T == LightComponent) {
            return self.lights.remove(entity);
        } else if (T == FpsCameraController) {
            return self.fps_controllers.remove(entity);
        } else {
            @compileError("Unknown component type: " ++ @typeName(T));
        }
    }

    /// Get a mutable pointer to an entity's component.
    pub fn getComponent(self: *Scene, comptime T: type, entity: Entity) ?*T {
        if (T == TransformComponent) {
            return self.transforms.get(entity);
        } else if (T == CameraComponent) {
            return self.cameras.get(entity);
        } else if (T == MeshRendererComponent) {
            return self.mesh_renderers.get(entity);
        } else if (T == LightComponent) {
            return self.lights.get(entity);
        } else if (T == FpsCameraController) {
            return self.fps_controllers.get(entity);
        } else {
            @compileError("Unknown component type: " ++ @typeName(T));
        }
    }

    /// Check if an entity has a specific component.
    pub fn hasComponent(self: *const Scene, comptime T: type, entity: Entity) bool {
        if (T == TransformComponent) {
            return self.transforms.has(entity);
        } else if (T == CameraComponent) {
            return self.cameras.has(entity);
        } else if (T == MeshRendererComponent) {
            return self.mesh_renderers.has(entity);
        } else if (T == LightComponent) {
            return self.lights.has(entity);
        } else if (T == FpsCameraController) {
            return self.fps_controllers.has(entity);
        } else {
            @compileError("Unknown component type: " ++ @typeName(T));
        }
    }

    // ==================== Hierarchy Management ====================

    /// Set an entity's parent. Pass Entity.invalid to unparent.
    pub fn setParent(self: *Scene, child: Entity, parent: Entity) void {
        const child_transform = self.transforms.get(child) orelse return;

        // Remove from current parent or root list
        if (child_transform.parent.isValid()) {
            self.unlinkFromParent(child, child_transform);
        } else {
            self.removeFromRootEntities(child);
        }

        if (parent.isValid()) {
            const parent_transform = self.transforms.get(parent) orelse {
                // Parent has no transform, add back to roots
                self.root_entities.append(self.allocator, child) catch {};
                return;
            };

            // Link as child
            child_transform.parent = parent;
            child_transform.next_sibling = parent_transform.first_child;
            child_transform.prev_sibling = Entity.invalid;

            if (parent_transform.first_child.isValid()) {
                if (self.transforms.get(parent_transform.first_child)) |first_child_transform| {
                    first_child_transform.prev_sibling = child;
                }
            }
            parent_transform.first_child = child;
        } else {
            // Unparenting - add back to roots
            child_transform.parent = Entity.invalid;
            self.root_entities.append(self.allocator, child) catch {};
        }

        child_transform.world_dirty = true;
    }

    /// Remove an entity's parent (make it a root entity).
    pub fn removeParent(self: *Scene, child: Entity) void {
        self.setParent(child, Entity.invalid);
    }

    /// Get an entity's parent.
    pub fn getParent(self: *const Scene, entity: Entity) Entity {
        const transform = self.transforms.getConst(entity) orelse return Entity.invalid;
        return transform.parent;
    }

    /// Get all children of an entity (caller must free the returned slice).
    pub fn getChildren(self: *Scene, entity: Entity, allocator: std.mem.Allocator) ![]Entity {
        var children: std.ArrayList(Entity) = .{};
        errdefer children.deinit(allocator);

        const transform = self.transforms.get(entity) orelse return try children.toOwnedSlice(allocator);

        var child = transform.first_child;
        while (child.isValid()) {
            try children.append(allocator, child);
            const child_transform = self.transforms.get(child) orelse break;
            child = child_transform.next_sibling;
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
        for (self.root_entities.items) |root| {
            if (self.entities.isAlive(root)) {
                self.updateEntityWorldTransform(root, Mat4.identity());
            }
        }
    }

    fn updateEntityWorldTransform(self: *Scene, entity: Entity, parent_world: Mat4) void {
        const transform = self.transforms.get(entity) orelse return;

        // Compute world matrix
        const local_matrix = transform.local.getMatrix();
        transform.world_matrix = parent_world.mul(local_matrix);
        transform.world_dirty = false;

        // Recursively update children
        var child = transform.first_child;
        while (child.isValid()) {
            self.updateEntityWorldTransform(child, transform.world_matrix);
            const child_transform = self.transforms.get(child) orelse break;
            child = child_transform.next_sibling;
        }
    }

    /// Get the world matrix for an entity (must call updateWorldTransforms first).
    pub fn getWorldMatrix(self: *const Scene, entity: Entity) Mat4 {
        const transform = self.transforms.getConst(entity) orelse return Mat4.identity();
        return transform.world_matrix;
    }

    // ==================== Queries ====================

    /// Get all entities with a MeshRenderer component.
    pub fn getMeshRenderers(self: *Scene) struct { items: []MeshRendererComponent, entities: []Entity } {
        return .{
            .items = self.mesh_renderers.items(),
            .entities = self.mesh_renderers.entities(),
        };
    }

    /// Get all entities with a Light component.
    pub fn getLights(self: *Scene) struct { items: []LightComponent, entities: []Entity } {
        return .{
            .items = self.lights.items(),
            .entities = self.lights.entities(),
        };
    }

    /// Get entity count.
    pub fn entityCount(self: *const Scene) u32 {
        return self.entities.count();
    }

    // ==================== Internal Helpers ====================

    fn unlinkFromParent(self: *Scene, entity: Entity, transform: *TransformComponent) void {
        // Update sibling links
        if (transform.prev_sibling.isValid()) {
            if (self.transforms.get(transform.prev_sibling)) |prev| {
                prev.next_sibling = transform.next_sibling;
            }
        }
        if (transform.next_sibling.isValid()) {
            if (self.transforms.get(transform.next_sibling)) |next| {
                next.prev_sibling = transform.prev_sibling;
            }
        }

        // Update parent's first_child if needed
        if (self.transforms.get(transform.parent)) |parent_transform| {
            if (parent_transform.first_child.eql(entity)) {
                parent_transform.first_child = transform.next_sibling;
            }
        }

        transform.parent = Entity.invalid;
        transform.prev_sibling = Entity.invalid;
        transform.next_sibling = Entity.invalid;
    }

    fn removeFromRootEntities(self: *Scene, entity: Entity) void {
        for (self.root_entities.items, 0..) |root, i| {
            if (root.eql(entity)) {
                _ = self.root_entities.swapRemove(i);
                return;
            }
        }
    }
};

test "scene entity creation" {
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const e1 = try scene.createEntity();
    const e2 = try scene.createEntity();

    try std.testing.expect(scene.entityExists(e1));
    try std.testing.expect(scene.entityExists(e2));
    try std.testing.expectEqual(@as(u32, 2), scene.entityCount());
}

test "scene component management" {
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const entity = try scene.createEntity();
    try scene.addComponent(entity, TransformComponent.withPosition(Vec3.init(1, 2, 3)));
    try scene.addComponent(entity, CameraComponent.init());

    try std.testing.expect(scene.hasComponent(TransformComponent, entity));
    try std.testing.expect(scene.hasComponent(CameraComponent, entity));

    const transform = scene.getComponent(TransformComponent, entity).?;
    try std.testing.expectEqual(@as(f32, 1), transform.local.position.x);
}

test "scene hierarchy" {
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const parent = try scene.createEntity();
    const child = try scene.createEntity();

    try scene.addComponent(parent, TransformComponent.init());
    try scene.addComponent(child, TransformComponent.withPosition(Vec3.init(1, 0, 0)));

    scene.setParent(child, parent);

    try std.testing.expect(scene.getParent(child).eql(parent));

    const children = try scene.getChildren(parent, std.testing.allocator);
    defer std.testing.allocator.free(children);

    try std.testing.expectEqual(@as(usize, 1), children.len);
    try std.testing.expect(children[0].eql(child));
}
