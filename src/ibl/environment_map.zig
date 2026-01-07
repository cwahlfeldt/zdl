const std = @import("std");
const sdl = @import("sdl3");
const Cubemap = @import("../resources/cubemap.zig").Cubemap;
const CubeFace = @import("../resources/cubemap.zig").CubeFace;

/// Environment map for Image-Based Lighting
/// Contains pre-filtered irradiance and specular reflections
pub const EnvironmentMap = struct {
    irradiance: Cubemap, // Diffuse IBL (typically 32x32)
    prefiltered: Cubemap, // Specular IBL with mip levels (typically 256x256)
    max_mip_level: f32, // Maximum mip level for roughness mapping

    /// Load environment from HDR equirectangular file
    pub fn loadFromHDR(
        allocator: std.mem.Allocator,
        device: *sdl.gpu.Device,
        path: []const u8,
    ) !EnvironmentMap {
        const loadHDR = @import("hdr_loader.zig").loadHDR;
        const generatePrefilteredFromHDR = @import("equirect_to_cubemap.zig").generatePrefilteredFromHDR;
        const generateIrradianceFromHDR = @import("equirect_to_cubemap.zig").generateIrradianceFromHDR;

        // 1. Load HDR file (Radiance .hdr format)
        var hdr_image = try loadHDR(allocator, path);
        defer hdr_image.deinit();

        // 2. Generate prefiltered cubemap (GGX importance sampling)
        const prefilter_mips: u32 = 5; // 128, 64, 32, 16, 8
        const env_cubemap = try generatePrefilteredFromHDR(allocator, device, &hdr_image, 128, prefilter_mips);

        // 3. Generate irradiance map (diffuse convolution)
        const irradiance_cubemap = try generateIrradianceFromHDR(allocator, device, &hdr_image, 32);

        // 4. Calculate max mip level for pre-filtered map
        const max_mip = @as(f32, @floatFromInt(prefilter_mips - 1));

        return .{
            .irradiance = irradiance_cubemap,
            .prefiltered = env_cubemap,
            .max_mip_level = max_mip,
        };
    }

    /// Load pre-computed environment maps from files
    pub fn loadPrecomputed(
        allocator: std.mem.Allocator,
        device: *sdl.gpu.Device,
        irr_path: []const u8,
        prefilter_path: []const u8,
    ) !EnvironmentMap {
        _ = allocator;
        _ = device;
        _ = irr_path;
        _ = prefilter_path;

        // TODO: Implement loading of pre-baked cubemap files
        // Expected format: KTX or custom format with all 6 faces + mips

        return error.NotImplemented;
    }

    /// Create a default neutral environment (for testing)
    pub fn createDefault(
        device: *sdl.gpu.Device,
    ) !EnvironmentMap {
        // Create small neutral gray environment
        var irradiance = try Cubemap.createSolid(
            device,
            32,
            [4]f32{ 0.5, 0.5, 0.5, 1.0 },
            .r16g16b16a16_float,
        );
        errdefer irradiance.deinit(device);

        // Create pre-filtered with 5 mip levels
        var prefiltered = try Cubemap.init(
            device,
            256,
            5,
            .r16g16b16a16_float,
            .{ .sampler = true },
        );
        errdefer prefiltered.deinit(device);

        // Fill all mip levels with gray (in a real implementation, each mip
        // would have increasing roughness blur)
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        for (0..5) |mip| {
            const mip_u32: u32 = @intCast(mip);
            const mip_size: u32 = 256 / std.math.pow(u32, 2, mip_u32);
            const face_size = mip_size * mip_size * 8; // RGBA16F = 8 bytes/pixel

            const face_data = try allocator.alloc(u8, face_size);
            defer allocator.free(face_data);

            const pixels_f16 = std.mem.bytesAsSlice(f16, face_data);
            var i: usize = 0;
            while (i < pixels_f16.len) : (i += 4) {
                pixels_f16[i] = @as(f16, @floatCast(0.5));
                pixels_f16[i + 1] = @as(f16, @floatCast(0.5));
                pixels_f16[i + 2] = @as(f16, @floatCast(0.5));
                pixels_f16[i + 3] = @as(f16, @floatCast(1.0));
            }

            // Upload to all 6 faces
            inline for (std.meta.fields(CubeFace)) |field| {
                const face: CubeFace = @enumFromInt(field.value);
                var mutable_prefiltered = prefiltered;
                try mutable_prefiltered.uploadFace(device, face, @intCast(mip), face_data);
            }
        }

        return .{
            .irradiance = irradiance,
            .prefiltered = prefiltered,
            .max_mip_level = 4.0, // 5 levels: 0, 1, 2, 3, 4
        };
    }

    pub fn deinit(self: *EnvironmentMap, device: *sdl.gpu.Device) void {
        self.irradiance.deinit(device);
        self.prefiltered.deinit(device);
    }
};
