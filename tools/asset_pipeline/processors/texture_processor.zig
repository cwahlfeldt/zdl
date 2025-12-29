const std = @import("std");
const asset_types = @import("../asset_types.zig");
const processor = @import("../processor.zig");
const hash = @import("../hash.zig");

const AssetType = asset_types.AssetType;
const ProcessResult = asset_types.ProcessResult;
const ProcessConfig = processor.ProcessConfig;
const Allocator = std.mem.Allocator;

/// Texture processor for image assets
/// Currently copies textures as-is; future versions will add:
/// - Format conversion
/// - Mipmap generation
/// - Compression (BCn, ASTC, ETC2)
pub const TextureProcessor = struct {
    allocator: Allocator,

    const Self = @This();

    const supported_types: []const AssetType = &.{.texture};

    pub fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn process(
        self: *Self,
        input_path: []const u8,
        output_path: []const u8,
        config: ProcessConfig,
    ) ProcessResult {
        _ = self;
        const start = std.time.nanoTimestamp();

        // For now, just copy the texture file
        // Future: implement proper processing with stb_image or similar
        std.fs.cwd().copyFile(input_path, std.fs.cwd(), output_path, .{}) catch |err| {
            const msg = std.fmt.allocPrint(
                config.allocator,
                "Failed to copy texture: {}",
                .{err},
            ) catch return ProcessResult.fail("Failed to copy texture");
            return ProcessResult.fail(msg);
        };

        const end = std.time.nanoTimestamp();
        const duration: u64 = @intCast(end - start);

        const output_hash = hash.hashFile(output_path) catch 0;

        var outputs = config.allocator.alloc([]const u8, 1) catch
            return ProcessResult.fail("Out of memory");
        outputs[0] = config.allocator.dupe(u8, output_path) catch
            return ProcessResult.fail("Out of memory");

        return .{
            .success = true,
            .output_paths = outputs,
            .output_hash = output_hash,
            .error_message = null,
            .warnings = &.{},
            .processing_time_ns = duration,
        };
    }

    pub fn getSupportedTypes(self: *Self) []const AssetType {
        _ = self;
        return supported_types;
    }

    pub fn getName(self: *Self) []const u8 {
        _ = self;
        return "TextureProcessor";
    }
};

/// Create a Processor interface from TextureProcessor
pub fn create(allocator: Allocator) !struct { processor.Processor, *TextureProcessor } {
    const impl = try allocator.create(TextureProcessor);
    impl.* = TextureProcessor.init(allocator);

    const proc = processor.Processor{
        .ptr = impl,
        .vtable = &.{
            .process = @ptrCast(&TextureProcessor.process),
            .getSupportedTypes = @ptrCast(&TextureProcessor.getSupportedTypes),
            .getName = @ptrCast(&TextureProcessor.getName),
            .deinit = @ptrCast(&TextureProcessor.deinit),
        },
    };

    return .{ proc, impl };
}
