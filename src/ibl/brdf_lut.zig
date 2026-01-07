const std = @import("std");
const sdl = @import("sdl3");
const Texture = @import("../resources/texture.zig").Texture;

/// BRDF Integration Lookup Table
/// Pre-computed lookup table for the split-sum approximation
/// Stores scale and bias factors for specular IBL
pub const BrdfLut = struct {
    texture: Texture,

    /// Generate BRDF LUT using GPU rendering
    /// Size is typically 512x512
    pub fn generate(
        allocator: std.mem.Allocator,
        device: *sdl.gpu.Device,
        size: u32,
    ) !BrdfLut {
        _ = allocator; // Reserved for future use

        // Create render target texture (RG16F format for scale/bias)
        const gpu_texture = try device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .r16g16_float,
            .width = size,
            .height = size,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .no_multisampling,
            .usage = .{ .sampler = true, .color_target = true },
        });
        errdefer device.releaseTexture(gpu_texture);

        const texture = Texture{
            .gpu_texture = gpu_texture,
            .width = size,
            .height = size,
        };

        // TODO: Load and compile BRDF LUT shaders
        // TODO: Create graphics pipeline for BRDF LUT generation
        // TODO: Render fullscreen quad to generate the LUT
        // For now, we'll return the texture and implement shader loading later
        // when we integrate with the engine's shader system

        return .{
            .texture = texture,
        };
    }

    /// Generate BRDF LUT on CPU (fallback method)
    /// This is slower but doesn't require shader compilation
    pub fn generateCPU(
        allocator: std.mem.Allocator,
        device: *sdl.gpu.Device,
        size: u32,
    ) !BrdfLut {
        // Allocate pixel data for RG16F
        const pixel_count = size * size;
        const byte_count = pixel_count * 4; // 2 channels * 2 bytes (f16)
        const pixels = try allocator.alloc(u8, byte_count);
        defer allocator.free(pixels);

        // Cast to f16 array for easier manipulation
        const pixels_f16 = std.mem.bytesAsSlice(f16, pixels);

        // Generate BRDF integration for each pixel
        for (0..size) |y| {
            for (0..size) |x| {
                const u: f32 = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(size));
                const v: f32 = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(size));

                // u = NdotV, v = roughness
                const NdotV = std.math.clamp(u, 0.001, 0.999);
                const roughness = std.math.clamp(v, 0.001, 0.999);

                const result = integrateBRDF(NdotV, roughness);

                const idx = (y * size + x) * 2;
                pixels_f16[idx] = @floatCast(result.scale);
                pixels_f16[idx + 1] = @floatCast(result.bias);
            }
        }

        // Create GPU texture
        const gpu_texture = try device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .r16g16_float,
            .width = size,
            .height = size,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .no_multisampling,
            .usage = .{ .sampler = true },
        });
        errdefer device.releaseTexture(gpu_texture);

        // Upload to GPU
        const transfer_buffer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = byte_count,
        });
        defer device.releaseTransferBuffer(transfer_buffer);

        const transfer_data = try device.mapTransferBuffer(transfer_buffer, false);
        const transfer_bytes = @as([*]u8, @ptrCast(transfer_data));
        @memcpy(transfer_bytes[0..byte_count], pixels);
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
                    .width = size,
                    .height = size,
                    .depth = 1,
                },
                false,
            );
        }
        try cmd.submit();

        return .{
            .texture = .{
                .gpu_texture = gpu_texture,
                .width = size,
                .height = size,
            },
        };
    }

    pub fn deinit(self: *BrdfLut, device: *sdl.gpu.Device) void {
        self.texture.deinit(device);
    }
};

const BRDFResult = struct {
    scale: f32,
    bias: f32,
};

/// CPU-based BRDF integration using Monte Carlo sampling
fn integrateBRDF(NdotV: f32, roughness: f32) BRDFResult {
    // View vector in tangent space
    const sin_theta = @sqrt(1.0 - NdotV * NdotV);
    const V = Vec3{ .x = sin_theta, .y = 0.0, .z = NdotV };
    const N = Vec3{ .x = 0.0, .y = 0.0, .z = 1.0 };

    var A: f32 = 0.0;
    var B: f32 = 0.0;

    const SAMPLE_COUNT = 1024;
    for (0..SAMPLE_COUNT) |i| {
        const Xi = hammersley(@intCast(i), SAMPLE_COUNT);
        const H = importanceSampleGGX(Xi, N, roughness);
        const L = reflect(V, H);

        const NdotL = @max(L.z, 0.0);
        const NdotH = @max(H.z, 0.0);
        const VdotH = @max(dot(V, H), 0.0);

        if (NdotL > 0.0) {
            const G = geometrySmith(NdotV, NdotL, roughness);
            const G_Vis = (G * VdotH) / (NdotH * NdotV);
            const Fc = std.math.pow(f32, 1.0 - VdotH, 5.0);

            A += (1.0 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }

    A /= @as(f32, @floatFromInt(SAMPLE_COUNT));
    B /= @as(f32, @floatFromInt(SAMPLE_COUNT));

    return .{ .scale = A, .bias = B };
}

const Vec2 = struct { x: f32, y: f32 };
const Vec3 = struct { x: f32, y: f32, z: f32 };

/// Hammersley low-discrepancy sequence
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

/// Importance sampling of GGX distribution
fn importanceSampleGGX(Xi: Vec2, N: Vec3, roughness: f32) Vec3 {
    const PI = std.math.pi;
    const a = roughness * roughness;

    const phi = 2.0 * PI * Xi.x;
    const cos_theta = @sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
    const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);

    // Tangent space
    const H_tangent = Vec3{
        .x = @cos(phi) * sin_theta,
        .y = @sin(phi) * sin_theta,
        .z = cos_theta,
    };

    // Build TBN
    const up = if (@abs(N.z) < 0.999) Vec3{ .x = 0.0, .y = 0.0, .z = 1.0 } else Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const tangent = normalize(cross(up, N));
    const bitangent = cross(N, tangent);

    // Transform to world space
    const sample = Vec3{
        .x = tangent.x * H_tangent.x + bitangent.x * H_tangent.y + N.x * H_tangent.z,
        .y = tangent.y * H_tangent.x + bitangent.y * H_tangent.y + N.y * H_tangent.z,
        .z = tangent.z * H_tangent.x + bitangent.z * H_tangent.y + N.z * H_tangent.z,
    };

    return normalize(sample);
}

fn geometrySchlickGGX(NdotV: f32, roughness: f32) f32 {
    const a = roughness;
    const k = (a * a) / 2.0;

    const nom = NdotV;
    const denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

fn geometrySmith(NdotV: f32, NdotL: f32, roughness: f32) f32 {
    const ggx2 = geometrySchlickGGX(NdotV, roughness);
    const ggx1 = geometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

fn dot(a: Vec3, b: Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

fn normalize(v: Vec3) Vec3 {
    const len = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return .{
        .x = v.x / len,
        .y = v.y / len,
        .z = v.z / len,
    };
}

fn reflect(V: Vec3, H: Vec3) Vec3 {
    const d = dot(V, H);
    return .{
        .x = 2.0 * d * H.x - V.x,
        .y = 2.0 * d * H.y - V.y,
        .z = 2.0 * d * H.z - V.z,
    };
}
