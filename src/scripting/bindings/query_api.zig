const std = @import("std");

const JSContext = @import("../js_context.zig").JSContext;
const JSRuntime = @import("../js_runtime.zig").JSRuntime;
const Scene = @import("../../ecs/scene.zig").Scene;
const bindings = @import("bindings.zig");
const component_api = @import("component_api.zig");

/// Register Query API on the global object.
pub fn register(ctx: *JSContext) !void {
    const query_code =
        \\if (typeof __component_store === 'undefined') {
        \\    var __component_store = {};
        \\}
        \\
        \\function __queryTypeName(arg) {
        \\    if (typeof arg === 'string') return arg;
        \\    if (typeof arg === 'function') {
        \\        try {
        \\            var sample = arg();
        \\            if (sample && sample.type) return sample.type;
        \\        } catch (e) {}
        \\        return null;
        \\    }
        \\    if (arg && typeof arg === 'object' && arg.type) return arg.type;
        \\    return null;
        \\}
        \\
        \\function __queryByTypes(typeNames) {
        \\    if (!typeNames || typeNames.length === 0) return [];
        \\    var baseStore = null;
        \\    for (var i = 0; i < typeNames.length; i++) {
        \\        var store = __component_store[typeNames[i]];
        \\        if (!store) return [];
        \\        if (!baseStore || Object.keys(store).length < Object.keys(baseStore).length) {
        \\            baseStore = store;
        \\        }
        \\    }
        \\    var results = [];
        \\    for (var id in baseStore) {
        \\        var ok = true;
        \\        for (var j = 0; j < typeNames.length; j++) {
        \\            var storeCheck = __component_store[typeNames[j]];
        \\            if (!storeCheck || !storeCheck[id]) {
        \\                ok = false;
        \\                break;
        \\            }
        \\        }
        \\        if (ok) results.push(parseInt(id, 10));
        \\    }
        \\    return results;
        \\}
        \\
        \\function __entityFromId(id) {
        \\    return { id: id, valid: true };
        \\}
        \\
        \\function QueryResult(ids) {
        \\    this._ids = ids || [];
        \\}
        \\QueryResult.prototype[Symbol.iterator] = function* () {
        \\    for (var i = 0; i < this._ids.length; i++) {
        \\        yield __entityFromId(this._ids[i]);
        \\    }
        \\};
        \\
        \\if (typeof World === 'undefined') { function World() {} }
        \\World.prototype.query = function() {
        \\    var typeNames = [];
        \\    for (var i = 0; i < arguments.length; i++) {
        \\        var typeName = __queryTypeName(arguments[i]);
        \\        if (typeName) typeNames.push(typeName);
        \\    }
        \\    var ids = null;
        \\    var key = typeNames.join('|');
        \\    var version = __component_store_version || 0;
        \\    if (__query_native_cache[key] && __query_native_cache_versions[key] === version) {
        \\        ids = __query_native_cache[key];
        \\    } else {
        \\        if (__query_native_requested[key] !== version) {
        \\            __query_native_requests.push(typeNames.slice());
        \\            __query_native_requested[key] = version;
        \\        }
        \\        ids = __queryByTypes(typeNames);
        \\    }
        \\    return new QueryResult(ids);
        \\};
        \\
        \\var __query_native_cache = {};
        \\var __query_native_cache_versions = {};
        \\var __query_native_requests = [];
        \\var __query_native_requested = {};
        \\
        \\true;
    ;
    const result = try ctx.eval(query_code, "<query>");
    ctx.freeValue(result);
}

