const std = @import("std");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Input = engine.Input;
const evalFile = engine.evalFile;

pub fn execute(allocator: std.mem.Allocator, path_opt: ?[]const u8) !void {
    const game_path = path_opt orelse "game.js";

    std.debug.print("Running ZDL game: {s}\n", .{game_path});

    // Check if the file exists
    const cwd = std.fs.cwd();
    const file = cwd.openFile(game_path, .{}) catch |err| {
        std.debug.print("Error: Could not find '{s}': {}\n", .{ game_path, err });
        std.debug.print("\nMake sure you're in a ZDL project directory.\n", .{});
        std.debug.print("Create a new project with: zdl create <project-name>\n", .{});
        std.process.exit(1);
    };
    file.close();

    std.debug.print("\n", .{});
    std.debug.print("=======================================================\n", .{});
    std.debug.print("  ZDL Game Engine\n", .{});
    std.debug.print("=======================================================\n", .{});
    std.debug.print("\n", .{});

    // Initialize engine with default settings
    std.debug.print("Initializing engine...\n", .{});
    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL Game",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 60,
    });
    defer eng.deinit();

    // Initialize scripting system
    std.debug.print("Initializing JavaScript runtime...\n", .{});
    try eng.initScripting();

    // Create an empty scene (JavaScript will populate it)
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Load and execute the JavaScript file
    std.debug.print("Loading game script: {s}\n", .{game_path});
    const result = evalFile(eng.script_system.?.context, game_path) catch |err| {
        std.debug.print("Error loading game script: {}\n", .{err});
        std.process.exit(1);
    };
    eng.script_system.?.context.freeValue(result);

    // Look for and call the main() function
    std.debug.print("Looking for main() function...\n", .{});
    const main_fn = eng.script_system.?.context.getGlobal("main");
    defer eng.script_system.?.context.freeValue(main_fn);

    if (eng.script_system.?.context.isFunction(main_fn)) {
        std.debug.print("Calling main()...\n", .{});
        // Call main() with no arguments and main_fn as the 'this' context
        const main_result = eng.script_system.?.context.call(main_fn, main_fn, &.{}) catch |err| {
            std.debug.print("Error calling main(): {}\n", .{err});
            std.process.exit(1);
        };
        eng.script_system.?.context.freeValue(main_result);
    } else {
        std.debug.print("Warning: No main() function found in {s}\n", .{game_path});
        std.debug.print("Your game script should export a main() function.\n", .{});
    }

    std.debug.print("\nStarting game loop...\n", .{});
    std.debug.print("Press ESC to quit\n\n", .{});

    // Run the game loop
    try eng.runScene(&scene, jsGameUpdate);
}

/// Update function that defers to JavaScript systems
fn jsGameUpdate(_: *Engine, _: *Scene, _: *Input, _: f32) !void {
    // All game logic is handled by JavaScript systems registered via world.addSystem()
}
