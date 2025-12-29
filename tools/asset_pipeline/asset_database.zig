const std = @import("std");
const asset_types = @import("asset_types.zig");
const hash = @import("hash.zig");

const AssetEntry = asset_types.AssetEntry;
const AssetType = asset_types.AssetType;
const AssetState = asset_types.AssetState;
const Allocator = std.mem.Allocator;

/// Database for tracking all assets and their processing state
pub const AssetDatabase = struct {
    allocator: Allocator,
    /// Map of asset path to entry
    assets: std.StringHashMap(AssetEntry),
    /// Path to source assets directory
    source_path: []const u8,
    /// Path to output directory
    output_path: []const u8,
    /// Path to cache directory
    cache_path: []const u8,

    const Self = @This();

    /// Database file header magic
    const MAGIC: [4]u8 = .{ 'Z', 'D', 'L', 'A' };
    const VERSION: u32 = 1;

    pub fn init(
        allocator: Allocator,
        source_path: []const u8,
        output_path: []const u8,
        cache_path: []const u8,
    ) !Self {
        return .{
            .allocator = allocator,
            .assets = std.StringHashMap(AssetEntry).init(allocator),
            .source_path = try allocator.dupe(u8, source_path),
            .output_path = try allocator.dupe(u8, output_path),
            .cache_path = try allocator.dupe(u8, cache_path),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.assets.iterator();
        while (it.next()) |entry| {
            var asset = entry.value_ptr;
            asset.deinit(self.allocator);
        }
        self.assets.deinit();
        self.allocator.free(self.source_path);
        self.allocator.free(self.output_path);
        self.allocator.free(self.cache_path);
    }

    /// Scan source directory for assets
    pub fn scan(self: *Self) !ScanResult {
        var result = ScanResult{};

        var dir = std.fs.cwd().openDir(self.source_path, .{ .iterate = true }) catch |err| {
            std.log.err("Failed to open source directory '{s}': {}", .{ self.source_path, err });
            return err;
        };
        defer dir.close();

        try self.scanDirectory(dir, "", &result);

        return result;
    }

    fn scanDirectory(self: *Self, dir: std.fs.Dir, prefix: []const u8, result: *ScanResult) !void {
        var walker = dir.iterate();
        while (try walker.next()) |entry| {
            const full_path = if (prefix.len > 0)
                try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ prefix, entry.name })
            else
                try self.allocator.dupe(u8, entry.name);
            defer self.allocator.free(full_path);

            switch (entry.kind) {
                .directory => {
                    var subdir = try dir.openDir(entry.name, .{ .iterate = true });
                    defer subdir.close();
                    try self.scanDirectory(subdir, full_path, result);
                },
                .file => {
                    const asset_type = AssetType.fromExtension(std.fs.path.extension(entry.name));
                    if (asset_type != .unknown) {
                        try self.addOrUpdateAsset(full_path);
                        result.found += 1;
                    }
                },
                else => {},
            }
        }
    }

    /// Add or update an asset entry
    pub fn addOrUpdateAsset(self: *Self, relative_path: []const u8) !void {
        const full_source_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.source_path, relative_path },
        );
        defer self.allocator.free(full_source_path);

        // Get current file info
        const current_hash = hash.hashFile(full_source_path) catch |err| {
            std.log.warn("Failed to hash '{s}': {}", .{ relative_path, err });
            return;
        };
        const current_mtime = hash.getFileModTime(full_source_path) catch |err| {
            std.log.warn("Failed to stat '{s}': {}", .{ relative_path, err });
            return;
        };

        if (self.assets.getPtr(relative_path)) |existing| {
            // Update existing entry
            if (existing.source_hash != current_hash) {
                existing.source_hash = current_hash;
                existing.last_modified = current_mtime;
                existing.state = .unprocessed;
            }
        } else {
            // Add new entry
            var entry = try AssetEntry.init(self.allocator, relative_path);
            entry.source_hash = current_hash;
            entry.last_modified = current_mtime;
            try self.assets.put(entry.path, entry);
        }
    }

    /// Get an asset entry by path
    pub fn getAsset(self: *Self, path: []const u8) ?*AssetEntry {
        return self.assets.getPtr(path);
    }

    /// Get all assets that need processing
    pub fn getDirtyAssets(self: *Self) ![][]const u8 {
        var dirty: std.ArrayListUnmanaged([]const u8) = .{};
        errdefer dirty.deinit(self.allocator);

        var it = self.assets.iterator();
        while (it.next()) |entry| {
            const asset = entry.value_ptr;
            if (asset.state == .unprocessed or asset.state == .failed) {
                try dirty.append(self.allocator, asset.path);
            }
        }

        return dirty.toOwnedSlice(self.allocator);
    }

    /// Get all assets of a specific type
    pub fn getAssetsByType(self: *Self, asset_type: AssetType) ![][]const u8 {
        var list: std.ArrayListUnmanaged([]const u8) = .{};
        errdefer list.deinit(self.allocator);

        var it = self.assets.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.asset_type == asset_type) {
                try list.append(self.allocator, entry.value_ptr.path);
            }
        }

        return list.toOwnedSlice(self.allocator);
    }

    /// Mark an asset as processed
    pub fn markProcessed(
        self: *Self,
        path: []const u8,
        output_paths: []const []const u8,
        output_hash: u64,
    ) !void {
        if (self.assets.getPtr(path)) |asset| {
            // Free old output paths
            for (asset.output_paths) |old_path| {
                self.allocator.free(old_path);
            }
            if (asset.output_paths.len > 0) {
                self.allocator.free(asset.output_paths);
            }

            // Store new output paths
            var new_paths = try self.allocator.alloc([]const u8, output_paths.len);
            for (output_paths, 0..) |out_path, i| {
                new_paths[i] = try self.allocator.dupe(u8, out_path);
            }

            asset.output_paths = new_paths;
            asset.processed_hash = output_hash;
            asset.last_processed = std.time.nanoTimestamp();
            asset.state = .processed;
            asset.error_message = null;
        }
    }

    /// Mark an asset as failed
    pub fn markFailed(self: *Self, path: []const u8, error_message: []const u8) !void {
        if (self.assets.getPtr(path)) |asset| {
            if (asset.error_message) |old_msg| {
                self.allocator.free(old_msg);
            }
            asset.error_message = try self.allocator.dupe(u8, error_message);
            asset.state = .failed;
        }
    }

    /// Check if an asset needs reprocessing
    pub fn needsProcessing(self: *Self, path: []const u8) bool {
        const asset = self.assets.get(path) orelse return true;
        return asset.state == .unprocessed or asset.state == .failed;
    }

    /// Get output path for an asset
    pub fn getOutputPath(self: *Self, source_path: []const u8) ![]const u8 {
        const asset = self.assets.get(source_path) orelse return error.AssetNotFound;

        // Replace source extension with output extension
        const stem = std.fs.path.stem(source_path);
        const dir = std.fs.path.dirname(source_path) orelse "";
        const out_ext = asset.asset_type.getOutputExtension();

        if (dir.len > 0) {
            return std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}/{s}{s}",
                .{ self.output_path, dir, stem, out_ext },
            );
        } else {
            return std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}{s}",
                .{ self.output_path, stem, out_ext },
            );
        }
    }

    /// Save database to cache file
    pub fn save(self: *Self) !void {
        // Ensure cache directory exists
        std.fs.cwd().makePath(self.cache_path) catch {};

        const db_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/asset_database.bin",
            .{self.cache_path},
        );
        defer self.allocator.free(db_path);

        const file = try std.fs.cwd().createFile(db_path, .{});
        defer file.close();

        // Write header
        _ = try file.writeAll(&MAGIC);

        var buf4: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf4, VERSION, .little);
        _ = try file.writeAll(&buf4);

        std.mem.writeInt(u32, &buf4, @intCast(self.assets.count()), .little);
        _ = try file.writeAll(&buf4);

        // Write each asset entry
        var it = self.assets.iterator();
        while (it.next()) |entry| {
            const asset = entry.value_ptr;

            // Write path
            std.mem.writeInt(u32, &buf4, @intCast(asset.path.len), .little);
            _ = try file.writeAll(&buf4);
            _ = try file.writeAll(asset.path);

            // Write type and state
            _ = try file.writeAll(&[_]u8{@intFromEnum(asset.asset_type)});
            _ = try file.writeAll(&[_]u8{@intFromEnum(asset.state)});

            // Write hashes and timestamps
            var buf8: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf8, asset.source_hash, .little);
            _ = try file.writeAll(&buf8);
            std.mem.writeInt(u64, &buf8, asset.processed_hash orelse 0, .little);
            _ = try file.writeAll(&buf8);

            var buf16: [16]u8 = undefined;
            std.mem.writeInt(i128, &buf16, asset.last_modified, .little);
            _ = try file.writeAll(&buf16);
            std.mem.writeInt(i128, &buf16, asset.last_processed, .little);
            _ = try file.writeAll(&buf16);

            // Write output paths
            std.mem.writeInt(u32, &buf4, @intCast(asset.output_paths.len), .little);
            _ = try file.writeAll(&buf4);
            for (asset.output_paths) |out_path| {
                std.mem.writeInt(u32, &buf4, @intCast(out_path.len), .little);
                _ = try file.writeAll(&buf4);
                _ = try file.writeAll(out_path);
            }
        }
    }

    /// Load database from cache file
    pub fn load(self: *Self) !bool {
        const db_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/asset_database.bin",
            .{self.cache_path},
        );
        defer self.allocator.free(db_path);

        const file = std.fs.cwd().openFile(db_path, .{}) catch return false;
        defer file.close();

        // Read and verify header
        var magic: [4]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, &MAGIC)) {
            return false;
        }

        var version_buf: [4]u8 = undefined;
        _ = try file.readAll(&version_buf);
        const version = std.mem.readInt(u32, &version_buf, .little);
        if (version != VERSION) {
            return false;
        }

        var count_buf: [4]u8 = undefined;
        _ = try file.readAll(&count_buf);
        const count = std.mem.readInt(u32, &count_buf, .little);

        // Read entries
        for (0..count) |_| {
            var len_buf: [4]u8 = undefined;
            _ = try file.readAll(&len_buf);
            const path_len = std.mem.readInt(u32, &len_buf, .little);
            const path = try self.allocator.alloc(u8, path_len);
            _ = try file.readAll(path);

            var type_buf: [1]u8 = undefined;
            _ = try file.readAll(&type_buf);
            var state_buf: [1]u8 = undefined;
            _ = try file.readAll(&state_buf);

            var hash_buf: [8]u8 = undefined;
            _ = try file.readAll(&hash_buf);
            const source_hash = std.mem.readInt(u64, &hash_buf, .little);
            _ = try file.readAll(&hash_buf);
            const processed_hash_val = std.mem.readInt(u64, &hash_buf, .little);

            var time_buf: [16]u8 = undefined;
            _ = try file.readAll(&time_buf);
            const last_modified = std.mem.readInt(i128, &time_buf, .little);
            _ = try file.readAll(&time_buf);
            const last_processed = std.mem.readInt(i128, &time_buf, .little);

            var entry = AssetEntry{
                .path = path,
                .asset_type = @enumFromInt(type_buf[0]),
                .state = @enumFromInt(state_buf[0]),
                .source_hash = source_hash,
                .processed_hash = if (processed_hash_val == 0) null else processed_hash_val,
                .last_modified = last_modified,
                .last_processed = last_processed,
                .output_paths = undefined,
                .error_message = null,
            };

            // Read output paths
            _ = try file.readAll(&len_buf);
            const output_count = std.mem.readInt(u32, &len_buf, .little);
            if (output_count > 0) {
                var outputs = try self.allocator.alloc([]const u8, output_count);
                for (0..output_count) |i| {
                    _ = try file.readAll(&len_buf);
                    const out_len = std.mem.readInt(u32, &len_buf, .little);
                    const out_path = try self.allocator.alloc(u8, out_len);
                    _ = try file.readAll(out_path);
                    outputs[i] = out_path;
                }
                entry.output_paths = outputs;
            } else {
                entry.output_paths = &.{};
            }

            try self.assets.put(path, entry);
        }

        return true;
    }

    /// Get summary statistics
    pub fn getStats(self: *Self) Stats {
        var stats = Stats{};
        var it = self.assets.iterator();
        while (it.next()) |entry| {
            stats.total += 1;
            switch (entry.value_ptr.state) {
                .unprocessed => stats.unprocessed += 1,
                .processing => stats.processing += 1,
                .processed => stats.processed += 1,
                .failed => stats.failed += 1,
                .up_to_date => stats.up_to_date += 1,
            }
        }
        return stats;
    }

    pub const Stats = struct {
        total: u32 = 0,
        unprocessed: u32 = 0,
        processing: u32 = 0,
        processed: u32 = 0,
        failed: u32 = 0,
        up_to_date: u32 = 0,
    };

    pub const ScanResult = struct {
        found: u32 = 0,
        new: u32 = 0,
        modified: u32 = 0,
    };
};

test "AssetDatabase basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var db = try AssetDatabase.init(allocator, "assets", "build/output", "build/cache");
    defer db.deinit();

    // Initial stats should be empty
    const stats = db.getStats();
    try testing.expectEqual(@as(u32, 0), stats.total);
}
