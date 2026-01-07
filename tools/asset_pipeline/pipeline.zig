const std = @import("std");
const asset_types = @import("asset_types.zig");
const asset_database = @import("asset_database.zig");
const processor = @import("processor.zig");
const hash = @import("hash.zig");

const AssetType = asset_types.AssetType;
const AssetState = asset_types.AssetState;
const BuildResult = asset_types.BuildResult;
const Platform = asset_types.Platform;
const QualityPreset = asset_types.QualityPreset;
const ProcessResult = asset_types.ProcessResult;
const AssetDatabase = asset_database.AssetDatabase;
const Processor = processor.Processor;
const ProcessConfig = processor.ProcessConfig;
const Allocator = std.mem.Allocator;

/// Main asset pipeline that coordinates processing of all assets
pub const Pipeline = struct {
    allocator: Allocator,
    database: AssetDatabase,
    processors: std.AutoHashMap(AssetType, Processor),
    config: PipelineConfig,

    const Self = @This();

    fn freeProcessResultOutputs(allocator: Allocator, result: ProcessResult) void {
        for (result.output_paths) |path| {
            allocator.free(path);
        }
        if (result.output_paths.len > 0) {
            allocator.free(result.output_paths);
        }
    }

    pub fn init(allocator: Allocator, config: PipelineConfig) !Self {
        var database = try AssetDatabase.init(
            allocator,
            config.source_path,
            config.output_path,
            config.cache_path,
        );

        // Try to load existing database
        _ = database.load() catch false;

        return .{
            .allocator = allocator,
            .database = database,
            .processors = std.AutoHashMap(AssetType, Processor).init(allocator),
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        // Note: processors are owned by caller and should be deinit'd there
        self.processors.deinit();
        self.database.deinit();
    }

    /// Register a processor for a specific asset type
    pub fn registerProcessor(self: *Self, asset_type: AssetType, proc: Processor) !void {
        try self.processors.put(asset_type, proc);
    }

    /// Scan for assets and update database
    pub fn scan(self: *Self) !AssetDatabase.ScanResult {
        return self.database.scan();
    }

    /// Process a single asset
    pub fn processAsset(self: *Self, asset_path: []const u8) !ProcessResult {
        const asset = self.database.getAsset(asset_path) orelse {
            return ProcessResult.fail("Asset not found in database");
        };

        const proc = self.processors.get(asset.asset_type) orelse {
            return ProcessResult.fail("No processor registered for this asset type");
        };

        // Build full paths
        const full_input = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.config.source_path, asset_path },
        );
        defer self.allocator.free(full_input);

        const full_output = try self.database.getOutputPath(asset_path);
        defer self.allocator.free(full_output);

        // Ensure output directory exists
        if (std.fs.path.dirname(full_output)) |dir| {
            std.fs.cwd().makePath(dir) catch {};
        }

        // Create process config
        const proc_config = ProcessConfig{
            .allocator = self.allocator,
            .platform = self.config.target_platform,
            .quality = self.config.quality,
            .verbose = self.config.verbose,
            .force = false,
        };

        // Process the asset
        const start = std.time.nanoTimestamp();
        const result = proc.process(full_input, full_output, proc_config);
        const end = std.time.nanoTimestamp();

        const duration_ns: u64 = @intCast(end - start);

        if (result.success) {
            const output_hash = if (result.output_paths.len > 0)
                hash.hashFile(full_output) catch 0
            else
                0;
            try self.database.markProcessed(asset_path, result.output_paths, output_hash);

            if (self.config.verbose) {
                const duration_ms = duration_ns / 1_000_000;
                std.log.info("Processed: {s} ({d}ms)", .{ asset_path, duration_ms });
            }
        } else {
            try self.database.markFailed(asset_path, result.error_message orelse "Unknown error");

            if (self.config.verbose) {
                std.log.err("Failed: {s} - {s}", .{
                    asset_path,
                    result.error_message orelse "Unknown error",
                });
            }
        }

        return result;
    }

    /// Process all dirty (unprocessed or failed) assets
    pub fn processDirty(self: *Self) !BuildResult {
        const dirty = try self.database.getDirtyAssets();
        defer self.allocator.free(dirty);

        return self.processAssets(dirty);
    }

    /// Process all assets regardless of state
    pub fn processAll(self: *Self) !BuildResult {
        var all_paths: std.ArrayListUnmanaged([]const u8) = .{};
        defer all_paths.deinit(self.allocator);

        var it = self.database.assets.iterator();
        while (it.next()) |entry| {
            try all_paths.append(self.allocator, entry.value_ptr.path);
        }

        return self.processAssets(all_paths.items);
    }

    /// Process specific list of assets
    fn processAssets(self: *Self, paths: []const []const u8) !BuildResult {
        const start_time = std.time.milliTimestamp();

        var result = BuildResult.empty();
        var error_messages: std.ArrayListUnmanaged(BuildResult.ErrorMessage) = .{};
        defer error_messages.deinit(self.allocator);

        for (paths) |path| {
            const asset = self.database.getAsset(path);
            if (asset == null) continue;

            // Skip if no processor available
            if (!self.processors.contains(asset.?.asset_type)) {
                result.skipped += 1;
                continue;
            }

            const proc_result = self.processAsset(path) catch |err| {
                result.errors += 1;
                try error_messages.append(self.allocator, .{
                    .asset_path = path,
                    .message = @errorName(err),
                });
                continue;
            };
            defer freeProcessResultOutputs(self.allocator, proc_result);

            if (proc_result.success) {
                result.processed += 1;
                result.warnings += @intCast(proc_result.warnings.len);
            } else {
                result.errors += 1;
                if (proc_result.error_message) |msg| {
                    try error_messages.append(self.allocator, .{
                        .asset_path = path,
                        .message = msg,
                    });
                }
            }
        }

        result.duration_ms = @intCast(std.time.milliTimestamp() - start_time);
        result.error_messages = try error_messages.toOwnedSlice(self.allocator);

        // Save database after processing
        self.database.save() catch |err| {
            std.log.warn("Failed to save asset database: {}", .{err});
        };

        return result;
    }

    /// Process assets of a specific type
    pub fn processType(self: *Self, asset_type: AssetType) !BuildResult {
        const paths = try self.database.getAssetsByType(asset_type);
        defer self.allocator.free(paths);
        return self.processAssets(paths);
    }

    /// Print build summary
    pub fn printSummary(self: *Self, result: BuildResult) void {
        _ = self;
        std.debug.print("\n=== Build Summary ===\n", .{});
        std.debug.print("Processed: {d}\n", .{result.processed});
        std.debug.print("Skipped:   {d}\n", .{result.skipped});
        std.debug.print("Errors:    {d}\n", .{result.errors});
        std.debug.print("Warnings:  {d}\n", .{result.warnings});
        std.debug.print("Duration:  {d}ms\n", .{result.duration_ms});

        if (result.error_messages.len > 0) {
            std.debug.print("\nErrors:\n", .{});
            for (result.error_messages) |err| {
                std.debug.print("  {s}: {s}\n", .{ err.asset_path, err.message });
            }
        }
    }

    /// Clean output directory
    pub fn clean(self: *Self) !void {
        std.fs.cwd().deleteTree(self.config.output_path) catch {};
        std.fs.cwd().deleteTree(self.config.cache_path) catch {};

        // Reset database
        self.database.deinit();
        self.database = try AssetDatabase.init(
            self.allocator,
            self.config.source_path,
            self.config.output_path,
            self.config.cache_path,
        );
    }
};

/// Configuration for the asset pipeline
pub const PipelineConfig = struct {
    /// Path to source assets directory
    source_path: []const u8,
    /// Path to output processed assets
    output_path: []const u8,
    /// Path for intermediate cache files
    cache_path: []const u8,
    /// Target platform
    target_platform: Platform = Platform.current(),
    /// Quality preset
    quality: QualityPreset = .high,
    /// Number of parallel jobs (0 = auto)
    parallel_jobs: u32 = 0,
    /// Verbose output
    verbose: bool = false,
};

test "Pipeline initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var pipeline = try Pipeline.init(allocator, .{
        .source_path = "test_assets",
        .output_path = "test_output",
        .cache_path = "test_cache",
    });
    defer pipeline.deinit();
}
