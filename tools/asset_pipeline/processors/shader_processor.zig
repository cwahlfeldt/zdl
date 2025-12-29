const std = @import("std");
const asset_types = @import("../asset_types.zig");
const processor = @import("../processor.zig");
const hash = @import("../hash.zig");

const AssetType = asset_types.AssetType;
const ProcessResult = asset_types.ProcessResult;
const Platform = asset_types.Platform;
const ProcessConfig = processor.ProcessConfig;
const Allocator = std.mem.Allocator;

/// Shader processor using glslangValidator for SPIR-V compilation
pub const ShaderProcessor = struct {
    allocator: Allocator,
    glslang_path: []const u8,

    const Self = @This();

    /// Supported shader types
    const supported_types: []const AssetType = &.{.shader};

    pub fn init(allocator: Allocator) !Self {
        // Try to find glslangValidator
        const glslang = findGlslangValidator(allocator) catch |err| {
            std.log.warn("glslangValidator not found: {}", .{err});
            return Self{
                .allocator = allocator,
                .glslang_path = "glslangValidator",
            };
        };

        return Self{
            .allocator = allocator,
            .glslang_path = glslang,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!std.mem.eql(u8, self.glslang_path, "glslangValidator")) {
            self.allocator.free(self.glslang_path);
        }
    }

    fn findGlslangValidator(allocator: Allocator) ![]const u8 {
        // Check if it's in PATH
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "which", "glslangValidator" },
        }) catch {
            return error.NotFound;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited == 0 and result.stdout.len > 0) {
            // Trim newline
            var path = result.stdout;
            while (path.len > 0 and (path[path.len - 1] == '\n' or path[path.len - 1] == '\r')) {
                path = path[0 .. path.len - 1];
            }
            return allocator.dupe(u8, path);
        }

        return error.NotFound;
    }

    pub fn process(
        self: *Self,
        input_path: []const u8,
        output_path: []const u8,
        config: ProcessConfig,
    ) ProcessResult {
        // Determine shader stage from extension
        const ext = std.fs.path.extension(input_path);
        const stage = getShaderStage(ext) orelse {
            return ProcessResult.fail("Unknown shader extension");
        };

        // Build command arguments
        var args: std.ArrayListUnmanaged([]const u8) = .{};
        defer args.deinit(config.allocator);

        args.append(config.allocator, self.glslang_path) catch return ProcessResult.fail("Out of memory");
        args.append(config.allocator, "-V") catch return ProcessResult.fail("Out of memory"); // Output SPIR-V

        // Target environment based on platform
        args.append(config.allocator, "--target-env") catch return ProcessResult.fail("Out of memory");
        const target_env = switch (config.platform) {
            .desktop_macos => "vulkan1.2",
            .mobile_ios, .mobile_android => "vulkan1.1",
            else => "vulkan1.2",
        };
        args.append(config.allocator, target_env) catch return ProcessResult.fail("Out of memory");

        // Note: -O flag is not supported in older versions of glslangValidator
        // Skip optimization flags for compatibility
        _ = config.shader.optimization_level;

        // Debug info
        if (config.shader.debug_info) {
            args.append(config.allocator, "-g") catch return ProcessResult.fail("Out of memory");
        }

        // Add defines
        for (config.shader.defines) |define| {
            const define_str = if (define.value) |val|
                std.fmt.allocPrint(config.allocator, "-D{s}={s}", .{ define.name, val }) catch
                    return ProcessResult.fail("Out of memory")
            else
                std.fmt.allocPrint(config.allocator, "-D{s}", .{define.name}) catch
                    return ProcessResult.fail("Out of memory");
            defer config.allocator.free(define_str);
            args.append(config.allocator, define_str) catch return ProcessResult.fail("Out of memory");
        }

        // Add include paths
        for (config.shader.include_paths) |inc_path| {
            args.append(config.allocator, "-I") catch return ProcessResult.fail("Out of memory");
            args.append(config.allocator, inc_path) catch return ProcessResult.fail("Out of memory");
        }

        // Shader stage
        args.append(config.allocator, "-S") catch return ProcessResult.fail("Out of memory");
        args.append(config.allocator, stage) catch return ProcessResult.fail("Out of memory");

        // Output path
        args.append(config.allocator, "-o") catch return ProcessResult.fail("Out of memory");
        args.append(config.allocator, output_path) catch return ProcessResult.fail("Out of memory");

        // Input file
        args.append(config.allocator, input_path) catch return ProcessResult.fail("Out of memory");

        // Run glslangValidator
        const start = std.time.nanoTimestamp();
        const result = std.process.Child.run(.{
            .allocator = config.allocator,
            .argv = args.items,
        }) catch |err| {
            const msg = std.fmt.allocPrint(
                config.allocator,
                "Failed to run glslangValidator: {}",
                .{err},
            ) catch return ProcessResult.fail("Failed to run glslangValidator");
            return ProcessResult.fail(msg);
        };
        defer config.allocator.free(result.stdout);
        defer config.allocator.free(result.stderr);

        const end = std.time.nanoTimestamp();
        const duration: u64 = @intCast(end - start);

        if (result.term.Exited != 0) {
            // Compilation failed
            const error_msg = if (result.stderr.len > 0)
                config.allocator.dupe(u8, result.stderr) catch "Shader compilation failed"
            else
                "Shader compilation failed";
            return .{
                .success = false,
                .output_paths = &.{},
                .output_hash = null,
                .error_message = error_msg,
                .warnings = &.{},
                .processing_time_ns = duration,
            };
        }

        // Success - compute output hash
        const output_hash = hash.hashFile(output_path) catch 0;

        // Create output paths array
        var outputs = config.allocator.alloc([]const u8, 1) catch return ProcessResult.fail("Out of memory");
        outputs[0] = config.allocator.dupe(u8, output_path) catch return ProcessResult.fail("Out of memory");

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
        return "ShaderProcessor";
    }

    /// Get shader stage string for glslangValidator from file extension
    fn getShaderStage(ext: []const u8) ?[]const u8 {
        const stages = std.StaticStringMap([]const u8).initComptime(.{
            .{ ".vert", "vert" },
            .{ ".frag", "frag" },
            .{ ".comp", "comp" },
            .{ ".geom", "geom" },
            .{ ".tesc", "tesc" },
            .{ ".tese", "tese" },
        });
        return stages.get(ext);
    }

    /// Validate a shader without producing output
    pub fn validate(self: *Self, shader_path: []const u8, allocator: Allocator) !ValidationResult {
        const ext = std.fs.path.extension(shader_path);
        const stage = getShaderStage(ext) orelse return error.UnknownShaderType;

        // Use -V for Vulkan GLSL validation (needed for descriptor set syntax)
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{
                self.glslang_path,
                "-V", // Vulkan mode
                "-S",
                stage,
                shader_path,
            },
        }) catch |err| {
            return .{ .valid = false, .message = @errorName(err) };
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        return .{
            .valid = result.term.Exited == 0,
            .message = if (result.stderr.len > 0)
                try allocator.dupe(u8, result.stderr)
            else
                null,
        };
    }

    pub const ValidationResult = struct {
        valid: bool,
        message: ?[]const u8,
    };
};

/// Create a Processor interface from ShaderProcessor
pub fn create(allocator: Allocator) !struct { processor.Processor, *ShaderProcessor } {
    const impl = try allocator.create(ShaderProcessor);
    impl.* = try ShaderProcessor.init(allocator);

    const proc = processor.Processor{
        .ptr = impl,
        .vtable = &.{
            .process = @ptrCast(&ShaderProcessor.process),
            .getSupportedTypes = @ptrCast(&ShaderProcessor.getSupportedTypes),
            .getName = @ptrCast(&ShaderProcessor.getName),
            .deinit = @ptrCast(&ShaderProcessor.deinit),
        },
    };

    return .{ proc, impl };
}

test "ShaderProcessor.getShaderStage" {
    const testing = std.testing;

    try testing.expectEqualStrings("vert", ShaderProcessor.getShaderStage(".vert").?);
    try testing.expectEqualStrings("frag", ShaderProcessor.getShaderStage(".frag").?);
    try testing.expectEqual(@as(?[]const u8, null), ShaderProcessor.getShaderStage(".xyz"));
}
