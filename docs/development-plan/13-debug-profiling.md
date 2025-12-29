# Debug and Profiling Tools

## Overview

Implement comprehensive debugging and profiling tools for ZDL development, including visual debuggers, performance profiling, memory tracking, and development overlays. These tools are essential for optimizing games and diagnosing issues.

## Current State

ZDL currently has:
- Basic FPS counter in window title
- Standard Zig debug logging
- No visual debugging tools
- No profiling infrastructure
- No memory tracking

## Goals

- Visual debug rendering (lines, shapes, text)
- Frame profiler with GPU timing
- Memory usage tracking and leak detection
- Entity/component inspector
- Render statistics overlay
- Console system for runtime commands
- Log viewer with filtering
- Performance graphs

## Architecture

### Directory Structure

```
src/
├── debug/
│   ├── debug.zig              # Module exports
│   ├── debug_draw.zig         # Visual debug rendering
│   ├── profiler.zig           # Performance profiler
│   ├── memory_tracker.zig     # Memory tracking
│   ├── console.zig            # In-game console
│   ├── inspector.zig          # Entity inspector
│   ├── stats_overlay.zig      # Statistics display
│   └── log_viewer.zig         # Log management
```

### Core Components

#### Debug Draw

```zig
pub const DebugDraw = struct {
    allocator: Allocator,
    device: *Device,

    // Render resources
    line_pipeline: *Pipeline,
    triangle_pipeline: *Pipeline,
    text_pipeline: *Pipeline,
    font: *Font,

    // Batched primitives
    lines: std.ArrayList(LineVertex),
    triangles: std.ArrayList(TriangleVertex),
    texts: std.ArrayList(TextEntry),

    // Settings
    enabled: bool,
    depth_test: bool,
    screen_scale: f32,

    pub fn init(allocator: Allocator, device: *Device) !DebugDraw;
    pub fn deinit(self: *DebugDraw) void;

    // 3D primitives (world space)
    pub fn line(self: *DebugDraw, from: Vec3, to: Vec3, color: Color) void;
    pub fn ray(self: *DebugDraw, origin: Vec3, direction: Vec3, length: f32, color: Color) void;
    pub fn box(self: *DebugDraw, center: Vec3, size: Vec3, color: Color) void;
    pub fn wireBox(self: *DebugDraw, center: Vec3, size: Vec3, color: Color) void;
    pub fn sphere(self: *DebugDraw, center: Vec3, radius: f32, color: Color) void;
    pub fn wireSphere(self: *DebugDraw, center: Vec3, radius: f32, color: Color) void;
    pub fn capsule(self: *DebugDraw, from: Vec3, to: Vec3, radius: f32, color: Color) void;
    pub fn cylinder(self: *DebugDraw, center: Vec3, radius: f32, height: f32, color: Color) void;
    pub fn cone(self: *DebugDraw, apex: Vec3, direction: Vec3, angle: f32, length: f32, color: Color) void;
    pub fn arrow(self: *DebugDraw, from: Vec3, to: Vec3, color: Color) void;
    pub fn axes(self: *DebugDraw, transform: Mat4, size: f32) void;
    pub fn frustum(self: *DebugDraw, view_proj: Mat4, color: Color) void;
    pub fn grid(self: *DebugDraw, center: Vec3, size: f32, divisions: u32, color: Color) void;
    pub fn aabb(self: *DebugDraw, bounds: AABB, color: Color) void;
    pub fn obb(self: *DebugDraw, bounds: OBB, color: Color) void;

    // 2D primitives (screen space)
    pub fn screenLine(self: *DebugDraw, from: Vec2, to: Vec2, color: Color) void;
    pub fn screenRect(self: *DebugDraw, rect: Rect, color: Color) void;
    pub fn screenCircle(self: *DebugDraw, center: Vec2, radius: f32, color: Color) void;

    // Text
    pub fn text3D(self: *DebugDraw, position: Vec3, str: []const u8, color: Color) void;
    pub fn text2D(self: *DebugDraw, position: Vec2, str: []const u8, color: Color) void;
    pub fn textFormat(self: *DebugDraw, position: Vec2, comptime fmt: []const u8, args: anytype, color: Color) void;

    // Persistent draws (until cleared)
    pub fn persistentLine(self: *DebugDraw, from: Vec3, to: Vec3, color: Color, duration: f32) void;
    pub fn persistentSphere(self: *DebugDraw, center: Vec3, radius: f32, color: Color, duration: f32) void;

    // Rendering
    pub fn render(self: *DebugDraw, frame: *RenderFrame, camera: *Camera) void;
    pub fn clear(self: *DebugDraw) void;
};

pub const LineVertex = struct {
    position: Vec3,
    color: Color,
};

pub const TriangleVertex = struct {
    position: Vec3,
    color: Color,
    normal: Vec3,
};

pub const TextEntry = struct {
    position: Vec3,     // World space (or Vec2 for screen space)
    text: []const u8,
    color: Color,
    screen_space: bool,
};
```

