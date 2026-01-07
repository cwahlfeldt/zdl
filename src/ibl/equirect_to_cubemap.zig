const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const HdrImage = @import("hdr_loader.zig").HdrImage;
const Cubemap = @import("../resources/cubemap.zig").Cubemap;
const CubeFace = @import("../resources/cubemap.zig").CubeFace;
const sdl = @import("sdl3");

/// Convert equirectangular HDR image to cubemap
pub fn equirectToCubemap(
    allocator: Allocator,
    device: *sdl.gpu.Device,
    hdr: *const HdrImage,
    cubemap_size: u32,
    mip_levels: u32,
) !Cubemap {
    const levels = @max(mip_levels, 1);
    // Create cubemap with mip levels
    var cubemap = try Cubemap.init(device, cubemap_size, levels, .r16g16b16a16_float, .{ .sampler = true });
    errdefer cubemap.deinit(device);

    // Convert each face
    const faces = [_]CubeFace{
        .positive_x,
        .negative_x,
        .positive_y,
        .negative_y,
        .positive_z,
        .negative_z,
    };

    for (0..levels) |mip| {
        const mip_u32: u32 = @intCast(mip);
        const shift: u5 = @intCast(mip_u32);
        const mip_size = @max(@as(u32, 1), cubemap_size >> shift);

        // Allocate face data buffer for this mip (RGBA16F = 8 bytes per pixel)
        const face_byte_size = mip_size * mip_size * 8;
        const face_data = try allocator.alloc(u8, face_byte_size);
        defer allocator.free(face_data);

        for (faces) |face| {
            try renderCubeFace(hdr, face, mip_size, face_data);
            var mutable_cubemap = cubemap;
            try mutable_cubemap.uploadFace(device, face, mip_u32, face_data);
        }
    }

    return cubemap;
}

/// Render a single cubemap face from equirectangular map
fn renderCubeFace(
    hdr: *const HdrImage,
    face: CubeFace,
    size: u32,
    out_data: []u8,
) !void {
    const pixels_f16 = std.mem.bytesAsSlice(f16, out_data);

    var y: u32 = 0;
    while (y < size) : (y += 1) {
        var x: u32 = 0;
        while (x < size) : (x += 1) {
            // Convert pixel coordinates to [-1, 1] range
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(size)) * 2.0 - 1.0;
            const v = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(size)) * 2.0 - 1.0;

            // Get 3D direction vector for this pixel
            const dir = cubemapDirection(face, u, v).normalize();

            // Sample equirectangular map
            const color = sampleEquirect(hdr, dir);

            // Write RGBA16F
            const pixel_idx = (y * size + x) * 4;
            pixels_f16[pixel_idx + 0] = @as(f16, @floatCast(color[0]));
            pixels_f16[pixel_idx + 1] = @as(f16, @floatCast(color[1]));
            pixels_f16[pixel_idx + 2] = @as(f16, @floatCast(color[2]));
            pixels_f16[pixel_idx + 3] = @as(f16, @floatCast(1.0));
        }
    }
}

/// Get 3D direction vector for a cubemap face pixel
fn cubemapDirection(face: CubeFace, u: f32, v: f32) Vec3 {
    return switch (face) {
        .positive_x => Vec3.init(1.0, -v, -u),
        .negative_x => Vec3.init(-1.0, -v, u),
        .positive_y => Vec3.init(u, 1.0, v),
        .negative_y => Vec3.init(u, -1.0, -v),
        .positive_z => Vec3.init(u, -v, 1.0),
        .negative_z => Vec3.init(-u, -v, -1.0),
    };
}

/// Sample equirectangular map using a 3D direction vector
fn sampleEquirect(hdr: *const HdrImage, dir: Vec3) [3]f32 {
    // Convert direction to spherical coordinates
    const phi = std.math.atan2(dir.z, dir.x);
    const theta = std.math.asin(dir.y);

    // Convert to UV coordinates [0, 1]
    const u = (phi / (2.0 * std.math.pi) + 0.5);
    const v = (theta / std.math.pi + 0.5);

    // Convert to pixel coordinates
    const fx = u * @as(f32, @floatFromInt(hdr.width));
    const fy = v * @as(f32, @floatFromInt(hdr.height));

    // Clamp to valid range
    const x = @as(u32, @intFromFloat(@max(0.0, @min(@as(f32, @floatFromInt(hdr.width - 1)), fx))));
    const y = @as(u32, @intFromFloat(@max(0.0, @min(@as(f32, @floatFromInt(hdr.height - 1)), fy))));

    // Sample pixel
    const pixel_idx = (y * hdr.width + x) * 3;
    return [3]f32{
        hdr.pixels[pixel_idx + 0],
        hdr.pixels[pixel_idx + 1],
        hdr.pixels[pixel_idx + 2],
    };
}

/// Generate pre-filtered environment map with multiple mip levels
/// Each mip level represents increasingly rough reflections
pub fn generatePrefilteredMap(
    allocator: Allocator,
    device: *sdl.gpu.Device,
    base_cubemap: *const Cubemap,
    mip_levels: u32,
) !Cubemap {
    _ = allocator;

    // Create cubemap with multiple mip levels using base cubemap size
    const prefiltered = try Cubemap.init(device, base_cubemap.size, mip_levels, .r16g16b16a16_float, .{ .sampler = true });
    errdefer prefiltered.deinit(device);

    // TODO: Implement GGX pre-filtering for each mip level
    // For now, just return empty cubemap

    return prefiltered;
}

/// Generate irradiance map from environment cubemap
/// This is a diffuse convolution of the environment
pub fn generateIrradianceMap(
    allocator: Allocator,
    device: *sdl.gpu.Device,
    env_cubemap: *const Cubemap,
) !Cubemap {
    _ = allocator;
    _ = env_cubemap;

    const irradiance_size = 32; // Small size for diffuse irradiance

    // Create irradiance cubemap
    const irradiance = try Cubemap.init(device, irradiance_size, 1, .r16g16b16a16_float, .{ .sampler = true });
    errdefer irradiance.deinit(device);

    // TODO: Implement diffuse convolution
    // For now, return empty cubemap

    return irradiance;
}
