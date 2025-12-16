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

    // Build Pong example (default)
    const pong = b.addExecutable(.{
        .name = "pong",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/pong/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pong.root_module.addImport("sdl3", sdl3.module("sdl3"));
    pong.root_module.addImport("engine", engine_module);
    b.installArtifact(pong);

    // Build Platformer example
    const platformer = b.addExecutable(.{
        .name = "platformer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/platformer/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    platformer.root_module.addImport("sdl3", sdl3.module("sdl3"));
    platformer.root_module.addImport("engine", engine_module);
    b.installArtifact(platformer);

    // Build Collector example (Phase 3 demo)
    const collector = b.addExecutable(.{
        .name = "collector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/collector/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    collector.root_module.addImport("sdl3", sdl3.module("sdl3"));
    collector.root_module.addImport("engine", engine_module);
    b.installArtifact(collector);

    // Build Cube3D example (Phase 4 demo)
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

    // Default run step (cube3d - best demo of Phase 4 features)
    const run_cube3d = b.addRunArtifact(cube3d);
    run_cube3d.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cube3d.addArgs(args);
    }
    const run_step = b.step("run", "Run Cube3D example (Phase 4 demo)");
    run_step.dependOn(&run_cube3d.step);

    // Run collector
    const run_collector = b.addRunArtifact(collector);
    run_collector.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_collector.addArgs(args);
    }
    const run_collector_step = b.step("run-collector", "Run Collector example (Phase 3 demo)");
    run_collector_step.dependOn(&run_collector.step);

    // Run pong
    const run_pong = b.addRunArtifact(pong);
    run_pong.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_pong.addArgs(args);
    }
    const run_pong_step = b.step("run-pong", "Run Pong example");
    run_pong_step.dependOn(&run_pong.step);

    // Run platformer
    const run_platformer = b.addRunArtifact(platformer);
    run_platformer.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_platformer.addArgs(args);
    }
    const run_platformer_step = b.step("run-platformer", "Run Platformer example");
    run_platformer_step.dependOn(&run_platformer.step);
}

/// Compile GLSL shaders to SPIR-V using glslangValidator
fn compileShaders(b: *std.Build) !void {
    const shader_dir = "src/shaders/";

    // List of shaders to compile
    const shaders = [_]struct { src: []const u8, stage: []const u8 }{
        .{ .src = "vertex.vert", .stage = "vert" },
        .{ .src = "fragment.frag", .stage = "frag" },
        .{ .src = "vertex_3d.vert", .stage = "vert" },
        .{ .src = "fragment_3d.frag", .stage = "frag" },
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