#### Profiler

```zig
pub const Profiler = struct {
    allocator: Allocator,

    // Frame data
    frames: RingBuffer(FrameData),
    current_frame: *FrameData,
    frame_index: u64,

    // Zones
    zone_stack: std.ArrayList(ZoneId),
    zones: std.StringHashMap(ZoneStats),

    // GPU timing
    gpu_timer_pool: GPUTimerPool,
    gpu_zones: std.StringHashMap(GPUZoneStats),

    // Memory tracking
    memory_tracker: ?*MemoryTracker,

    // Settings
    enabled: bool,
    capture_gpu: bool,
    history_size: u32,

    pub fn init(allocator: Allocator, config: ProfilerConfig) !Profiler;
    pub fn deinit(self: *Profiler) void;

    // Frame lifecycle
    pub fn beginFrame(self: *Profiler) void;
    pub fn endFrame(self: *Profiler) void;

    // CPU zones
    pub fn beginZone(self: *Profiler, name: []const u8) ZoneId;
    pub fn endZone(self: *Profiler, zone: ZoneId) void;

    // GPU zones
    pub fn beginGPUZone(self: *Profiler, cmd: *CommandBuffer, name: []const u8) void;
    pub fn endGPUZone(self: *Profiler, cmd: *CommandBuffer, name: []const u8) void;

    // Counters
    pub fn counter(self: *Profiler, name: []const u8, value: f64) void;
    pub fn incrementCounter(self: *Profiler, name: []const u8) void;

    // Queries
    pub fn getFrameTime(self: *Profiler) f32;
    pub fn getAverageFrameTime(self: *Profiler, frame_count: u32) f32;
    pub fn getZoneStats(self: *Profiler, name: []const u8) ?ZoneStats;
    pub fn getGPUZoneStats(self: *Profiler, name: []const u8) ?GPUZoneStats;
    pub fn getFrameHistory(self: *Profiler) []FrameData;
};

pub const ZoneStats = struct {
    name: []const u8,
    call_count: u64,
    total_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    avg_time_ns: u64,

    pub fn getAvgMs(self: ZoneStats) f32;
    pub fn getTotalMs(self: ZoneStats) f32;
};

pub const GPUZoneStats = struct {
    name: []const u8,
    gpu_time_ns: u64,
};

pub const FrameData = struct {
    frame_number: u64,
    timestamp: i64,
    cpu_time_ns: u64,
    gpu_time_ns: u64,
    zones: []ZoneSample,
    counters: std.StringHashMap(f64),
};

// Scoped zone helper
pub fn scopedZone(profiler: *Profiler, name: []const u8) ScopedZone {
    return ScopedZone{ .profiler = profiler, .zone = profiler.beginZone(name) };
}

pub const ScopedZone = struct {
    profiler: *Profiler,
    zone: ZoneId,

    pub fn deinit(self: ScopedZone) void {
        self.profiler.endZone(self.zone);
    }
};

// Usage macro-like function
pub inline fn PROFILE_SCOPE(profiler: *Profiler, comptime name: []const u8) ScopedZone {
    return scopedZone(profiler, name);
}
```

