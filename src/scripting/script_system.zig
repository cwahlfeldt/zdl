const std = @import("std");
const quickjs = @import("quickjs");

const Entity = @import("../ecs/entity.zig").Entity;
const Scene = @import("../ecs/scene.zig").Scene;
const Engine = @import("../engine/engine.zig").Engine;
const Input = @import("../input/input.zig").Input;
const TransformComponent = @import("../ecs/components/transform_component.zig").TransformComponent;

const JSRuntime = @import("js_runtime.zig").JSRuntime;
const JSContext = @import("js_context.zig").JSContext;
const ScriptComponent = @import("script_component.zig").ScriptComponent;
const bindings = @import("bindings/bindings.zig");

const math_api = @import("bindings/math_api.zig");
const console_api = @import("bindings/console_api.zig");
const engine_api = @import("bindings/engine_api.zig");
const input_api = @import("bindings/input_api.zig");
const scene_api = @import("bindings/scene_api.zig");
const transform_api = @import("bindings/transform_api.zig");

/// System that manages JavaScript scripting.
/// Initializes the JS runtime, registers bindings, and updates scripts each frame.
pub const ScriptSystem = struct {
    allocator: std.mem.Allocator,
    runtime: *JSRuntime,
    context: *JSContext,

    /// Total time elapsed
    total_time: f32,

    /// Hot reload check interval (in seconds)
    reload_check_interval: f32,
    reload_check_timer: f32,

    /// Scripts pending load
    pending_loads: std.ArrayList(Entity),

    const Self = @This();

    /// Initialize the script system.
    pub fn init(allocator: std.mem.Allocator) !Self {
        std.debug.print("[ScriptSystem] Allocating runtime...\n", .{});
        // Allocate runtime on the heap to avoid dangling pointers
        const runtime = try allocator.create(JSRuntime);
        errdefer allocator.destroy(runtime);
        std.debug.print("[ScriptSystem] Initializing runtime...\n", .{});
        runtime.* = try JSRuntime.init(allocator);
        std.debug.print("[ScriptSystem] Runtime initialized\n", .{});

        // Allocate context on the heap
        std.debug.print("[ScriptSystem] Allocating context...\n", .{});
        const context = try allocator.create(JSContext);
        errdefer allocator.destroy(context);
        std.debug.print("[ScriptSystem] Initializing context...\n", .{});
        context.* = JSContext.init(runtime, allocator);
        std.debug.print("[ScriptSystem] Context initialized\n", .{});

        // Register all API bindings
        std.debug.print("[ScriptSystem] Registering math API...\n", .{});
        try math_api.register(context);
        std.debug.print("[ScriptSystem] Registering console API...\n", .{});
        try console_api.register(context);
        try console_api.installPrintFunction(context);
        std.debug.print("[ScriptSystem] Registering engine API...\n", .{});
        try engine_api.register(context);
        std.debug.print("[ScriptSystem] Registering input API...\n", .{});
        try input_api.register(context);
        std.debug.print("[ScriptSystem] Registering scene API...\n", .{});
        try scene_api.register(context);
        std.debug.print("[ScriptSystem] Registering transform API...\n", .{});
        try transform_api.register(context);
        std.debug.print("[ScriptSystem] All APIs registered\n", .{});

        return .{
            .allocator = allocator,
            .runtime = runtime,
            .context = context,
            .total_time = 0,
            .reload_check_interval = 1.0,
            .reload_check_timer = 0,
            .pending_loads = .{},
        };
    }

    /// Deinitialize the script system.
    pub fn deinit(self: *Self) void {
        self.pending_loads.deinit(self.allocator);
        self.context.deinit();
        self.allocator.destroy(self.context);
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);
    }

    /// Load a script component.
    pub fn loadScript(self: *Self, script: *ScriptComponent, entity: Entity) void {
        script.load(self.context, entity, self.allocator) catch |err| {
            std.debug.print("[ScriptSystem] Failed to load script: {any}\n", .{err});
        };
    }

    /// Update all scripts in the scene.
    pub fn update(
        self: *Self,
        scene: *Scene,
        engine: *Engine,
        input: *Input,
        delta_time: f32,
    ) void {
        self.total_time += delta_time;

        // Set up binding context
        var ctx = bindings.BindingContext{
            .js_ctx = self.context,
            .engine = engine,
            .scene = scene,
            .input = input,
            .delta_time = delta_time,
            .current_entity = Entity.invalid,
            .allocator = self.allocator,
        };
        bindings.setContext(&ctx);
        defer bindings.setContext(null);

        // Update engine state in JavaScript
        engine_api.updateFrame(
            self.context,
            delta_time,
            self.total_time,
            60, // TODO: get actual FPS
            engine.window_width,
            engine.window_height,
            engine.input.mouse_captured,
        );

        // Update input state in JavaScript
        input_api.updateFrame(self.context, input);

        // Update scene state in JavaScript
        scene_api.updateFrame(
            self.context,
            scene.entityCount(),
            scene.getActiveCamera(),
        );

        // Get script components and entities
        const scripts = scene.scripts.items();
        const entities = scene.scripts.entities();

        // Sync transforms from Zig to JavaScript for all scripted entities
        for (entities) |entity| {
            if (scene.getComponent(TransformComponent, entity)) |transform| {
                transform_api.syncTransform(self.context, entity, transform);
            }
        }

        // Start any unstarted scripts
        for (scripts, entities) |*script, entity| {
            if (!script.started and script.enabled) {
                if (!script.loaded) {
                    script.load(self.context, entity, self.allocator) catch continue;
                }
                ctx.current_entity = entity;
                script.callStart(self.context);
            }
        }

        // Update all scripts
        for (scripts, entities) |*script, entity| {
            if (script.enabled and script.started) {
                ctx.current_entity = entity;
                script.callUpdate(self.context, delta_time);
            }
        }

        // Process transform updates from JavaScript
        transform_api.processUpdates(self.context, scene);

        // Process pending JavaScript jobs (promises)
        self.context.processPendingJobs();

        // Flush console messages
        console_api.flushMessages(self.context);

        // Check for engine quit request
        if (engine_api.checkQuitRequested(self.context)) {
            engine.should_quit = true;
        }

        // Check for mouse capture request
        if (engine_api.checkMouseCaptureRequest(self.context)) |captured| {
            engine.setMouseCapture(captured);
        }

        // Check for gamepad rumble request
        if (input_api.checkRumbleRequest(self.context)) |rumble| {
            if (input.getGamepad()) |gamepad| {
                gamepad.rumble(rumble.low, rumble.high, rumble.duration);
            }
        }

        // Process scene requests (entity creation/destruction)
        self.processSceneRequests(scene);

        // Hot reload check
        self.reload_check_timer += delta_time;
        if (self.reload_check_timer >= self.reload_check_interval) {
            self.reload_check_timer = 0;
            self.checkHotReload(scene);
        }

        // Run garbage collection periodically
        if (@mod(@as(i32, @intFromFloat(self.total_time)), 30) == 0) {
            self.runtime.runGC();
        }
    }

    /// Process scene modification requests from JavaScript.
    fn processSceneRequests(self: *Self, scene: *Scene) void {
        // Check for entity creation request
        if (scene_api.checkCreateEntityRequest(self.context)) {
            if (scene.createEntity()) |entity| {
                scene_api.registerEntity(self.context, entity);
                std.debug.print("[ScriptSystem] Created entity from JS: {any}\n", .{entity});
            } else |err| {
                std.debug.print("[ScriptSystem] Failed to create entity: {any}\n", .{err});
            }
        }

        // Process entity destruction requests
        const destroy_requests = scene_api.getDestroyRequests(self.context, self.allocator) catch &[_]Entity{};
        defer if (destroy_requests.len > 0) self.allocator.free(destroy_requests);

        for (destroy_requests) |entity| {
            scene_api.unregisterEntity(self.context, entity);
            scene.destroyEntity(entity) catch |err| {
                std.debug.print("[ScriptSystem] Failed to destroy entity: {any}\n", .{err});
            };
        }

        // Check for camera change request
        if (scene_api.checkSetCameraRequest(self.context)) |camera_entity| {
            scene.setActiveCamera(camera_entity);
        }
    }

    /// Check for scripts that need hot reloading.
    fn checkHotReload(self: *Self, scene: *Scene) void {
        const scripts = scene.scripts.items();
        const entities = scene.scripts.entities();

        for (scripts, entities) |*script, entity| {
            if (script.needsReload()) {
                std.debug.print("[ScriptSystem] Hot-reloading: {s}\n", .{script.script_path});
                script.reload(self.context, entity, self.allocator) catch |err| {
                    std.debug.print("[ScriptSystem] Hot-reload failed: {any}\n", .{err});
                };
            }
        }
    }

    /// Call onDestroy for all scripts (when shutting down).
    pub fn shutdown(self: *Self, scene: *Scene) void {
        const scripts = scene.scripts.items();

        for (scripts) |*script| {
            if (script.started) {
                script.callDestroy(self.context);
            }
            script.cleanup(self.context);
        }
    }
};
