// ZDL Font System
// Text rendering with BMFont format support

const std = @import("std");
const sdl = @import("sdl3");
const Vec2 = @import("../math/vec2.zig").Vec2;
const Texture = @import("../resources/texture.zig").Texture;
const Color = @import("../render/render.zig").Color;
const UIRenderer = @import("ui_renderer.zig").UIRenderer;
const Rect = @import("ui.zig").Rect;

/// Single glyph information
pub const Glyph = struct {
    /// UV coordinates in atlas (normalized 0-1)
    uv: Rect,
    /// Glyph size in pixels
    width: f32,
    height: f32,
    /// Offset from cursor position to top-left of glyph
    offset_x: f32,
    offset_y: f32,
    /// Horizontal advance after rendering this glyph
    advance: f32,
};

/// Font for text rendering
pub const Font = struct {
    allocator: std.mem.Allocator,
    device: ?*sdl.gpu.Device,
    /// Font atlas texture
    texture: ?Texture,
    /// Glyph lookup by Unicode codepoint
    glyphs: std.AutoHashMap(u32, Glyph),
    /// Font metrics
    line_height: f32,
    base: f32,
    /// Atlas dimensions for UV calculation
    atlas_width: f32,
    atlas_height: f32,

    pub fn init(allocator: std.mem.Allocator) Font {
        return .{
            .allocator = allocator,
            .device = null,
            .texture = null,
            .glyphs = std.AutoHashMap(u32, Glyph).init(allocator),
            .line_height = 16,
            .base = 12,
            .atlas_width = 256,
            .atlas_height = 256,
        };
    }

    pub fn deinit(self: *Font) void {
        if (self.texture) |tex| {
            if (self.device) |dev| {
                dev.releaseTexture(tex.gpu_texture);
                if (tex.sampler) |s| dev.releaseSampler(s);
            }
        }
        self.glyphs.deinit();
    }

    /// Load a BMFont format font (.fnt file)
    pub fn loadBMFont(allocator: std.mem.Allocator, device: *sdl.gpu.Device, fnt_path: []const u8) !Font {
        var font = Font.init(allocator);
        font.device = device;
        errdefer font.deinit();

        // Read the .fnt file
        const fnt_data = try std.fs.cwd().readFileAlloc(allocator, fnt_path, 1024 * 1024);
        defer allocator.free(fnt_data);

        // Get directory of .fnt file for relative texture paths
        const dir_path = std.fs.path.dirname(fnt_path) orelse ".";

        // Parse BMFont text format
        var lines = std.mem.splitScalar(u8, fnt_data, '\n');
        var texture_file: ?[]const u8 = null;
        defer if (texture_file) |tf| allocator.free(tf);

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            if (std.mem.startsWith(u8, trimmed, "common ")) {
                // Parse common line for line height and base
                font.line_height = parseAttr(trimmed, "lineHeight") orelse 16;
                font.base = parseAttr(trimmed, "base") orelse 12;
                font.atlas_width = parseAttr(trimmed, "scaleW") orelse 256;
                font.atlas_height = parseAttr(trimmed, "scaleH") orelse 256;
            } else if (std.mem.startsWith(u8, trimmed, "page ")) {
                // Parse page line for texture file
                if (parseStringAttr(trimmed, "file")) |file| {
                    texture_file = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, file });
                }
            } else if (std.mem.startsWith(u8, trimmed, "char ")) {
                // Parse char line for glyph data
                const id = @as(u32, @intFromFloat(parseAttr(trimmed, "id") orelse continue));
                const x = parseAttr(trimmed, "x") orelse 0;
                const y = parseAttr(trimmed, "y") orelse 0;
                const w = parseAttr(trimmed, "width") orelse 0;
                const h = parseAttr(trimmed, "height") orelse 0;
                const xoffset = parseAttr(trimmed, "xoffset") orelse 0;
                const yoffset = parseAttr(trimmed, "yoffset") orelse 0;
                const xadvance = parseAttr(trimmed, "xadvance") orelse w;

                const glyph = Glyph{
                    .uv = Rect.init(
                        x / font.atlas_width,
                        y / font.atlas_height,
                        w / font.atlas_width,
                        h / font.atlas_height,
                    ),
                    .width = w,
                    .height = h,
                    .offset_x = xoffset,
                    .offset_y = yoffset,
                    .advance = xadvance,
                };

                try font.glyphs.put(id, glyph);
            }
        }

        // Load texture
        if (texture_file) |tex_path| {
            var tex = try Texture.load(device, tex_path);
            // Create a sampler for the font texture
            tex.sampler = try device.createSampler(.{
                .min_filter = .nearest,
                .mag_filter = .nearest,
                .mipmap_mode = .nearest,
                .address_mode_u = .clamp_to_edge,
                .address_mode_v = .clamp_to_edge,
                .address_mode_w = .clamp_to_edge,
            });
            font.texture = tex;
        }

        return font;
    }

    /// Create a simple built-in font (ASCII only, monospace)
    pub fn createBuiltin(allocator: std.mem.Allocator, device: *sdl.gpu.Device) !Font {
        var font = Font.init(allocator);
        font.device = device;
        errdefer font.deinit();

        // Create a simple 8x16 bitmap font texture (16x6 grid = 96 characters)
        const char_width: u32 = 8;
        const char_height: u32 = 16;
        const chars_per_row: u32 = 16;
        const rows: u32 = 6;
        const tex_width: u32 = char_width * chars_per_row; // 128
        const tex_height: u32 = char_height * rows; // 96

        font.atlas_width = @floatFromInt(tex_width);
        font.atlas_height = @floatFromInt(tex_height);
        font.line_height = @floatFromInt(char_height);
        font.base = @floatFromInt(char_height - 2);

        // Create texture data with simple bitmap patterns
        const pixels = try allocator.alloc(u8, tex_width * tex_height * 4);
        defer allocator.free(pixels);
        @memset(pixels, 0);

        // Generate basic ASCII glyphs (32-127)
        for (32..128) |c| {
            const char_index = c - 32;
            const grid_x = char_index % chars_per_row;
            const grid_y = char_index / chars_per_row;

            // Add glyph to map
            const glyph = Glyph{
                .uv = Rect.init(
                    @as(f32, @floatFromInt(grid_x * char_width)) / font.atlas_width,
                    @as(f32, @floatFromInt(grid_y * char_height)) / font.atlas_height,
                    @as(f32, @floatFromInt(char_width)) / font.atlas_width,
                    @as(f32, @floatFromInt(char_height)) / font.atlas_height,
                ),
                .width = @floatFromInt(char_width),
                .height = @floatFromInt(char_height),
                .offset_x = 0,
                .offset_y = 0,
                .advance = @floatFromInt(char_width),
            };
            try font.glyphs.put(@intCast(c), glyph);

            // Draw simple glyph pattern
            drawBuiltinGlyph(
                pixels,
                tex_width,
                @intCast(grid_x * char_width),
                @intCast(grid_y * char_height),
                char_width,
                char_height,
                @intCast(c),
            );
        }

        // Create texture from pixel data
        font.texture = try Texture.createFromRGBA(device, tex_width, tex_height, pixels);

        return font;
    }

    /// Get glyph for a codepoint (returns null if not found)
    pub fn getGlyph(self: *const Font, codepoint: u32) ?Glyph {
        return self.glyphs.get(codepoint);
    }

    /// Measure text dimensions
    pub fn measureText(self: *const Font, text: []const u8) Vec2 {
        var width: f32 = 0;
        var max_width: f32 = 0;
        var lines: f32 = 1;

        for (text) |c| {
            if (c == '\n') {
                max_width = @max(max_width, width);
                width = 0;
                lines += 1;
                continue;
            }

            if (self.getGlyph(c)) |glyph| {
                width += glyph.advance;
            }
        }

        max_width = @max(max_width, width);
        return Vec2.init(max_width, lines * self.line_height);
    }

    /// Draw text using the UI renderer
    pub fn drawText(
        self: *const Font,
        renderer: *UIRenderer,
        text: []const u8,
        x: f32,
        y: f32,
        color: Color,
    ) void {
        if (self.texture == null) return;

        var cursor_x = x;
        var cursor_y = y;

        for (text) |c| {
            if (c == '\n') {
                cursor_x = x;
                cursor_y += self.line_height;
                continue;
            }

            if (self.getGlyph(c)) |glyph| {
                const dest_rect = Rect.init(
                    cursor_x + glyph.offset_x,
                    cursor_y + glyph.offset_y,
                    glyph.width,
                    glyph.height,
                );

                renderer.drawTexturedRect(
                    dest_rect,
                    self.texture.?,
                    glyph.uv,
                    color,
                );

                cursor_x += glyph.advance;
            }
        }
    }
};

