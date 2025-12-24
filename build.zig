const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Compile shaders
    compileShaders(b) catch |err| {
        std.debug.print("Warning: Failed to compile shaders: {}\n", .{err});
    };

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
}

/// Compile GLSL shaders to SPIR-V using glslangValidator
fn compileShaders(b: *std.Build) !void {
    const shader_dir = "src/shaders/";

    // List of shaders to compile
    const shaders = [_]struct { src: []const u8, stage: []const u8 }{
        .{ .src = "vertex.vert", .stage = "vert" },
        .{ .src = "fragment.frag", .stage = "frag" },
    };

    for (shaders) |shader| {
        const src_path = b.fmt("{s}{s}", .{ shader_dir, shader.src });
        const out_path = b.fmt("{s}{s}.spv", .{ shader_dir, shader.src[0 .. shader.src.len - 5] });

        // Run glslangValidator
        const result = std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &[_][]const u8{
                "glslangValidator",
                "-V",
                src_path,
                "-o",
                out_path,
            },
        }) catch |err| {
            std.debug.print("Shader compilation skipped (glslangValidator not found): {}\n", .{err});
            return;
        };
        defer b.allocator.free(result.stdout);
        defer b.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            std.debug.print("Failed to compile {s}:\n{s}\n", .{ src_path, result.stderr });
            return error.ShaderCompilationFailed;
        }

        std.debug.print("Compiled shader: {s} -> {s}\n", .{ src_path, out_path });
    }
}