#### Memory Tracker

```zig
pub const MemoryTracker = struct {
    allocator: Allocator,

    // Allocation tracking
    allocations: std.AutoHashMap(usize, AllocationInfo),
    total_allocated: usize,
    total_freed: usize,
    peak_usage: usize,
    allocation_count: u64,
    free_count: u64,

    // Categories
    categories: std.StringHashMap(CategoryStats),

    // Leak detection
    check_leaks: bool,
    allocation_stack_traces: bool,

    pub fn init(allocator: Allocator) MemoryTracker;
    pub fn deinit(self: *MemoryTracker) void;

    // Allocation tracking
    pub fn trackAlloc(self: *MemoryTracker, ptr: usize, size: usize, category: ?[]const u8) void;
    pub fn trackFree(self: *MemoryTracker, ptr: usize) void;
    pub fn trackRealloc(self: *MemoryTracker, old_ptr: usize, new_ptr: usize, new_size: usize) void;

    // Queries
    pub fn getCurrentUsage(self: *MemoryTracker) usize;
    pub fn getPeakUsage(self: *MemoryTracker) usize;
    pub fn getCategoryStats(self: *MemoryTracker, category: []const u8) ?CategoryStats;
    pub fn getAllCategories(self: *MemoryTracker) []CategoryStats;

    // Leak detection
    pub fn checkForLeaks(self: *MemoryTracker) []AllocationInfo;
    pub fn dumpLeaks(self: *MemoryTracker, writer: anytype) void;

    // Wrapped allocator
    pub fn wrappedAllocator(self: *MemoryTracker) std.mem.Allocator;
};

pub const AllocationInfo = struct {
    ptr: usize,
    size: usize,
    category: ?[]const u8,
    timestamp: i64,
    stack_trace: ?[]usize,
};

pub const CategoryStats = struct {
    name: []const u8,
    current_usage: usize,
    peak_usage: usize,
    allocation_count: u64,
};
```

#### Console System

```zig
pub const Console = struct {
    allocator: Allocator,

    // Command system
    commands: std.StringHashMap(CommandEntry),

    // History
    input_history: std.ArrayList([]const u8),
    output_history: std.ArrayList(ConsoleLine),
    history_index: usize,

    // State
    is_open: bool,
    input_buffer: [256]u8,
    input_len: usize,
    scroll_offset: usize,

    // Autocomplete
    suggestions: std.ArrayList([]const u8),
    suggestion_index: usize,

    pub fn init(allocator: Allocator) !Console;
    pub fn deinit(self: *Console) void;

    // Commands
    pub fn registerCommand(
        self: *Console,
        name: []const u8,
        description: []const u8,
        handler: CommandHandler,
    ) !void;

    // Input
    pub fn handleChar(self: *Console, char: u8) void;
    pub fn handleKey(self: *Console, key: Key) void;
    pub fn execute(self: *Console, command: []const u8) void;

    // Output
    pub fn print(self: *Console, text: []const u8) void;
    pub fn printf(self: *Console, comptime fmt: []const u8, args: anytype) void;
    pub fn printError(self: *Console, text: []const u8) void;
    pub fn printWarning(self: *Console, text: []const u8) void;

    // State
    pub fn toggle(self: *Console) void;
    pub fn open(self: *Console) void;
    pub fn close(self: *Console) void;
    pub fn clear(self: *Console) void;

    // Rendering
    pub fn render(self: *Console, ui: *UIContext) void;
};

pub const CommandHandler = fn(args: [][]const u8) void;

pub const CommandEntry = struct {
    name: []const u8,
    description: []const u8,
    handler: CommandHandler,
    arg_count: ?usize,
};

pub const ConsoleLine = struct {
    text: []const u8,
    color: Color,
    timestamp: i64,
};

// Built-in commands
pub fn registerBuiltinCommands(console: *Console) void {
    console.registerCommand("help", "Show available commands", cmdHelp);
    console.registerCommand("clear", "Clear console output", cmdClear);
    console.registerCommand("quit", "Exit the game", cmdQuit);
    console.registerCommand("fps", "Toggle FPS display", cmdFps);
    console.registerCommand("vsync", "Toggle vsync", cmdVsync);
    console.registerCommand("wireframe", "Toggle wireframe mode", cmdWireframe);
    console.registerCommand("stats", "Show engine statistics", cmdStats);
    console.registerCommand("spawn", "Spawn entity", cmdSpawn);
    console.registerCommand("teleport", "Teleport player", cmdTeleport);
    console.registerCommand("timescale", "Set time scale", cmdTimescale);
}
```

