const std = @import("std");
const asset_types = @import("asset_types.zig");

const AssetType = asset_types.AssetType;
const ProcessResult = asset_types.ProcessResult;
const Platform = asset_types.Platform;
const QualityPreset = asset_types.QualityPreset;
const Allocator = std.mem.Allocator;

/// Interface for asset processors
pub const Processor = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        process: *const fn (
            ptr: *anyopaque,
            input_path: []const u8,
            output_path: []const u8,
            config: ProcessConfig,
        ) ProcessResult,
        getSupportedTypes: *const fn (ptr: *anyopaque) []const AssetType,
        getName: *const fn (ptr: *anyopaque) []const u8,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn process(
        self: Processor,
        input_path: []const u8,
        output_path: []const u8,
        config: ProcessConfig,
    ) ProcessResult {
        return self.vtable.process(self.ptr, input_path, output_path, config);
    }

    pub fn getSupportedTypes(self: Processor) []const AssetType {
        return self.vtable.getSupportedTypes(self.ptr);
    }

    pub fn getName(self: Processor) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    pub fn deinit(self: Processor) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Configuration passed to processors
pub const ProcessConfig = struct {
    allocator: Allocator,
    platform: Platform,
    quality: QualityPreset,
    verbose: bool = false,
    force: bool = false,

    /// Custom options per processor type
    shader: ShaderOptions = .{},
    texture: TextureOptions = .{},
    mesh: MeshOptions = .{},
    audio: AudioOptions = .{},

    pub const ShaderOptions = struct {
        debug_info: bool = false,
        optimization_level: OptLevel = .performance,
        defines: []const Define = &.{},
        include_paths: []const []const u8 = &.{},
    };

    pub const TextureOptions = struct {
        generate_mipmaps: bool = true,
        srgb: bool = true,
        max_size: ?u32 = null,
        compression: TextureCompression = .auto,
    };

    pub const MeshOptions = struct {
        optimize_vertex_cache: bool = true,
        generate_tangents: bool = true,
        generate_lods: bool = false,
        lod_count: u32 = 3,
    };

    pub const AudioOptions = struct {
        sample_rate: u32 = 44100,
        normalize: bool = true,
        compression: AudioCompression = .auto,
    };

    pub const OptLevel = enum {
        none,
        size,
        performance,
    };

    pub const Define = struct {
        name: []const u8,
        value: ?[]const u8 = null,
    };

    pub const TextureCompression = enum {
        none,
        auto,
        bc1,
        bc3,
        bc5,
        bc7,
        astc_4x4,
        astc_6x6,
        astc_8x8,
    };

    pub const AudioCompression = enum {
        none,
        auto,
        ogg,
        mp3,
        opus,
    };
};

/// Helper to create a Processor from a concrete implementation
pub fn makeProcessor(comptime T: type) Processor {
    const gen = struct {
        fn process(
            ptr: *anyopaque,
            input_path: []const u8,
            output_path: []const u8,
            config: ProcessConfig,
        ) ProcessResult {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.process(input_path, output_path, config);
        }

        fn getSupportedTypes(ptr: *anyopaque) []const AssetType {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getSupportedTypes();
        }

        fn getName(ptr: *anyopaque) []const u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getName();
        }

        fn deinit(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.deinit();
        }
    };

    return .{
        .ptr = undefined,
        .vtable = &.{
            .process = gen.process,
            .getSupportedTypes = gen.getSupportedTypes,
            .getName = gen.getName,
            .deinit = gen.deinit,
        },
    };
}
