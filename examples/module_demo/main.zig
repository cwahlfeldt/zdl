const std = @import("std");
const engine = @import("engine");

const JSRuntime = engine.JSRuntime;
const JSContext = engine.JSContext;
const evalFile = engine.evalFile;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== ZDL Module Import Demo ===\n\n", .{});

    // Initialize JavaScript runtime
    std.debug.print("Initializing JavaScript runtime...\n", .{});
    var runtime = try JSRuntime.init(allocator);
    defer runtime.deinit();

    var ctx = JSContext.init(&runtime, allocator);
    defer ctx.deinit();

    // Register all API bindings
    std.debug.print("Registering API bindings...\n", .{});

    const console_api = @import("engine").console_api;
    const zdl_api = @import("engine").zdl_api;
    const world_api = @import("engine").world_api;
    const component_api = @import("engine").component_api;

    try console_api.register(&ctx);
    try console_api.installPrintFunction(&ctx);
    try zdl_api.register(&ctx);
    try world_api.register(&ctx);
    try component_api.register(&ctx);

    std.debug.print("API bindings registered\n\n", .{});

    // Load and execute the module demo
    std.debug.print("Loading examples/module_demo.js...\n", .{});

    const result = evalFile(&ctx, "examples/module_demo.js") catch |err| {
        std.debug.print("Error loading module: {}\n", .{err});
        return err;
    };
    defer ctx.freeValue(result);

    // Flush console messages
    console_api.flushMessages(&ctx);

    // Check if JavaScript requested a window configuration
    std.debug.print("\nChecking for window configuration requests from JavaScript...\n", .{});
    if (try zdl_api.getQueuedWindowConfig(&ctx, allocator)) |config| {
        defer allocator.free(config.title);
        std.debug.print("✓ JavaScript requested window: {s} ({d}x{d})\n", .{ config.title, config.width, config.height });
        std.debug.print("  In a real engine, this would create/reconfigure the SDL window!\n", .{});
    } else {
        std.debug.print("  No window configuration requests.\n", .{});
    }

    std.debug.print("\n=== Demo completed successfully! ===\n", .{});
}
