const std = @import("std");
const zdl = @import("engine");
const Engine = zdl.Engine;
const Application = zdl.Application;
const PlatformerGame = @import("platformer.zig").PlatformerGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator, .{
        .window_title = "Platformer Demo - ZDL Engine",
        .window_width = 960,
        .window_height = 540,
    });
    defer engine.deinit();

    var game = PlatformerGame{
        .player = undefined,
        .tilemap = undefined,
    };

    const app = Application.createApplication(PlatformerGame, &game);
    try engine.run(app);
}
