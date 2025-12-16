const std = @import("std");

pub const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub fn zero() Vec4 {
        return .{ .x = 0, .y = 0, .z = 0, .w = 0 };
    }

    pub fn add(a: Vec4, b: Vec4) Vec4 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z, .w = a.w + b.w };
    }

    pub fn sub(a: Vec4, b: Vec4) Vec4 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z, .w = a.w - b.w };
    }

    pub fn mul(a: Vec4, scalar: f32) Vec4 {
        return .{ .x = a.x * scalar, .y = a.y * scalar, .z = a.z * scalar, .w = a.w * scalar };
    }

    pub fn div(a: Vec4, scalar: f32) Vec4 {
        return .{ .x = a.x / scalar, .y = a.y / scalar, .z = a.z / scalar, .w = a.w / scalar };
    }

    pub fn dot(a: Vec4, b: Vec4) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    }

    pub fn length(self: Vec4) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
    }

    pub fn normalize(self: Vec4) Vec4 {
        const len = self.length();
        if (len == 0) return zero();
        return self.div(len);
    }
};
