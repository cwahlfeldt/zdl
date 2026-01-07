const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const HdrImage = @import("hdr_loader.zig").HdrImage;
const Cubemap = @import("../resources/cubemap.zig").Cubemap;
const CubeFace = @import("../resources/cubemap.zig").CubeFace;
const sdl = @import("sdl3");

const Vec2 = struct {
    x: f32,
    y: f32,
};

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

    for (faces) |face| {
        var prev_size = cubemap_size;
        var prev_data = try allocator.alloc(u8, prev_size * prev_size * 8);

        try renderCubeFace(hdr, face, prev_size, prev_data);
        var mutable_cubemap = cubemap;
        try mutable_cubemap.uploadFace(device, face, 0, prev_data);

        var mip: u32 = 1;
        while (mip < levels) : (mip += 1) {
            const shift: u5 = @intCast(mip);
            const mip_size = @max(@as(u32, 1), cubemap_size >> shift);
            const mip_data = try allocator.alloc(u8, mip_size * mip_size * 8);

            downsampleFaceF16(prev_data, prev_size, mip_data, mip_size);
            try mutable_cubemap.uploadFace(device, face, mip, mip_data);

            allocator.free(prev_data);
            prev_data = mip_data;
            prev_size = mip_size;
        }

        allocator.free(prev_data);
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

fn downsampleFaceF16(prev_data: []const u8, prev_size: u32, out_data: []u8, out_size: u32) void {
    const prev_pixels = std.mem.bytesAsSlice(f16, prev_data);
    const out_pixels = std.mem.bytesAsSlice(f16, out_data);

    var y: u32 = 0;
    while (y < out_size) : (y += 1) {
        var x: u32 = 0;
        while (x < out_size) : (x += 1) {
            const src_x = x * 2;
            const src_y = y * 2;

            var accum: [4]f32 = .{ 0, 0, 0, 0 };
            var dy: u32 = 0;
            while (dy < 2) : (dy += 1) {
                var dx: u32 = 0;
                while (dx < 2) : (dx += 1) {
                    const px = src_x + dx;
                    const py = src_y + dy;
                    const idx = (py * prev_size + px) * 4;
                    accum[0] += @as(f32, @floatCast(prev_pixels[idx + 0]));
                    accum[1] += @as(f32, @floatCast(prev_pixels[idx + 1]));
                    accum[2] += @as(f32, @floatCast(prev_pixels[idx + 2]));
                    accum[3] += @as(f32, @floatCast(prev_pixels[idx + 3]));
                }
            }

            const out_idx = (y * out_size + x) * 4;
            out_pixels[out_idx + 0] = @as(f16, @floatCast(accum[0] * 0.25));
            out_pixels[out_idx + 1] = @as(f16, @floatCast(accum[1] * 0.25));
            out_pixels[out_idx + 2] = @as(f16, @floatCast(accum[2] * 0.25));
            out_pixels[out_idx + 3] = @as(f16, @floatCast(accum[3] * 0.25));
        }
    }
}

fn prefilterFace(
    hdr: *const HdrImage,
    face: CubeFace,
    size: u32,
    roughness: f32,
    sample_count: u32,
    out_data: []u8,
) !void {
    const pixels_f16 = std.mem.bytesAsSlice(f16, out_data);
    const rough = std.math.clamp(roughness, 0.0, 1.0);

    var y: u32 = 0;
    while (y < size) : (y += 1) {
        var x: u32 = 0;
        while (x < size) : (x += 1) {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(size)) * 2.0 - 1.0;
            const v = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(size)) * 2.0 - 1.0;
            const N = cubemapDirection(face, u, v).normalize();
            const V = N;

            var prefiltered = Vec3.zero();
            var total_weight: f32 = 0.0;

            var i: u32 = 0;
            while (i < sample_count) : (i += 1) {
                const Xi = hammersley(i, sample_count);
                const H = importanceSampleGGX(Xi, N, rough);
                const VdotH = Vec3.dot(V, H);
                const L = Vec3.sub(Vec3.mul(H, 2.0 * VdotH), V).normalize();
                const NdotL = @max(Vec3.dot(N, L), 0.0);
                if (NdotL > 0.0) {
                    const sample = sampleEquirect(hdr, L);
                    prefiltered = Vec3.add(prefiltered, Vec3.mul(Vec3.init(sample[0], sample[1], sample[2]), NdotL));
                    total_weight += NdotL;
                }
            }

            const inv_weight = if (total_weight > 0.0) 1.0 / total_weight else 0.0;
            const color = Vec3.mul(prefiltered, inv_weight);

            const pixel_idx = (y * size + x) * 4;
            pixels_f16[pixel_idx + 0] = @as(f16, @floatCast(color.x));
            pixels_f16[pixel_idx + 1] = @as(f16, @floatCast(color.y));
            pixels_f16[pixel_idx + 2] = @as(f16, @floatCast(color.z));
            pixels_f16[pixel_idx + 3] = @as(f16, @floatCast(1.0));
        }
    }
}

