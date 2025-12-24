const std = @import("std");
const math = @import("../../math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Quat = @import("../../math/quat.zig").Quat;
const Transform = @import("../../transform.zig").Transform;
const Entity = @import("../entity.zig").Entity;

/// Transform component with hierarchy support.
/// Stores local transform relative to parent and caches world matrix.
pub const TransformComponent = struct {
    /// Local transform (relative to parent, or world space if no parent)
    local: Transform,

    /// Cached world matrix (computed from hierarchy)
    world_matrix: Mat4,

    /// Whether world matrix needs recomputation
    world_dirty: bool,

    /// Parent entity (invalid if root)
    parent: Entity,

    /// First child entity (invalid if no children)
    first_child: Entity,

    /// Next sibling entity (invalid if last sibling)
    next_sibling: Entity,

    /// Previous sibling entity (invalid if first sibling)
    prev_sibling: Entity,

    /// Create an identity transform component (no parent).
    pub fn init() TransformComponent {
        return .{
            .local = Transform.init(),
            .world_matrix = Mat4.identity(),
            .world_dirty = true,
            .parent = Entity.invalid,
            .first_child = Entity.invalid,
            .next_sibling = Entity.invalid,
            .prev_sibling = Entity.invalid,
        };
    }

    /// Create a transform component with a specific position.
    pub fn withPosition(position: Vec3) TransformComponent {
        return .{
            .local = Transform.withPosition(position),
            .world_matrix = Mat4.identity(),
            .world_dirty = true,
            .parent = Entity.invalid,
            .first_child = Entity.invalid,
            .next_sibling = Entity.invalid,
            .prev_sibling = Entity.invalid,
        };
    }

    /// Create a transform component from an existing Transform.
    pub fn withTransform(transform: Transform) TransformComponent {
        return .{
            .local = transform,
            .world_matrix = Mat4.identity(),
            .world_dirty = true,
            .parent = Entity.invalid,
            .first_child = Entity.invalid,
            .next_sibling = Entity.invalid,
            .prev_sibling = Entity.invalid,
        };
    }

    /// Mark transform as dirty (world matrix needs recalculation).
    pub fn markDirty(self: *TransformComponent) void {
        self.world_dirty = true;
    }

    /// Get the local position.
    pub fn getPosition(self: *const TransformComponent) Vec3 {
        return self.local.position;
    }

    /// Set the local position and mark dirty.
    pub fn setPosition(self: *TransformComponent, position: Vec3) void {
        self.local.position = position;
        self.world_dirty = true;
    }

    /// Translate by a delta and mark dirty.
    pub fn translate(self: *TransformComponent, delta: Vec3) void {
        self.local.translate(delta);
        self.world_dirty = true;
    }

    /// Get the local rotation.
    pub fn getRotation(self: *const TransformComponent) Quat {
        return self.local.rotation;
    }

    /// Set the local rotation and mark dirty.
    pub fn setRotation(self: *TransformComponent, rotation: Quat) void {
        self.local.rotation = rotation;
        self.world_dirty = true;
    }

    /// Rotate by a quaternion and mark dirty.
    pub fn rotate(self: *TransformComponent, rotation: Quat) void {
        self.local.rotate(rotation);
        self.world_dirty = true;
    }

    /// Rotate using Euler angles (pitch, yaw, roll in radians).
    pub fn rotateEuler(self: *TransformComponent, pitch: f32, yaw: f32, roll: f32) void {
        self.local.rotateEuler(pitch, yaw, roll);
        self.world_dirty = true;
    }

    /// Set rotation using Euler angles.
    pub fn setRotationEuler(self: *TransformComponent, pitch: f32, yaw: f32, roll: f32) void {
        self.local.setRotationEuler(pitch, yaw, roll);
        self.world_dirty = true;
    }

    /// Get the local scale.
    pub fn getScale(self: *const TransformComponent) Vec3 {
        return self.local.scale;
    }

    /// Set the local scale and mark dirty.
    pub fn setScale(self: *TransformComponent, scale: Vec3) void {
        self.local.scale = scale;
        self.world_dirty = true;
    }

    /// Scale uniformly and mark dirty.
    pub fn scaleUniform(self: *TransformComponent, factor: f32) void {
        self.local.scaleUniform(factor);
        self.world_dirty = true;
    }

    /// Get the local forward direction (Z axis).
    pub fn forward(self: *const TransformComponent) Vec3 {
        return self.local.forward();
    }

    /// Get the local right direction (X axis).
    pub fn right(self: *const TransformComponent) Vec3 {
        return self.local.right();
    }

    /// Get the local up direction (Y axis).
    pub fn up(self: *const TransformComponent) Vec3 {
        return self.local.up();
    }

    /// Look at a target position.
    pub fn lookAt(self: *TransformComponent, target: Vec3, up_vector: Vec3) void {
        self.local.lookAt(target, up_vector);
        self.world_dirty = true;
    }

    /// Check if this transform has a parent.
    pub fn hasParent(self: *const TransformComponent) bool {
        return self.parent.isValid();
    }

    /// Check if this transform has children.
    pub fn hasChildren(self: *const TransformComponent) bool {
        return self.first_child.isValid();
    }

    /// Get the world position from the cached world matrix.
    pub fn getWorldPosition(self: *const TransformComponent) Vec3 {
        return Vec3.init(
            self.world_matrix.data[12],
            self.world_matrix.data[13],
            self.world_matrix.data[14],
        );
    }
};
