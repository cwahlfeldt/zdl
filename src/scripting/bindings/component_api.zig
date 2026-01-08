const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;
const bindings = @import("bindings.zig");
const Scene = @import("../../ecs/scene.zig").Scene;
const JSRuntime = @import("../js_runtime.zig").JSRuntime;

/// Register Component API on the global object.
pub fn register(ctx: *JSContext) !void {
    const component_code =
        \\var Component = {
        \\    register: function(typeName, schema, isTag) {
        \\        if (!typeName) return false;
        \\        __component_registry[typeName] = {
        \\            schema: schema || {},
        \\            isTag: !!isTag
        \\        };
        \\        __component_ops.push({
        \\            op: "register",
        \\            typeName: typeName,
        \\            schema: schema || {},
        \\            isTag: !!isTag
        \\        });
        \\        __component_store_version++;
        \\        return true;
        \\    },
        \\
        \\    add: function(entity, typeName, data) {
        \\        if (!entity || !entity.valid) return false;
        \\        if (!__component_store[typeName]) __component_store[typeName] = {};
        \\        __component_store[typeName]['' + entity.id] = data || {};
        \\        __component_ops.push({
        \\            op: "add",
        \\            entity: entity,
        \\            typeName: typeName,
        \\            data: data || {}
        \\        });
        \\        __component_store_version++;
        \\        return true;
        \\    },
        \\
        \\    get: function(entity, typeName) {
        \\        if (!entity || !entity.valid) return null;
        \\        var store = __component_store[typeName];
        \\        if (!store) return null;
        \\        return store['' + entity.id] || null;
        \\    },
        \\
        \\    has: function(entity, typeName) {
        \\        if (!entity || !entity.valid) return false;
        \\        var store = __component_store[typeName];
        \\        if (!store) return false;
        \\        return !!store['' + entity.id];
        \\    },
        \\
        \\    remove: function(entity, typeName) {
        \\        if (!entity || !entity.valid) return false;
        \\        var store = __component_store[typeName];
        \\        if (!store) return false;
        \\        if (store['' + entity.id]) {
        \\            delete store['' + entity.id];
        \\            __component_ops.push({
        \\                op: "remove",
        \\                entity: entity,
        \\                typeName: typeName
        \\            });
        \\            __component_store_version++;
        \\            return true;
        \\        }
        \\        return false;
        \\    },
        \\
        \\    update: function(entity, typeName, data) {
        \\        if (!entity || !entity.valid) return false;
        \\        if (!__component_store[typeName]) __component_store[typeName] = {};
        \\        __component_store[typeName]['' + entity.id] = data || {};
        \\        __component_ops.push({
        \\            op: "update",
        \\            entity: entity,
        \\            typeName: typeName,
        \\            data: data || {}
        \\        });
        \\        __component_store_version++;
        \\        return true;
        \\    }
        \\};
        \\
        \\var __component_registry = {};
        \\var __component_store = {};
        \\var __component_ops = [];
        \\var __component_store_version = 0;
        \\
        \\true;
    ;
    const result = try ctx.eval(component_code, "<component>");
    ctx.freeValue(result);
}

