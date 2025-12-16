const std = @import("std");
const zdl = @import("engine");
const Engine = zdl.Engine;
const Application = zdl.Application;
const PongGame = @import("pong.zig").PongGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator, .{
        .window_title = "Pong - ZDL Engine",
        .window_width = 960,
        .window_height = 540,
    });
    defer engine.deinit();

    var game = PongGame{
        .left_paddle = undefined,
        .right_paddle = undefined,
        .ball = undefined,
        .score_left = undefined,
        .score_right = undefined,
    };

    const app = Application.createApplication(PongGame, &game);
    try engine.run(app);
}
