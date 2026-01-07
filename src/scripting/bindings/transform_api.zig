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
        \\function Transform(entityId) {
        \\    this._entityId = entityId;
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
        \\function __vec3Add(a, b) {
        \\    return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };
        \\}
        \\
        \\function __vec3MulScalar(v, s) {
        \\    return { x: v.x * s, y: v.y * s, z: v.z * s };
        \\}
        \\
        \\function __quatMul(a, b) {
        \\    return {
        \\        x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        \\        y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        \\        z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        \\        w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        \\    };
        \\}
        \\
        \\function __quatNormalize(q) {
        \\    var len = Math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
        \\    if (len === 0) return { x: 0, y: 0, z: 0, w: 1 };
        \\    return { x: q.x / len, y: q.y / len, z: q.z / len, w: q.w / len };
        \\}
        \\
        \\Transform.prototype = {
        \\    // Position
        \\    get position() { return new Vec3(this._position.x, this._position.y, this._position.z); },
        \\    set position(v) {
        \\        this._position = {x: v.x, y: v.y, z: v.z};
        \\        this._dirty = true;
        \\        this._queueUpdate('position', this._position);
        \\    },
        \\
        \\    // Rotation (quaternion)
        \\    get rotation() { return new Quat(this._rotation.x, this._rotation.y, this._rotation.z, this._rotation.w); },
        \\    set rotation(q) {
        \\        this._rotation = {x: q.x, y: q.y, z: q.z, w: q.w};
        \\        this._dirty = true;
        \\        this._queueUpdate('rotation', this._rotation);
        \\    },
        \\
        \\    // Scale
        \\    get scale() { return new Vec3(this._scale.x, this._scale.y, this._scale.z); },
        \\    set scale(v) {
        \\        this._scale = {x: v.x, y: v.y, z: v.z};
        \\        this._dirty = true;
        \\        this._queueUpdate('scale', this._scale);
        \\    },
        \\
        \\    // Direction vectors (read-only, computed from rotation)
        \\    forward: function() { return new Vec3(this._forward.x, this._forward.y, this._forward.z); },
        \\    right: function() { return new Vec3(this._right.x, this._right.y, this._right.z); },
        \\    up: function() { return new Vec3(this._up.x, this._up.y, this._up.z); },
        \\
        \\    // Operations
        \\    translate: function(delta) {
        \\        this._position = __vec3Add(this._position, delta);
        \\        this._dirty = true;
        \\        this._queueUpdate('position', this._position);
        \\    },
        \\
        \\    rotate: function(quat) {
        \\        this._rotation = __quatNormalize(__quatMul(this._rotation, quat));
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
        \\        this._queueUpdate('setRotationEuler', { pitch: pitch, yaw: yaw, roll: roll });
        \\        this._dirty = true;
        \\    },
        \\
        \\    scaleUniform: function(factor) {
        \\        this._scale = __vec3MulScalar(this._scale, factor);
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
        \\                entityId: this._entityId,
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
        \\function __getTransform(entityId) {
        \\    var key = '' + entityId;
        \\    if (!__transform_cache[key]) {
        \\        __transform_cache[key] = new Transform(entityId);
        \\    }
        \\    return __transform_cache[key];
        \\}
        \\
        \\// Entity method to get transform
        \\function __entity_getTransform(entity) {
        \\    if (!entity || !entity.valid) return null;
        \\    return __getTransform(entity.id);
        \\}
        \\
        \\true;
    ;
    const result = try ctx.eval(transform_code, "<transform>");
    ctx.freeValue(result);
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

    defer ctx.freeValue(pos);
    defer ctx.freeValue(rot);
    defer ctx.freeValue(scale);
    defer ctx.freeValue(forward);
    defer ctx.freeValue(right);
    defer ctx.freeValue(up);

    const call_result = ctx.call(sync_method, transform_js, &.{ pos, rot, scale, forward, right, up }) catch return;
    ctx.freeValue(call_result);

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
    } else if (std.mem.eql(u8, update_type, "setRotationEuler")) {
        const pitch_val = ctx.getProperty(value, "pitch");
        const yaw_val = ctx.getProperty(value, "yaw");
        const roll_val = ctx.getProperty(value, "roll");
        defer ctx.freeValue(pitch_val);
        defer ctx.freeValue(yaw_val);
        defer ctx.freeValue(roll_val);

        const pitch = ctx.toFloat32(pitch_val) catch 0;
        const yaw = ctx.toFloat32(yaw_val) catch 0;
        const roll = ctx.toFloat32(roll_val) catch 0;

        transform.setRotationEuler(pitch, yaw, roll);
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
