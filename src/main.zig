const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const EngineConfig = @import("engine/engine.zig").EngineConfig;
const Application = @import("engine/application.zig");
const PongGame = @import("game/pong.zig").PongGame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the engine
    var engine = try Engine.init(allocator, .{
        .window_title = "Pong - ZDL Engine",
        .window_width = 960,
        .window_height = 540,
    });
    defer engine.deinit();

    // Create your game
    var game = PongGame{
        .left_paddle = undefined,
        .right_paddle = undefined,
        .ball = undefined,
        .score_left = undefined,
        .score_right = undefined,
    };

    // Run the game loop
    const app = Application.createApplication(PongGame, &game);
    try engine.run(app);
}
