const std = @import("std");

/// 4x4 matrix for transformations (column-major order to match GPU conventions)
pub const Mat4 = struct {
    data: [16]f32,

    /// Create identity matrix
    pub fn identity() Mat4 {
        return .{ .data = [_]f32{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        } };
    }

    /// Create orthographic projection matrix
    /// Used for 2D rendering - maps a rectangular region to normalized device coordinates
    /// Vulkan/Metal compatible (Y-down clip space)
    pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        var result = Mat4{ .data = [_]f32{0} ** 16 };

        result.data[0] = 2.0 / (right - left);
        result.data[5] = 2.0 / (top - bottom);
        result.data[10] = 1.0 / (far - near);  // Vulkan uses [0, 1] depth range
        result.data[12] = -(right + left) / (right - left);
        result.data[13] = -(top + bottom) / (top - bottom);
        result.data[14] = -near / (far - near);
        result.data[15] = 1.0;

        return result;
    }

    /// Create perspective projection matrix
    /// Uses [0, 1] depth range for Vulkan/Metal. SDL3 GPU handles Y-flip internally.
    pub fn perspective(fov_radians: f32, aspect: f32, near: f32, far: f32) Mat4 {
        var result = Mat4{ .data = [_]f32{0} ** 16 };

        const tan_half_fov = @tan(fov_radians / 2.0);

        result.data[0] = 1.0 / (aspect * tan_half_fov);
        result.data[5] = 1.0 / tan_half_fov;
        result.data[10] = far / (near - far);
        result.data[11] = -1.0;
        result.data[14] = -(far * near) / (far - near);

        return result;
    }

    /// Create translation matrix
    pub fn translate(x: f32, y: f32, z: f32) Mat4 {
        var result = identity();
        result.data[12] = x;
        result.data[13] = y;
        result.data[14] = z;
        return result;
    }

    /// Create scale matrix
    pub fn scale(x: f32, y: f32, z: f32) Mat4 {
        var result = identity();
        result.data[0] = x;
        result.data[5] = y;
        result.data[10] = z;
        return result;
    }

    /// Create rotation matrix around Z axis (for 2D rotation)
    pub fn rotateZ(radians: f32) Mat4 {
        var result = identity();
        const c = @cos(radians);
        const s = @sin(radians);

        result.data[0] = c;
        result.data[1] = s;
        result.data[4] = -s;
        result.data[5] = c;

        return result;
    }

    /// Matrix multiplication
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var result = Mat4{ .data = [_]f32{0} ** 16 };

        var i: usize = 0;
        while (i < 4) : (i += 1) {
            var j: usize = 0;
            while (j < 4) : (j += 1) {
                var sum: f32 = 0;
                var k: usize = 0;
                while (k < 4) : (k += 1) {
                    sum += a.data[k * 4 + i] * b.data[j * 4 + k];
                }
                result.data[j * 4 + i] = sum;
            }
        }

        return result;
    }

    /// Invert a 4x4 matrix. Returns null if not invertible.
    pub fn inverse(self: Mat4) ?Mat4 {
        const m = self.data;
        var inv: [16]f32 = undefined;

        inv[0] = m[5] * m[10] * m[15] -
            m[5] * m[11] * m[14] -
            m[9] * m[6] * m[15] +
            m[9] * m[7] * m[14] +
            m[13] * m[6] * m[11] -
            m[13] * m[7] * m[10];

        inv[4] = -m[4] * m[10] * m[15] +
            m[4] * m[11] * m[14] +
            m[8] * m[6] * m[15] -
            m[8] * m[7] * m[14] -
            m[12] * m[6] * m[11] +
            m[12] * m[7] * m[10];

        inv[8] = m[4] * m[9] * m[15] -
            m[4] * m[11] * m[13] -
            m[8] * m[5] * m[15] +
            m[8] * m[7] * m[13] +
            m[12] * m[5] * m[11] -
            m[12] * m[7] * m[9];

        inv[12] = -m[4] * m[9] * m[14] +
            m[4] * m[10] * m[13] +
            m[8] * m[5] * m[14] -
            m[8] * m[6] * m[13] -
            m[12] * m[5] * m[10] +
            m[12] * m[6] * m[9];

        inv[1] = -m[1] * m[10] * m[15] +
            m[1] * m[11] * m[14] +
            m[9] * m[2] * m[15] -
            m[9] * m[3] * m[14] -
            m[13] * m[2] * m[11] +
            m[13] * m[3] * m[10];

        inv[5] = m[0] * m[10] * m[15] -
            m[0] * m[11] * m[14] -
            m[8] * m[2] * m[15] +
            m[8] * m[3] * m[14] +
            m[12] * m[2] * m[11] -
            m[12] * m[3] * m[10];

        inv[9] = -m[0] * m[9] * m[15] +
            m[0] * m[11] * m[13] +
            m[8] * m[1] * m[15] -
            m[8] * m[3] * m[13] -
            m[12] * m[1] * m[11] +
            m[12] * m[3] * m[9];

        inv[13] = m[0] * m[9] * m[14] -
            m[0] * m[10] * m[13] -
            m[8] * m[1] * m[14] +
            m[8] * m[2] * m[13] +
            m[12] * m[1] * m[10] -
            m[12] * m[2] * m[9];

        inv[2] = m[1] * m[6] * m[15] -
            m[1] * m[7] * m[14] -
            m[5] * m[2] * m[15] +
            m[5] * m[3] * m[14] +
            m[13] * m[2] * m[7] -
            m[13] * m[3] * m[6];

        inv[6] = -m[0] * m[6] * m[15] +
            m[0] * m[7] * m[14] +
            m[4] * m[2] * m[15] -
            m[4] * m[3] * m[14] -
            m[12] * m[2] * m[7] +
            m[12] * m[3] * m[6];

        inv[10] = m[0] * m[5] * m[15] -
            m[0] * m[7] * m[13] -
            m[4] * m[1] * m[15] +
            m[4] * m[3] * m[13] +
            m[12] * m[1] * m[7] -
            m[12] * m[3] * m[5];

        inv[14] = -m[0] * m[5] * m[14] +
            m[0] * m[6] * m[13] +
            m[4] * m[1] * m[14] -
            m[4] * m[2] * m[13] -
            m[12] * m[1] * m[6] +
            m[12] * m[2] * m[5];

        inv[3] = -m[1] * m[6] * m[11] +
            m[1] * m[7] * m[10] +
            m[5] * m[2] * m[11] -
            m[5] * m[3] * m[10] -
            m[9] * m[2] * m[7] +
            m[9] * m[3] * m[6];

        inv[7] = m[0] * m[6] * m[11] -
            m[0] * m[7] * m[10] -
            m[4] * m[2] * m[11] +
            m[4] * m[3] * m[10] +
            m[8] * m[2] * m[7] -
            m[8] * m[3] * m[6];

        inv[11] = -m[0] * m[5] * m[11] +
            m[0] * m[7] * m[9] +
            m[4] * m[1] * m[11] -
            m[4] * m[3] * m[9] -
            m[8] * m[1] * m[7] +
            m[8] * m[3] * m[5];

        inv[15] = m[0] * m[5] * m[10] -
            m[0] * m[6] * m[9] -
            m[4] * m[1] * m[10] +
            m[4] * m[2] * m[9] +
            m[8] * m[1] * m[6] -
            m[8] * m[2] * m[5];

        const det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
        if (det == 0.0) return null;

        const inv_det = 1.0 / det;
        for (inv[0..]) |*v| {
            v.* *= inv_det;
        }

        return .{ .data = inv };
    }

    /// Create a view matrix using lookAt
    /// eye: camera position
    /// target: point to look at
    /// up: up direction (usually world up: 0, 1, 0)
    pub fn lookAt(eye: @import("vec3.zig").Vec3, target: @import("vec3.zig").Vec3, up: @import("vec3.zig").Vec3) Mat4 {
        const f = target.sub(eye).normalize();
        const r = f.cross(up).normalize();
        const u = r.cross(f);

        return .{ .data = [_]f32{
            r.x,  u.x,  -f.x, 0,
            r.y,  u.y,  -f.y, 0,
            r.z,  u.z,  -f.z, 0,
            -r.dot(eye), -u.dot(eye), f.dot(eye), 1,
        } };
    }

    /// Multiply a Vec4 by this matrix
    pub fn multiplyVec4(self: Mat4, v: @import("vec4.zig").Vec4) @import("vec4.zig").Vec4 {
        const Vec4 = @import("vec4.zig").Vec4;
        return Vec4.init(
            self.data[0] * v.x + self.data[4] * v.y + self.data[8] * v.z + self.data[12] * v.w,
            self.data[1] * v.x + self.data[5] * v.y + self.data[9] * v.z + self.data[13] * v.w,
            self.data[2] * v.x + self.data[6] * v.y + self.data[10] * v.z + self.data[14] * v.w,
            self.data[3] * v.x + self.data[7] * v.y + self.data[11] * v.z + self.data[15] * v.w,
        );
    }

    /// Transform a point (position) by this matrix
    /// Assumes w=1 and performs perspective divide if needed
    pub fn multiplyPoint(self: Mat4, p: @import("vec3.zig").Vec3) @import("vec3.zig").Vec3 {
        const Vec3 = @import("vec3.zig").Vec3;
        const x = self.data[0] * p.x + self.data[4] * p.y + self.data[8] * p.z + self.data[12];
        const y = self.data[1] * p.x + self.data[5] * p.y + self.data[9] * p.z + self.data[13];
        const z = self.data[2] * p.x + self.data[6] * p.y + self.data[10] * p.z + self.data[14];
        const w = self.data[3] * p.x + self.data[7] * p.y + self.data[11] * p.z + self.data[15];

        if (@abs(w) > 0.0001) {
            return Vec3.init(x / w, y / w, z / w);
        }
        return Vec3.init(x, y, z);
    }

    /// Transform a direction vector by this matrix (ignores translation)
    /// Assumes w=0
    pub fn multiplyDirection(self: Mat4, d: @import("vec3.zig").Vec3) @import("vec3.zig").Vec3 {
        const Vec3 = @import("vec3.zig").Vec3;
        return Vec3.init(
            self.data[0] * d.x + self.data[4] * d.y + self.data[8] * d.z,
            self.data[1] * d.x + self.data[5] * d.y + self.data[9] * d.z,
            self.data[2] * d.x + self.data[6] * d.y + self.data[10] * d.z,
        );
    }
};
