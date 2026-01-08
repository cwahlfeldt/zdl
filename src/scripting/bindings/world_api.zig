const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;
const JSRuntime = @import("../js_runtime.zig").JSRuntime;
const Scene = @import("../../ecs/scene.zig").Scene;
const Entity = @import("../../ecs/entity.zig").Entity;
const bindings = @import("bindings.zig");
const component_api = @import("component_api.zig");
const scene_api = @import("scene_api.zig");

/// Register World API and zdl.createWorld.
pub fn register(ctx: *JSContext) !void {
    const world_code =
        \\if (typeof zdl === 'undefined') { var zdl = {}; }
        \\
        \\function __worldTypeName(arg) {
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
        \\function __worldNormalizeMetadata(meta) {
        \\    if (!meta || typeof meta !== 'object') return { name: null, description: null };
        \\    var name = meta.name;
        \\    if (typeof name !== 'string' || name.length === 0) name = null;
        \\    var description = meta.description;
        \\    if (typeof description !== 'string' || description.length === 0) description = null;
        \\    return { name: name, description: description };
        \\}
        \\
        \\function World() {}
        \\
        \\World.prototype.getComponent = function(entity, typeRef) {
        \\    if (!entity || !entity.valid) return null;
        \\    var typeName = __worldTypeName(typeRef);
        \\    if (!typeName) return null;
        \\    var version = __component_store_version || 0;
        \\    var cache = __world_component_cache[typeName];
        \\    var cacheVersions = __world_component_cache_versions[typeName];
        \\    var key = '' + entity.id;
        \\    if (cache && cacheVersions && cacheVersions[key] === version && cache[key] !== undefined) {
        \\        return cache[key];
        \\    }
        \\    var reqKey = 'get:' + typeName + '|' + key;
        \\    if (__world_component_requests_map[reqKey] !== version) {
        \\        __world_component_requests.push({ op: "get", entity: entity, typeName: typeName });
        \\        __world_component_requests_map[reqKey] = version;
        \\    }
        \\    return Component.get(entity, typeName);
        \\};
        \\
        \\World.prototype.hasComponent = function(entity, typeRef) {
        \\    if (!entity || !entity.valid) return false;
        \\    var typeName = __worldTypeName(typeRef);
        \\    if (!typeName) return false;
        \\    var version = __component_store_version || 0;
        \\    var cache = __world_component_has_cache[typeName];
        \\    var cacheVersions = __world_component_has_cache_versions[typeName];
        \\    var key = '' + entity.id;
        \\    if (cache && cacheVersions && cacheVersions[key] === version) {
        \\        return !!cache[key];
        \\    }
        \\    var reqKey = 'has:' + typeName + '|' + key;
        \\    if (__world_component_requests_map[reqKey] !== version) {
        \\        __world_component_requests.push({ op: "has", entity: entity, typeName: typeName });
        \\        __world_component_requests_map[reqKey] = version;
        \\    }
        \\    return Component.has(entity, typeName);
        \\};
        \\
        \\World.prototype.updateComponent = function(entity, data) {
        \\    if (!entity || !entity.valid) return false;
        \\    var typeName = __worldTypeName(data);
        \\    if (!typeName) return false;
        \\    return Component.update(entity, typeName, data);
        \\};
        \\
        \\World.prototype.addEntity = function(metadataFn) {
        \\    return function() {
        \\        var metadata = __worldNormalizeMetadata(metadataFn ? metadataFn({}) : {});
        \\        var entity = { id: 0, valid: false };
        \\        var components = [];
        \\        var seen = {};
        \\        for (var i = 0; i < arguments.length; i++) {
        \\            var comp = arguments[i];
        \\            if (typeof comp === 'function') {
        \\                try { comp = comp(); } catch (e) { comp = null; }
        \\            }
        \\            if (!comp || !comp.type) {
        \\                if (typeof __native_console_warn === 'function') {
        \\                    __native_console_warn("World.addEntity: component missing type, skipping.");
        \\                }
        \\                continue;
        \\            }
        \\            if (seen[comp.type]) {
        \\                if (typeof __native_console_warn === 'function') {
        \\                    __native_console_warn("World.addEntity: duplicate component type '" + comp.type + "', skipping.");
        \\                }
        \\                continue;
        \\            }
        \\            seen[comp.type] = true;
        \\            components.push({ typeName: comp.type, data: comp });
        \\        }
        \\        __world_create_entity_requests.push({
        \\            entity: entity,
        \\            name: metadata.name,
        \\            description: metadata.description,
        \\            components: components
        \\        });
        \\        return entity;
        \\    };
        \\};
        \\
        \\World.prototype.addComponents = function(factories) {
        \\    if (!factories || !factories.length) return;
        \\    for (var i = 0; i < factories.length; i++) {
        \\        var factory = factories[i];
        \\        if (typeof factory !== 'function') continue;
        \\        var sample = factory();
        \\        if (!sample || !sample.type) continue;
        \\        var schema = {};
        \\        for (var key in sample) {
        \\            if (key === 'type' || key === 'name') continue;
        \\            schema[key] = typeof sample[key];
        \\        }
        \\        var isTag = true;
        \\        for (var key2 in sample) {
        \\            if (key2 !== 'type' && key2 !== 'name') { isTag = false; break; }
        \\        }
        \\        Component.register(sample.type, schema, isTag);
        \\    }
        \\};
        \\
        \\World.prototype.addSystem = function(fn, phase) {
        \\    if (typeof fn !== 'function') return;
        \\    phase = phase || "update";
        \\    if (phase === "init") __world_systems_init.push(fn);
        \\    else if (phase === "destroy") __world_systems_destroy.push(fn);
        \\    else __world_systems_update.push(fn);
        \\};
        \\
        \\zdl.createWorld = function() {
        \\    var world = new World();
        \\    __world_active = world;
        \\    return world;
        \\};
        \\
        \\function __world_run_systems(phase) {
        \\    if (!__world_active) return;
        \\    var list = null;
        \\    if (phase === "init") list = __world_systems_init;
        \\    else if (phase === "destroy") list = __world_systems_destroy;
        \\    else list = __world_systems_update;
        \\    for (var i = 0; i < list.length; i++) {
        \\        try { list[i](__world_active); } catch (e) {}
        \\    }
        \\}
        \\
        \\var __world_component_cache = {};
        \\var __world_component_cache_versions = {};
        \\var __world_component_has_cache = {};
        \\var __world_component_has_cache_versions = {};
        \\var __world_component_requests = [];
        \\var __world_component_requests_map = {};
        \\var __world_create_entity_requests = [];
        \\var __world_active = null;
        \\var __world_systems_init = [];
        \\var __world_systems_update = [];
        \\var __world_systems_destroy = [];
        \\
        \\true;
    ;
    const result = try ctx.eval(world_code, "<world>");
    ctx.freeValue(result);
}

pub fn processCreateEntityRequests(ctx: *JSContext, scene: *Scene) void {
    const requests = ctx.getGlobal("__world_create_entity_requests");
    defer ctx.freeValue(requests);
    if (ctx.isUndefined(requests)) return;

    const component_store = ctx.getGlobal("__component_store");
    defer ctx.freeValue(component_store);

    const store_version_val = ctx.getGlobal("__component_store_version");
    defer ctx.freeValue(store_version_val);
    var store_version = ctx.toInt32(store_version_val) catch 0;

    var i: u32 = 0;
    while (true) : (i += 1) {
        const request = ctx.context.getPropertyUint32(requests, i);
        defer ctx.freeValue(request);

        if (ctx.isUndefined(request)) break;
        if (!ctx.isObject(request)) continue;

        const entity_obj = ctx.getProperty(request, "entity");
        const name_val = ctx.getProperty(request, "name");
        const components_val = ctx.getProperty(request, "components");
        defer ctx.freeValue(entity_obj);
        defer ctx.freeValue(name_val);
        defer ctx.freeValue(components_val);

        var entity: Entity = undefined;
        if (!ctx.isUndefined(name_val) and !ctx.isNull(name_val)) {
            if (ctx.toCString(name_val)) |name_cstr| {
                defer ctx.freeCString(name_cstr);
                const name_len = std.mem.len(name_cstr);
                const name_z: [:0]const u8 = name_cstr[0..name_len :0];
                entity = scene.createEntityNamed(name_z);
            } else |_| {
                entity = scene.createEntity();
            }
        } else {
            entity = scene.createEntity();
        }

        if (ctx.isObject(entity_obj)) {
            ctx.setProperty(entity_obj, "id", ctx.newFloat64(@floatFromInt(entity.id))) catch {};
            ctx.setProperty(entity_obj, "valid", ctx.newBool(true)) catch {};
        }

        scene_api.registerEntity(ctx, entity);

        if (!ctx.isObject(components_val)) {
            continue;
        }

        var added_components = false;
        var comp_index: u32 = 0;
        while (true) : (comp_index += 1) {
            const comp = ctx.context.getPropertyUint32(components_val, comp_index);
            defer ctx.freeValue(comp);

            if (ctx.isUndefined(comp)) break;
            if (!ctx.isObject(comp)) continue;

            const type_val = ctx.getProperty(comp, "typeName");
            const data_val = ctx.getProperty(comp, "data");
            defer ctx.freeValue(type_val);
            defer ctx.freeValue(data_val);

            const type_cstr = ctx.toCString(type_val) catch continue;
            defer ctx.freeCString(type_cstr);
            const type_name = std.mem.span(type_cstr);
            const type_z: [:0]const u8 = type_cstr[0..type_name.len :0];

            const data_json = ctx.context.jsonStringify(data_val, quickjs.UNDEFINED, quickjs.UNDEFINED);
            defer ctx.context.freeValue(data_json);
            if (ctx.context.isException(data_json) or ctx.isUndefined(data_json)) continue;

            if (ctx.toCString(data_json)) |data_cstr| {
                defer ctx.freeCString(data_cstr);
                scene.addJsComponent(entity, type_name, std.mem.span(data_cstr)) catch {};
            } else |_| {}

            if (ctx.isObject(component_store)) {
                const type_map = getOrCreateMap(ctx, component_store, type_z);
                defer ctx.freeValue(type_map);

                var key_buf: [64]u8 = undefined;
                const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch continue;
                const data_ref = ctx.dupValue(data_val);
                ctx.setProperty(type_map, key, data_ref) catch {
                    ctx.freeValue(data_ref);
                };
            }
            added_components = true;
        }

        if (added_components) {
            store_version += 1;
            ctx.setGlobal("__component_store_version", ctx.newInt32(store_version)) catch {};
        }
    }

    ctx.setGlobal("__world_create_entity_requests", ctx.newArray()) catch {};
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

pub fn runSystems(ctx: *JSContext, phase: []const u8) void {
    const run_fn = ctx.getGlobal("__world_run_systems");
    defer ctx.freeValue(run_fn);
    if (!ctx.isFunction(run_fn)) return;

    const phase_val = ctx.newString(phase);
    defer ctx.freeValue(phase_val);
    const result = ctx.call(run_fn, quickjs.UNDEFINED, &.{phase_val}) catch return;
    ctx.freeValue(result);
}

test "world get/has uses native cache updates" {
    var runtime = try JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    try component_api.register(&ctx);
    try register(&ctx);

    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const entity = scene.createEntity();
    const entity_js = bindings.entityToJS(&ctx, entity);
    try ctx.setGlobal("__entity", entity_js);

    const setup_code =
        \\var world = zdl.createWorld();
        \\Component.register("Health", {value: "number"}, false);
        \\Component.add(__entity, "Health", {value: 10});
        \\var first = world.getComponent(__entity, function(){ return {type:"Health"}; });
        \\var hasFirst = world.hasComponent(__entity, function(){ return {type:"Health"}; });
        \\__first_value = first ? first.value : null;
        \\__has_first = hasFirst;
        \\true;
    ;
    const setup_result = try ctx.eval(setup_code, "<world-test>");
    ctx.freeValue(setup_result);

    component_api.processQueue(&ctx, &scene);
    component_api.processComponentRequests(&ctx, &scene);

    const cache = ctx.getGlobal("__world_component_cache");
    defer ctx.freeValue(cache);

    const health_cache = ctx.getProperty(cache, "Health");
    defer ctx.freeValue(health_cache);

    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch return error.TestUnexpectedResult;
    const cached_val = ctx.getProperty(health_cache, key);
    defer ctx.freeValue(cached_val);

    const cached_value_prop = ctx.getProperty(cached_val, "value");
    defer ctx.freeValue(cached_value_prop);
    const cached_value = ctx.toInt32(cached_value_prop) catch return error.TestUnexpectedResult;

    try std.testing.expectEqual(@as(i32, 10), cached_value);

    const has_cache = ctx.getGlobal("__world_component_has_cache");
    defer ctx.freeValue(has_cache);
    const health_has_cache = ctx.getProperty(has_cache, "Health");
    defer ctx.freeValue(health_has_cache);
    const cached_has_val = ctx.getProperty(health_has_cache, key);
    defer ctx.freeValue(cached_has_val);
    const cached_has = ctx.toBool(cached_has_val) catch return error.TestUnexpectedResult;
    try std.testing.expect(cached_has);
}

test "world addEntity queues native creation and components" {
    var runtime = try JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    try component_api.register(&ctx);
    try register(&ctx);

    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const setup_code =
        \\var world = zdl.createWorld();
        \\Component.register("Tag", {}, true);
        \\Component.register("Position", {x: "number"}, false);
        \\function Tag() { return { type: "Tag" }; }
        \\function Position(x) { return { type: "Position", x: x }; }
        \\var entity = world.addEntity(function(){ return { name: "player" }; })( Tag, Position(3) );
        \\__created_entity = entity;
        \\true;
    ;
    const setup_result = try ctx.eval(setup_code, "<world-create-test>");
    ctx.freeValue(setup_result);

    component_api.processQueue(&ctx, &scene);
    processCreateEntityRequests(&ctx, &scene);

    const created = ctx.getGlobal("__created_entity");
    defer ctx.freeValue(created);

    const id_val = ctx.getProperty(created, "id");
    defer ctx.freeValue(id_val);
    const id_f = ctx.toFloat64(id_val) catch return error.TestUnexpectedResult;
    const created_id: u64 = @intFromFloat(id_f);
    const entity = Entity{ .id = created_id };

    try std.testing.expect(entity.isValid());
    try std.testing.expect(scene.hasJsComponent(entity, "Tag"));
    try std.testing.expect(scene.hasJsComponent(entity, "Position"));
}

test "world systems run by phase" {
    var runtime = try JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    try component_api.register(&ctx);
    try register(&ctx);

    const setup_code =
        \\var world = zdl.createWorld();
        \\var calls = [];
        \\world.addSystem(function(){ calls.push("init"); }, "init");
        \\world.addSystem(function(){ calls.push("update"); }, "update");
        \\world.addSystem(function(){ calls.push("destroy"); }, "destroy");
        \\__calls = calls;
        \\true;
    ;
    const setup_result = try ctx.eval(setup_code, "<world-system-test>");
    ctx.freeValue(setup_result);

    runSystems(&ctx, "init");
    runSystems(&ctx, "update");
    runSystems(&ctx, "destroy");

    const calls_val = ctx.getGlobal("__calls");
    defer ctx.freeValue(calls_val);

    const expected = [_][]const u8{ "init", "update", "destroy" };
    var idx: usize = 0;
    while (true) : (idx += 1) {
        const item = ctx.context.getPropertyUint32(calls_val, @intCast(idx));
        defer ctx.freeValue(item);
        if (ctx.isUndefined(item)) break;
        if (idx >= expected.len) return error.TestUnexpectedResult;
        if (ctx.toCString(item)) |cstr| {
            defer ctx.freeCString(cstr);
            try std.testing.expectEqualStrings(expected[idx], std.mem.span(cstr));
        } else |_| {
            return error.TestUnexpectedResult;
        }
    }

    try std.testing.expectEqual(expected.len, idx);
}
