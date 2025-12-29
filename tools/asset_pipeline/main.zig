const std = @import("std");
const pipeline_mod = @import("pipeline.zig");
const asset_types = @import("asset_types.zig");
const shader_processor = @import("processors/shader_processor.zig");
const texture_processor = @import("processors/texture_processor.zig");

const Pipeline = pipeline_mod.Pipeline;
const PipelineConfig = pipeline_mod.PipelineConfig;
const Platform = asset_types.Platform;
const QualityPreset = asset_types.QualityPreset;
const AssetType = asset_types.AssetType;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];
    const cmd_args = args[2..];

    if (std.mem.eql(u8, command, "build")) {
        try buildCommand(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "clean")) {
        try cleanCommand(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "info")) {
        try infoCommand(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "validate")) {
        try validateCommand(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    const usage =
        \\ZDL Asset Pipeline
        \\
        \\USAGE:
        \\    zdl-assets <command> [options]
        \\
        \\COMMANDS:
        \\    build       Build/process assets
        \\    clean       Clean output and cache directories
        \\    info        Show asset database info
        \\    validate    Validate shaders without building
        \\    help        Show this help message
        \\
        \\BUILD OPTIONS:
        \\    --source=<path>     Source assets directory (default: assets)
        \\    --output=<path>     Output directory (default: build/assets)
        \\    --cache=<path>      Cache directory (default: build/cache)
        \\    --platform=<plat>   Target platform: desktop, mobile (default: current)
        \\    --quality=<q>       Quality: low, medium, high, ultra (default: high)
        \\    --force             Force rebuild all assets
        \\    --verbose           Verbose output
        \\
        \\EXAMPLES:
        \\    zdl-assets build
        \\    zdl-assets build --source=assets --output=build/assets --verbose
        \\    zdl-assets build --platform=mobile --quality=medium
        \\    zdl-assets clean
        \\    zdl-assets validate src/shaders/*.vert
        \\
    ;
    std.debug.print("{s}", .{usage});
}

fn buildCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var config = PipelineConfig{
        .source_path = "assets",
        .output_path = "build/assets",
        .cache_path = "build/cache",
        .verbose = false,
    };

    var force = false;

    // Parse arguments
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--source=")) {
            config.source_path = arg["--source=".len..];
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            config.output_path = arg["--output=".len..];
        } else if (std.mem.startsWith(u8, arg, "--cache=")) {
            config.cache_path = arg["--cache=".len..];
        } else if (std.mem.startsWith(u8, arg, "--platform=")) {
            const plat = arg["--platform=".len..];
            config.target_platform = parsePlatform(plat);
        } else if (std.mem.startsWith(u8, arg, "--quality=")) {
            const qual = arg["--quality=".len..];
            config.quality = parseQuality(qual);
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            config.verbose = true;
        }
    }

    std.debug.print("ZDL Asset Pipeline\n", .{});
    std.debug.print("Source: {s}\n", .{config.source_path});
    std.debug.print("Output: {s}\n", .{config.output_path});
    std.debug.print("Platform: {s}\n", .{@tagName(config.target_platform)});
    std.debug.print("Quality: {s}\n\n", .{@tagName(config.quality)});

    // Initialize pipeline
    var pipe = try Pipeline.init(allocator, config);
    defer pipe.deinit();

    // Register processors
    const shader_proc, const shader_impl = try shader_processor.create(allocator);
    defer {
        shader_impl.deinit();
        allocator.destroy(shader_impl);
    }
    try pipe.registerProcessor(.shader, shader_proc);

    const tex_proc, const tex_impl = try texture_processor.create(allocator);
    defer {
        tex_impl.deinit();
        allocator.destroy(tex_impl);
    }
    try pipe.registerProcessor(.texture, tex_proc);

    // Scan for assets
    std.debug.print("Scanning for assets...\n", .{});
    const scan_result = pipe.scan() catch |err| {
        std.debug.print("Error scanning assets: {}\n", .{err});
        std.debug.print("Make sure the source directory exists: {s}\n", .{config.source_path});
        return;
    };
    std.debug.print("Found {d} assets\n\n", .{scan_result.found});

    if (scan_result.found == 0) {
        std.debug.print("No assets to process.\n", .{});
        return;
    }

    // Process assets
    std.debug.print("Processing assets...\n", .{});
    const result = if (force)
        try pipe.processAll()
    else
        try pipe.processDirty();

    pipe.printSummary(result);

    // Free error messages
    allocator.free(result.error_messages);
}

fn cleanCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var output_path: []const u8 = "build/assets";
    var cache_path: []const u8 = "build/cache";

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--output=")) {
            output_path = arg["--output=".len..];
        } else if (std.mem.startsWith(u8, arg, "--cache=")) {
            cache_path = arg["--cache=".len..];
        }
    }

    std.debug.print("Cleaning...\n", .{});

    std.fs.cwd().deleteTree(output_path) catch |err| {
        if (err != error.FileNotFound) {
            std.debug.print("Failed to clean output: {}\n", .{err});
        }
    };

    std.fs.cwd().deleteTree(cache_path) catch |err| {
        if (err != error.FileNotFound) {
            std.debug.print("Failed to clean cache: {}\n", .{err});
        }
    };

    _ = allocator;
    std.debug.print("Done.\n", .{});
}

fn infoCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var config = PipelineConfig{
        .source_path = "assets",
        .output_path = "build/assets",
        .cache_path = "build/cache",
    };

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--source=")) {
            config.source_path = arg["--source=".len..];
        } else if (std.mem.startsWith(u8, arg, "--cache=")) {
            config.cache_path = arg["--cache=".len..];
        }
    }

    var pipe = try Pipeline.init(allocator, config);
    defer pipe.deinit();

    _ = pipe.scan() catch {};

    const stats = pipe.database.getStats();

    std.debug.print("Asset Database Info\n", .{});
    std.debug.print("===================\n", .{});
    std.debug.print("Source:      {s}\n", .{config.source_path});
    std.debug.print("Cache:       {s}\n\n", .{config.cache_path});
    std.debug.print("Total:       {d}\n", .{stats.total});
    std.debug.print("Processed:   {d}\n", .{stats.processed});
    std.debug.print("Unprocessed: {d}\n", .{stats.unprocessed});
    std.debug.print("Failed:      {d}\n", .{stats.failed});
}

fn validateCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zdl-assets validate <shader-files...>\n", .{});
        return;
    }

    var shader_proc = try shader_processor.ShaderProcessor.init(allocator);
    defer shader_proc.deinit();

    var valid_count: u32 = 0;
    var invalid_count: u32 = 0;

    for (args) |shader_path| {
        // Skip options
        if (std.mem.startsWith(u8, shader_path, "-")) continue;

        const result = shader_proc.validate(shader_path, allocator) catch |err| {
            std.debug.print("FAIL {s}: {}\n", .{ shader_path, err });
            invalid_count += 1;
            continue;
        };

        if (result.valid) {
            std.debug.print("OK   {s}\n", .{shader_path});
            valid_count += 1;
        } else {
            std.debug.print("FAIL {s}\n", .{shader_path});
            if (result.message) |msg| {
                std.debug.print("     {s}\n", .{msg});
                allocator.free(msg);
            }
            invalid_count += 1;
        }
    }

    std.debug.print("\nResults: {d} valid, {d} invalid\n", .{ valid_count, invalid_count });
}

fn parsePlatform(s: []const u8) Platform {
    if (std.mem.eql(u8, s, "desktop") or std.mem.eql(u8, s, "linux")) {
        return .desktop_linux;
    } else if (std.mem.eql(u8, s, "windows")) {
        return .desktop_windows;
    } else if (std.mem.eql(u8, s, "macos") or std.mem.eql(u8, s, "mac")) {
        return .desktop_macos;
    } else if (std.mem.eql(u8, s, "ios")) {
        return .mobile_ios;
    } else if (std.mem.eql(u8, s, "android") or std.mem.eql(u8, s, "mobile")) {
        return .mobile_android;
    } else if (std.mem.eql(u8, s, "web")) {
        return .web;
    }
    return Platform.current();
}

fn parseQuality(s: []const u8) QualityPreset {
    if (std.mem.eql(u8, s, "low")) {
        return .low;
    } else if (std.mem.eql(u8, s, "medium")) {
        return .medium;
    } else if (std.mem.eql(u8, s, "high")) {
        return .high;
    } else if (std.mem.eql(u8, s, "ultra")) {
        return .ultra;
    }
    return .high;
}

test {
    _ = @import("asset_types.zig");
    _ = @import("asset_database.zig");
    _ = @import("pipeline.zig");
    _ = @import("hash.zig");
    _ = @import("processor.zig");
    _ = @import("processors/shader_processor.zig");
    _ = @import("processors/texture_processor.zig");
}
