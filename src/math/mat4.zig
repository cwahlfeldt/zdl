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
    pub fn perspective(fov_radians: f32, aspect: f32, near: f32, far: f32) Mat4 {
        var result = Mat4{ .data = [_]f32{0} ** 16 };

        const tan_half_fov = @tan(fov_radians / 2.0);

        result.data[0] = 1.0 / (aspect * tan_half_fov);
        result.data[5] = 1.0 / tan_half_fov;
        result.data[10] = -(far + near) / (far - near);
        result.data[11] = -1.0;
        result.data[14] = -(2.0 * far * near) / (far - near);

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
};
