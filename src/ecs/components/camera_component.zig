const std = @import("std");
const math = @import("../../math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

/// Camera component for perspective rendering.
/// View matrix is derived from the entity's TransformComponent.
pub const CameraComponent = struct {
    /// Field of view in radians
    fov: f32,
    /// Near clipping plane
    near: f32,
    /// Far clipping plane
    far: f32,

    /// Create a camera with default settings (45° FOV, 0.1-100 range).
    pub fn init() CameraComponent {
        return .{
            .fov = std.math.pi / 4.0, // 45 degrees
            .near = 0.1,
            .far = 100.0,
        };
    }

    /// Create a camera with custom settings.
    pub fn initWithSettings(fov: f32, near: f32, far: f32) CameraComponent {
        return .{
            .fov = fov,
            .near = near,
            .far = far,
        };
    }

    /// Get the projection matrix for this camera.
    pub fn getProjectionMatrix(self: CameraComponent, aspect: f32) Mat4 {
        return Mat4.perspective(self.fov, aspect, self.near, self.far);
    }

    /// Get the view matrix from a world transform matrix.
    /// The view matrix is the inverse of the camera's world transform.
    /// For an orthonormal matrix (rotation + translation), the inverse is transpose of rotation
    /// with negated, rotated translation.
    pub fn getViewMatrix(world_matrix: Mat4) Mat4 {
        // For a TRS matrix with uniform scale of 1, we can compute the inverse efficiently:
        // The rotation part is transposed, and the translation is negated and rotated.

        // Extract rotation columns (as rows for transpose)
        const r0 = Vec3.init(world_matrix.data[0], world_matrix.data[4], world_matrix.data[8]);
        const r1 = Vec3.init(world_matrix.data[1], world_matrix.data[5], world_matrix.data[9]);
        const r2 = Vec3.init(world_matrix.data[2], world_matrix.data[6], world_matrix.data[10]);

        // Extract translation
        const t = Vec3.init(world_matrix.data[12], world_matrix.data[13], world_matrix.data[14]);

        // Negate and rotate translation by transposed rotation
        const neg_t = Vec3.init(
            -(r0.x * t.x + r0.y * t.y + r0.z * t.z),
            -(r1.x * t.x + r1.y * t.y + r1.z * t.z),
            -(r2.x * t.x + r2.y * t.y + r2.z * t.z),
        );

        return Mat4{
            .data = [_]f32{
                r0.x, r1.x, r2.x, 0,
                r0.y, r1.y, r2.y, 0,
                r0.z, r1.z, r2.z, 0,
                neg_t.x, neg_t.y, neg_t.z, 1,
            },
        };
    }

    /// Set field of view in degrees (converted to radians internally).
    pub fn setFovDegrees(self: *CameraComponent, degrees: f32) void {
        self.fov = degrees * std.math.pi / 180.0;
    }

    /// Get field of view in degrees.
    pub fn getFovDegrees(self: CameraComponent) f32 {
        return self.fov * 180.0 / std.math.pi;
    }
};
