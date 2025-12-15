const std = @import("std");
const math = @import("math/math.zig");
const Vec2 = math.Vec2;
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
