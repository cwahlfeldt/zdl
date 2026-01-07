const std = @import("std");
const sdl = @import("sdl3");

/// Cubemap face indices for uploading data
pub const CubeFace = enum(u32) {
    positive_x = 0, // Right
    negative_x = 1, // Left
    positive_y = 2, // Top
    negative_y = 3, // Bottom
    positive_z = 4, // Front
    negative_z = 5, // Back
};

/// Cubemap texture resource for environment mapping
pub const Cubemap = struct {
    texture: sdl.gpu.Texture,
    size: u32,
    mip_levels: u32,
    format: sdl.gpu.TextureFormat,

    /// Initialize a new cubemap texture
    pub fn init(
        device: *sdl.gpu.Device,
        size: u32,
        mip_levels: u32,
        format: sdl.gpu.TextureFormat,
        usage: sdl.gpu.TextureUsageFlags,
    ) !Cubemap {
        const gpu_texture = try device.createTexture(.{
            .texture_type = .cube,
            .format = format,
            .width = size,
            .height = size,
            .layer_count_or_depth = 6, // 6 faces for cubemap
            .num_levels = mip_levels,
            .sample_count = .no_multisampling,
            .usage = usage,
        });

        return .{
            .texture = gpu_texture,
            .size = size,
            .mip_levels = mip_levels,
            .format = format,
        };
    }

    /// Release the cubemap texture
    pub fn deinit(self: *Cubemap, device: *sdl.gpu.Device) void {
        device.releaseTexture(self.texture);
    }

    /// Upload data to a specific face and mip level
    pub fn uploadFace(
        self: *Cubemap,
        device: *sdl.gpu.Device,
        face: CubeFace,
        mip: u32,
        data: []const u8,
    ) !void {
        const mip_size = self.size >> @intCast(mip);
        const bytes_per_pixel = getBytesPerPixel(self.format);
        const expected_size = mip_size * mip_size * bytes_per_pixel;

        if (data.len < expected_size) {
            return error.InsufficientData;
        }

        // Create transfer buffer
        const transfer_buffer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = expected_size,
        });
        defer device.releaseTransferBuffer(transfer_buffer);

        // Copy data to transfer buffer
        const transfer_data = try device.mapTransferBuffer(transfer_buffer, false);
        const transfer_bytes = @as([*]u8, @ptrCast(transfer_data));
        @memcpy(transfer_bytes[0..expected_size], data[0..expected_size]);
        device.unmapTransferBuffer(transfer_buffer);

        // Upload to GPU
        const cmd = try device.acquireCommandBuffer();
        {
            const copy_pass = cmd.beginCopyPass();
            defer copy_pass.end();

            copy_pass.uploadToTexture(
                .{ .transfer_buffer = transfer_buffer, .offset = 0 },
                .{
                    .texture = self.texture,
                    .mip_level = mip,
                    .layer = @intFromEnum(face),
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .width = mip_size,
                    .height = mip_size,
                    .depth = 1,
                },
                false,
            );
        }
        try cmd.submit();
    }

    /// Create a solid-color cubemap (useful for testing or default environments)
    pub fn createSolid(
        device: *sdl.gpu.Device,
        size: u32,
        color: [4]f32,
        format: sdl.gpu.TextureFormat,
    ) !Cubemap {
        var cubemap = try init(device, size, 1, format, .{ .sampler = true });
        errdefer cubemap.deinit(device);

        const bytes_per_pixel = getBytesPerPixel(format);
        const face_size = size * size * bytes_per_pixel;

        // Allocate temporary buffer for one face
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        const face_data = try allocator.alloc(u8, face_size);
        defer allocator.free(face_data);

        // Fill with solid color (simplified - assumes RGBA16F)
        if (format == .r16g16b16a16_float) {
            const pixels_f16 = std.mem.bytesAsSlice(f16, face_data);
            var i: usize = 0;
            while (i < pixels_f16.len) : (i += 4) {
                pixels_f16[i] = @floatCast(color[0]);
                pixels_f16[i + 1] = @floatCast(color[1]);
                pixels_f16[i + 2] = @floatCast(color[2]);
                pixels_f16[i + 3] = @floatCast(color[3]);
            }
        } else if (format == .r8g8b8a8_unorm) {
            var i: usize = 0;
            while (i < face_data.len) : (i += 4) {
                face_data[i] = @intFromFloat(color[0] * 255.0);
                face_data[i + 1] = @intFromFloat(color[1] * 255.0);
                face_data[i + 2] = @intFromFloat(color[2] * 255.0);
                face_data[i + 3] = @intFromFloat(color[3] * 255.0);
            }
        }

        // Upload to all 6 faces
        inline for (std.meta.fields(CubeFace)) |field| {
            const face: CubeFace = @enumFromInt(field.value);
            try cubemap.uploadFace(device, face, 0, face_data);
        }

        return cubemap;
    }
};

/// Helper function to get bytes per pixel for a texture format
fn getBytesPerPixel(format: sdl.gpu.TextureFormat) u32 {
    return switch (format) {
        .r8g8b8a8_unorm => 4,
        .r16g16b16a16_float => 8,
        .r32g32b32a32_float => 16,
        .r16g16_float => 4,
        .r8g8_unorm => 2,
        else => 4, // Default fallback
    };
}
