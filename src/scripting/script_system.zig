const std = @import("std");
const quickjs = @import("quickjs");

const Entity = @import("../ecs/entity.zig").Entity;
const Scene = @import("../ecs/scene.zig").Scene;
const Input = @import("../input/input.zig").Input;
const TransformComponent = @import("../ecs/components/transform_component.zig").TransformComponent;

const JSRuntime = @import("js_runtime.zig").JSRuntime;
const JSContext = @import("js_context.zig").JSContext;
const ScriptComponent = @import("script_component.zig").ScriptComponent;
const SystemRegistry = @import("system_registry.zig").SystemRegistry;
const ScriptContext = @import("script_context.zig").ScriptContext;
const bindings = @import("bindings/bindings.zig");

const math_api = @import("bindings/math_api.zig");
const console_api = @import("bindings/console_api.zig");
const engine_api = @import("bindings/engine_api.zig");
const input_api = @import("bindings/input_api.zig");
const scene_api = @import("bindings/scene_api.zig");
const transform_api = @import("bindings/transform_api.zig");
const component_api = @import("bindings/component_api.zig");
const query_api = @import("bindings/query_api.zig");
const world_api = @import("bindings/world_api.zig");
const zdl_api = @import("bindings/zdl_api.zig");
const component_sync = @import("bindings/component_sync.zig");

/// System that manages JavaScript scripting.
/// Initializes the JS runtime, registers bindings, and updates scripts each frame.
pub const ScriptSystem = struct {
    allocator: std.mem.Allocator,
    runtime: *JSRuntime,
    context: *JSContext,
    system_registry: SystemRegistry,

    /// Total time elapsed
    total_time: f32,

    /// Hot reload check interval (in seconds)
    reload_check_interval: f32,
    reload_check_timer: f32,

    /// Scripts pending load
    pending_loads: std.ArrayList(Entity),

    /// Whether world init systems have run
    systems_initialized: bool,

    /// Whether Flecs world has been connected to the registry
    flecs_connected: bool,

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
        std.debug.print("[ScriptSystem] Registering component API...\n", .{});
        try component_api.register(context);
        std.debug.print("[ScriptSystem] Registering zdl API...\n", .{});
        try zdl_api.register(context);
        std.debug.print("[ScriptSystem] Registering world API...\n", .{});
        try world_api.register(context);
        std.debug.print("[ScriptSystem] Registering query API...\n", .{});
        try query_api.register(context);
        std.debug.print("[ScriptSystem] All APIs registered\n", .{});

        var system_registry = SystemRegistry.init(allocator);
        // Note: Flecs world will be set later when update() is called with a scene
        system_registry.setFlecsWorld(null, context);

        // Initialize component sync mesh cache
        component_sync.init(allocator);

        return .{
            .allocator = allocator,
            .runtime = runtime,
            .context = context,
            .system_registry = system_registry,
            .total_time = 0,
            .reload_check_interval = 1.0,
            .reload_check_timer = 0,
            .pending_loads = .{},
            .systems_initialized = false,
            .flecs_connected = false,
        };
    }

    /// Deinitialize the script system.
    pub fn deinit(self: *Self, device: anytype) void {
        // Clean up component sync mesh cache
        component_sync.deinit(device);

        self.system_registry.deinit();
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
        script_ctx: *const ScriptContext,
        input: *Input,
        delta_time: f32,
    ) void {
        self.total_time += delta_time;

        // Connect Flecs world to system registry on first update
        if (!self.flecs_connected) {
            self.system_registry.setFlecsWorld(scene.world, self.context);
            self.flecs_connected = true;
            std.debug.print("[ScriptSystem] Connected Flecs world to system registry\n", .{});
        }

        // Set up binding context
        var ctx = bindings.BindingContext{
            .js_ctx = self.context,
            .script_ctx = script_ctx,
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
            @as(u32, @intFromFloat(script_ctx.fps)),
            script_ctx.window_width,
            script_ctx.window_height,
            script_ctx.mouse_captured,
        );

        // Update input state in JavaScript
        input_api.updateFrame(self.context, input);

        // Update scene state in JavaScript
        scene_api.updateFrame(
            self.context,
            scene.entityCount(),
            scene.getActiveCamera(),
        );

        // Sync transforms from Zig to JavaScript for all scripted entities
        scene.iterateScripts(syncTransformCallback, &ctx);

        // Start any unstarted scripts
        scene.iterateScripts(startScriptCallback, &ctx);

        // Update all scripts
        scene.iterateScripts(updateScriptCallback, &ctx);

        // Process transform updates from JavaScript
        transform_api.processUpdates(self.context, scene);

        // Process pending JavaScript jobs (promises)
        self.context.processPendingJobs();

        // Flush console messages
        console_api.flushMessages(self.context);

        // Check for engine quit request
        if (engine_api.checkQuitRequested(self.context)) {
            script_ctx.requestQuit();
        }

        // Check for mouse capture request
        if (engine_api.checkMouseCaptureRequest(self.context)) |captured| {
            script_ctx.setMouseCapture(captured);
        }

        // Check for gamepad rumble request
        if (input_api.checkRumbleRequest(self.context)) |rumble| {
            if (input.getGamepad()) |gamepad| {
                gamepad.rumble(rumble.low, rumble.high, rumble.duration);
            }
        }

        // Process scene requests (entity creation/destruction)
        self.processSceneRequests(scene);

        // Process setParent requests
        scene_api.processSetParentRequests(self.context, scene);

        // Process component operations from JavaScript (registers types)
        component_api.processQueue(self.context, scene);

        // Process world entity creation requests
        world_api.processCreateEntityRequests(self.context, scene);
        component_api.processComponentRequests(self.context, scene);

        // Refresh native query cache for requested queries
        query_api.processNativeCache(self.context, scene, self.allocator);

        // Sync JS components to native components for rendering
        component_sync.syncComponentsToNative(self.context, scene, self.allocator, script_ctx.getDevice()) catch |err| {
            std.debug.print("[ScriptSystem] Error syncing components to native: {}\n", .{err});
        };

        // Sync JavaScript systems to native registry (only adds new ones)
        world_api.syncSystemsToRegistry(self.context, &self.system_registry, self.allocator) catch |err| {
            std.debug.print("[ScriptSystem] Error syncing systems to registry: {}\n", .{err});
        };

        // Run world init systems once
        if (!self.systems_initialized) {
            self.system_registry.runPhase(.init);
            self.systems_initialized = true;
        }

        // Run world update systems every frame
        self.system_registry.runPhase(.update);

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
            const entity = scene.createEntity();
            scene_api.registerEntity(self.context, entity);
            std.debug.print("[ScriptSystem] Created entity from JS: {any}\n", .{entity});
        }

        // Process entity destruction requests
        const destroy_requests = scene_api.getDestroyRequests(self.context, self.allocator) catch &[_]Entity{};
        defer if (destroy_requests.len > 0) self.allocator.free(destroy_requests);

        for (destroy_requests) |entity| {
            scene_api.unregisterEntity(self.context, entity);
            scene.destroyEntity(entity);
        }

        // Check for camera change request
        if (scene_api.checkSetCameraRequest(self.context)) |camera_entity| {
            scene.setActiveCamera(camera_entity);
        }
    }

    /// Check for scripts that need hot reloading.
    fn checkHotReload(self: *Self, scene: *Scene) void {
        scene.iterateScripts(hotReloadCallback, self);
    }

    /// Call onDestroy for all scripts (when shutting down).
    pub fn shutdown(self: *Self, scene: *Scene) void {
        // Run destroy phase systems through the registry
        self.system_registry.runPhase(.destroy);
        scene.iterateScripts(shutdownScriptCallback, self);
    }
};

