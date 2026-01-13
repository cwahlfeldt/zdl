const std = @import("std");
const create = @import("commands/create.zig");
const run = @import("commands/run.zig");
const build = @import("commands/build.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "create")) {
        if (args.len < 3) {
            std.debug.print("Error: 'create' command requires a project path\n", .{});
            std.debug.print("Usage: zdl create <path>\n", .{});
            std.process.exit(1);
        }
        try create.execute(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "run")) {
        const path = if (args.len >= 3) args[2] else null;
        try run.execute(allocator, path);
    } else if (std.mem.eql(u8, command, "build")) {
        const path = if (args.len >= 3) args[2] else null;
        try build.execute(allocator, path);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{command});
        printUsage();
        std.process.exit(1);
    }
}

fn printUsage() void {
    std.debug.print(
        \\ZDL Game Engine CLI
        \\
        \\Usage:
        \\  zdl <command> [options]
        \\
        \\Commands:
        \\  create <path>    Create a new ZDL project at the specified path
        \\  run [path]       Run a ZDL game (defaults to game.js in current directory)
        \\  build [path]     Build a ZDL game for distribution
        \\  help             Show this help message
        \\
        \\Examples:
        \\  zdl create my-game
        \\  zdl run
        \\  zdl run game.js
        \\
    , .{});
}