#### Entity Inspector

```zig
pub const Inspector = struct {
    allocator: Allocator,

    // Selection
    selected_entity: ?Entity,
    hovered_entity: ?Entity,

    // UI state
    expanded_components: std.AutoHashMap(ComponentTypeId, bool),
    scroll_offset: f32,

    // Gizmos
    gizmo_mode: GizmoMode,
    gizmo_space: GizmoSpace,

    pub fn init(allocator: Allocator) Inspector;

    // Selection
    pub fn select(self: *Inspector, entity: Entity) void;
    pub fn deselect(self: *Inspector) void;
    pub fn pickEntity(self: *Inspector, scene: *Scene, ray: Ray) ?Entity;

    // Rendering
    pub fn render(self: *Inspector, ui: *UIContext, scene: *Scene) void;
    pub fn renderGizmo(self: *Inspector, debug: *DebugDraw, scene: *Scene) void;

    // Gizmo interaction
    pub fn handleGizmoInput(self: *Inspector, input: *Input, camera: *Camera) void;
};

pub const GizmoMode = enum {
    translate,
    rotate,
    scale,
};

pub const GizmoSpace = enum {
    local,
    world,
};

fn renderEntityInspector(inspector: *Inspector, ui: *UIContext, scene: *Scene) void {
    const entity = inspector.selected_entity orelse return;

    if (ui.beginPanel("Inspector", .{})) {
        // Entity header
        ui.label("Entity: {d}", .{entity.index});

        // Transform component
        if (scene.getComponent(entity, TransformComponent)) |transform| {
            if (ui.collapsingHeader("Transform", .{ .default_open = true })) {
                var pos = transform.position;
                if (ui.vec3Input("Position", &pos)) {
                    transform.setPosition(pos);
                }

                var euler = transform.rotation.toEuler();
                if (ui.vec3Input("Rotation", &euler)) {
                    transform.setRotation(Quat.fromEuler(euler.x, euler.y, euler.z));
                }

                var scale = transform.scale;
                if (ui.vec3Input("Scale", &scale)) {
                    transform.setScale(scale);
                }
            }
        }

        // Other components...
        if (scene.getComponent(entity, MeshRendererComponent)) |_| {
            if (ui.collapsingHeader("Mesh Renderer", .{})) {
                // Mesh renderer properties
            }
        }

        ui.endPanel();
    }
}
```

#### Statistics Overlay

