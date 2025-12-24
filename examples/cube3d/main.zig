const std = @import("std");
const engine = @import("engine");
const Engine = engine.Engine;
const Application = engine.Application;
const Cube3D = @import("cube3d.zig").Cube3D;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - 3D Cube Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 60,
    });
    defer eng.deinit();

    var game: Cube3D = .{};

    const app = Application.createApplication(Cube3D, &game);
    try eng.run(app);
}
