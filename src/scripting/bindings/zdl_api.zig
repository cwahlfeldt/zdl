const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;

/// Window configuration request from JavaScript.
pub const WindowConfig = struct {
    width: u32,
    height: u32,
    title: []const u8,
};

/// Register the ZDL API module with createWindow function.
/// Note: world_api.zig already provides zdl.createWorld().
///
/// This uses a command queue pattern: JavaScript calls push config to a queue,
/// then Zig can process them with `getQueuedWindowConfig()`.
pub fn register(ctx: *JSContext) !void {
    const zdl_code =
        \\if (typeof zdl === 'undefined') { var zdl = {}; }
        \\
        \\// Queue for window configuration requests
        \\var __zdl_window_queue = [];
        \\
        \\zdl.createWindow = function(config) {
        \\    config = config || {};
        \\    var size = config.size || "1280x720";
        \\    var title = config.title || "ZDL Game";
        \\
        \\    // Parse size string (e.g., "1920x1080")
        \\    var width = 1280;
        \\    var height = 720;
        \\    if (size && typeof size === 'string') {
        \\        var parts = size.split('x');
        \\        if (parts.length === 2) {
        \\            width = parseInt(parts[0]) || 1280;
        \\            height = parseInt(parts[1]) || 720;
        \\        }
        \\    }
        \\
        \\    // Queue the window configuration for Zig to process
        \\    var windowConfig = {
        \\        width: width,
        \\        height: height,
        \\        title: title,
        \\        _isWindowConfig: true
        \\    };
        \\    __zdl_window_queue.push(windowConfig);
        \\
        \\    return windowConfig;
        \\};
        \\
        \\// Helper function for Zig to retrieve queued window configs
        \\function __zdl_get_window_queue() {
        \\    var queue = __zdl_window_queue;
        \\    __zdl_window_queue = [];
        \\    return queue;
        \\}
        \\
        \\true;
    ;
    const result = try ctx.eval(zdl_code, "<zdl>");
    ctx.freeValue(result);
}

/// Get queued window configuration requests from JavaScript.
/// Returns null if no windows are queued.
/// The caller must free the returned title string.
pub fn getQueuedWindowConfig(ctx: *JSContext, allocator: std.mem.Allocator) !?WindowConfig {
    const get_queue_fn = ctx.getGlobal("__zdl_get_window_queue");
    defer ctx.freeValue(get_queue_fn);

    if (!ctx.isFunction(get_queue_fn)) return null;

    const queue_result = ctx.call(get_queue_fn, quickjs.UNDEFINED, &.{}) catch return null;
    defer ctx.freeValue(queue_result);

    // Check if queue has any items
    const length_prop = ctx.getProperty(queue_result, "length");
    defer ctx.freeValue(length_prop);

    const length = ctx.toInt32(length_prop) catch return null;
    if (length == 0) return null;

    // Get the first window config
    const first_item = ctx.context.getPropertyUint32(queue_result, 0);
    defer ctx.freeValue(first_item);

    if (ctx.isUndefined(first_item)) return null;

    // Extract width
    const width_prop = ctx.getProperty(first_item, "width");
    defer ctx.freeValue(width_prop);
    const width = @as(u32, @intCast(ctx.toInt32(width_prop) catch 1280));

    // Extract height
    const height_prop = ctx.getProperty(first_item, "height");
    defer ctx.freeValue(height_prop);
    const height = @as(u32, @intCast(ctx.toInt32(height_prop) catch 720));

    // Extract title
    const title_prop = ctx.getProperty(first_item, "title");
    defer ctx.freeValue(title_prop);
    const title_cstr = ctx.toCString(title_prop) catch return null;
    defer ctx.freeCString(title_cstr);
    const title = try allocator.dupe(u8, std.mem.span(title_cstr));

    return WindowConfig{
        .width = width,
        .height = height,
        .title = title,
    };
}

test "zdl createWindow parses config" {
    var runtime = try @import("../js_runtime.zig").JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    try register(&ctx);

    const test_code =
        \\var window = zdl.createWindow({ size: "1920x1080", title: "Test Game" });
        \\__test_window = window;
        \\true;
    ;
    const result = try ctx.eval(test_code, "<test>");
    ctx.freeValue(result);

    const window_val = ctx.getGlobal("__test_window");
    defer ctx.freeValue(window_val);

    const width_val = ctx.getProperty(window_val, "width");
    defer ctx.freeValue(width_val);
    const width = ctx.toInt32(width_val) catch return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i32, 1920), width);

    const height_val = ctx.getProperty(window_val, "height");
    defer ctx.freeValue(height_val);
    const height = ctx.toInt32(height_val) catch return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i32, 1080), height);

    const title_val = ctx.getProperty(window_val, "title");
    defer ctx.freeValue(title_val);
    const title_cstr = ctx.toCString(title_val) catch return error.TestUnexpectedResult;
    defer ctx.freeCString(title_cstr);
    try std.testing.expectEqualStrings("Test Game", std.mem.span(title_cstr));
}

test "zdl getQueuedWindowConfig" {
    var runtime = try @import("../js_runtime.zig").JSRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, std.testing.allocator);
    defer ctx.deinit();

    try register(&ctx);

    // Create a window config
    const test_code =
        \\zdl.createWindow({ size: "800x600", title: "Queue Test" });
        \\true;
    ;
    const result = try ctx.eval(test_code, "<test>");
    ctx.freeValue(result);

    // Retrieve the queued config
    const config = try getQueuedWindowConfig(&ctx, std.testing.allocator);
    try std.testing.expect(config != null);

    defer std.testing.allocator.free(config.?.title);

    try std.testing.expectEqual(@as(u32, 800), config.?.width);
    try std.testing.expectEqual(@as(u32, 600), config.?.height);
    try std.testing.expectEqualStrings("Queue Test", config.?.title);

    // Queue should be empty now
    const config2 = try getQueuedWindowConfig(&ctx, std.testing.allocator);
    try std.testing.expect(config2 == null);
}