// ============================================================================
// Iterator Callbacks
// ============================================================================

// Callback to sync transforms for scripted entities
fn syncTransformCallback(entity: Entity, _: *ScriptComponent, userdata: *anyopaque) void {
    const ctx: *bindings.BindingContext = @alignCast(@ptrCast(userdata));
    if (ctx.scene.getComponent(TransformComponent, entity)) |transform| {
        transform_api.syncTransform(ctx.js_ctx, entity, transform);
    }
}

// Callback to start unstarted scripts
fn startScriptCallback(entity: Entity, script: *ScriptComponent, userdata: *anyopaque) void {
    const ctx: *bindings.BindingContext = @alignCast(@ptrCast(userdata));
    if (!script.started and script.enabled) {
        if (!script.loaded) {
            script.load(ctx.js_ctx, entity, ctx.allocator) catch return;
        }
        ctx.current_entity = entity;
        script.callStart(ctx.js_ctx);
    }
}

// Callback to update scripts
fn updateScriptCallback(entity: Entity, script: *ScriptComponent, userdata: *anyopaque) void {
    const ctx: *bindings.BindingContext = @alignCast(@ptrCast(userdata));
    if (script.enabled and script.started) {
        ctx.current_entity = entity;
        script.callUpdate(ctx.js_ctx, ctx.delta_time);
    }
}

// Callback to check for hot reload
fn hotReloadCallback(entity: Entity, script: *ScriptComponent, userdata: *anyopaque) void {
    const self: *ScriptSystem = @alignCast(@ptrCast(userdata));
    if (script.needsReload()) {
        std.debug.print("[ScriptSystem] Hot-reloading: {s}\n", .{script.script_path});
        script.reload(self.context, entity, self.allocator) catch |err| {
            std.debug.print("[ScriptSystem] Hot-reload failed: {any}\n", .{err});
        };
    }
}

// Callback to shutdown scripts
fn shutdownScriptCallback(_: Entity, script: *ScriptComponent, userdata: *anyopaque) void {
    const self: *ScriptSystem = @alignCast(@ptrCast(userdata));
    if (script.started) {
        script.callDestroy(self.context);
    }
    script.cleanup(self.context);
}
