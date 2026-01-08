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

    // Get quickjs dependency for JavaScript scripting
    const quickjs = b.dependency("quickjs", .{
        .target = target,
        .optimize = optimize,
    });

    // Get zflecs dependency for ECS
    const zflecs = b.dependency("zflecs", .{
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
    engine_module.addImport("quickjs", quickjs.module("quickjs"));
    engine_module.addImport("zflecs", zflecs.module("root"));
    engine_module.linkLibrary(zflecs.artifact("flecs"));
    engine_module.addIncludePath(quickjs.path("."));


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

    // Build Animation Demo example
    const animation_demo = b.addExecutable(.{
        .name = "animation_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/animation_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    animation_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    animation_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(animation_demo);

    // Animation Demo run step
    const run_animation_demo = b.addRunArtifact(animation_demo);
    run_animation_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_animation_demo.addArgs(args);
    }
    const run_animation_step = b.step("run-animation", "Run Animation Demo example");
    run_animation_step.dependOn(&run_animation_demo.step);

    // Build UI Demo example
    const ui_demo = b.addExecutable(.{
        .name = "ui_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/ui_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ui_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    ui_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(ui_demo);

    // UI Demo run step
    const run_ui_demo = b.addRunArtifact(ui_demo);
    run_ui_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_ui_demo.addArgs(args);
    }
    const run_ui_step = b.step("run-ui", "Run UI Demo example");
    run_ui_step.dependOn(&run_ui_demo.step);

    // Build PBR Demo example
    const pbr_demo = b.addExecutable(.{
        .name = "pbr_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/pbr_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pbr_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    pbr_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(pbr_demo);

    // PBR Demo run step
    const run_pbr_demo = b.addRunArtifact(pbr_demo);
    run_pbr_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_pbr_demo.addArgs(args);
    }
    const run_pbr_step = b.step("run-pbr", "Run PBR Demo example");
    run_pbr_step.dependOn(&run_pbr_demo.step);

    // Build Helmet Showcase example
    const helmet_showcase = b.addExecutable(.{
        .name = "helmet_showcase",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/helmet_showcase/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    helmet_showcase.root_module.addImport("sdl3", sdl3.module("sdl3"));
    helmet_showcase.root_module.addImport("engine", engine_module);
    b.installArtifact(helmet_showcase);

    // Helmet Showcase run step
    const run_helmet_showcase = b.addRunArtifact(helmet_showcase);
    run_helmet_showcase.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_helmet_showcase.addArgs(args);
    }
    const run_helmet_showcase_step = b.step("run-helmet-showcase", "Run Damaged Helmet showcase example");
    run_helmet_showcase_step.dependOn(&run_helmet_showcase.step);

    // Build Raymarch PBR Demo example
    const raymarch_pbr = b.addExecutable(.{
        .name = "raymarch_pbr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/raymarch_pbr/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    raymarch_pbr.root_module.addImport("sdl3", sdl3.module("sdl3"));
    raymarch_pbr.root_module.addImport("engine", engine_module);
    b.installArtifact(raymarch_pbr);

    // Raymarch PBR Demo run step
    const run_raymarch_pbr = b.addRunArtifact(raymarch_pbr);
    run_raymarch_pbr.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_raymarch_pbr.addArgs(args);
    }
    const run_raymarch_pbr_step = b.step("run-raymarch-pbr", "Run Raymarch PBR Demo example");
    run_raymarch_pbr_step.dependOn(&run_raymarch_pbr.step);

    // Build Gamepad Demo example
    const gamepad_demo = b.addExecutable(.{
        .name = "gamepad_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/gamepad_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gamepad_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    gamepad_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(gamepad_demo);

    // Gamepad Demo run step
    const run_gamepad_demo = b.addRunArtifact(gamepad_demo);
    run_gamepad_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_gamepad_demo.addArgs(args);
    }
    const run_gamepad_step = b.step("run-gamepad", "Run Gamepad Demo example");
    run_gamepad_step.dependOn(&run_gamepad_demo.step);

    // Build Scripting Demo example
    const scripting_demo = b.addExecutable(.{
        .name = "scripting_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/scripting_demo/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scripting_demo.root_module.addImport("sdl3", sdl3.module("sdl3"));
    scripting_demo.root_module.addImport("engine", engine_module);
    b.installArtifact(scripting_demo);

    // Scripting Demo run step
    const run_scripting_demo = b.addRunArtifact(scripting_demo);
    run_scripting_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_scripting_demo.addArgs(args);
    }
    const run_scripting_step = b.step("run-scripting", "Run Scripting Demo example");
    run_scripting_step.dependOn(&run_scripting_demo.step);

    // Note: Shader compilation is handled by the asset pipeline tool (zdl-assets)
    // Run: zig build assets -- build --source=src/shaders --output=src/shaders
    // Or:  ./zig-out/bin/zdl-assets build --source=assets --output=build/assets

    // Tests
    const engine_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    engine_tests.root_module.addImport("sdl3", sdl3.module("sdl3"));
    engine_tests.root_module.addImport("quickjs", quickjs.module("quickjs"));
    engine_tests.root_module.addImport("zflecs", zflecs.module("root"));
    engine_tests.root_module.linkLibrary(zflecs.artifact("flecs"));
    engine_tests.linkLibC();
    engine_tests.root_module.addIncludePath(quickjs.path("."));

    const run_tests = b.addRunArtifact(engine_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