/// Parse a numeric attribute from a BMFont line
fn parseAttr(line: []const u8, name: []const u8) ?f32 {
    const search = std.fmt.allocPrint(std.heap.page_allocator, "{s}=", .{name}) catch return null;
    defer std.heap.page_allocator.free(search);

    const start = std.mem.indexOf(u8, line, search) orelse return null;
    const value_start = start + search.len;

    // Find end of value (space or end of line)
    var value_end = value_start;
    while (value_end < line.len and line[value_end] != ' ' and line[value_end] != '\t') {
        value_end += 1;
    }

    const value_str = line[value_start..value_end];
    return std.fmt.parseFloat(f32, value_str) catch null;
}

/// Parse a string attribute from a BMFont line
fn parseStringAttr(line: []const u8, name: []const u8) ?[]const u8 {
    const search = std.fmt.allocPrint(std.heap.page_allocator, "{s}=\"", .{name}) catch return null;
    defer std.heap.page_allocator.free(search);

    const start = std.mem.indexOf(u8, line, search) orelse return null;
    const value_start = start + search.len;

    // Find closing quote
    const value_end = std.mem.indexOfPos(u8, line, value_start, "\"") orelse return null;

    return line[value_start..value_end];
}

/// Draw a simple built-in glyph pattern
fn drawBuiltinGlyph(pixels: []u8, tex_width: u32, start_x: u32, start_y: u32, width: u32, height: u32, char: u8) void {
    // Simple 5x7 font patterns for ASCII characters
    const patterns = getBuiltinPatterns();

    const char_idx = if (char >= 32 and char < 128) char - 32 else 0;
    const pattern = patterns[@intCast(char_idx)];

    // Center the 5x7 pattern in the 8x16 cell
    const offset_x: u32 = 1;
    const offset_y: u32 = 4;

    for (0..7) |py| {
        const row = pattern[py];
        for (0..5) |px| {
            const bit = @as(u3, @intCast(4 - px));
            if ((row >> bit) & 1 == 1) {
                const pixel_x = start_x + offset_x + @as(u32, @intCast(px));
                const pixel_y = start_y + offset_y + @as(u32, @intCast(py));
                if (pixel_x < tex_width and pixel_y < tex_width) {
                    const idx = (pixel_y * tex_width + pixel_x) * 4;
                    if (idx + 3 < pixels.len) {
                        pixels[idx + 0] = 255; // R
                        pixels[idx + 1] = 255; // G
                        pixels[idx + 2] = 255; // B
                        pixels[idx + 3] = 255; // A
                    }
                }
            }
        }
    }
    _ = width;
    _ = height;
}

