const std = @import("std");

pub fn execute(allocator: std.mem.Allocator, path_opt: ?[]const u8) !void {
    _ = allocator;

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

    // TODO: In a full implementation, this would:
    // 1. Initialize the Engine
    // 2. Initialize ScriptSystem
    // 3. Load the JavaScript module
    // 4. Call the main() function
    // 5. Run the game loop
    //
    // For now, we just print a message indicating what would happen

    std.debug.print("\n", .{});
    std.debug.print("=======================================================\n", .{});
    std.debug.print("  ZDL Game Engine\n", .{});
    std.debug.print("=======================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Game file: {s}\n", .{game_path});
    std.debug.print("\n", .{});
    std.debug.print("NOTE: Full game execution is not yet implemented.\n", .{});
    std.debug.print("The 'zdl run' command will:\n", .{});
    std.debug.print("  1. Initialize the ZDL engine\n", .{});
    std.debug.print("  2. Load and execute {s}\n", .{game_path});
    std.debug.print("  3. Call the exported main() function\n", .{});
    std.debug.print("  4. Run the game loop with JavaScript systems\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("For now, use the scripting_demo example:\n", .{});
    std.debug.print("  zig build run-scripting-demo\n", .{});
    std.debug.print("\n", .{});
}
