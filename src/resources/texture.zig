const std = @import("std");
const sdl = @import("sdl3");
const Color = @import("../render/render.zig").Color;

/// Texture resource that wraps SDL GPU texture
pub const Texture = struct {
    gpu_texture: sdl.gpu.Texture,
    sampler: ?sdl.gpu.Sampler = null,
    width: u32,
    height: u32,

    /// Load a texture from a file and upload it to the GPU
    pub fn loadFromFile(
        device: *sdl.gpu.Device,
        file_path: []const u8,
    ) !Texture {
        // Load the image using SDL_image
        // Create a null-terminated path (SDL requires [:0]const u8)
        var path_buffer: [4096]u8 = undefined;
        if (file_path.len >= path_buffer.len) return error.PathTooLong;
        @memcpy(path_buffer[0..file_path.len], file_path);
        path_buffer[file_path.len] = 0;
        const path_z: [:0]const u8 = path_buffer[0..file_path.len :0];

        const surface = sdl.image.loadFile(path_z) catch return error.FailedToLoadImage;
        defer surface.deinit();

        const width: u32 = @intCast(surface.getWidth());
        const height: u32 = @intCast(surface.getHeight());

        // Convert surface to RGBA8 if needed
        const rgba_surface = if (surface.getFormat() != sdl.pixels.Format.array_rgba_32)
            try surface.convertFormat(sdl.pixels.Format.array_rgba_32)
        else
            surface;
        defer if (surface.getFormat() != sdl.pixels.Format.array_rgba_32) rgba_surface.deinit();

        // Get pixel data
        const pixels = rgba_surface.getPixels() orelse return error.NoPixelData;
        const pitch = rgba_surface.getPitch();
        const expected_pitch = width * 4; // RGBA = 4 bytes per pixel

        // Create GPU texture
        const gpu_texture = try device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .r8g8b8a8_unorm,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .no_multisampling,
            .usage = .{ .sampler = true },
        });
        errdefer device.releaseTexture(gpu_texture);

        // Create transfer buffer for uploading pixel data
        const transfer_size = width * height * 4;
        const transfer_buffer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = transfer_size,
        });
        defer device.releaseTransferBuffer(transfer_buffer);

        // Copy pixel data to transfer buffer
        const transfer_data = try device.mapTransferBuffer(transfer_buffer, false);
        const transfer_bytes = @as([*]u8, @ptrCast(transfer_data));

        if (pitch == expected_pitch) {
            // Direct copy if pitch matches
            @memcpy(transfer_bytes[0..transfer_size], @as([*]const u8, @ptrCast(pixels))[0..transfer_size]);
        } else {
            // Copy row by row if pitch doesn't match
            const src_bytes = @as([*]const u8, @ptrCast(pixels));
            for (0..height) |row| {
                const src_offset = row * pitch;
                const dst_offset = row * expected_pitch;
                @memcpy(
                    transfer_bytes[dst_offset .. dst_offset + expected_pitch],
                    src_bytes[src_offset .. src_offset + expected_pitch],
                );
            }
        }

        device.unmapTransferBuffer(transfer_buffer);

        // Upload to GPU texture
        const cmd = try device.acquireCommandBuffer();
        {
            const copy_pass = cmd.beginCopyPass();
            defer copy_pass.end();

            copy_pass.uploadToTexture(
                .{ .transfer_buffer = transfer_buffer, .offset = 0 },
                .{
                    .texture = gpu_texture,
                    .mip_level = 0,
                    .layer = 0,
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                false,
            );
        }
        try cmd.submit();

        return .{
            .gpu_texture = gpu_texture,
            .width = width,
            .height = height,
        };
    }

    /// Create a simple colored texture (for testing without image files)
    pub fn createColored(
        device: *sdl.gpu.Device,
        width: u32,
        height: u32,
        color: [4]u8,
    ) !Texture {
        const gpu_texture = try device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .r8g8b8a8_unorm,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .no_multisampling,
            .usage = .{ .sampler = true },
        });
        errdefer device.releaseTexture(gpu_texture);

        const transfer_size = width * height * 4;
        const transfer_buffer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = transfer_size,
        });
        defer device.releaseTransferBuffer(transfer_buffer);

        // Fill with solid color
        const transfer_data = try device.mapTransferBuffer(transfer_buffer, false);
        const pixels = @as([*]u8, @ptrCast(transfer_data));

        var i: usize = 0;
        while (i < transfer_size) : (i += 4) {
            pixels[i] = color[0]; // R
            pixels[i + 1] = color[1]; // G
            pixels[i + 2] = color[2]; // B
            pixels[i + 3] = color[3]; // A
        }

        device.unmapTransferBuffer(transfer_buffer);

        // Upload to GPU
        const cmd = try device.acquireCommandBuffer();
        {
            const copy_pass = cmd.beginCopyPass();
            defer copy_pass.end();

            copy_pass.uploadToTexture(
                .{ .transfer_buffer = transfer_buffer, .offset = 0 },
                .{
                    .texture = gpu_texture,
                    .mip_level = 0,
                    .layer = 0,
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                false,
            );
        }
        try cmd.submit();

        return .{
            .gpu_texture = gpu_texture,
            .width = width,
            .height = height,
        };
    }

    /// Load a texture from in-memory image data (PNG, JPG, etc.)
    pub fn loadFromMemory(
        device: *sdl.gpu.Device,
        data: []const u8,
    ) !Texture {
        // Load the image from memory using SDL's IOStream
        const stream = sdl.io_stream.Stream.initFromConstMem(data) catch return error.InvalidData;
        // close_when_done=true means loadIo will close the stream for us
        const surface = sdl.image.loadIo(stream, true) catch return error.InvalidImageFormat;
        defer surface.deinit();

        const width: u32 = @intCast(surface.getWidth());
        const height: u32 = @intCast(surface.getHeight());

        // Convert surface to RGBA8 if needed
        const rgba_surface = if (surface.getFormat() != sdl.pixels.Format.array_rgba_32)
            try surface.convertFormat(sdl.pixels.Format.array_rgba_32)
        else
            surface;
        defer if (surface.getFormat() != sdl.pixels.Format.array_rgba_32) rgba_surface.deinit();

        // Get pixel data
        const pixels = rgba_surface.getPixels() orelse return error.NoPixelData;
        const pitch = rgba_surface.getPitch();
        const expected_pitch = width * 4;

        // Create GPU texture
        const gpu_texture = try device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .r8g8b8a8_unorm,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .no_multisampling,
            .usage = .{ .sampler = true },
        });
        errdefer device.releaseTexture(gpu_texture);

        // Create transfer buffer for uploading pixel data
        const transfer_size = width * height * 4;
        const transfer_buffer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = transfer_size,
        });
        defer device.releaseTransferBuffer(transfer_buffer);

        // Copy pixel data to transfer buffer
        const transfer_data = try device.mapTransferBuffer(transfer_buffer, false);
        const transfer_bytes = @as([*]u8, @ptrCast(transfer_data));

        if (pitch == expected_pitch) {
            @memcpy(transfer_bytes[0..transfer_size], @as([*]const u8, @ptrCast(pixels))[0..transfer_size]);
        } else {
            const src_bytes = @as([*]const u8, @ptrCast(pixels));
            for (0..height) |row| {
                const src_offset = row * pitch;
                const dst_offset = row * expected_pitch;
                @memcpy(
                    transfer_bytes[dst_offset .. dst_offset + expected_pitch],
                    src_bytes[src_offset .. src_offset + expected_pitch],
                );
            }
        }

        device.unmapTransferBuffer(transfer_buffer);

        // Upload to GPU texture
        const cmd = try device.acquireCommandBuffer();
        {
            const copy_pass = cmd.beginCopyPass();
            defer copy_pass.end();

            copy_pass.uploadToTexture(
                .{ .transfer_buffer = transfer_buffer, .offset = 0 },
                .{
                    .texture = gpu_texture,
                    .mip_level = 0,
                    .layer = 0,
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                false,
            );
        }
        try cmd.submit();

        return .{
            .gpu_texture = gpu_texture,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: Texture, device: *sdl.gpu.Device) void {
        device.releaseTexture(self.gpu_texture);
        if (self.sampler) |s| device.releaseSampler(s);
    }

    /// Alias for loadFromFile for consistency
    pub fn load(device: *sdl.gpu.Device, path: []const u8) !Texture {
        return loadFromFile(device, path);
    }

    /// Create a solid color texture with its own sampler
    pub fn createSolid(device: *sdl.gpu.Device, width: u32, height: u32, color: Color) !Texture {
        const color_bytes = [4]u8{
            @intFromFloat(color.r * 255.0),
            @intFromFloat(color.g * 255.0),
            @intFromFloat(color.b * 255.0),
            @intFromFloat(color.a * 255.0),
        };

        var tex = try createColored(device, width, height, color_bytes);

        // Create a sampler for this texture
        tex.sampler = try device.createSampler(.{
            .min_filter = .nearest,
            .mag_filter = .nearest,
            .mipmap_mode = .nearest,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });

        return tex;
    }

    /// Create a texture from raw RGBA pixel data with its own sampler
    pub fn createFromRGBA(device: *sdl.gpu.Device, width: u32, height: u32, pixels: []const u8) !Texture {
        const gpu_texture = try device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .r8g8b8a8_unorm,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .no_multisampling,
            .usage = .{ .sampler = true },
        });
        errdefer device.releaseTexture(gpu_texture);

        const transfer_size = width * height * 4;
        const transfer_buffer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = transfer_size,
        });
        defer device.releaseTransferBuffer(transfer_buffer);

        const transfer_data = try device.mapTransferBuffer(transfer_buffer, false);
        const dest = @as([*]u8, @ptrCast(transfer_data));
        @memcpy(dest[0..transfer_size], pixels[0..transfer_size]);
        device.unmapTransferBuffer(transfer_buffer);

        const cmd = try device.acquireCommandBuffer();
        {
            const copy_pass = cmd.beginCopyPass();
            defer copy_pass.end();

            copy_pass.uploadToTexture(
                .{ .transfer_buffer = transfer_buffer, .offset = 0 },
                .{
                    .texture = gpu_texture,
                    .mip_level = 0,
                    .layer = 0,
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                false,
            );
        }
        try cmd.submit();

        // Create a sampler for this texture
        const sampler = try device.createSampler(.{
            .min_filter = .nearest,
            .mag_filter = .nearest,
            .mipmap_mode = .nearest,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });

        return .{
            .gpu_texture = gpu_texture,
            .sampler = sampler,
            .width = width,
            .height = height,
        };
    }
};