```zig
pub const StatsOverlay = struct {
    profiler: *Profiler,
    enabled: bool,

    // Display options
    show_fps: bool,
    show_frame_time: bool,
    show_frame_graph: bool,
    show_memory: bool,
    show_render_stats: bool,
    show_ecs_stats: bool,

    // Graph data
    frame_times: RingBuffer(f32),
    gpu_times: RingBuffer(f32),

    pub fn init(profiler: *Profiler) StatsOverlay;

    pub fn update(self: *StatsOverlay) void {
        if (!self.enabled) return;

        self.frame_times.push(self.profiler.getFrameTime());
        if (self.profiler.getGPUZoneStats("Frame")) |gpu| {
            self.gpu_times.push(@intToFloat(f32, gpu.gpu_time_ns) / 1_000_000.0);
        }
    }

    pub fn render(self: *StatsOverlay, ui: *UIContext, engine: *Engine, scene: *Scene) void {
        if (!self.enabled) return;

        const x: f32 = 10;
        var y: f32 = 10;
        const line_height: f32 = 18;

        if (self.show_fps) {
            const fps = 1000.0 / self.profiler.getAverageFrameTime(60);
            ui.text2D(.{ .x = x, .y = y }, "FPS: {d:.1}", .{fps}, .white);
            y += line_height;
        }

        if (self.show_frame_time) {
            const frame_ms = self.profiler.getFrameTime();
            const color = if (frame_ms > 16.67) Color.red else if (frame_ms > 8.33) Color.yellow else Color.green;
            ui.text2D(.{ .x = x, .y = y }, "Frame: {d:.2}ms", .{frame_ms}, color);
            y += line_height;
        }

        if (self.show_frame_graph) {
            self.renderFrameGraph(ui, x, y, 200, 60);
            y += 70;
        }

        if (self.show_memory) {
            if (self.profiler.memory_tracker) |mem| {
                const usage_mb = @intToFloat(f32, mem.getCurrentUsage()) / (1024 * 1024);
                ui.text2D(.{ .x = x, .y = y }, "Memory: {d:.1}MB", .{usage_mb}, .white);
                y += line_height;
            }
        }

        if (self.show_render_stats) {
            ui.text2D(.{ .x = x, .y = y }, "Draw calls: {d}", .{engine.render_stats.draw_calls}, .white);
            y += line_height;
            ui.text2D(.{ .x = x, .y = y }, "Triangles: {d}", .{engine.render_stats.triangles}, .white);
            y += line_height;
        }

        if (self.show_ecs_stats) {
            ui.text2D(.{ .x = x, .y = y }, "Entities: {d}", .{scene.getEntityCount()}, .white);
            y += line_height;
        }
    }

    fn renderFrameGraph(self: *StatsOverlay, ui: *UIContext, x: f32, y: f32, w: f32, h: f32) void {
        // Background
        ui.drawRect(.{ .x = x, .y = y, .w = w, .h = h }, .{ .r = 0, .g = 0, .b = 0, .a = 0.5 });

        // Target line (16.67ms = 60fps)
        const target_y = y + h - (16.67 / 33.33) * h;
        ui.drawLine(.{ .x = x, .y = target_y }, .{ .x = x + w, .y = target_y }, .{ .r = 0, .g = 1, .b = 0, .a = 0.5 });

        // Frame time bars
        const bar_width = w / @intToFloat(f32, self.frame_times.capacity);
        var i: usize = 0;
        for (self.frame_times.items()) |frame_time| {
            const bar_height = std.math.min((frame_time / 33.33) * h, h);
            const bar_x = x + @intToFloat(f32, i) * bar_width;
            const bar_y = y + h - bar_height;

            const color = if (frame_time > 16.67) Color.red else Color.green;
            ui.drawRect(.{ .x = bar_x, .y = bar_y, .w = bar_width - 1, .h = bar_height }, color);
            i += 1;
        }
    }
};
```

### Debug Configuration

