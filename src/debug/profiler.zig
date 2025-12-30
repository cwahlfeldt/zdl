const std = @import("std");

/// Zone identifier for tracking profiler zones
pub const ZoneId = u32;

/// Statistics for a profiled zone
pub const ZoneStats = struct {
    name: []const u8,
    call_count: u64,
    total_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,

    pub fn getAvgNs(self: ZoneStats) u64 {
        if (self.call_count == 0) return 0;
        return self.total_time_ns / self.call_count;
    }

    pub fn getAvgMs(self: ZoneStats) f32 {
        return @as(f32, @floatFromInt(self.getAvgNs())) / 1_000_000.0;
    }

    pub fn getTotalMs(self: ZoneStats) f32 {
        return @as(f32, @floatFromInt(self.total_time_ns)) / 1_000_000.0;
    }

    pub fn getMinMs(self: ZoneStats) f32 {
        return @as(f32, @floatFromInt(self.min_time_ns)) / 1_000_000.0;
    }

    pub fn getMaxMs(self: ZoneStats) f32 {
        return @as(f32, @floatFromInt(self.max_time_ns)) / 1_000_000.0;
    }
};

/// Active zone tracking
const ActiveZone = struct {
    name: []const u8,
    start_time: i128,
};

/// Frame timing data
pub const FrameData = struct {
    frame_number: u64,
    timestamp_ns: i128,
    cpu_time_ns: u64,
    counters: std.StringHashMap(f64),

    pub fn init(allocator: std.mem.Allocator, frame_num: u64, timestamp: i128) FrameData {
        return .{
            .frame_number = frame_num,
            .timestamp_ns = timestamp,
            .cpu_time_ns = 0,
            .counters = std.StringHashMap(f64).init(allocator),
        };
    }

    pub fn deinit(self: *FrameData) void {
        self.counters.deinit();
    }
};

/// Ring buffer for frame history
fn RingBuffer(comptime T: type) type {
    return struct {
        items: []T,
        head: usize,
        count: usize,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, cap: usize) !Self {
            const items = try allocator.alloc(T, cap);
            return .{
                .items = items,
                .head = 0,
                .count = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn push(self: *Self, item: T) void {
            self.items[self.head] = item;
            self.head = (self.head + 1) % self.items.len;
            if (self.count < self.items.len) {
                self.count += 1;
            }
        }

        pub fn capacity(self: Self) usize {
            return self.items.len;
        }

        pub fn getLatest(self: Self) ?T {
            if (self.count == 0) return null;
            const idx = if (self.head == 0) self.items.len - 1 else self.head - 1;
            return self.items[idx];
        }

        pub fn iterator(self: *const Self) Iterator {
            return .{
                .buffer = self,
                .index = 0,
            };
        }

        pub const Iterator = struct {
            buffer: *const Self,
            index: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.buffer.count) return null;
                const start = if (self.buffer.count < self.buffer.items.len)
                    0
                else
                    self.buffer.head;
                const idx = (start + self.index) % self.buffer.items.len;
                self.index += 1;
                return self.buffer.items[idx];
            }
        };
    };
}

