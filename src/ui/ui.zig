// ZDL UI Module
// Immediate-mode inspired UI system for in-game interfaces, debug overlays, menus, and HUDs

pub const UIContext = @import("ui_context.zig").UIContext;
pub const UIRenderer = @import("ui_renderer.zig").UIRenderer;
pub const Vertex2D = @import("ui_renderer.zig").Vertex2D;
pub const UIUniforms = @import("ui_renderer.zig").UIUniforms;

pub const Font = @import("font.zig").Font;
pub const Glyph = @import("font.zig").Glyph;

pub const Style = @import("style.zig").Style;
pub const Theme = @import("style.zig").Theme;
pub const Insets = @import("style.zig").Insets;

// Re-export common types from engine
pub const Color = @import("../engine/engine.zig").Color;
pub const Vec2 = @import("../math/vec2.zig").Vec2;

// Common UI types
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.width and
            py >= self.y and py < self.y + self.height;
    }

    pub fn right(self: Rect) f32 {
        return self.x + self.width;
    }

    pub fn bottom(self: Rect) f32 {
        return self.y + self.height;
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return self.x < other.right() and self.right() > other.x and
            self.y < other.bottom() and self.bottom() > other.y;
    }
};

pub const WidgetId = struct {
    hash: u64,

    pub fn from(comptime str: []const u8, index: usize) WidgetId {
        var hash: u64 = 14695981039346656037; // FNV-1a offset basis
        for (str) |c| {
            hash ^= c;
            hash *%= 1099511628211; // FNV-1a prime
        }
        hash ^= index;
        hash *%= 1099511628211;
        return .{ .hash = hash };
    }

    pub fn fromPtr(ptr: *const anyopaque) WidgetId {
        return .{ .hash = @intFromPtr(ptr) };
    }

    pub fn eql(self: WidgetId, other: WidgetId) bool {
        return self.hash == other.hash;
    }
};
