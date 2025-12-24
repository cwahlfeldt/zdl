const std = @import("std");
const math = @import("math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

/// 3D Camera with perspective projection
pub const Camera = struct {
    position: Vec3,
    target: Vec3,
    up: Vec3,
    fov: f32, // Field of view in radians
    aspect: f32,
    near: f32,
    far: f32,

    /// Create a new 3D camera
    pub fn init(width: f32, height: f32) Camera {
        return .{
            .position = Vec3.init(0, 0, -5),
            .target = Vec3.zero(),
            .up = Vec3.init(0, 1, 0),
            .fov = std.math.pi / 4.0, // 45 degrees
            .aspect = width / height,
            .near = 0.1,
            .far = 100.0,
        };
    }

    /// Create a camera with custom settings
    pub fn initWithSettings(
        position: Vec3,
        target: Vec3,
        fov: f32,
        aspect: f32,
        near: f32,
        far: f32,
    ) Camera {
        return .{
            .position = position,
            .target = target,
            .up = Vec3.init(0, 1, 0),
            .fov = fov,
            .aspect = aspect,
            .near = near,
            .far = far,
        };
    }

    /// Get the view matrix (camera transform)
    pub fn getViewMatrix(self: Camera) Mat4 {
        return Mat4.lookAt(self.position, self.target, self.up);
    }

    /// Get the projection matrix
    pub fn getProjectionMatrix(self: Camera) Mat4 {
        return Mat4.perspective(self.fov, self.aspect, self.near, self.far);
    }

    /// Get combined view-projection matrix
    pub fn getViewProjectionMatrix(self: Camera) Mat4 {
        const view = self.getViewMatrix();
        const projection = self.getProjectionMatrix();
        return projection.mul(view);
    }

    /// Update aspect ratio (call when window is resized)
    pub fn resize(self: *Camera, width: f32, height: f32) void {
        self.aspect = width / height;
    }

    /// Move the camera forward/backward along its view direction
    pub fn moveForward(self: *Camera, distance: f32) void {
        const forward = self.target.sub(self.position).normalize();
        self.position = self.position.add(forward.mul(distance));
        self.target = self.target.add(forward.mul(distance));
    }

    /// Move the camera left/right
    pub fn moveRight(self: *Camera, distance: f32) void {
        const forward = self.target.sub(self.position).normalize();
        const right = forward.cross(self.up).normalize();
        self.position = self.position.add(right.mul(distance));
        self.target = self.target.add(right.mul(distance));
    }

    /// Move the camera up/down
    pub fn moveUp(self: *Camera, distance: f32) void {
        self.position = self.position.add(self.up.mul(distance));
        self.target = self.target.add(self.up.mul(distance));
    }

    /// Orbit around the target point
    pub fn orbit(self: *Camera, yaw: f32, pitch: f32) void {
        const to_camera = self.position.sub(self.target);
        const distance = to_camera.length();

        // Convert to spherical coordinates
        var theta = std.math.atan2(to_camera.x, to_camera.z);
        var phi = std.math.acos(to_camera.y / distance);

        // Apply rotation
        theta += yaw;
        phi += pitch;

        // Clamp phi to avoid gimbal lock
        phi = @max(0.1, @min(std.math.pi - 0.1, phi));

        // Convert back to Cartesian
        const x = distance * @sin(phi) * @sin(theta);
        const y = distance * @cos(phi);
        const z = distance * @sin(phi) * @cos(theta);

        self.position = self.target.add(Vec3.init(x, y, z));
    }

    /// Look at a specific point
    pub fn lookAt(self: *Camera, target: Vec3) void {
        self.target = target;
    }

    /// Set camera position
    pub fn setPosition(self: *Camera, position: Vec3) void {
        const offset = position.sub(self.position);
        self.position = position;
        self.target = self.target.add(offset);
    }

    /// Get the forward direction vector
    pub fn getForward(self: Camera) Vec3 {
        return self.target.sub(self.position).normalize();
    }

    /// Get the right direction vector
    pub fn getRight(self: Camera) Vec3 {
        return self.getForward().cross(self.up).normalize();
    }
};