/// Process queued component operations from JavaScript.
pub fn processQueue(ctx: *JSContext, scene: *Scene) void {
    const ops = ctx.getGlobal("__component_ops");
    defer ctx.freeValue(ops);

    var i: u32 = 0;
    while (true) : (i += 1) {
        const op_val = ctx.context.getPropertyUint32(ops, i);
        defer ctx.freeValue(op_val);

        if (ctx.isUndefined(op_val)) break;

        const op_type = ctx.getProperty(op_val, "op");
        defer ctx.freeValue(op_type);

        const op_cstr = ctx.toCString(op_type) catch continue;
        defer ctx.freeCString(op_cstr);
        const op = std.mem.span(op_cstr);

        if (std.mem.eql(u8, op, "register")) {
            const type_val = ctx.getProperty(op_val, "typeName");
            const schema_val = ctx.getProperty(op_val, "schema");
            const is_tag_val = ctx.getProperty(op_val, "isTag");
            defer ctx.freeValue(type_val);
            defer ctx.freeValue(schema_val);
            defer ctx.freeValue(is_tag_val);

            const type_cstr = ctx.toCString(type_val) catch continue;
            defer ctx.freeCString(type_cstr);

            const type_name = std.mem.span(type_cstr);
            const is_tag = ctx.toBool(is_tag_val) catch false;

            const schema_json = ctx.context.jsonStringify(schema_val, quickjs.UNDEFINED, quickjs.UNDEFINED);
            defer ctx.context.freeValue(schema_json);
            if (ctx.context.isException(schema_json) or ctx.isUndefined(schema_json)) continue;

            if (ctx.toCString(schema_json)) |schema_cstr| {
                defer ctx.freeCString(schema_cstr);
                scene.registerJsComponent(type_name, std.mem.span(schema_cstr), is_tag) catch {};
            } else |_| {}
        } else if (std.mem.eql(u8, op, "add") or std.mem.eql(u8, op, "update")) {
            const entity_val = ctx.getProperty(op_val, "entity");
            const type_val = ctx.getProperty(op_val, "typeName");
            const data_val = ctx.getProperty(op_val, "data");
            defer ctx.freeValue(entity_val);
            defer ctx.freeValue(type_val);
            defer ctx.freeValue(data_val);

            const entity = bindings.jsToEntity(ctx, entity_val) catch continue;
            const type_cstr = ctx.toCString(type_val) catch continue;
            defer ctx.freeCString(type_cstr);

            const data_json = ctx.context.jsonStringify(data_val, quickjs.UNDEFINED, quickjs.UNDEFINED);
            defer ctx.context.freeValue(data_json);
            if (ctx.context.isException(data_json) or ctx.isUndefined(data_json)) continue;

            if (ctx.toCString(data_json)) |data_cstr| {
                defer ctx.freeCString(data_cstr);
                const payload = std.mem.span(data_cstr);
                if (std.mem.eql(u8, op, "add")) {
                    scene.addJsComponent(entity, std.mem.span(type_cstr), payload) catch {};
                } else {
                    scene.updateJsComponent(entity, std.mem.span(type_cstr), payload) catch {};
                }
            } else |_| {}
        } else if (std.mem.eql(u8, op, "remove")) {
            const entity_val = ctx.getProperty(op_val, "entity");
            const type_val = ctx.getProperty(op_val, "typeName");
            defer ctx.freeValue(entity_val);
            defer ctx.freeValue(type_val);

            const entity = bindings.jsToEntity(ctx, entity_val) catch continue;
            const type_cstr = ctx.toCString(type_val) catch continue;
            defer ctx.freeCString(type_cstr);

            scene.removeJsComponent(entity, std.mem.span(type_cstr));
        }
    }

    ctx.setGlobal("__component_ops", ctx.newArray()) catch {};
}

