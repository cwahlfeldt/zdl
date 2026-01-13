const std = @import("std");
const sdl = @import("sdl3");

/// Context passed to ScriptSystem containing engine state.
/// This decouples ScriptSystem from direct Engine dependency.
pub const ScriptContext = struct {
    // Time
    delta_time: f32,
    total_time: f64,
    fps: f32,

    // Window
    window_width: u32,
    window_height: u32,

    // Mouse capture state
    mouse_captured: bool,

    // GPU device for resource creation (passed as anyopaque to avoid dependency on sdl)
    device: *anyopaque,

    // Callbacks for engine operations (opaque to avoid circular deps)
    engine_ptr: *anyopaque,
    set_mouse_capture_fn: *const fn (*anyopaque, bool) void,
    request_quit_fn: *const fn (*anyopaque) void,

    /// Set mouse capture mode
    pub fn setMouseCapture(self: *const ScriptContext, captured: bool) void {
        self.set_mouse_capture_fn(self.engine_ptr, captured);
    }

    /// Request the engine to quit
    pub fn requestQuit(self: *const ScriptContext) void {
        self.request_quit_fn(self.engine_ptr);
    }

    /// Get the GPU device (cast from opaque pointer)
    pub fn getDevice(self: *const ScriptContext) *sdl.gpu.Device {
        return @ptrCast(@alignCast(self.device));
    }
};
