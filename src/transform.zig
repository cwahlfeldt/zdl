const std = @import("std");
const math = @import("math/math.zig");
const Vec3 = math.Vec3;
const Quat = @import("math/quat.zig").Quat;
const Mat4 = math.Mat4;

/// 3D Transform representing position, rotation, and scale
/// Uses TRS (Translate-Rotate-Scale) order for matrix composition
pub const Transform = struct {
    position: Vec3,
    rotation: Quat,
    scale: Vec3,

    /// Create a new transform with default values (identity)
    pub fn init() Transform {
        return .{
            .position = Vec3.zero(),
            .rotation = Quat.identity(),
            .scale = Vec3.init(1, 1, 1),
        };
    }

    /// Create a transform with specific position
    pub fn withPosition(position: Vec3) Transform {
        return .{
            .position = position,
            .rotation = Quat.identity(),
            .scale = Vec3.init(1, 1, 1),
        };
    }

    /// Create a transform with specific position and rotation
    pub fn withPositionRotation(position: Vec3, rotation: Quat) Transform {
        return .{
            .position = position,
            .rotation = rotation,
            .scale = Vec3.init(1, 1, 1),
        };
    }

    /// Generate the model matrix (TRS order)
    /// This transforms from local space to world space
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

    /// Translate by a vector
    pub fn translate(self: *Transform, delta: Vec3) void {
        self.position = self.position.add(delta);
    }

    /// Rotate by a quaternion
    pub fn rotate(self: *Transform, rotation: Quat) void {
        self.rotation = self.rotation.mul(rotation);
    }

    /// Rotate around an axis by an angle (in radians)
    pub fn rotateAxis(self: *Transform, axis: Vec3, angle: f32) void {
        const rotation = Quat.fromAxisAngle(axis.normalize(), angle);
        self.rotate(rotation);
    }

    /// Rotate using Euler angles (pitch, yaw, roll in radians)
    pub fn rotateEuler(self: *Transform, pitch: f32, yaw: f32, roll: f32) void {
        const rotation = Quat.fromEuler(pitch, yaw, roll);
        self.rotate(rotation);
    }

    /// Set the rotation using Euler angles
    pub fn setRotationEuler(self: *Transform, pitch: f32, yaw: f32, roll: f32) void {
        self.rotation = Quat.fromEuler(pitch, yaw, roll);
    }

    /// Scale uniformly
    pub fn scaleUniform(self: *Transform, factor: f32) void {
        self.scale = self.scale.mul(factor);
    }

    /// Get the forward direction vector (local Z axis)
    pub fn forward(self: Transform) Vec3 {
        return self.rotation.rotateVec3(Vec3.init(0, 0, 1));
    }

    /// Get the right direction vector (local X axis)
    pub fn right(self: Transform) Vec3 {
        return self.rotation.rotateVec3(Vec3.init(1, 0, 0));
    }

    /// Get the up direction vector (local Y axis)
    pub fn up(self: Transform) Vec3 {
        return self.rotation.rotateVec3(Vec3.init(0, 1, 0));
    }

    /// Look at a target position
    /// Up vector defaults to world up (0, 1, 0)
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

/// Helper function to convert a rotation matrix to a quaternion
/// Assumes the input is a pure rotation matrix (orthonormal)
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
