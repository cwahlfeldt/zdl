const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;
const bindings = @import("bindings.zig");
const Entity = @import("../../ecs/entity.zig").Entity;

/// Register Scene API on the global object.
pub fn register(ctx: *JSContext) !void {
    const scene_code =
        \\var Scene = {
        \\    // Entity management (these call into the script system)
        \\    createEntity: function() {
        \\        __scene_create_entity = true;
        \\        return null; // Will be replaced by script system
        \\    },
        \\
        \\    destroyEntity: function(entity) {
        \\        if (!entity) return;
        \\        __scene_destroy_entities.push(entity);
        \\    },
        \\
        \\    entityExists: function(entity) {
        \\        if (!entity || !entity.valid) return false;
        \\        // Check in the entities registry
        \\        return __scene_entities['' + entity.id] || false;
        \\    },
        \\
        \\    // Camera management
        \\    setActiveCamera: function(entity) {
        \\        if (!entity) return;
        \\        __scene_set_camera = entity;
        \\    },
        \\
        \\    getActiveCamera: function() {
        \\        return __scene_active_camera;
        \\    },
        \\
        \\    // Find entities by name/tag (if implemented)
        \\    findByName: function(name) {
        \\        return __scene_named_entities[name] || null;
        \\    },
        \\
        \\    findByTag: function(tag) {
        \\        return __scene_tagged_entities[tag] || [];
        \\    },
        \\
        \\    // Get entity count
        \\    entityCount: function() {
        \\        return __scene_entity_count || 0;
        \\    },
        \\
        \\    // Parent-child hierarchy
        \\    setParent: function(child, parent) {
        \\        if (!child || !parent) return;
        \\        __scene_set_parent_requests.push({ child: child, parent: parent });
        \\    }
        \\};
        \\
        \\// Internal state managed by script system
        \\var __scene_create_entity = false;
        \\var __scene_destroy_entities = [];
        \\var __scene_set_camera = null;
        \\var __scene_active_camera = null;
        \\var __scene_entities = {};
        \\var __scene_named_entities = {};
        \\var __scene_tagged_entities = {};
        \\var __scene_entity_count = 0;
        \\var __scene_set_parent_requests = [];
        \\
        \\true;
    ;
    const result = try ctx.eval(scene_code, "<scene>");
    ctx.freeValue(result);
}

/// Update scene state for the current frame.
pub fn updateFrame(ctx: *JSContext, entity_count: u32, active_camera: Entity) void {
    ctx.setGlobal("__scene_entity_count", ctx.newInt32(@intCast(entity_count))) catch {};

    if (active_camera.isValid()) {
        const camera_js = bindings.entityToJS(ctx, active_camera);
        ctx.setGlobal("__scene_active_camera", camera_js) catch {};
    } else {
        ctx.setGlobal("__scene_active_camera", quickjs.NULL) catch {};
    }
}

/// Register an entity in the JavaScript registry.
pub fn registerEntity(ctx: *JSContext, entity: Entity) void {
    const entities = ctx.getGlobal("__scene_entities");
    defer ctx.freeValue(entities);

    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch return;

    ctx.setProperty(entities, key, ctx.newBool(true)) catch {};
}

/// Unregister an entity from the JavaScript registry.
pub fn unregisterEntity(ctx: *JSContext, entity: Entity) void {
    const entities = ctx.getGlobal("__scene_entities");
    defer ctx.freeValue(entities);

    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch return;

    ctx.setProperty(entities, key, ctx.newBool(false)) catch {};
}

/// Check if entity creation was requested.
pub fn checkCreateEntityRequest(ctx: *JSContext) bool {
    const flag = ctx.getGlobal("__scene_create_entity");
    defer ctx.freeValue(flag);

    const result = ctx.toBool(flag) catch false;
    if (result) {
        ctx.setGlobal("__scene_create_entity", ctx.newBool(false)) catch {};
    }
    return result;
}

/// Get entities to destroy.
pub fn getDestroyRequests(ctx: *JSContext, allocator: std.mem.Allocator) ![]Entity {
    const arr = ctx.getGlobal("__scene_destroy_entities");
    defer ctx.freeValue(arr);

    var entities: std.ArrayList(Entity) = .{};
    errdefer entities.deinit(allocator);

    var i: u32 = 0;
    while (true) : (i += 1) {
        const item = ctx.context.getPropertyUint32(arr, i);
        defer ctx.freeValue(item);

        if (ctx.isUndefined(item)) break;

        if (bindings.jsToEntity(ctx, item)) |entity| {
            try entities.append(allocator, entity);
        } else |_| {}
    }

    // Clear the array
    ctx.setGlobal("__scene_destroy_entities", ctx.newArray()) catch {};

    return entities.toOwnedSlice(allocator);
}

/// Check if camera was set.
pub fn checkSetCameraRequest(ctx: *JSContext) ?Entity {
    const camera_val = ctx.getGlobal("__scene_set_camera");
    defer ctx.freeValue(camera_val);

    if (ctx.isNull(camera_val)) return null;

    const entity = bindings.jsToEntity(ctx, camera_val) catch return null;

    // Clear the request
    ctx.setGlobal("__scene_set_camera", quickjs.NULL) catch {};

    return entity;
}

/// Process setParent requests from JavaScript.
pub fn processSetParentRequests(ctx: *JSContext, scene: *@import("../../ecs/scene.zig").Scene) void {
    const requests = ctx.getGlobal("__scene_set_parent_requests");
    defer ctx.freeValue(requests);

    if (ctx.isUndefined(requests)) return;

    var i: u32 = 0;
    while (true) : (i += 1) {
        const request = ctx.context.getPropertyUint32(requests, i);
        defer ctx.freeValue(request);

        if (ctx.isUndefined(request)) break;

        const child_val = ctx.getProperty(request, "child");
        const parent_val = ctx.getProperty(request, "parent");
        defer ctx.freeValue(child_val);
        defer ctx.freeValue(parent_val);

        const child = bindings.jsToEntity(ctx, child_val) catch continue;
        const parent = bindings.jsToEntity(ctx, parent_val) catch continue;

        scene.setParent(child, parent);
    }

    // Clear the requests
    ctx.setGlobal("__scene_set_parent_requests", ctx.newArray()) catch {};
}
