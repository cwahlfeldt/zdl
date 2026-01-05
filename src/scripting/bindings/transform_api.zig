const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;
const bindings = @import("bindings.zig");
const Entity = @import("../../ecs/entity.zig").Entity;
const TransformComponent = @import("../../ecs/components/transform_component.zig").TransformComponent;
const Scene = @import("../../ecs/scene.zig").Scene;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Quat = @import("../../math/quat.zig").Quat;

/// Register transform-related methods on entities.
pub fn register(ctx: *JSContext) !void {
    const transform_code =
        \\// Transform wrapper that syncs with Zig side
        \\function Transform(entityIndex, entityGen) {
        \\    this._entityIndex = entityIndex;
        \\    this._entityGen = entityGen;
        \\    // Use plain objects initially to avoid constructor issues
        \\    this._position = {x: 0, y: 0, z: 0};
        \\    this._rotation = {x: 0, y: 0, z: 0, w: 1};
        \\    this._scale = {x: 1, y: 1, z: 1};
        \\    this._forward = {x: 0, y: 0, z: -1};
        \\    this._right = {x: 1, y: 0, z: 0};
        \\    this._up = {x: 0, y: 1, z: 0};
        \\    this._dirty = false;
        \\}
        \\
        \\Transform.prototype = {
        \\    // Position
        \\    get position() { return this._position; },
        \\    set position(v) {
        \\        this._position = v;
        \\        this._dirty = true;
        \\        this._queueUpdate('position', v);
        \\    },
        \\
        \\    // Rotation (quaternion)
        \\    get rotation() { return this._rotation; },
        \\    set rotation(q) {
        \\        this._rotation = q;
        \\        this._dirty = true;
        \\        this._queueUpdate('rotation', q);
        \\    },
        \\
        \\    // Scale
        \\    get scale() { return this._scale; },
        \\    set scale(v) {
        \\        this._scale = v;
        \\        this._dirty = true;
        \\        this._queueUpdate('scale', v);
        \\    },
        \\
        \\    // Direction vectors (read-only, computed from rotation)
        \\    forward: function() { return this._forward; },
        \\    right: function() { return this._right; },
        \\    up: function() { return this._up; },
        \\
        \\    // Operations
        \\    translate: function(delta) {
        \\        this._position = this._position.add(delta);
        \\        this._dirty = true;
        \\        this._queueUpdate('position', this._position);
        \\    },
        \\
        \\    rotate: function(quat) {
        \\        this._rotation = this._rotation.mul(quat).normalize();
        \\        this._dirty = true;
        \\        this._queueUpdate('rotation', this._rotation);
        \\    },
        \\
        \\    rotateAxis: function(axis, angle) {
        \\        var q = Quat.fromAxisAngle(axis, angle);
        \\        this.rotate(q);
        \\    },
        \\
        \\    rotateEuler: function(pitch, yaw, roll) {
        \\        this._queueUpdate('rotateEuler', { pitch: pitch, yaw: yaw, roll: roll });
        \\        this._dirty = true;
        \\    },
        \\
        \\    setRotationEuler: function(pitch, yaw, roll) {
        \\        this._rotation = Quat.fromEuler(pitch, yaw, roll);
        \\        this._dirty = true;
        \\        this._queueUpdate('rotation', this._rotation);
        \\    },
        \\
        \\    scaleUniform: function(factor) {
        \\        this._scale = this._scale.mul(factor);
        \\        this._dirty = true;
        \\        this._queueUpdate('scale', this._scale);
        \\    },
        \\
        \\    lookAt: function(target, upVector) {
        \\        upVector = upVector || Vec3.up();
        \\        this._queueUpdate('lookAt', { target: target, up: upVector });
        \\        this._dirty = true;
        \\    },
        \\
        \\    // Internal: queue an update for the Zig side
        \\    _queueUpdate: function(type, value) {
        \\        try {
        \\            __transform_updates.push({
        \\                entityIndex: this._entityIndex,
        \\                entityGen: this._entityGen,
        \\                type: type,
        \\                value: value
        \\            });
        \\        } catch (e) {
        \\            // Silently ignore queue errors to prevent stack overflow
        \\        }
        \\    },
        \\
        \\    // Internal: sync state from Zig
        \\    _syncFromZig: function(pos, rot, scale, forward, right, up) {
        \\        this._position = pos;
        \\        this._rotation = rot;
        \\        this._scale = scale;
        \\        this._forward = forward;
        \\        this._right = right;
        \\        this._up = up;
        \\        this._dirty = false;
        \\    }
        \\};
        \\
        \\// Transform update queue
        \\var __transform_updates = [];
        \\var __transform_cache = {};
        \\
        \\// Get or create a transform wrapper for an entity
        \\function __getTransform(entityIndex, entityGen) {
        \\    var key = entityIndex + '_' + entityGen;
        \\    if (!__transform_cache[key]) {
        \\        __transform_cache[key] = new Transform(entityIndex, entityGen);
        \\    }
        \\    return __transform_cache[key];
        \\}
        \\
        \\// Entity method to get transform
        \\function __entity_getTransform(entity) {
        \\    if (!entity || !entity.valid) return null;
        \\    return __getTransform(entity.index, entity.generation);
        \\}
        \\
        \\true;
    ;
    _ = try ctx.eval(transform_code, "<transform>");
}

