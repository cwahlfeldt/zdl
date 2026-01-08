const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk = b.option([]const u8, "ultralight", "Path to Ultralight SDK") orelse "SDK";

    const sdk_bin = try std.fs.path.join(b.allocator, &.{ sdk, "bin" });
    defer b.allocator.free(sdk_bin);

    const sdk_include = try std.fs.path.join(b.allocator, &.{ sdk, "include" });
    defer b.allocator.free(sdk_include);

    const ul = b.addModule("ul", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    ul.addRPath(.{ .cwd_relative = sdk_bin });
    ul.addLibraryPath(.{ .cwd_relative = sdk_bin });
    ul.addIncludePath(.{ .cwd_relative = sdk_include });
    ul.linkSystemLibrary("Ultralight", .{});
    ul.linkSystemLibrary("UltralightCore", .{});
    ul.linkSystemLibrary("WebCore", .{});
    ul.linkSystemLibrary("AppCore", .{});

    const example_app = b.addExecutable(.{ .name = "example", .root_module = b.path("example.zig") });

    //     .name = options.name,
    // .root_module = options.root_module,
    // .version = options.version,
    // .kind = .exe,
    // .linkage = options.linkage,
    // .max_rss = options.max_rss,
    // .use_llvm = options.use_llvm,
    // .use_lld = options.use_lld,
    // .zig_lib_dir = options.zig_lib_dir,
    // .win32_manifest = options.win32_manifest,

    example_app.root_module.addImport("ul", ul);

    const example_app_artifact = b.addRunArtifact(example_app);
    b.step("run", "Run the example app").dependOn(&example_app_artifact.step);
}