pub fn processNativeCache(ctx: *JSContext, scene: *Scene, allocator: std.mem.Allocator) void {
    const requests = ctx.getGlobal("__query_native_requests");
    defer ctx.freeValue(requests);

    const cache = ctx.getGlobal("__query_native_cache");
    defer ctx.freeValue(cache);

    const cache_versions = ctx.getGlobal("__query_native_cache_versions");
    defer ctx.freeValue(cache_versions);

    const version_val = ctx.getGlobal("__component_store_version");
    defer ctx.freeValue(version_val);
    const version = ctx.toInt32(version_val) catch 0;

    var request_index: u32 = 0;
    while (true) : (request_index += 1) {
        const request_val = ctx.context.getPropertyUint32(requests, request_index);
        defer ctx.freeValue(request_val);

        if (ctx.isUndefined(request_val)) break;
        if (!ctx.isObject(request_val)) continue;

        var type_names = std.ArrayList([]const u8).empty;
        var cstrings = std.ArrayList([*:0]const u8).empty;
        defer {
            for (cstrings.items) |cstr| {
                ctx.freeCString(cstr);
            }
            cstrings.deinit(allocator);
            type_names.deinit(allocator);
        }

        const length_val = ctx.getProperty(request_val, "length");
        defer ctx.freeValue(length_val);
        const length_i32 = ctx.toInt32(length_val) catch 0;
        if (length_i32 <= 0) continue;

        var i: u32 = 0;
        while (i < @as(u32, @intCast(length_i32))) : (i += 1) {
            const item = ctx.context.getPropertyUint32(request_val, i);
            defer ctx.freeValue(item);
            if (ctx.isUndefined(item) or ctx.isNull(item)) continue;

            const type_cstr = ctx.toCString(item) catch continue;
            cstrings.append(allocator, type_cstr) catch {
                ctx.freeCString(type_cstr);
                continue;
            };
            type_names.append(allocator, std.mem.span(type_cstr)) catch continue;
        }

        if (type_names.items.len == 0) continue;

        const entities = scene.queryJsComponents(allocator, type_names.items) catch continue;
        defer allocator.free(entities);

        var key_builder = std.ArrayList(u8).empty;
        defer key_builder.deinit(allocator);

        for (type_names.items, 0..) |name, idx| {
            if (idx > 0) {
                key_builder.append(allocator, '|') catch continue;
            }
            key_builder.appendSlice(allocator, name) catch continue;
        }

        const key_slice = key_builder.toOwnedSlice(allocator) catch continue;
        defer allocator.free(key_slice);

        var key_z_buf = allocator.alloc(u8, key_slice.len + 1) catch continue;
        @memcpy(key_z_buf[0..key_slice.len], key_slice);
        key_z_buf[key_slice.len] = 0;
        const key_z: [:0]const u8 = key_z_buf[0..key_slice.len :0];
        defer allocator.free(key_z_buf);

        const result = ctx.newArray();
        for (entities, 0..) |entity, idx| {
            ctx.context.setPropertyUint32(result, @intCast(idx), ctx.newFloat64(@floatFromInt(entity.id))) catch {};
        }

        ctx.setProperty(cache, key_z, result) catch {
            ctx.freeValue(result);
            continue;
        };
        ctx.setProperty(cache_versions, key_z, ctx.newInt32(version)) catch {};
    }

    ctx.setGlobal("__query_native_requests", ctx.newArray()) catch {};
}

test "query api returns intersection results" {
    var runtime = try JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    try component_api.register(&ctx);
    try register(&ctx);

    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const entity_a = scene.createEntity();
    const entity_b = scene.createEntity();

    const entity_a_js = bindings.entityToJS(&ctx, entity_a);
    const entity_b_js = bindings.entityToJS(&ctx, entity_b);
    try ctx.setGlobal("__entity_a", entity_a_js);
    try ctx.setGlobal("__entity_b", entity_b_js);

    const setup_code =
        \\Component.register("Player", {}, true);
        \\Component.register("Position", {x: "number"}, false);
        \\Component.add(__entity_a, "Player", {});
        \\Component.add(__entity_a, "Position", {x: 1});
        \\Component.add(__entity_b, "Player", {});
        \\true;
    ;
    const setup_result = try ctx.eval(setup_code, "<query-test>");
    ctx.freeValue(setup_result);

    component_api.processQueue(&ctx, &scene);

    const query_code =
        \\var world = new World();
        \\var ids = [];
        \\for (var e of world.query(function(){ return {type: "Player"}; }, function(){ return {type: "Position"}; })) {
        \\    ids.push(e.id);
        \\}
        \\__query_ids = ids;
        \\true;
    ;
    const query_result = try ctx.eval(query_code, "<query-test>");
    ctx.freeValue(query_result);

    processNativeCache(&ctx, &scene, std.testing.allocator);

    const ids_val = ctx.getGlobal("__query_ids");
    defer ctx.freeValue(ids_val);

    var ids = std.ArrayList(u64).empty;
    defer ids.deinit(std.testing.allocator);

    var i: u32 = 0;
    while (true) : (i += 1) {
        const item = ctx.context.getPropertyUint32(ids_val, i);
        defer ctx.freeValue(item);
        if (ctx.isUndefined(item)) break;
        const id_float = ctx.toFloat64(item) catch continue;
        try ids.append(std.testing.allocator, @intFromFloat(id_float));
    }

    try std.testing.expectEqual(@as(usize, 1), ids.items.len);
    try std.testing.expectEqual(entity_a.id, ids.items[0]);
}
