const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;
const bindings = @import("bindings.zig");

/// Register Engine API on the global object.
/// Provides access to engine properties like deltaTime, fps, etc.
pub fn register(ctx: *JSContext) !void {
    const engine_code =
        \\var Engine = {
        \\    // These are updated each frame by the script system
        \\    deltaTime: 0,
        \\    time: 0,
        \\    fps: 0,
        \\
        \\    // Window info
        \\    windowWidth: 0,
        \\    windowHeight: 0,
        \\
        \\    quit: function() {
        \\        __engine_quit = true;
        \\    },
        \\
        \\    setMouseCapture: function(captured) {
        \\        __engine_mouse_capture = captured;
        \\    },
        \\
        \\    isMouseCaptured: function() {
        \\        return __engine_mouse_captured || false;
        \\    }
        \\};
        \\
        \\// Internal flags set by the script system
        \\var __engine_quit = false;
        \\var __engine_mouse_capture = null;
        \\var __engine_mouse_captured = false;
        \\
        \\true;
    ;
    _ = try ctx.eval(engine_code, "<engine>");
}

/// Update engine properties for the current frame.
pub fn updateFrame(ctx: *JSContext, delta_time: f32, total_time: f32, fps: u32, width: u32, height: u32, mouse_captured: bool) void {
    const engine = ctx.getGlobal("Engine");
    defer ctx.freeValue(engine);

    ctx.setProperty(engine, "deltaTime", ctx.newFloat(delta_time)) catch {};
    ctx.setProperty(engine, "time", ctx.newFloat(total_time)) catch {};
    ctx.setProperty(engine, "fps", ctx.newInt32(@intCast(fps))) catch {};
    ctx.setProperty(engine, "windowWidth", ctx.newInt32(@intCast(width))) catch {};
    ctx.setProperty(engine, "windowHeight", ctx.newInt32(@intCast(height))) catch {};

    // Update mouse captured state
    ctx.setGlobal("__engine_mouse_captured", ctx.newBool(mouse_captured)) catch {};
}

/// Check if quit was requested from JavaScript.
pub fn checkQuitRequested(ctx: *JSContext) bool {
    const quit_flag = ctx.getGlobal("__engine_quit");
    defer ctx.freeValue(quit_flag);

    return ctx.toBool(quit_flag) catch false;
}

/// Check if mouse capture state changed.
pub fn checkMouseCaptureRequest(ctx: *JSContext) ?bool {
    const capture_val = ctx.getGlobal("__engine_mouse_capture");
    defer ctx.freeValue(capture_val);

    if (ctx.isNull(capture_val)) return null;

    const result = ctx.toBool(capture_val) catch return null;

    // Reset the request
    ctx.setGlobal("__engine_mouse_capture", quickjs.NULL) catch {};

    return result;
}
