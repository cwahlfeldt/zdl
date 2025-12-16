const std = @import("std");
const zdl = @import("engine");
const Engine = zdl.Engine;
const Application = zdl.Application;
const Cube3D = @import("cube3d.zig").Cube3D;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator, .{
        .window_title = "ZDL - 3D Cube Demo (Phase 4)",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 60,
    });
    defer engine.deinit();

    var game: Cube3D = undefined;

    const app = Application.createApplication(Cube3D, &game);
    try engine.run(app);
}
