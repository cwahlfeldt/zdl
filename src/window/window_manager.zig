const std = @import("std");
const sdl = @import("sdl3");

/// Configuration for creating a window
pub const WindowConfig = struct {
    title: [:0]const u8 = "ZDL",
    width: u32 = 1280,
    height: u32 = 720,
    resizable: bool = true,
    fullscreen: bool = false,
};

/// Manages window creation, event polling, and window state.
/// This is a thin wrapper around SDL window functionality.
pub const WindowManager = struct {
    window: sdl.video.Window,
    width: u32,
    height: u32,
    title: [:0]const u8,

    /// Initialize SDL and create a window
    pub fn init(config: WindowConfig) !WindowManager {
        try sdl.init(.{ .video = true });
        errdefer sdl.quit(.{ .video = true });

        var flags = sdl.video.Window.Flags{};
        if (config.resizable) {
            flags.resizable = true;
        }
        if (config.fullscreen) {
            flags.fullscreen = true;
        }

        const window = try sdl.video.Window.init(
            config.title,
            config.width,
            config.height,
            flags,
        );
        errdefer window.deinit();

        return .{
            .window = window,
            .width = config.width,
            .height = config.height,
            .title = config.title,
        };
    }

    /// Clean up window and SDL
    pub fn deinit(self: *WindowManager) void {
        self.window.deinit();
        sdl.quit(.{ .video = true });
    }

    /// Set the window title
    pub fn setTitle(self: *WindowManager, title: [:0]const u8) void {
        self.window.setTitle(title) catch {};
    }

    /// Get current window size
    pub fn getSize(self: *const WindowManager) struct { width: u32, height: u32 } {
        return .{ .width = self.width, .height = self.height };
    }

    /// Update stored dimensions (called when resize is detected)
    pub fn updateSize(self: *WindowManager, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
    }

    /// Get the underlying SDL window (for GPU device binding)
    pub fn getSDLWindow(self: *WindowManager) sdl.video.Window {
        return self.window;
    }
};
