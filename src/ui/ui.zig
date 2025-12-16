const std = @import("std");
const sprite = @import("../renderer/sprite.zig");
const SpriteBatch = sprite.SpriteBatch;
const Color = sprite.Color;

/// Simple bitmap font for rendering numbers and text
/// This is a minimal implementation that renders text using colored rectangles
/// For production use, consider implementing proper bitmap font texture support
pub const BitmapFont = struct {
    char_width: f32,
    char_height: f32,
    spacing: f32,

    pub fn init(char_width: f32, char_height: f32, spacing: f32) BitmapFont {
        return .{
            .char_width = char_width,
            .char_height = char_height,
            .spacing = spacing,
        };
    }

    /// Render a number at the given position
    pub fn renderNumber(
        self: BitmapFont,
        batch: *SpriteBatch,
        number: i32,
        x: f32,
        y: f32,
        color: Color,
    ) !void {
        var buffer: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buffer, "{d}", .{number});
        try self.renderText(batch, text, x, y, color);
    }

    /// Render text at the given position
    /// Note: This is a simplified version that just draws rectangles
    /// For proper text rendering, you'd use a bitmap font texture
    pub fn renderText(
        self: BitmapFont,
        batch: *SpriteBatch,
        text: []const u8,
        x: f32,
        y: f32,
        color: Color,
    ) !void {
        var current_x = x;

        for (text) |char| {
            // Draw a simple representation of each character
            // In a real implementation, you'd use UV coordinates from a font atlas
            if (char != ' ') {
                try batch.addQuad(
                    current_x + self.char_width / 2,
                    y,
                    self.char_width,
                    self.char_height,
                    color,
                );
            }

            current_x += self.char_width + self.spacing;
        }
    }

    /// Get the width of text in pixels
    pub fn getTextWidth(self: BitmapFont, text: []const u8) f32 {
        return @as(f32, @floatFromInt(text.len)) * (self.char_width + self.spacing);
    }
};

/// Simple HUD element for displaying scores, health, etc.
pub const HUD = struct {
    font: BitmapFont,

    pub fn init(font: BitmapFont) HUD {
        return .{
            .font = font,
        };
    }

    /// Draw a score in the top-left corner
    pub fn drawScore(
        self: HUD,
        batch: *SpriteBatch,
        score: i32,
        screen_width: f32,
        screen_height: f32,
    ) !void {
        const x = -screen_width / 2 + 20;
        const y = -screen_height / 2 + 20;
        try self.font.renderNumber(batch, score, x, y, Color.white());
    }

    /// Draw text at a specific position
    pub fn drawText(
        self: HUD,
        batch: *SpriteBatch,
        text: []const u8,
        x: f32,
        y: f32,
        color: Color,
    ) !void {
        try self.font.renderText(batch, text, x, y, color);
    }

    /// Draw centered text
    pub fn drawTextCentered(
        self: HUD,
        batch: *SpriteBatch,
        text: []const u8,
        y: f32,
        color: Color,
    ) !void {
        const width = self.font.getTextWidth(text);
        try self.font.renderText(batch, text, -width / 2, y, color);
    }

    /// Draw a health bar
    pub fn drawHealthBar(
        self: HUD,
        batch: *SpriteBatch,
        current_health: f32,
        max_health: f32,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    ) !void {
        _ = self;

        // Background (dark red)
        try batch.addQuad(
            x,
            y,
            width,
            height,
            Color{ .r = 0.3, .g = 0.0, .b = 0.0, .a = 1.0 },
        );

        // Foreground (bright red/green based on health)
        const health_ratio = @max(0.0, @min(1.0, current_health / max_health));
        const health_width = width * health_ratio;

        const r: f32 = if (health_ratio < 0.5) 1.0 else (1.0 - health_ratio) * 2.0;
        const g: f32 = if (health_ratio > 0.5) 1.0 else health_ratio * 2.0;

        try batch.addQuad(
            x - (width - health_width) / 2,
            y,
            health_width,
            height,
            Color{ .r = r, .g = g, .b = 0.0, .a = 1.0 },
        );
    }
};