/// Performance profiler for tracking frame timing and CPU zones
pub const Profiler = struct {
    allocator: std.mem.Allocator,

    // Frame data
    frame_times: RingBuffer(f32),
    frame_index: u64,
    frame_start_time: i128,

    // Zone tracking
    zone_stack: std.array_list.Managed(ActiveZone),
    zone_stats: std.StringHashMap(ZoneStats),
    next_zone_id: ZoneId,

    // Counters
    counters: std.StringHashMap(f64),

    // Settings
    enabled: bool,
    history_size: u32,

    pub fn init(allocator: std.mem.Allocator) !Profiler {
        return .{
            .allocator = allocator,
            .frame_times = try RingBuffer(f32).init(allocator, 120),
            .frame_index = 0,
            .frame_start_time = 0,
            .zone_stack = std.array_list.Managed(ActiveZone).init(allocator),
            .zone_stats = std.StringHashMap(ZoneStats).init(allocator),
            .next_zone_id = 0,
            .counters = std.StringHashMap(f64).init(allocator),
            .enabled = true,
            .history_size = 120,
        };
    }

    pub fn deinit(self: *Profiler) void {
        self.frame_times.deinit();
        self.zone_stack.deinit();
        self.zone_stats.deinit();
        self.counters.deinit();
    }

    /// Start a new frame
    pub fn beginFrame(self: *Profiler) void {
        if (!self.enabled) return;
        self.frame_start_time = std.time.nanoTimestamp();
        self.frame_index += 1;
    }

    /// End the current frame
    pub fn endFrame(self: *Profiler) void {
        if (!self.enabled) return;

        const end_time = std.time.nanoTimestamp();
        const frame_time_ns = end_time - self.frame_start_time;
        const frame_time_ms = @as(f32, @floatFromInt(frame_time_ns)) / 1_000_000.0;

        self.frame_times.push(frame_time_ms);
    }

    /// Begin a CPU profiling zone
    pub fn beginZone(self: *Profiler, name: []const u8) ZoneId {
        if (!self.enabled) return 0;

        const zone_id = self.next_zone_id;
        self.next_zone_id += 1;

        self.zone_stack.append(.{
            .name = name,
            .start_time = std.time.nanoTimestamp(),
        }) catch return zone_id;

        return zone_id;
    }

    /// End a CPU profiling zone
    pub fn endZone(self: *Profiler, zone_id: ZoneId) void {
        _ = zone_id;
        if (!self.enabled) return;

        if (self.zone_stack.pop()) |zone| {
            const end_time = std.time.nanoTimestamp();
            const elapsed_ns: u64 = @intCast(end_time - zone.start_time);

            const result = self.zone_stats.getOrPut(zone.name) catch return;
            if (result.found_existing) {
                result.value_ptr.call_count += 1;
                result.value_ptr.total_time_ns += elapsed_ns;
                result.value_ptr.min_time_ns = @min(result.value_ptr.min_time_ns, elapsed_ns);
                result.value_ptr.max_time_ns = @max(result.value_ptr.max_time_ns, elapsed_ns);
            } else {
                result.value_ptr.* = .{
                    .name = zone.name,
                    .call_count = 1,
                    .total_time_ns = elapsed_ns,
                    .min_time_ns = elapsed_ns,
                    .max_time_ns = elapsed_ns,
                };
            }
        }
    }

    /// Track a counter value
    pub fn counter(self: *Profiler, name: []const u8, value: f64) void {
        if (!self.enabled) return;
        self.counters.put(name, value) catch {};
    }

    /// Increment a counter
    pub fn incrementCounter(self: *Profiler, name: []const u8) void {
        if (!self.enabled) return;
        const result = self.counters.getOrPut(name) catch return;
        if (result.found_existing) {
            result.value_ptr.* += 1.0;
        } else {
            result.value_ptr.* = 1.0;
        }
    }

    /// Get the most recent frame time in milliseconds
    pub fn getFrameTime(self: *const Profiler) f32 {
        return self.frame_times.getLatest() orelse 0.0;
    }

    /// Get average frame time over the last N frames
    pub fn getAverageFrameTime(self: *const Profiler, frame_count: u32) f32 {
        var total: f32 = 0.0;
        var count: u32 = 0;
        var iter = self.frame_times.iterator();
        while (iter.next()) |frame_time| {
            total += frame_time;
            count += 1;
            if (count >= frame_count) break;
        }
        if (count == 0) return 0.0;
        return total / @as(f32, @floatFromInt(count));
    }

    /// Get FPS based on average frame time
    pub fn getFps(self: *const Profiler) f32 {
        const avg = self.getAverageFrameTime(60);
        if (avg <= 0.0) return 0.0;
        return 1000.0 / avg;
    }

    /// Get statistics for a named zone
    pub fn getZoneStats(self: *const Profiler, name: []const u8) ?ZoneStats {
        return self.zone_stats.get(name);
    }

    /// Get a counter value
    pub fn getCounter(self: *const Profiler, name: []const u8) f64 {
        return self.counters.get(name) orelse 0.0;
    }

    /// Reset all zone statistics
    pub fn resetZoneStats(self: *Profiler) void {
        self.zone_stats.clearRetainingCapacity();
    }

    /// Reset all counters
    pub fn resetCounters(self: *Profiler) void {
        self.counters.clearRetainingCapacity();
    }

    /// Get frame time history iterator
    pub fn getFrameTimeIterator(self: *const Profiler) RingBuffer(f32).Iterator {
        return self.frame_times.iterator();
    }

    /// Get frame history capacity
    pub fn getFrameHistoryCapacity(self: *const Profiler) usize {
        return self.frame_times.capacity();
    }

    /// Get current frame count in history
    pub fn getFrameHistoryCount(self: *const Profiler) usize {
        return self.frame_times.count;
    }
};

/// Scoped zone helper - automatically ends zone when going out of scope
pub const ScopedZone = struct {
    profiler: *Profiler,
    zone_id: ZoneId,

    pub fn end(self: ScopedZone) void {
        self.profiler.endZone(self.zone_id);
    }
};

/// Create a scoped zone that automatically ends when the returned struct is used with defer
pub inline fn scopedZone(profiler: *Profiler, name: []const u8) ScopedZone {
    return .{
        .profiler = profiler,
        .zone_id = profiler.beginZone(name),
    };
}
