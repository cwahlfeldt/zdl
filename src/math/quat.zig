const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;
const Mat4 = @import("mat4.zig").Mat4;

/// Quaternion for representing 3D rotations
/// Format: (x, y, z, w) where w is the scalar component
pub const Quat = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    /// Create a quaternion from components
    pub fn init(x: f32, y: f32, z: f32, w: f32) Quat {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    /// Create identity quaternion (no rotation)
    pub fn identity() Quat {
        return .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    }

    /// Create quaternion from axis-angle representation
    /// axis should be normalized, angle in radians
    pub fn fromAxisAngle(axis: Vec3, angle: f32) Quat {
        const half_angle = angle / 2.0;
        const s = @sin(half_angle);
        const c = @cos(half_angle);

        return .{
            .x = axis.x * s,
            .y = axis.y * s,
            .z = axis.z * s,
            .w = c,
        };
    }

    /// Create quaternion from Euler angles (in radians)
    /// Order: YXZ (yaw, pitch, roll)
    pub fn fromEuler(pitch: f32, yaw: f32, roll: f32) Quat {
        const cy = @cos(yaw * 0.5);
        const sy = @sin(yaw * 0.5);
        const cp = @cos(pitch * 0.5);
        const sp = @sin(pitch * 0.5);
        const cr = @cos(roll * 0.5);
        const sr = @sin(roll * 0.5);

        return .{
            .w = cr * cp * cy + sr * sp * sy,
            .x = sr * cp * cy - cr * sp * sy,
            .y = cr * sp * cy + sr * cp * sy,
            .z = cr * cp * sy - sr * sp * cy,
        };
    }

    /// Multiply two quaternions (combine rotations)
    pub fn mul(a: Quat, b: Quat) Quat {
        return .{
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        };
    }

    /// Normalize quaternion
    pub fn normalize(self: Quat) Quat {
        const len = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        if (len == 0) return identity();

        return .{
            .x = self.x / len,
            .y = self.y / len,
            .z = self.z / len,
            .w = self.w / len,
        };
    }

    /// Convert quaternion to 4x4 rotation matrix
    pub fn toMat4(self: Quat) Mat4 {
        const xx = self.x * self.x;
        const yy = self.y * self.y;
        const zz = self.z * self.z;
        const xy = self.x * self.y;
        const xz = self.x * self.z;
        const yz = self.y * self.z;
        const wx = self.w * self.x;
        const wy = self.w * self.y;
        const wz = self.w * self.z;

        return .{ .data = [_]f32{
            1 - 2 * (yy + zz), 2 * (xy + wz),     2 * (xz - wy),     0,
            2 * (xy - wz),     1 - 2 * (xx + zz), 2 * (yz + wx),     0,
            2 * (xz + wy),     2 * (yz - wx),     1 - 2 * (xx + yy), 0,
            0,                 0,                 0,                 1,
        } };
    }

    /// Spherical linear interpolation between two quaternions
    pub fn slerp(a: Quat, b: Quat, t: f32) Quat {
        var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;

        // If the dot product is negative, slerp won't take the shorter path
        var b_adjusted = b;
        if (dot < 0) {
            b_adjusted.x = -b.x;
            b_adjusted.y = -b.y;
            b_adjusted.z = -b.z;
            b_adjusted.w = -b.w;
            dot = -dot;
        }

        const DOT_THRESHOLD = 0.9995;
        if (dot > DOT_THRESHOLD) {
            // If quaternions are very close, use linear interpolation
            return .{
                .x = a.x + t * (b_adjusted.x - a.x),
                .y = a.y + t * (b_adjusted.y - a.y),
                .z = a.z + t * (b_adjusted.z - a.z),
                .w = a.w + t * (b_adjusted.w - a.w),
            };
        }

        const theta = std.math.acos(dot);
        const theta_t = theta * t;
        const sin_theta = @sin(theta);
        const sin_theta_t = @sin(theta_t);

        const s0 = @cos(theta_t) - dot * sin_theta_t / sin_theta;
        const s1 = sin_theta_t / sin_theta;

        return .{
            .x = a.x * s0 + b_adjusted.x * s1,
            .y = a.y * s0 + b_adjusted.y * s1,
            .z = a.z * s0 + b_adjusted.z * s1,
            .w = a.w * s0 + b_adjusted.w * s1,
        };
    }

    /// Conjugate (inverse for unit quaternions)
    pub fn conjugate(self: Quat) Quat {
        return .{ .x = -self.x, .y = -self.y, .z = -self.z, .w = self.w };
    }

    /// Rotate a vector by this quaternion
    pub fn rotateVec3(self: Quat, v: Vec3) Vec3 {
        const u = Vec3.init(self.x, self.y, self.z);
        const s = self.w;

        const u_cross_v = u.cross(v);
        const u_cross_u_cross_v = u.cross(u_cross_v);

        return v
            .add(u_cross_v.mul(2.0 * s))
            .add(u_cross_u_cross_v.mul(2.0));
    }
};
