const std = @import("std");
const math = @import("../../math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Quat = @import("../../math/quat.zig").Quat;

/// 3D Transform representing position, rotation, and scale.
/// This is now a pure data component - hierarchy is managed by Flecs' ChildOf relationship.
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

    /// Generate the local model matrix (TRS order).
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

/// Transform component with cached world matrix.
/// Hierarchy is now handled by Flecs' ChildOf relationship.
pub const TransformComponent = struct {
    /// Local transform (relative to parent if parented, or world space if root)
    local: Transform,

    /// Cached world matrix (computed by transform system)
    world_matrix: Mat4,

    /// Create an identity transform component.
    pub fn init() TransformComponent {
        return .{
            .local = Transform.init(),
            .world_matrix = Mat4.identity(),
        };
    }

    /// Create a transform component with a specific position.
    pub fn withPosition(position: Vec3) TransformComponent {
        return .{
            .local = Transform.withPosition(position),
            .world_matrix = Mat4.identity(),
        };
    }

    /// Create a transform component from an existing Transform.
    pub fn withTransform(transform: Transform) TransformComponent {
        return .{
            .local = transform,
            .world_matrix = Mat4.identity(),
        };
    }

    /// Get the local position.
    pub fn getPosition(self: *const TransformComponent) Vec3 {
        return self.local.position;
    }

    /// Set the local position.
    pub fn setPosition(self: *TransformComponent, position: Vec3) void {
        self.local.position = position;
    }

    /// Translate by a delta.
    pub fn translate(self: *TransformComponent, delta: Vec3) void {
        self.local.translate(delta);
    }

    /// Get the local rotation.
    pub fn getRotation(self: *const TransformComponent) Quat {
        return self.local.rotation;
    }

    /// Set the local rotation.
    pub fn setRotation(self: *TransformComponent, rotation: Quat) void {
        self.local.rotation = rotation;
    }

    /// Rotate by a quaternion.
    pub fn rotate(self: *TransformComponent, rotation: Quat) void {
        self.local.rotate(rotation);
    }

    /// Rotate using Euler angles (pitch, yaw, roll in radians).
    pub fn rotateEuler(self: *TransformComponent, pitch: f32, yaw: f32, roll: f32) void {
        self.local.rotateEuler(pitch, yaw, roll);
    }

    /// Set rotation using Euler angles.
    pub fn setRotationEuler(self: *TransformComponent, pitch: f32, yaw: f32, roll: f32) void {
        self.local.setRotationEuler(pitch, yaw, roll);
    }

    /// Get the local scale.
    pub fn getScale(self: *const TransformComponent) Vec3 {
        return self.local.scale;
    }

    /// Set the local scale.
    pub fn setScale(self: *TransformComponent, scale: Vec3) void {
        self.local.scale = scale;
    }

    /// Scale uniformly.
    pub fn scaleUniform(self: *TransformComponent, factor: f32) void {
        self.local.scaleUniform(factor);
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
