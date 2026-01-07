const std = @import("std");
const Allocator = std.mem.Allocator;

/// HDR image data loaded from Radiance RGBE format
pub const HdrImage = struct {
    width: u32,
    height: u32,
    /// RGB float data (3 floats per pixel, range 0.0+)
    pixels: []f32,
    allocator: Allocator,

    pub fn deinit(self: *HdrImage) void {
        self.allocator.free(self.pixels);
    }
};

/// Load a Radiance HDR (.hdr) file
/// Returns RGB float data with 3 components per pixel
pub fn loadHDR(allocator: Allocator, file_path: []const u8) !HdrImage {
    // Read the entire file
    const file = try std.fs.openFileAbsolute(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const file_data = try allocator.alloc(u8, file_size);
    defer allocator.free(file_data);

    _ = try file.readAll(file_data);

    // Parse HDR header
    var pos: usize = 0;

    // Check magic bytes
    if (!std.mem.startsWith(u8, file_data, "#?RADIANCE\n") and
        !std.mem.startsWith(u8, file_data, "#?RGBE\n")) {
        return error.InvalidHDRFormat;
    }

    // Skip to resolution line (starts with -Y)
    while (pos < file_data.len - 1) : (pos += 1) {
        if (file_data[pos] == '\n' and pos + 1 < file_data.len and file_data[pos + 1] == '-') {
            pos += 1;
            break;
        }
    }

    // Parse resolution line: "-Y height +X width"
    const resolution_line_start = pos;
    while (pos < file_data.len and file_data[pos] != '\n') : (pos += 1) {}
    const resolution_line = file_data[resolution_line_start..pos];

    var height: u32 = 0;
    var width: u32 = 0;

    // Parse the resolution line
    var it = std.mem.tokenizeAny(u8, resolution_line, " \t");
    const y_dir = it.next() orelse return error.InvalidResolution;
    if (!std.mem.eql(u8, y_dir, "-Y")) return error.InvalidResolution;

    const height_str = it.next() orelse return error.InvalidResolution;
    height = try std.fmt.parseInt(u32, height_str, 10);

    const x_dir = it.next() orelse return error.InvalidResolution;
    if (!std.mem.eql(u8, x_dir, "+X")) return error.InvalidResolution;

    const width_str = it.next() orelse return error.InvalidResolution;
    width = try std.fmt.parseInt(u32, width_str, 10);

    pos += 1; // Skip newline after resolution

    // Allocate output buffer (RGB floats)
    const pixel_count = width * height;
    const pixels = try allocator.alloc(f32, pixel_count * 3);
    errdefer allocator.free(pixels);

    // Decode RLE compressed scanlines
    const scanline_data = file_data[pos..];
    try decodeRGBE(scanline_data, pixels, width, height);

    return HdrImage{
        .width = width,
        .height = height,
        .pixels = pixels,
        .allocator = allocator,
    };
}

/// Decode RGBE data into RGB float array
fn decodeRGBE(data: []const u8, out: []f32, width: u32, height: u32) !void {
    var pos: usize = 0;
    var pixel_idx: usize = 0;

    var y: u32 = 0;
    while (y < height) : (y += 1) {
        // Check for new RLE format (scanlines > 8 and < 32768)
        if (width >= 8 and width < 32768 and pos + 4 <= data.len) {
            const r = data[pos];
            const g = data[pos + 1];
            const b = data[pos + 2];
            const e = data[pos + 3];

            if (r == 2 and g == 2 and b < 128) {
                // New RLE format
                const scanline_width = (@as(u32, b) << 8) | @as(u32, e);
                if (scanline_width != width) return error.InvalidScanlineWidth;

                pos += 4;
                try decodeScanlineRLE(data, &pos, out, pixel_idx, width);
                pixel_idx += width * 3;
                continue;
            }
        }

        // Old RLE format or uncompressed
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            if (pos + 4 > data.len) return error.UnexpectedEndOfFile;

            const r = data[pos];
            const g = data[pos + 1];
            const b = data[pos + 2];
            const e = data[pos + 3];
            pos += 4;

            // Check for run
            if (r == 1 and g == 1 and b == 1) {
                const count = @as(u32, e);
                if (x + count > width) return error.InvalidRun;

                // Repeat the previous pixel
                if (x == 0) return error.InvalidRun;

                const prev_r = out[pixel_idx - 3];
                const prev_g = out[pixel_idx - 2];
                const prev_b = out[pixel_idx - 1];

                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    out[pixel_idx] = prev_r;
                    out[pixel_idx + 1] = prev_g;
                    out[pixel_idx + 2] = prev_b;
                    pixel_idx += 3;
                }
                x += count - 1;
            } else {
                // Regular pixel
                rgbeToFloat(r, g, b, e, out[pixel_idx..pixel_idx + 3]);
                pixel_idx += 3;
            }
        }
    }
}

/// Decode a single RLE-compressed scanline (new format)
fn decodeScanlineRLE(data: []const u8, pos: *usize, out: []f32, start_idx: usize, width: u32) !void {
    // Allocate temporary buffers for each channel
    var temp_buf: [4096]u8 = undefined;
    if (width > temp_buf.len) return error.ScanlineTooWide;

    // Decode each of 4 channels
    var channel: u8 = 0;
    while (channel < 4) : (channel += 1) {
        var x: u32 = 0;
        const channel_offset = @as(usize, channel) * width;
        while (x < width) {
            if (pos.* >= data.len) return error.UnexpectedEndOfFile;

            const code = data[pos.*];
            pos.* += 1;

            if (code > 128) {
                // Run
                const count = code - 128;
                if (x + count > width) return error.InvalidRun;
                if (pos.* >= data.len) return error.UnexpectedEndOfFile;

                const value = data[pos.*];
                pos.* += 1;

                var i: u8 = 0;
                while (i < count) : (i += 1) {
                    temp_buf[channel_offset + x] = value;
                    x += 1;
                }
            } else {
                // Non-run
                const count = code;
                if (x + count > width) return error.InvalidRun;
                if (pos.* + count > data.len) return error.UnexpectedEndOfFile;

                var i: u8 = 0;
                while (i < count) : (i += 1) {
                    temp_buf[channel_offset + x] = data[pos.*];
                    pos.* += 1;
                    x += 1;
                }
            }
        }
    }

    // Convert RGBE to float
    var i: u32 = 0;
    while (i < width) : (i += 1) {
        const r = temp_buf[i + width * 0];
        const g = temp_buf[i + width * 1];
        const b = temp_buf[i + width * 2];
        const e = temp_buf[i + width * 3];

        const out_idx = start_idx + i * 3;
        rgbeToFloat(r, g, b, e, out[out_idx..out_idx + 3]);
    }
}

/// Convert RGBE values to RGB float
fn rgbeToFloat(r: u8, g: u8, b: u8, e: u8, out: []f32) void {
    if (e == 0) {
        out[0] = 0.0;
        out[1] = 0.0;
        out[2] = 0.0;
    } else {
        // Radiance RGBE uses mantissa in [0..255], scale by 1/256.
        const f = std.math.ldexp(@as(f32, 1.0), @as(i32, @intCast(e)) - 136);
        out[0] = @as(f32, @floatFromInt(r)) * f;
        out[1] = @as(f32, @floatFromInt(g)) * f;
        out[2] = @as(f32, @floatFromInt(b)) * f;
    }
}