```zig
pub const DebugConfig = struct {
    // Global debug toggle
    debug_enabled: bool = true,

    // Components
    debug_draw_enabled: bool = true,
    profiler_enabled: bool = true,
    console_enabled: bool = true,
    inspector_enabled: bool = true,
    stats_overlay_enabled: bool = true,

    // Hotkeys
    toggle_console_key: Key = .grave_accent,  // `
    toggle_debug_key: Key = .f1,
    toggle_profiler_key: Key = .f2,
    toggle_inspector_key: Key = .f3,
    toggle_stats_key: Key = .f4,
    screenshot_key: Key = .f12,

    // Rendering
    show_wireframe: bool = false,
    show_bounds: bool = false,
    show_colliders: bool = false;
    show_normals: bool = false;
    show_light_volumes: bool = false;
};
```

## Usage Examples

### Debug Drawing

```zig
// In game update
pub fn update(engine: *Engine, scene: *Scene, debug: *DebugDraw, dt: f32) !void {
    // Draw player forward direction
    const player_pos = player_transform.getWorldPosition();
    const forward = player_transform.forward();
    debug.arrow(player_pos, player_pos.add(forward.scale(2)), .green);

    // Draw enemy detection radius
    for (enemies) |enemy| {
        const pos = scene.getComponent(enemy, TransformComponent).?.getWorldPosition();
        debug.wireSphere(pos, detection_radius, .yellow);
    }

    // Draw navigation path
    if (nav_path) |path| {
        for (path.points[0 .. path.points.len - 1], path.points[1..]) |from, to| {
            debug.line(from, to, .cyan);
        }
    }

    // Draw physics colliders
    if (debug_config.show_colliders) {
        for (scene.getComponents(ColliderComponent)) |collider| {
            debug.aabb(collider.getBounds(), .magenta);
        }
    }
}
```

### Profiling

```zig
pub fn update(engine: *Engine, scene: *Scene, profiler: *Profiler, dt: f32) !void {
    profiler.beginFrame();
    defer profiler.endFrame();

    {
        const zone = profiler.beginZone("Physics");
        defer profiler.endZone(zone);

        physics.step(dt);
    }

    {
        const zone = profiler.beginZone("AI");
        defer profiler.endZone(zone);

        for (enemies) |enemy| {
            updateEnemyAI(enemy, dt);
        }
    }

    {
        const zone = profiler.beginZone("Animation");
        defer profiler.endZone(zone);

        animation_system.update(scene, dt);
    }

    // Track counters
    profiler.counter("Active Enemies", @intToFloat(f64, active_enemy_count));
    profiler.counter("Particles", @intToFloat(f64, particle_count));
}
```

### Console Commands

```zig
// Register game-specific commands
console.registerCommand("god", "Toggle god mode", struct {
    fn handler(args: [][]const u8) void {
        god_mode = !god_mode;
        console.printf("God mode: {s}", .{if (god_mode) "ON" else "OFF"});
    }
}.handler);

console.registerCommand("spawn", "Spawn entity at position", struct {
    fn handler(args: [][]const u8) void {
        if (args.len < 1) {
            console.printError("Usage: spawn <type> [x y z]");
            return;
        }
        const entity_type = args[0];
        const pos = if (args.len >= 4)
            Vec3.init(parseFloat(args[1]), parseFloat(args[2]), parseFloat(args[3]))
        else
            player_position;

        spawnEntity(entity_type, pos);
        console.printf("Spawned {s} at ({d}, {d}, {d})", .{ entity_type, pos.x, pos.y, pos.z });
    }
}.handler);

// In-game usage: press ` to open console, type "spawn enemy 10 0 5"
```

## Implementation Steps

### Phase 1: Debug Drawing
1. Create debug draw renderer
2. Implement basic shapes (lines, boxes, spheres)
3. Add 3D text rendering
4. Implement persistent draws

### Phase 2: Profiler
1. Create frame timing infrastructure
2. Implement CPU zones
3. Add GPU timing queries
4. Create profiler data structures

### Phase 3: Memory Tracking
1. Create allocation tracking
2. Implement category tracking
3. Add leak detection
4. Create wrapped allocator

### Phase 4: Console
1. Implement console UI
2. Create command system
3. Add input history
4. Implement autocomplete

### Phase 5: Inspector
1. Create entity picker
2. Implement component display
3. Add transform gizmos
4. Create property editors

### Phase 6: Stats Overlay
1. Create stats rendering
2. Add frame graph
3. Implement memory display
4. Add render statistics

## Performance Considerations

- Disable debug tools in release builds
- Use conditional compilation for debug code
- Batch debug draws for efficiency
- Profile the profiler itself
- Use ring buffers for history

## References

- [RenderDoc](https://renderdoc.org/) - GPU debugging
- [Tracy Profiler](https://github.com/wolfpld/tracy) - Frame profiler
- [Quake Console](http://fabiensanglard.net/quake3/quakeConsole.php) - Console inspiration
- [Unity Profiler](https://docs.unity3d.com/Manual/Profiler.html)
