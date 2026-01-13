const std = @import("std");
const quickjs = @import("quickjs");

const Entity = @import("../../ecs/entity.zig").Entity;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Vec2 = @import("../../math/vec2.zig").Vec2;
const Quat = @import("../../math/quat.zig").Quat;

const Scene = @import("../../ecs/scene.zig").Scene;
const Input = @import("../../input/input.zig").Input;
const JSContext = @import("../js_context.zig").JSContext;
const ScriptContext = @import("../script_context.zig").ScriptContext;

/// Context passed to all native function callbacks.
/// Stored in thread-local storage for access from C callbacks.
pub const BindingContext = struct {
    js_ctx: *JSContext,
    script_ctx: *const ScriptContext,
    scene: *Scene,
    input: *Input,
    delta_time: f32,
    current_entity: Entity,
    allocator: std.mem.Allocator,
};

/// Thread-local storage for binding context.
pub threadlocal var binding_ctx: ?*BindingContext = null;

/// Get the current binding context.
pub fn getContext() ?*BindingContext {
    return binding_ctx;
}

/// Set the current binding context.
pub fn setContext(ctx: ?*BindingContext) void {
    binding_ctx = ctx;
}

// ============================================================================
// Vec3 <-> JavaScript Conversion
// ============================================================================

/// Create a JavaScript object from a Zig Vec3.
pub fn vec3ToJS(ctx: *JSContext, v: Vec3) quickjs.Value {
    const obj = ctx.newObject();
    ctx.setProperty(obj, "x", ctx.newFloat(v.x)) catch {};
    ctx.setProperty(obj, "y", ctx.newFloat(v.y)) catch {};
    ctx.setProperty(obj, "z", ctx.newFloat(v.z)) catch {};
    return obj;
}

/// Extract a Zig Vec3 from a JavaScript object.
pub fn jsToVec3(ctx: *JSContext, value: quickjs.Value) !Vec3 {
    if (!ctx.isObject(value)) return error.TypeMismatch;

    const x_val = ctx.getProperty(value, "x");
    const y_val = ctx.getProperty(value, "y");
    const z_val = ctx.getProperty(value, "z");
    defer ctx.freeValue(x_val);
    defer ctx.freeValue(y_val);
    defer ctx.freeValue(z_val);

    const x = ctx.toFloat32(x_val) catch 0;
    const y = ctx.toFloat32(y_val) catch 0;
    const z = ctx.toFloat32(z_val) catch 0;

    return Vec3.init(x, y, z);
}

// ============================================================================
// Vec2 <-> JavaScript Conversion
// ============================================================================

/// Create a JavaScript object from a Zig Vec2.
pub fn vec2ToJS(ctx: *JSContext, v: Vec2) quickjs.Value {
    const obj = ctx.newObject();
    ctx.setProperty(obj, "x", ctx.newFloat(v.x)) catch {};
    ctx.setProperty(obj, "y", ctx.newFloat(v.y)) catch {};
    return obj;
}

/// Extract a Zig Vec2 from a JavaScript object.
pub fn jsToVec2(ctx: *JSContext, value: quickjs.Value) !Vec2 {
    if (!ctx.isObject(value)) return error.TypeMismatch;

    const x_val = ctx.getProperty(value, "x");
    const y_val = ctx.getProperty(value, "y");
    defer ctx.freeValue(x_val);
    defer ctx.freeValue(y_val);

    const x = ctx.toFloat32(x_val) catch 0;
    const y = ctx.toFloat32(y_val) catch 0;

    return Vec2.init(x, y);
}

// ============================================================================
// Quat <-> JavaScript Conversion
// ============================================================================

/// Create a JavaScript object from a Zig Quat.
pub fn quatToJS(ctx: *JSContext, q: Quat) quickjs.Value {
    const obj = ctx.newObject();
    ctx.setProperty(obj, "x", ctx.newFloat(q.x)) catch {};
    ctx.setProperty(obj, "y", ctx.newFloat(q.y)) catch {};
    ctx.setProperty(obj, "z", ctx.newFloat(q.z)) catch {};
    ctx.setProperty(obj, "w", ctx.newFloat(q.w)) catch {};
    return obj;
}

/// Extract a Zig Quat from a JavaScript object.
pub fn jsToQuat(ctx: *JSContext, value: quickjs.Value) !Quat {
    if (!ctx.isObject(value)) return error.TypeMismatch;

    const x_val = ctx.getProperty(value, "x");
    const y_val = ctx.getProperty(value, "y");
    const z_val = ctx.getProperty(value, "z");
    const w_val = ctx.getProperty(value, "w");
    defer ctx.freeValue(x_val);
    defer ctx.freeValue(y_val);
    defer ctx.freeValue(z_val);
    defer ctx.freeValue(w_val);

    const x = ctx.toFloat32(x_val) catch 0;
    const y = ctx.toFloat32(y_val) catch 0;
    const z = ctx.toFloat32(z_val) catch 0;
    const w = ctx.toFloat32(w_val) catch 1;

    return Quat{ .x = x, .y = y, .z = z, .w = w };
}

// ============================================================================
// Entity <-> JavaScript Conversion
// ============================================================================

/// Create a JavaScript object from a Zig Entity.
pub fn entityToJS(ctx: *JSContext, entity: Entity) quickjs.Value {
    const obj = ctx.newObject();
    ctx.setProperty(obj, "id", ctx.newFloat(@floatFromInt(entity.id))) catch {};
    ctx.setProperty(obj, "valid", ctx.newBool(entity.isValid())) catch {};
    return obj;
}

/// Extract a Zig Entity from a JavaScript object.
pub fn jsToEntity(ctx: *JSContext, value: quickjs.Value) !Entity {
    if (!ctx.isObject(value)) return error.TypeMismatch;

    const id_val = ctx.getProperty(value, "id");
    defer ctx.freeValue(id_val);

    const id_float = ctx.toFloat64(id_val) catch return error.InvalidEntity;
    const id: u64 = @intFromFloat(id_float);

    return Entity{ .id = id };
}

// ============================================================================
// StickValue <-> JavaScript Conversion
// ============================================================================

/// Create a JavaScript object from a StickValue.
pub fn stickValueToJS(ctx: *JSContext, stick: anytype) quickjs.Value {
    const obj = ctx.newObject();
    ctx.setProperty(obj, "x", ctx.newFloat(stick.x)) catch {};
    ctx.setProperty(obj, "y", ctx.newFloat(stick.y)) catch {};
    return obj;
}

// ============================================================================
// Error Handling
// ============================================================================

/// Throw a JavaScript type error.
pub fn throwTypeError(ctx: *JSContext, msg: [:0]const u8) quickjs.Value {
    return ctx.context.throwTypeError(msg);
}

/// Throw a JavaScript reference error.
pub fn throwReferenceError(ctx: *JSContext, msg: [:0]const u8) quickjs.Value {
    return ctx.context.throwReferenceError(msg);
}

/// Get the undefined value.
pub fn jsUndefined() quickjs.Value {
    return quickjs.UNDEFINED;
}

/// Get the null value.
pub fn null_val() quickjs.Value {
    return quickjs.NULL;
}
