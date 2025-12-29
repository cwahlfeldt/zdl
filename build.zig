const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get zig-sdl3 dependency
    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
    });

    // Create engine module
    const engine_module = b.createModule(.{
        .root_source_file = b.path("src/engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_module.addImport("sdl3", sdl3.module("sdl3"));

    // Build Asset Pipeline tool
    const zdl_assets = b.addExecutable(.{
        .name = "zdl-assets",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/asset_pipeline/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(zdl_assets);

    // Run asset pipeline step
    const run_assets = b.addRunArtifact(zdl_assets);
    run_assets.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_assets.addArgs(args);
    }
    const assets_step = b.step("assets", "Run asset pipeline tool");
    assets_step.dependOn(&run_assets.step);

    // Build Cube3D example
    const cube3d = b.addExecutable(.{
        .name = "cube3d",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/cube3d/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cube3d.root_module.addImport("sdl3", sdl3.module("sdl3"));
    cube3d.root_module.addImport("engine", engine_module);
    b.installArtifact(cube3d);

    // Build Scene Demo example
    const scene_demo = b.addExecutable(.{
        .name = "scene_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/scene_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scene_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    scene_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(scene_demo);

    // Default run step (Cube3D)
    const run_cube3d = b.addRunArtifact(cube3d);
    run_cube3d.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cube3d.addArgs(args);
    }
    const run_step = b.step("run", "Run Cube3D example");
    run_step.dependOn(&run_cube3d.step);

    // Scene Demo run step
    const run_scene_demo = b.addRunArtifact(scene_demo);
    run_scene_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_scene_demo.addArgs(args);
    }
    const run_scene_step = b.step("run-scene", "Run Scene Demo example");
    run_scene_step.dependOn(&run_scene_demo.step);

    // Note: Shader compilation is handled by the asset pipeline tool (zdl-assets)
    // Run: zig build assets -- build --source=src/shaders --output=src/shaders
    // Or:  ./zig-out/bin/zdl-assets build --source=assets --output=build/assets
}