pub fn processComponentRequests(ctx: *JSContext, scene: *Scene) void {
    const requests = ctx.getGlobal("__world_component_requests");
    defer ctx.freeValue(requests);
    if (ctx.isUndefined(requests)) return;

    const cache = ctx.getGlobal("__world_component_cache");
    defer ctx.freeValue(cache);
    if (ctx.isUndefined(cache)) return;

    const cache_versions = ctx.getGlobal("__world_component_cache_versions");
    defer ctx.freeValue(cache_versions);
    if (ctx.isUndefined(cache_versions)) return;

    const has_cache = ctx.getGlobal("__world_component_has_cache");
    defer ctx.freeValue(has_cache);
    if (ctx.isUndefined(has_cache)) return;

    const has_cache_versions = ctx.getGlobal("__world_component_has_cache_versions");
    defer ctx.freeValue(has_cache_versions);
    if (ctx.isUndefined(has_cache_versions)) return;

    const version_val = ctx.getGlobal("__component_store_version");
    defer ctx.freeValue(version_val);
    const version = ctx.toInt32(version_val) catch 0;

    var i: u32 = 0;
    while (true) : (i += 1) {
        const request = ctx.context.getPropertyUint32(requests, i);
        defer ctx.freeValue(request);

        if (ctx.isUndefined(request)) break;

        const op_val = ctx.getProperty(request, "op");
        const entity_val = ctx.getProperty(request, "entity");
        const type_val = ctx.getProperty(request, "typeName");
        defer ctx.freeValue(op_val);
        defer ctx.freeValue(entity_val);
        defer ctx.freeValue(type_val);

        const op_cstr = ctx.toCString(op_val) catch continue;
        defer ctx.freeCString(op_cstr);

        const type_cstr = ctx.toCString(type_val) catch continue;
        defer ctx.freeCString(type_cstr);

        const entity = bindings.jsToEntity(ctx, entity_val) catch continue;
        const type_name = std.mem.span(type_cstr);
        const type_z: [:0]const u8 = type_cstr[0..type_name.len :0];

        var key_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch continue;

        const type_map = getOrCreateMap(ctx, cache, type_z);
        defer ctx.freeValue(type_map);
        const type_versions = getOrCreateMap(ctx, cache_versions, type_z);
        defer ctx.freeValue(type_versions);
        const type_has_map = getOrCreateMap(ctx, has_cache, type_z);
        defer ctx.freeValue(type_has_map);
        const type_has_versions = getOrCreateMap(ctx, has_cache_versions, type_z);
        defer ctx.freeValue(type_has_versions);

        const op = std.mem.span(op_cstr);
        if (std.mem.eql(u8, op, "get")) {
            var has = false;
            var value = quickjs.NULL;
            if (scene.getJsComponent(entity, type_name)) |json| {
                value = ctx.context.parseJSON(json, "<component>");
                if (!ctx.context.isException(value)) {
                    has = true;
                } else {
                    ctx.context.freeValue(value);
                    value = quickjs.NULL;
                }
            }

            ctx.setProperty(type_map, key, value) catch {};
            ctx.setProperty(type_versions, key, ctx.newInt32(version)) catch {};
            ctx.setProperty(type_has_map, key, ctx.newBool(has)) catch {};
            ctx.setProperty(type_has_versions, key, ctx.newInt32(version)) catch {};
        } else if (std.mem.eql(u8, op, "has")) {
            const has = scene.hasJsComponent(entity, type_name);
            ctx.setProperty(type_has_map, key, ctx.newBool(has)) catch {};
            ctx.setProperty(type_has_versions, key, ctx.newInt32(version)) catch {};
        }
    }

    ctx.setGlobal("__world_component_requests", ctx.newArray()) catch {};
}

fn getOrCreateMap(ctx: *JSContext, parent: quickjs.Value, type_name: [:0]const u8) quickjs.Value {
    const existing = ctx.getProperty(parent, type_name);
    if (!ctx.isUndefined(existing)) {
        return existing;
    }
    ctx.freeValue(existing);
    const created = ctx.newObject();
    const created_ref = ctx.dupValue(created);
    ctx.setProperty(parent, type_name, created_ref) catch {
        ctx.freeValue(created_ref);
    };
    return created;
}

test "component api queues update scene storage" {
    var runtime = try JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    try register(&ctx);

    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const entity = scene.createEntity();
    const entity_js = bindings.entityToJS(&ctx, entity);
    try ctx.setGlobal("__test_entity", entity_js);

    const register_add =
        \\Component.register("Health", {value: "number"}, false);
        \\Component.add(__test_entity, "Health", {value: 100});
        \\true;
    ;
    const result1 = try ctx.eval(register_add, "<component-test>");
    ctx.freeValue(result1);

    processQueue(&ctx, &scene);

    try std.testing.expect(scene.hasJsComponent(entity, "Health"));
    try std.testing.expectEqualStrings("{\"value\":100}", scene.getJsComponent(entity, "Health").?);

    const schema = scene.getJsComponentSchema("Health") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("{\"value\":\"number\"}", schema.schema_json);

    const update_code =
        \\Component.update(__test_entity, "Health", {value: 90});
        \\true;
    ;
    const result2 = try ctx.eval(update_code, "<component-test>");
    ctx.freeValue(result2);

    processQueue(&ctx, &scene);

    try std.testing.expectEqualStrings("{\"value\":90}", scene.getJsComponent(entity, "Health").?);

    const remove_code =
        \\Component.remove(__test_entity, "Health");
        \\true;
    ;
    const result3 = try ctx.eval(remove_code, "<component-test>");
    ctx.freeValue(result3);

    processQueue(&ctx, &scene);

    try std.testing.expect(!scene.hasJsComponent(entity, "Health"));
}
