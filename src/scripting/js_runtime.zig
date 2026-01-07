const std = @import("std");
const quickjs = @import("quickjs");

/// Global JavaScript runtime wrapper.
/// Only one runtime should exist per application.
/// The runtime manages memory allocation and garbage collection.
pub const JSRuntime = struct {
    runtime: *quickjs.Runtime,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new JavaScript runtime.
    pub fn init(allocator: std.mem.Allocator) !Self {
        const runtime = try quickjs.Runtime.init(allocator);

        // Configure memory limits
        runtime.setMemoryLimit(64 * 1024 * 1024); // 64MB
        runtime.setMaxStackSize(256 * 1024); // 256KB stack
        runtime.setGCThreshold(8 * 1024 * 1024); // 8MB GC threshold

        return .{
            .runtime = runtime,
            .allocator = allocator,
        };
    }

    /// Deinitialize the runtime and free all resources.
    pub fn deinit(self: *Self) void {
        self.runtime.runGC();
        self.runtime.deinit();
    }

    /// Trigger garbage collection.
    pub fn runGC(self: *Self) void {
        self.runtime.runGC();
    }

    /// Set memory limit (0 to disable).
    pub fn setMemoryLimit(self: *Self, limit: usize) void {
        self.runtime.setMemoryLimit(limit);
    }

    /// Get memory usage statistics.
    pub fn getMemoryUsage(self: *Self) quickjs.Runtime.MemoryUsage {
        return self.runtime.computeMemoryUsage();
    }

    /// Check if there are pending async jobs (promises).
    pub fn isJobPending(self: *Self) bool {
        return self.runtime.isJobPending();
    }
};
