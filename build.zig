const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get zig-sdl3 dependency with SDL_image extension enabled
    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_image = true,
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

    // Build Debug Demo example
    const debug_demo = b.addExecutable(.{
        .name = "debug_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/debug_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    debug_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    debug_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(debug_demo);

    // Debug Demo run step
    const run_debug_demo = b.addRunArtifact(debug_demo);
    run_debug_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_debug_demo.addArgs(args);
    }
    const run_debug_step = b.step("run-debug", "Run Debug Demo example");
    run_debug_step.dependOn(&run_debug_demo.step);

    // Build glTF Demo example
    const gltf_demo = b.addExecutable(.{
        .name = "gltf_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/gltf_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gltf_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    gltf_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(gltf_demo);

    // glTF Demo run step
    const run_gltf_demo = b.addRunArtifact(gltf_demo);
    run_gltf_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_gltf_demo.addArgs(args);
    }
    const run_gltf_step = b.step("run-gltf", "Run glTF Demo example");
    run_gltf_step.dependOn(&run_gltf_demo.step);

    // Note: Shader compilation is handled by the asset pipeline tool (zdl-assets)
    // Run: zig build assets -- build --source=src/shaders --output=src/shaders
    // Or:  ./zig-out/bin/zdl-assets build --source=assets --output=build/assets

    // Tests
    const engine_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/engine.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    engine_tests.root_module.addImport("sdl3", sdl3.module("sdl3"));

    const run_tests = b.addRunArtifact(engine_tests);
    const test_step = b.step("test", "Run engine unit tests");
    test_step.dependOn(&run_tests.step);
}