fn irradianceFace(
    hdr: *const HdrImage,
    face: CubeFace,
    size: u32,
    out_data: []u8,
) !void {
    const pixels_f16 = std.mem.bytesAsSlice(f16, out_data);
    const sample_count: u32 = 64;

    var y: u32 = 0;
    while (y < size) : (y += 1) {
        var x: u32 = 0;
        while (x < size) : (x += 1) {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(size)) * 2.0 - 1.0;
            const v = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(size)) * 2.0 - 1.0;
            const N = cubemapDirection(face, u, v).normalize();

            const tbn = buildTangentFrame(N);
            var irradiance = Vec3.zero();

            var i: u32 = 0;
            while (i < sample_count) : (i += 1) {
                const Xi = hammersley(i, sample_count);
                const L = uniformSampleHemisphere(Xi, tbn);
                const NdotL = @max(Vec3.dot(N, L), 0.0);
                if (NdotL > 0.0) {
                    const sample = sampleEquirect(hdr, L);
                    irradiance = Vec3.add(irradiance, Vec3.mul(Vec3.init(sample[0], sample[1], sample[2]), NdotL));
                }
            }

            const scale = (2.0 * std.math.pi) / @as(f32, @floatFromInt(sample_count));
            irradiance = Vec3.mul(irradiance, scale);

            const pixel_idx = (y * size + x) * 4;
            pixels_f16[pixel_idx + 0] = @as(f16, @floatCast(irradiance.x));
            pixels_f16[pixel_idx + 1] = @as(f16, @floatCast(irradiance.y));
            pixels_f16[pixel_idx + 2] = @as(f16, @floatCast(irradiance.z));
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

fn hammersley(i: u32, N: u32) Vec2 {
    var bits = i;
    bits = (bits << 16) | (bits >> 16);
    bits = ((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1);
    bits = ((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2);
    bits = ((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4);
    bits = ((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8);
    const radical_inverse = @as(f32, @floatFromInt(bits)) * 2.3283064365386963e-10;

    return .{
        .x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(N)),
        .y = radical_inverse,
    };
}

fn buildTangentFrame(n: Vec3) struct { t: Vec3, b: Vec3, n: Vec3 } {
    const up = if (@abs(n.z) < 0.999) Vec3.init(0.0, 0.0, 1.0) else Vec3.init(1.0, 0.0, 0.0);
    const t = Vec3.cross(up, n).normalize();
    const b = Vec3.cross(n, t);
    return .{ .t = t, .b = b, .n = n };
}

fn uniformSampleHemisphere(xi: Vec2, tbn: anytype) Vec3 {
    const phi = 2.0 * std.math.pi * xi.x;
    const cos_theta = 1.0 - xi.y;
    const sin_theta = @sqrt(@max(0.0, 1.0 - cos_theta * cos_theta));
    const H = Vec3.init(@cos(phi) * sin_theta, @sin(phi) * sin_theta, cos_theta);
    return Vec3.add(
        Vec3.add(Vec3.mul(tbn.t, H.x), Vec3.mul(tbn.b, H.y)),
        Vec3.mul(tbn.n, H.z),
    ).normalize();
}

fn importanceSampleGGX(xi: Vec2, n: Vec3, roughness: f32) Vec3 {
    const a = roughness * roughness;
    const phi = 2.0 * std.math.pi * xi.x;
    const cos_theta = @sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    const sin_theta = @sqrt(@max(0.0, 1.0 - cos_theta * cos_theta));

    const H = Vec3.init(@cos(phi) * sin_theta, @sin(phi) * sin_theta, cos_theta);
    const tbn = buildTangentFrame(n);

    return Vec3.add(
        Vec3.add(Vec3.mul(tbn.t, H.x), Vec3.mul(tbn.b, H.y)),
        Vec3.mul(tbn.n, H.z),
    ).normalize();
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

/// Generate prefiltered environment map from an HDR equirectangular image.
/// Uses GGX importance sampling per mip level.
pub fn generatePrefilteredFromHDR(
    allocator: Allocator,
    device: *sdl.gpu.Device,
    hdr: *const HdrImage,
    base_size: u32,
    mip_levels: u32,
) !Cubemap {
    const levels = @max(mip_levels, 1);
    var prefiltered = try Cubemap.init(device, base_size, levels, .r16g16b16a16_float, .{ .sampler = true });
    errdefer prefiltered.deinit(device);

    const faces = [_]CubeFace{
        .positive_x,
        .negative_x,
        .positive_y,
        .negative_y,
        .positive_z,
        .negative_z,
    };

    const max_mip = if (levels > 1) @as(f32, @floatFromInt(levels - 1)) else 1.0;
    const base_samples: u32 = 64;

    for (faces) |face| {
        var mip: u32 = 0;
        while (mip < levels) : (mip += 1) {
            const shift: u5 = @intCast(mip);
            const mip_size = @max(@as(u32, 1), base_size >> shift);
            const mip_data = try allocator.alloc(u8, mip_size * mip_size * 8);
            defer allocator.free(mip_data);

            const roughness = if (levels > 1)
                @as(f32, @floatFromInt(mip)) / max_mip
            else
                0.0;
            const sample_count = @max(@as(u32, 16), base_samples >> @intCast(mip));

            try prefilterFace(hdr, face, mip_size, roughness, sample_count, mip_data);

            var mutable_prefiltered = prefiltered;
            try mutable_prefiltered.uploadFace(device, face, mip, mip_data);
        }
    }

    return prefiltered;
}

/// Generate irradiance map directly from an HDR equirectangular image.
pub fn generateIrradianceFromHDR(
    allocator: Allocator,
    device: *sdl.gpu.Device,
    hdr: *const HdrImage,
    size: u32,
) !Cubemap {
    var irradiance = try Cubemap.init(device, size, 1, .r16g16b16a16_float, .{ .sampler = true });
    errdefer irradiance.deinit(device);

    const faces = [_]CubeFace{
        .positive_x,
        .negative_x,
        .positive_y,
        .negative_y,
        .positive_z,
        .negative_z,
    };

    for (faces) |face| {
        const face_data = try allocator.alloc(u8, size * size * 8);
        defer allocator.free(face_data);

        try irradianceFace(hdr, face, size, face_data);

        var mutable_irradiance = irradiance;
        try mutable_irradiance.uploadFace(device, face, 0, face_data);
    }

    return irradiance;
}
