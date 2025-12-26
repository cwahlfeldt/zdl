const std = @import("std");
const math = @import("../../math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Quat = @import("../../math/quat.zig").Quat;
const Entity = @import("../entity.zig").Entity;

/// 3D Transform representing position, rotation, and scale.
/// Uses TRS (Translate-Rotate-Scale) order for matrix composition.
pub const Transform = struct {
    position: Vec3,
    rotation: Quat,
    scale: Vec3,

    /// Create a new transform with default values (identity).
    pub fn init() Transform {
        return .{
            .position = Vec3.zero(),
            .rotation = Quat.identity(),
            .scale = Vec3.init(1, 1, 1),
        };
    }

    /// Create a transform with specific position.
    pub fn withPosition(position: Vec3) Transform {
        return .{
            .position = position,
            .rotation = Quat.identity(),
            .scale = Vec3.init(1, 1, 1),
        };
    }

    /// Create a transform with specific position and rotation.
    pub fn withPositionRotation(position: Vec3, rotation: Quat) Transform {
        return .{
            .position = position,
            .rotation = rotation,
            .scale = Vec3.init(1, 1, 1),
        };
    }

    /// Generate the model matrix (TRS order).
    /// This transforms from local space to world space.
    pub fn getMatrix(self: Transform) Mat4 {
        // Start with rotation
        var result = self.rotation.toMat4();

        // Apply scale to rotation matrix
        result.data[0] *= self.scale.x;
        result.data[1] *= self.scale.x;
        result.data[2] *= self.scale.x;

        result.data[4] *= self.scale.y;
        result.data[5] *= self.scale.y;
        result.data[6] *= self.scale.y;

        result.data[8] *= self.scale.z;
        result.data[9] *= self.scale.z;
        result.data[10] *= self.scale.z;

        // Apply translation
        result.data[12] = self.position.x;
        result.data[13] = self.position.y;
        result.data[14] = self.position.z;

        return result;
    }

    /// Translate by a vector.
    pub fn translate(self: *Transform, delta: Vec3) void {
        self.position = self.position.add(delta);
    }

    /// Rotate by a quaternion.
    pub fn rotate(self: *Transform, rotation: Quat) void {
        self.rotation = self.rotation.mul(rotation);
    }

    /// Rotate around an axis by an angle (in radians).
    pub fn rotateAxis(self: *Transform, axis: Vec3, angle: f32) void {
        const rot = Quat.fromAxisAngle(axis.normalize(), angle);
        self.rotate(rot);
    }

    /// Rotate using Euler angles (pitch, yaw, roll in radians).
    pub fn rotateEuler(self: *Transform, pitch: f32, yaw: f32, roll: f32) void {
        const rot = Quat.fromEuler(pitch, yaw, roll);
        self.rotate(rot);
    }

    /// Set the rotation using Euler angles.
    pub fn setRotationEuler(self: *Transform, pitch: f32, yaw: f32, roll: f32) void {
        self.rotation = Quat.fromEuler(pitch, yaw, roll);
    }

    /// Scale uniformly.
    pub fn scaleUniform(self: *Transform, factor: f32) void {
        self.scale = self.scale.mul(factor);
    }

    /// Get the forward direction vector (local Z axis).
    pub fn forward(self: Transform) Vec3 {
        return self.rotation.rotateVec3(Vec3.init(0, 0, 1));
    }

    /// Get the right direction vector (local X axis).
    pub fn right(self: Transform) Vec3 {
        return self.rotation.rotateVec3(Vec3.init(1, 0, 0));
    }

    /// Get the up direction vector (local Y axis).
    pub fn up(self: Transform) Vec3 {
        return self.rotation.rotateVec3(Vec3.init(0, 1, 0));
    }

    /// Look at a target position.
    pub fn lookAt(self: *Transform, target: Vec3, up_vector: Vec3) void {
        const forward_dir = target.sub(self.position).normalize();
        const right_dir = forward_dir.cross(up_vector).normalize();
        const up_dir = right_dir.cross(forward_dir);

        // Construct rotation matrix from basis vectors
        // Note: This creates a matrix where -Z is forward (standard OpenGL convention)
        const mat = Mat4{
            .data = [_]f32{
                right_dir.x,    right_dir.y,    right_dir.z,    0,
                up_dir.x,       up_dir.y,       up_dir.z,       0,
                -forward_dir.x, -forward_dir.y, -forward_dir.z, 0,
                0,              0,              0,              1,
            },
        };

        // Convert matrix to quaternion
        self.rotation = matrixToQuat(mat);
    }
};

/// Helper function to convert a rotation matrix to a quaternion.
/// Assumes the input is a pure rotation matrix (orthonormal).
fn matrixToQuat(m: Mat4) Quat {
    const trace = m.data[0] + m.data[5] + m.data[10];

    if (trace > 0) {
        const s = 0.5 / @sqrt(trace + 1.0);
        return Quat{
            .w = 0.25 / s,
            .x = (m.data[6] - m.data[9]) * s,
            .y = (m.data[8] - m.data[2]) * s,
            .z = (m.data[1] - m.data[4]) * s,
        };
    } else if (m.data[0] > m.data[5] and m.data[0] > m.data[10]) {
        const s = 2.0 * @sqrt(1.0 + m.data[0] - m.data[5] - m.data[10]);
        return Quat{
            .w = (m.data[6] - m.data[9]) / s,
            .x = 0.25 * s,
            .y = (m.data[4] + m.data[1]) / s,
            .z = (m.data[8] + m.data[2]) / s,
        };
    } else if (m.data[5] > m.data[10]) {
        const s = 2.0 * @sqrt(1.0 + m.data[5] - m.data[0] - m.data[10]);
        return Quat{
            .w = (m.data[8] - m.data[2]) / s,
            .x = (m.data[4] + m.data[1]) / s,
            .y = 0.25 * s,
            .z = (m.data[9] + m.data[6]) / s,
        };
    } else {
        const s = 2.0 * @sqrt(1.0 + m.data[10] - m.data[0] - m.data[5]);
        return Quat{
            .w = (m.data[1] - m.data[4]) / s,
            .x = (m.data[8] + m.data[2]) / s,
            .y = (m.data[9] + m.data[6]) / s,
            .z = 0.25 * s,
        };
    }
}

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