/// Get built-in 5x7 font patterns for ASCII 32-127
fn getBuiltinPatterns() [96][7]u8 {
    return .{
        // Space (32)
        .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000 },
        // ! (33)
        .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100 },
        // " (34)
        .{ 0b01010, 0b01010, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000 },
        // # (35)
        .{ 0b01010, 0b11111, 0b01010, 0b01010, 0b11111, 0b01010, 0b00000 },
        // $ (36)
        .{ 0b00100, 0b01111, 0b10100, 0b01110, 0b00101, 0b11110, 0b00100 },
        // % (37)
        .{ 0b11001, 0b11010, 0b00100, 0b01000, 0b01011, 0b10011, 0b00000 },
        // & (38)
        .{ 0b01100, 0b10010, 0b01100, 0b10101, 0b10010, 0b01101, 0b00000 },
        // ' (39)
        .{ 0b00100, 0b00100, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000 },
        // ( (40)
        .{ 0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010 },
        // ) (41)
        .{ 0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000 },
        // * (42)
        .{ 0b00000, 0b00100, 0b10101, 0b01110, 0b10101, 0b00100, 0b00000 },
        // + (43)
        .{ 0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000 },
        // , (44)
        .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00110, 0b00100, 0b01000 },
        // - (45)
        .{ 0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000 },
        // . (46)
        .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00110, 0b00110 },
        // / (47)
        .{ 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b00000, 0b00000 },
        // 0 (48)
        .{ 0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110 },
        // 1 (49)
        .{ 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        // 2 (50)
        .{ 0b01110, 0b10001, 0b00001, 0b00110, 0b01000, 0b10000, 0b11111 },
        // 3 (51)
        .{ 0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110 },
        // 4 (52)
        .{ 0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010 },
        // 5 (53)
        .{ 0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110 },
        // 6 (54)
        .{ 0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 },
        // 7 (55)
        .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000 },
        // 8 (56)
        .{ 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110 },
        // 9 (57)
        .{ 0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100 },
        // : (58)
        .{ 0b00000, 0b00110, 0b00110, 0b00000, 0b00110, 0b00110, 0b00000 },
        // ; (59)
        .{ 0b00000, 0b00110, 0b00110, 0b00000, 0b00110, 0b00100, 0b01000 },
        // < (60)
        .{ 0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010 },
        // = (61)
        .{ 0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000 },
        // > (62)
        .{ 0b01000, 0b00100, 0b00010, 0b00001, 0b00010, 0b00100, 0b01000 },
        // ? (63)
        .{ 0b01110, 0b10001, 0b00001, 0b00110, 0b00100, 0b00000, 0b00100 },
        // @ (64)
        .{ 0b01110, 0b10001, 0b10111, 0b10101, 0b10110, 0b10000, 0b01110 },
        // A (65)
        .{ 0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        // B (66)
        .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110 },
        // C (67)
        .{ 0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110 },
        // D (68)
        .{ 0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110 },
        // E (69)
        .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 },
        // F (70)
        .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000 },
        // G (71)
        .{ 0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111 },
        // H (72)
        .{ 0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        // I (73)
        .{ 0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        // J (74)
        .{ 0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100 },
        // K (75)
        .{ 0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001 },
        // L (76)
        .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 },
        // M (77)
        .{ 0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001 },
        // N (78)
        .{ 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001 },
        // O (79)
        .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        // P (80)
        .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000 },
        // Q (81)
        .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101 },
        // R (82)
        .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 },
        // S (83)
        .{ 0b01110, 0b10001, 0b10000, 0b01110, 0b00001, 0b10001, 0b01110 },
        // T (84)
        .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
        // U (85)
        .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        // V (86)
        .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 },
        // W (87)
        .{ 0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001 },
        // X (88)
        .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001 },
        // Y (89)
        .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100 },
        // Z (90)
        .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111 },
        // [ (91)
        .{ 0b01110, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110 },
        // \ (92)
        .{ 0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0b00000, 0b00000 },
        // ] (93)
        .{ 0b01110, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110 },
        // ^ (94)
        .{ 0b00100, 0b01010, 0b10001, 0b00000, 0b00000, 0b00000, 0b00000 },
        // _ (95)
        .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111 },
        // ` (96)
        .{ 0b01000, 0b00100, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000 },
        // a (97)
        .{ 0b00000, 0b00000, 0b01110, 0b00001, 0b01111, 0b10001, 0b01111 },
        // b (98)
        .{ 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b11110 },
        // c (99)
        .{ 0b00000, 0b00000, 0b01110, 0b10000, 0b10000, 0b10001, 0b01110 },
        // d (100)
        .{ 0b00001, 0b00001, 0b01111, 0b10001, 0b10001, 0b10001, 0b01111 },
        // e (101)
        .{ 0b00000, 0b00000, 0b01110, 0b10001, 0b11111, 0b10000, 0b01110 },
        // f (102)
        .{ 0b00110, 0b01000, 0b11110, 0b01000, 0b01000, 0b01000, 0b01000 },
        // g (103)
        .{ 0b00000, 0b01111, 0b10001, 0b10001, 0b01111, 0b00001, 0b01110 },
        // h (104)
        .{ 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b10001 },
        // i (105)
        .{ 0b00100, 0b00000, 0b01100, 0b00100, 0b00100, 0b00100, 0b01110 },
        // j (106)
        .{ 0b00010, 0b00000, 0b00110, 0b00010, 0b00010, 0b10010, 0b01100 },
        // k (107)
        .{ 0b10000, 0b10000, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010 },
        // l (108)
        .{ 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        // m (109)
        .{ 0b00000, 0b00000, 0b11010, 0b10101, 0b10101, 0b10101, 0b10101 },
        // n (110)
        .{ 0b00000, 0b00000, 0b11110, 0b10001, 0b10001, 0b10001, 0b10001 },
        // o (111)
        .{ 0b00000, 0b00000, 0b01110, 0b10001, 0b10001, 0b10001, 0b01110 },
        // p (112)
        .{ 0b00000, 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000 },
        // q (113)
        .{ 0b00000, 0b01111, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001 },
        // r (114)
        .{ 0b00000, 0b00000, 0b10110, 0b11000, 0b10000, 0b10000, 0b10000 },
        // s (115)
        .{ 0b00000, 0b00000, 0b01111, 0b10000, 0b01110, 0b00001, 0b11110 },
        // t (116)
        .{ 0b01000, 0b01000, 0b11110, 0b01000, 0b01000, 0b01000, 0b00110 },
        // u (117)
        .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10001, 0b10011, 0b01101 },
        // v (118)
        .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 },
        // w (119)
        .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10101, 0b10101, 0b01010 },
        // x (120)
        .{ 0b00000, 0b00000, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001 },
        // y (121)
        .{ 0b00000, 0b10001, 0b10001, 0b10001, 0b01111, 0b00001, 0b01110 },
        // z (122)
        .{ 0b00000, 0b00000, 0b11111, 0b00010, 0b00100, 0b01000, 0b11111 },
        // { (123)
        .{ 0b00110, 0b01000, 0b01000, 0b10000, 0b01000, 0b01000, 0b00110 },
        // | (124)
        .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
        // } (125)
        .{ 0b01100, 0b00010, 0b00010, 0b00001, 0b00010, 0b00010, 0b01100 },
        // ~ (126)
        .{ 0b00000, 0b00000, 0b01000, 0b10101, 0b00010, 0b00000, 0b00000 },
        // DEL (127) - blank
        .{ 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000 },
    };
}
