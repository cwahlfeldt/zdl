// ZDL Debug Module
// Provides debugging and profiling tools for engine development

pub const DebugDraw = @import("debug_draw.zig").DebugDraw;
pub const LineVertex = @import("debug_draw.zig").LineVertex;
pub const DebugUniforms = @import("debug_draw.zig").DebugUniforms;

pub const Profiler = @import("profiler.zig").Profiler;
pub const ScopedZone = @import("profiler.zig").ScopedZone;
pub const ZoneStats = @import("profiler.zig").ZoneStats;
pub const scopedZone = @import("profiler.zig").scopedZone;

pub const StatsOverlay = @import("stats_overlay.zig").StatsOverlay;
pub const RenderStats = @import("stats_overlay.zig").RenderStats;
pub const StatsOverlayConfig = @import("stats_overlay.zig").StatsOverlayConfig;

// Re-export common types from engine
pub const Color = @import("../engine/engine.zig").Color;
