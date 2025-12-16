const std = @import("std");
const math = @import("math/math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

/// 2D Camera with orthographic projection
pub const Camera2D = struct {
    position: Vec2,
    width: f32,
    height: f32,

    /// Create a new 2D camera
    pub fn init(width: f32, height: f32) Camera2D {
        return .{
            .position = Vec2.zero(),
            .width = width,
            .height = height,
        };
    }

    /// Get the view-projection matrix for this camera
    /// In 2D, this creates an orthographic projection centered on the camera position
    pub fn getViewProjectionMatrix(self: Camera2D) Mat4 {
        const half_width = self.width / 2.0;
        const half_height = self.height / 2.0;

        const left = self.position.x - half_width;
        const right = self.position.x + half_width;
        const bottom = self.position.y + half_height; // Y-down in screen space
        const top = self.position.y - half_height;

        return Mat4.ortho(left, right, bottom, top, -1.0, 1.0);
    }

    /// Update camera size (call when window is resized)
    pub fn resize(self: *Camera2D, width: f32, height: f32) void {
        self.width = width;
        self.height = height;
    }

    /// Convert screen coordinates to world coordinates
    pub fn screenToWorld(self: Camera2D, screen_x: f32, screen_y: f32) Vec2 {
        const world_x = self.position.x + (screen_x - self.width / 2.0);
        const world_y = self.position.y + (screen_y - self.height / 2.0);
        return Vec2.init(world_x, world_y);
    }

    /// Convert world coordinates to screen coordinates
    pub fn worldToScreen(self: Camera2D, world_x: f32, world_y: f32) Vec2 {
        const screen_x = (world_x - self.position.x) + self.width / 2.0;
        const screen_y = (world_y - self.position.y) + self.height / 2.0;
        return Vec2.init(screen_x, screen_y);
    }
};

/// 3D Camera with perspective projection
pub const Camera3D = struct {
    position: Vec3,
    target: Vec3,
    up: Vec3,
    fov: f32, // Field of view in radians
    aspect: f32,
    near: f32,
    far: f32,

    /// Create a new 3D camera
    pub fn init(width: f32, height: f32) Camera3D {
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

    /// Get the view matrix (camera transform)
    pub fn getViewMatrix(self: Camera3D) Mat4 {
        return Mat4.lookAt(self.position, self.target, self.up);
    }

    /// Get the projection matrix
    pub fn getProjectionMatrix(self: Camera3D) Mat4 {
        return Mat4.perspective(self.fov, self.aspect, self.near, self.far);
    }

    /// Get combined view-projection matrix
    pub fn getViewProjectionMatrix(self: Camera3D) Mat4 {
        const view = self.getViewMatrix();
        const projection = self.getProjectionMatrix();
        return projection.mul(view);
    }

    /// Update aspect ratio (call when window is resized)
    pub fn resize(self: *Camera3D, width: f32, height: f32) void {
        self.aspect = width / height;
    }

    /// Move the camera forward/backward along its view direction
    pub fn moveForward(self: *Camera3D, distance: f32) void {
        const forward = self.target.sub(self.position).normalize();
        self.position = self.position.add(forward.mul(distance));
        self.target = self.target.add(forward.mul(distance));
    }

    /// Move the camera left/right
    pub fn moveRight(self: *Camera3D, distance: f32) void {
        const forward = self.target.sub(self.position).normalize();
        const right = forward.cross(self.up).normalize();
        self.position = self.position.add(right.mul(distance));
        self.target = self.target.add(right.mul(distance));
    }

    /// Move the camera up/down
    pub fn moveUp(self: *Camera3D, distance: f32) void {
        self.position = self.position.add(self.up.mul(distance));
        self.target = self.target.add(self.up.mul(distance));
    }

    /// Orbit around the target point
    pub fn orbit(self: *Camera3D, yaw: f32, pitch: f32) void {
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
    pub fn lookAt(self: *Camera3D, target: Vec3) void {
        self.target = target;
    }
};
