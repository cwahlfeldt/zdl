// Example: Creating a window from JavaScript configuration
//
// This demonstrates how to use zdl.createWindow() from JavaScript
// and process the configuration in Zig to create a real SDL window.

const std = @import("std");
const engine = @import("engine");

const JSRuntime = engine.JSRuntime;
const JSContext = engine.JSContext;
const Engine = engine.Engine;
const evalFile = engine.evalFile;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Window Creation from JavaScript Example ===\n\n", .{});

    // 1. Initialize JavaScript runtime and context
    var runtime = try JSRuntime.init(allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, allocator);
    defer ctx.deinit();

    // 2. Register bindings
    const console_api = engine.console_api;
    const zdl_api = engine.zdl_api;

    try console_api.register(&ctx);
    try console_api.installPrintFunction(&ctx);
    try zdl_api.register(&ctx);

    // 3. Run JavaScript that creates a window
    const js_code =
        \\console.log("Configuring window from JavaScript...");
        \\
        \\const window = zdl.createWindow({
        \\  size: "1920x1080",
        \\  title: "JS-Configured Window"
        \\});
        \\
        \\console.log("Window config created:", window.width + "x" + window.height);
        \\true;
    ;

    const result = ctx.eval(js_code, "<example>") catch |err| {
        std.debug.print("JavaScript error: {}\n", .{err});
        return err;
    };
    ctx.freeValue(result);

    console_api.flushMessages(&ctx);

    // 4. Retrieve the window configuration from JavaScript
    if (try zdl_api.getQueuedWindowConfig(&ctx, allocator)) |config| {
        defer allocator.free(config.title);

        std.debug.print("\n--- Window Configuration from JavaScript ---\n", .{});
        std.debug.print("Title:  {s}\n", .{config.title});
        std.debug.print("Width:  {d}\n", .{config.width});
        std.debug.print("Height: {d}\n", .{config.height});

        // 5. Now create the engine with this configuration
        std.debug.print("\n--- Creating Engine with JS Configuration ---\n", .{});

        // Convert title to null-terminated string for SDL
        const title_z = try allocator.dupeZ(u8, config.title);
        defer allocator.free(title_z);

        var eng = try Engine.init(allocator, .{
            .window_title = title_z,
            .window_width = config.width,
            .window_height = config.height,
        });
        defer eng.deinit();

        std.debug.print("✓ Engine initialized with window: {s} ({d}x{d})\n", .{
            title_z,
            config.width,
            config.height,
        });

        std.debug.print("\n--- Real SDL window created successfully! ---\n", .{});
        std.debug.print("Window is visible! Press ESC or close window to exit.\n", .{});

        // Simple event loop to keep window open
        const sdl = @import("sdl3");
        var running = true;
        while (running) {
            while (sdl.events.poll()) |event| {
                switch (event) {
                    .quit => running = false,
                    .key_down => |key| {
                        if (key.scancode == .escape) running = false;
                    },
                    else => {},
                }
            }

            // Clear to a nice blue color and present
            if (try eng.beginFrame()) |frame_value| {
                var frame = frame_value;
                try frame.end();
            }

            // Frame timing
            sdl.timer.delayMilliseconds(16); // ~60 FPS
        }

        std.debug.print("\n--- Window closed ---\n", .{});
    } else {
        std.debug.print("No window configuration requested from JavaScript.\n", .{});
    }

    std.debug.print("\n=== Example completed! ===\n", .{});
}