/// Sync a transform from Zig to JavaScript.
pub fn syncTransform(ctx: *JSContext, entity: Entity, transform: *const TransformComponent) void {
    // Get or create the transform wrapper
    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "__transform_cache['{d}']", .{entity.id}) catch return;

    var code_buf: [128]u8 = undefined;
    const get_code = std.fmt.bufPrintZ(&code_buf, "__getTransform({d})", .{entity.id}) catch return;

    const transform_js = ctx.eval(get_code, "<transform>") catch return;
    defer ctx.freeValue(transform_js);

    if (ctx.isNull(transform_js) or ctx.isUndefined(transform_js)) return;

    // Get the sync method
    const sync_method = ctx.getProperty(transform_js, "_syncFromZig");
    defer ctx.freeValue(sync_method);

    if (!ctx.isFunction(sync_method)) return;

    // Create the arguments
    const pos = bindings.vec3ToJS(ctx, transform.local.position);
    const rot = bindings.quatToJS(ctx, transform.local.rotation);
    const scale = bindings.vec3ToJS(ctx, transform.local.scale);
    const forward = bindings.vec3ToJS(ctx, transform.forward());
    const right = bindings.vec3ToJS(ctx, transform.right());
    const up = bindings.vec3ToJS(ctx, transform.up());

    // Call the sync method
    _ = ctx.call(sync_method, transform_js, &.{ pos, rot, scale, forward, right, up }) catch {};

    _ = key;
}

/// Process transform updates from JavaScript.
pub fn processUpdates(ctx: *JSContext, scene: *Scene) void {
    const updates_arr = ctx.getGlobal("__transform_updates");
    defer ctx.freeValue(updates_arr);

    var i: u32 = 0;
    while (true) : (i += 1) {
        const update = ctx.context.getPropertyUint32(updates_arr, i);
        defer ctx.freeValue(update);

        if (ctx.isUndefined(update)) break;

        // Extract update data
        const entity_id_val = ctx.getProperty(update, "entityId");
        const update_type = ctx.getProperty(update, "type");
        const value = ctx.getProperty(update, "value");
        defer ctx.freeValue(entity_id_val);
        defer ctx.freeValue(update_type);
        defer ctx.freeValue(value);

        const id_float = ctx.toFloat64(entity_id_val) catch continue;
        const id: u64 = @intFromFloat(id_float);

        const entity = Entity{
            .id = id,
        };

        // Get the transform component
        if (scene.getComponent(TransformComponent, entity)) |transform| {
            // Get the update type as string
            if (ctx.toCString(update_type)) |type_str| {
                defer ctx.freeCString(type_str);

                applyUpdate(ctx, transform, std.mem.span(type_str), value);
            } else |_| {}
        }
    }

    // Clear the updates array
    ctx.setGlobal("__transform_updates", ctx.newArray()) catch {};
}

fn applyUpdate(ctx: *JSContext, transform: *TransformComponent, update_type: []const u8, value: quickjs.Value) void {
    if (std.mem.eql(u8, update_type, "position")) {
        if (bindings.jsToVec3(ctx, value)) |vec| {
            transform.setPosition(vec);
        } else |_| {}
    } else if (std.mem.eql(u8, update_type, "rotation")) {
        if (bindings.jsToQuat(ctx, value)) |quat| {
            transform.setRotation(quat);
        } else |_| {}
    } else if (std.mem.eql(u8, update_type, "scale")) {
        if (bindings.jsToVec3(ctx, value)) |vec| {
            transform.setScale(vec);
        } else |_| {}
    } else if (std.mem.eql(u8, update_type, "rotateEuler")) {
        const pitch_val = ctx.getProperty(value, "pitch");
        const yaw_val = ctx.getProperty(value, "yaw");
        const roll_val = ctx.getProperty(value, "roll");
        defer ctx.freeValue(pitch_val);
        defer ctx.freeValue(yaw_val);
        defer ctx.freeValue(roll_val);

        const pitch = ctx.toFloat32(pitch_val) catch 0;
        const yaw = ctx.toFloat32(yaw_val) catch 0;
        const roll = ctx.toFloat32(roll_val) catch 0;

        transform.rotateEuler(pitch, yaw, roll);
    } else if (std.mem.eql(u8, update_type, "lookAt")) {
        const target_val = ctx.getProperty(value, "target");
        const up_val = ctx.getProperty(value, "up");
        defer ctx.freeValue(target_val);
        defer ctx.freeValue(up_val);

        const target = bindings.jsToVec3(ctx, target_val) catch Vec3.zero();
        const up = bindings.jsToVec3(ctx, up_val) catch Vec3.init(0, 1, 0);

        transform.lookAt(target, up);
    }
}
