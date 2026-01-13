const std = @import("std");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Input = engine.Input;
const evalFile = engine.evalFile;

const ProjectConfig = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    window: WindowConfig = .{},

    const WindowConfig = struct {
        width: u32 = 1280,
        height: u32 = 720,
        title: ?[]const u8 = null,
    };
};

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

    // Try to load project configuration from zdl.json
    const project_config = loadProjectConfig(allocator) catch |err| blk: {
        if (err != error.FileNotFound) {
            std.debug.print("Warning: Error reading zdl.json: {}\n", .{err});
        }
        break :blk ProjectConfig{};
    };
    defer {
        if (project_config.name) |n| allocator.free(n);
        if (project_config.version) |v| allocator.free(v);
        if (project_config.window.title) |t| allocator.free(t);
    }

    // Determine window settings
    var window_title_buf: [256:0]u8 = undefined;
    const window_title: [:0]const u8 = if (project_config.window.title) |title| blk: {
        const len = @min(title.len, 255);
        @memcpy(window_title_buf[0..len], title[0..len]);
        window_title_buf[len] = 0;
        break :blk window_title_buf[0..len :0];
    } else "ZDL Game";

    if (project_config.window.title != null or
        project_config.window.width != 1280 or
        project_config.window.height != 720) {
        std.debug.print("Using configuration from zdl.json:\n", .{});
        std.debug.print("  Window: {s} ({d}x{d})\n", .{
            window_title,
            project_config.window.width,
            project_config.window.height,
        });
    }

    // Initialize engine with project settings
    std.debug.print("Initializing engine...\n", .{});
    var eng = try Engine.init(allocator, .{
        .window_title = window_title,
        .window_width = project_config.window.width,
        .window_height = project_config.window.height,
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

/// Load project configuration from zdl.json
fn loadProjectConfig(allocator: std.mem.Allocator) !ProjectConfig {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile("zdl.json", .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    var config = ProjectConfig{};

    // Extract name
    if (root.get("name")) |name_val| {
        config.name = try allocator.dupe(u8, name_val.string);
    }

    // Extract version
    if (root.get("version")) |version_val| {
        config.version = try allocator.dupe(u8, version_val.string);
    }

    // Extract window configuration
    if (root.get("window")) |window_val| {
        const window_obj = window_val.object;

        if (window_obj.get("width")) |width_val| {
            config.window.width = @intCast(width_val.integer);
        }

        if (window_obj.get("height")) |height_val| {
            config.window.height = @intCast(height_val.integer);
        }

        if (window_obj.get("title")) |title_val| {
            config.window.title = try allocator.dupe(u8, title_val.string);
        }
    }

    return config;
}
