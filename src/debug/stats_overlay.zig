const std = @import("std");
const Profiler = @import("profiler.zig").Profiler;

/// Render statistics for tracking draw calls and GPU usage
pub const RenderStats = struct {
    draw_calls: u32 = 0,
    triangles: u32 = 0,
    vertices: u32 = 0,
    texture_binds: u32 = 0,
    pipeline_binds: u32 = 0,

    pub fn reset(self: *RenderStats) void {
        self.draw_calls = 0;
        self.triangles = 0;
        self.vertices = 0;
        self.texture_binds = 0;
        self.pipeline_binds = 0;
    }
};

/// Statistics overlay display configuration
pub const StatsOverlayConfig = struct {
    show_fps: bool = true,
    show_frame_time: bool = true,
    show_frame_graph: bool = false,
    show_memory: bool = false,
    show_render_stats: bool = true,
    show_ecs_stats: bool = true,
    show_profiler_zones: bool = false,
};

/// Statistics overlay for displaying debug information
/// Note: This is a data-only overlay. Actual rendering requires a text/UI system.
/// For now, it provides formatted strings that can be displayed in window title or console.
pub const StatsOverlay = struct {
    profiler: *Profiler,
    config: StatsOverlayConfig,
    enabled: bool,

    // Render stats (updated externally by engine)
    render_stats: RenderStats,

    // ECS stats
    entity_count: u32,

    // Memory stats (bytes)
    memory_used: usize,
    memory_peak: usize,

    pub fn init(profiler: *Profiler) StatsOverlay {
        return .{
            .profiler = profiler,
            .config = .{},
            .enabled = true,
            .render_stats = .{},
            .entity_count = 0,
            .memory_used = 0,
            .memory_peak = 0,
        };
    }

    /// Update stats from external sources
    pub fn updateEntityCount(self: *StatsOverlay, count: u32) void {
        self.entity_count = count;
    }

    /// Update memory stats
    pub fn updateMemory(self: *StatsOverlay, used: usize, peak: usize) void {
        self.memory_used = used;
        self.memory_peak = peak;
    }

    /// Get current FPS
    pub fn getFps(self: *const StatsOverlay) f32 {
        return self.profiler.getFps();
    }

    /// Get current frame time in milliseconds
    pub fn getFrameTime(self: *const StatsOverlay) f32 {
        return self.profiler.getFrameTime();
    }

    /// Get average frame time in milliseconds
    pub fn getAverageFrameTime(self: *const StatsOverlay) f32 {
        return self.profiler.getAverageFrameTime(60);
    }

    /// Format stats as a single-line string suitable for window title
    pub fn formatTitleString(self: *const StatsOverlay, buffer: []u8) []const u8 {
        if (!self.enabled) return "";

        const fps = self.getFps();
        const frame_ms = self.getFrameTime();

        const result = std.fmt.bufPrint(buffer, "FPS: {d:.1} | {d:.2}ms | DC: {d} | Ents: {d}", .{
            fps,
            frame_ms,
            self.render_stats.draw_calls,
            self.entity_count,
        }) catch return "Stats Error";

        return result;
    }

    /// Format detailed stats as multiple lines
    pub fn formatDetailedString(self: *const StatsOverlay, allocator: std.mem.Allocator) ![]const u8 {
        if (!self.enabled) return "";

        var lines = std.ArrayList(u8).init(allocator);
        const writer = lines.writer();

        if (self.config.show_fps) {
            try writer.print("FPS: {d:.1}\n", .{self.getFps()});
        }

        if (self.config.show_frame_time) {
            const frame_ms = self.getFrameTime();
            const avg_ms = self.getAverageFrameTime();
            try writer.print("Frame: {d:.2}ms (avg: {d:.2}ms)\n", .{ frame_ms, avg_ms });
        }

        if (self.config.show_render_stats) {
            try writer.print("Draw Calls: {d}\n", .{self.render_stats.draw_calls});
            try writer.print("Triangles: {d}\n", .{self.render_stats.triangles});
            try writer.print("Vertices: {d}\n", .{self.render_stats.vertices});
        }

        if (self.config.show_ecs_stats) {
            try writer.print("Entities: {d}\n", .{self.entity_count});
        }

        if (self.config.show_memory and self.memory_used > 0) {
            const used_mb = @as(f32, @floatFromInt(self.memory_used)) / (1024.0 * 1024.0);
            const peak_mb = @as(f32, @floatFromInt(self.memory_peak)) / (1024.0 * 1024.0);
            try writer.print("Memory: {d:.2}MB (peak: {d:.2}MB)\n", .{ used_mb, peak_mb });
        }

        return lines.toOwnedSlice();
    }

    /// Print stats to stderr (for debugging)
    pub fn printToStderr(self: *const StatsOverlay) void {
        if (!self.enabled) return;

        const fps = self.getFps();
        const frame_ms = self.getFrameTime();

        std.debug.print(
            "\x1b[2K\rFPS: {d:.1} | Frame: {d:.2}ms | DC: {d} | Tris: {d} | Ents: {d}",
            .{
                fps,
                frame_ms,
                self.render_stats.draw_calls,
                self.render_stats.triangles,
                self.entity_count,
            },
        );
    }

    /// Toggle overlay visibility
    pub fn toggle(self: *StatsOverlay) void {
        self.enabled = !self.enabled;
    }

    /// Reset render stats (call at start of each frame)
    pub fn resetFrameStats(self: *StatsOverlay) void {
        self.render_stats.reset();
    }

    /// Record a draw call
    pub fn recordDrawCall(self: *StatsOverlay, vertex_count: u32, index_count: u32) void {
        self.render_stats.draw_calls += 1;
        self.render_stats.vertices += vertex_count;
        self.render_stats.triangles += index_count / 3;
    }

    /// Record a texture bind
    pub fn recordTextureBind(self: *StatsOverlay) void {
        self.render_stats.texture_binds += 1;
    }

    /// Record a pipeline bind
    pub fn recordPipelineBind(self: *StatsOverlay) void {
        self.render_stats.pipeline_binds += 1;
    }
};
