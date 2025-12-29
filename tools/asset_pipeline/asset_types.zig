const std = @import("std");

/// Type of asset being processed
pub const AssetType = enum {
    texture,
    mesh,
    shader,
    audio,
    scene,
    font,
    script,
    unknown,

    /// Determine asset type from file extension
    pub fn fromExtension(ext: []const u8) AssetType {
        const extensions = std.StaticStringMap(AssetType).initComptime(.{
            // Textures
            .{ ".png", .texture },
            .{ ".jpg", .texture },
            .{ ".jpeg", .texture },
            .{ ".bmp", .texture },
            .{ ".tga", .texture },
            .{ ".dds", .texture },
            .{ ".ktx", .texture },
            .{ ".ktx2", .texture },

            // Meshes
            .{ ".gltf", .mesh },
            .{ ".glb", .mesh },
            .{ ".obj", .mesh },
            .{ ".fbx", .mesh },

            // Shaders
            .{ ".vert", .shader },
            .{ ".frag", .shader },
            .{ ".comp", .shader },
            .{ ".geom", .shader },
            .{ ".tesc", .shader },
            .{ ".tese", .shader },
            .{ ".glsl", .shader },
            .{ ".hlsl", .shader },
            .{ ".metal", .shader },

            // Audio
            .{ ".wav", .audio },
            .{ ".ogg", .audio },
            .{ ".mp3", .audio },
            .{ ".flac", .audio },

            // Scenes
            .{ ".scene", .scene },
            .{ ".prefab", .scene },

            // Fonts
            .{ ".ttf", .font },
            .{ ".otf", .font },

            // Scripts
            .{ ".js", .script },
            .{ ".lua", .script },
        });

        return extensions.get(ext) orelse .unknown;
    }

    /// Get the output extension for processed assets
    pub fn getOutputExtension(self: AssetType) []const u8 {
        return switch (self) {
            .texture => ".ztex",
            .mesh => ".zmesh",
            .shader => ".spv",
            .audio => ".zaud",
            .scene => ".zscene",
            .font => ".zfont",
            .script => ".js",
            .unknown => "",
        };
    }

    /// Check if this asset type should be processed
    pub fn requiresProcessing(self: AssetType) bool {
        return switch (self) {
            .unknown => false,
            else => true,
        };
    }
};

/// Current state of an asset in the pipeline
pub const AssetState = enum {
    /// Asset has never been processed
    unprocessed,
    /// Asset is currently being processed
    processing,
    /// Asset was successfully processed
    processed,
    /// Processing failed with an error
    failed,
    /// Asset is up to date (source unchanged since last process)
    up_to_date,
};

/// Metadata about a single asset
pub const AssetEntry = struct {
    /// Virtual path (relative to assets root)
    path: []const u8,
    /// Type of asset
    asset_type: AssetType,
    /// Hash of source file content
    source_hash: u64,
    /// Hash of processed output (null if not processed)
    processed_hash: ?u64,
    /// Source file modification time (ns since epoch)
    last_modified: i128,
    /// Time when asset was last processed (ns since epoch)
    last_processed: i128,
    /// Path(s) to output file(s)
    output_paths: []const []const u8,
    /// Current state
    state: AssetState,
    /// Error message if state is .failed
    error_message: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !AssetEntry {
        return .{
            .path = try allocator.dupe(u8, path),
            .asset_type = AssetType.fromExtension(std.fs.path.extension(path)),
            .source_hash = 0,
            .processed_hash = null,
            .last_modified = 0,
            .last_processed = 0,
            .output_paths = &.{},
            .state = .unprocessed,
            .error_message = null,
        };
    }

    pub fn deinit(self: *AssetEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        for (self.output_paths) |output_path| {
            allocator.free(output_path);
        }
        if (self.output_paths.len > 0) {
            allocator.free(self.output_paths);
        }
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Target platform for asset processing
pub const Platform = enum {
    desktop_windows,
    desktop_linux,
    desktop_macos,
    mobile_ios,
    mobile_android,
    web,

    pub fn isDesktop(self: Platform) bool {
        return switch (self) {
            .desktop_windows, .desktop_linux, .desktop_macos => true,
            else => false,
        };
    }

    pub fn isMobile(self: Platform) bool {
        return switch (self) {
            .mobile_ios, .mobile_android => true,
            else => false,
        };
    }

    /// Get current platform at comptime
    pub fn current() Platform {
        const builtin = @import("builtin");
        return switch (builtin.os.tag) {
            .macos => .desktop_macos,
            .windows => .desktop_windows,
            .linux => .desktop_linux,
            .ios => .mobile_ios,
            else => .desktop_linux,
        };
    }
};

/// Quality preset for asset processing
pub const QualityPreset = enum {
    /// Fastest processing, smallest size, lowest quality
    low,
    /// Balanced
    medium,
    /// High quality, larger files
    high,
    /// Maximum quality, longest processing time
    ultra,

    pub fn getTextureMaxSize(self: QualityPreset) u32 {
        return switch (self) {
            .low => 512,
            .medium => 1024,
            .high => 2048,
            .ultra => 4096,
        };
    }
};

/// Result of processing an asset
pub const ProcessResult = struct {
    success: bool,
    output_paths: []const []const u8,
    output_hash: ?u64,
    error_message: ?[]const u8,
    warnings: []const []const u8,
    processing_time_ns: u64,

    pub fn ok(output_paths: []const []const u8, output_hash: u64, time_ns: u64) ProcessResult {
        return .{
            .success = true,
            .output_paths = output_paths,
            .output_hash = output_hash,
            .error_message = null,
            .warnings = &.{},
            .processing_time_ns = time_ns,
        };
    }

    pub fn fail(error_message: []const u8) ProcessResult {
        return .{
            .success = false,
            .output_paths = &.{},
            .output_hash = null,
            .error_message = error_message,
            .warnings = &.{},
            .processing_time_ns = 0,
        };
    }
};

/// Summary of a build operation
pub const BuildResult = struct {
    /// Number of assets successfully processed
    processed: u32,
    /// Number of assets skipped (up to date)
    skipped: u32,
    /// Number of assets that failed
    errors: u32,
    /// Number of warnings generated
    warnings: u32,
    /// Total build duration in milliseconds
    duration_ms: u64,
    /// List of error messages
    error_messages: []const ErrorMessage,

    pub const ErrorMessage = struct {
        asset_path: []const u8,
        message: []const u8,
    };

    pub fn empty() BuildResult {
        return .{
            .processed = 0,
            .skipped = 0,
            .errors = 0,
            .warnings = 0,
            .duration_ms = 0,
            .error_messages = &.{},
        };
    }
};

test "AssetType.fromExtension" {
    const testing = std.testing;

    try testing.expectEqual(AssetType.texture, AssetType.fromExtension(".png"));
    try testing.expectEqual(AssetType.texture, AssetType.fromExtension(".jpg"));
    try testing.expectEqual(AssetType.mesh, AssetType.fromExtension(".gltf"));
    try testing.expectEqual(AssetType.mesh, AssetType.fromExtension(".glb"));
    try testing.expectEqual(AssetType.shader, AssetType.fromExtension(".vert"));
    try testing.expectEqual(AssetType.shader, AssetType.fromExtension(".frag"));
    try testing.expectEqual(AssetType.audio, AssetType.fromExtension(".wav"));
    try testing.expectEqual(AssetType.unknown, AssetType.fromExtension(".xyz"));
}
