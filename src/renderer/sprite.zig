const std = @import("std");
const math = @import("../math/math.zig");
const Vec2 = math.Vec2;

/// Vertex format for sprite rendering (position + color)
pub const SpriteVertex = struct {
    x: f32,
    y: f32,
    z: f32, // Position (z for layering)
    r: f32,
    g: f32,
    b: f32,
    a: f32, // Color
};

/// Color helper
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn white() Color {
        return .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    }

    pub fn red() Color {
        return .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    }

    pub fn green() Color {
        return .{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    }

    pub fn blue() Color {
        return .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    }

    pub fn yellow() Color {
        return .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    }

    pub fn black() Color {
        return .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    }
};

/// Sprite batch for rendering multiple quads efficiently
pub const SpriteBatch = struct {
    vertices: std.ArrayList(SpriteVertex),
    allocator: std.mem.Allocator,
    max_sprites: usize,

    pub fn init(allocator: std.mem.Allocator, max_sprites: usize) SpriteBatch {
        return .{
            .vertices = std.ArrayList(SpriteVertex){},
            .allocator = allocator,
            .max_sprites = max_sprites,
        };
    }

    pub fn deinit(self: *SpriteBatch) void {
        self.vertices.deinit(self.allocator);
    }

    /// Clear all sprites from the batch
    pub fn clear(self: *SpriteBatch) void {
        self.vertices.clearRetainingCapacity();
    }

    /// Add a colored quad to the batch
    /// Position is the center of the quad
    pub fn addQuad(self: *SpriteBatch, x: f32, y: f32, width: f32, height: f32, color: Color) !void {
        const half_w = width / 2.0;
        const half_h = height / 2.0;

        const z: f32 = 0.0; // Z-depth for 2D (can be used for layering)

        // Two triangles forming a quad (counter-clockwise winding)
        // Triangle 1: top-left, bottom-left, bottom-right
        // Triangle 2: top-left, bottom-right, top-right

        try self.vertices.append(self.allocator, .{ .x = x - half_w, .y = y - half_h, .z = z, .r = color.r, .g = color.g, .b = color.b, .a = color.a }); // top-left
        try self.vertices.append(self.allocator, .{ .x = x - half_w, .y = y + half_h, .z = z, .r = color.r, .g = color.g, .b = color.b, .a = color.a }); // bottom-left
        try self.vertices.append(self.allocator, .{ .x = x + half_w, .y = y + half_h, .z = z, .r = color.r, .g = color.g, .b = color.b, .a = color.a }); // bottom-right

        try self.vertices.append(self.allocator, .{ .x = x - half_w, .y = y - half_h, .z = z, .r = color.r, .g = color.g, .b = color.b, .a = color.a }); // top-left
        try self.vertices.append(self.allocator, .{ .x = x + half_w, .y = y + half_h, .z = z, .r = color.r, .g = color.g, .b = color.b, .a = color.a }); // bottom-right
        try self.vertices.append(self.allocator, .{ .x = x + half_w, .y = y - half_h, .z = z, .r = color.r, .g = color.g, .b = color.b, .a = color.a }); // top-right
    }

    /// Get the vertex data for rendering
    pub fn getVertices(self: *SpriteBatch) []const SpriteVertex {
        return self.vertices.items;
    }

    /// Get the number of vertices
    pub fn getVertexCount(self: *SpriteBatch) u32 {
        return @intCast(self.vertices.items.len);
    }
};
