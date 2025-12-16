const std = @import("std");
const zdl = @import("engine");
const Engine = zdl.Engine;
const Application = zdl.Application;
const CollectorGame = @import("collector.zig").CollectorGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator, .{
        .window_title = "Coin Collector - Phase 3 Demo - ZDL Engine",
        .window_width = 960,
        .window_height = 720,
    });
    defer engine.deinit();

    var game: CollectorGame = undefined;

    const app = Application.createApplication(CollectorGame, &game);
    try engine.run(app);
}
