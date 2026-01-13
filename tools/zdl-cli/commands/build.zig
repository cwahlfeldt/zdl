const std = @import("std");

const ProjectConfig = struct {
    name: []const u8,
    version: []const u8,
    entry: []const u8,
    output: []const u8,
    window: WindowConfig,
    assets: AssetsConfig,

    const WindowConfig = struct {
        width: u32,
        height: u32,
        title: []const u8,
    };

    const AssetsConfig = struct {
        include: []const []const u8,
    };
};

pub fn execute(allocator: std.mem.Allocator, path_opt: ?[]const u8) !void {
    const project_root = path_opt orelse ".";

    std.debug.print("Building ZDL project at: {s}\n", .{project_root});

    // Open project directory
    const cwd = std.fs.cwd();
    var project_dir = cwd.openDir(project_root, .{ .iterate = true }) catch |err| {
        std.debug.print("Error: Could not open project directory '{s}': {}\n", .{ project_root, err });
        std.process.exit(1);
    };
    defer project_dir.close();

    // Read project.json
    std.debug.print("Reading project configuration...\n", .{});
    const config = try readProjectConfig(allocator, project_dir);
    defer freeProjectConfig(allocator, config);

    std.debug.print("Project: {s} v{s}\n", .{ config.name, config.version });
    std.debug.print("Entry point: {s}\n", .{config.entry});
    std.debug.print("Output directory: {s}\n", .{config.output});

    // Create output directory
    std.debug.print("\nCreating output directory...\n", .{});
    project_dir.makePath(config.output) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var output_dir = try project_dir.openDir(config.output, .{});
    defer output_dir.close();

    // Bundle JavaScript files
    std.debug.print("Bundling JavaScript files...\n", .{});
    try bundleJavaScript(allocator, project_dir, output_dir, config.entry);

    // Copy assets
    std.debug.print("Processing assets...\n", .{});
    try processAssets(allocator, project_dir, output_dir, config.assets.include);

    // Create runtime configuration file
    std.debug.print("Creating runtime configuration...\n", .{});
    try createRuntimeConfig(output_dir, config);

    // Create launcher script (for future: package with engine binary)
    std.debug.print("Creating launcher...\n", .{});
    try createLauncher(output_dir, config);

    std.debug.print("\n✓ Build completed successfully!\n", .{});
    std.debug.print("\nOutput directory: {s}/{s}\n", .{ project_root, config.output });
    std.debug.print("\nTo run the built game:\n", .{});
    std.debug.print("  cd {s}/{s}\n", .{ project_root, config.output });
    std.debug.print("  zdl run game.bundle.js\n", .{});
    std.debug.print("\n", .{});
}

fn readProjectConfig(allocator: std.mem.Allocator, project_dir: std.fs.Dir) !ProjectConfig {
    const file = project_dir.openFile("zdl.json", .{}) catch |err| {
        std.debug.print("Error: Could not find zdl.json: {}\n", .{err});
        std.debug.print("Make sure you're in a ZDL project directory.\n", .{});
        std.process.exit(1);
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract configuration with defaults
    const name = if (root.get("name")) |n| try allocator.dupe(u8, n.string) else try allocator.dupe(u8, "unnamed-project");
    const version = if (root.get("version")) |v| try allocator.dupe(u8, v.string) else try allocator.dupe(u8, "1.0.0");
    const entry = if (root.get("entry")) |e| try allocator.dupe(u8, e.string) else try allocator.dupe(u8, "game.js");
    const output = if (root.get("output")) |o| try allocator.dupe(u8, o.string) else try allocator.dupe(u8, "dist/");

    // Window config
    const window_obj = if (root.get("window")) |w| w.object else std.json.ObjectMap.init(allocator);
    const window = ProjectConfig.WindowConfig{
        .width = if (window_obj.get("width")) |w| @intCast(w.integer) else 1280,
        .height = if (window_obj.get("height")) |h| @intCast(h.integer) else 720,
        .title = if (window_obj.get("title")) |t| try allocator.dupe(u8, t.string) else try allocator.dupe(u8, "ZDL Game"),
    };

    // Assets config
    var include_list = std.ArrayListUnmanaged([]const u8){};
    defer include_list.deinit(allocator);

    if (root.get("assets")) |assets_obj| {
        if (assets_obj.object.get("include")) |include_array| {
            for (include_array.array.items) |item| {
                try include_list.append(allocator, try allocator.dupe(u8, item.string));
            }
        }
    }
    if (include_list.items.len == 0) {
        try include_list.append(allocator, try allocator.dupe(u8, "assets/**/*"));
    }

    const assets = ProjectConfig.AssetsConfig{
        .include = try include_list.toOwnedSlice(allocator),
    };

    return ProjectConfig{
        .name = name,
        .version = version,
        .entry = entry,
        .output = output,
        .window = window,
        .assets = assets,
    };
}

fn freeProjectConfig(allocator: std.mem.Allocator, config: ProjectConfig) void {
    allocator.free(config.name);
    allocator.free(config.version);
    allocator.free(config.entry);
    allocator.free(config.output);
    allocator.free(config.window.title);
    for (config.assets.include) |pattern| {
        allocator.free(pattern);
    }
    allocator.free(config.assets.include);
}

fn bundleJavaScript(
    allocator: std.mem.Allocator,
    project_dir: std.fs.Dir,
    output_dir: std.fs.Dir,
    entry_file: []const u8,
) !void {
    // For now, we'll do a simple bundling approach:
    // 1. Read the entry file
    // 2. Scan for local imports (relative paths)
    // 3. Inline them into a single file
    // 4. Keep external imports (like "zdl") as-is

    var visited = std.StringHashMap(void).init(allocator);
    defer {
        var iter = visited.keyIterator();
        while (iter.next()) |key| {
            allocator.free(key.*);
        }
        visited.deinit();
    }

    var bundle = std.ArrayListUnmanaged(u8){};
    defer bundle.deinit(allocator);

    // Add bundle header
    try bundle.appendSlice(allocator, "// ZDL Game Bundle\n");
    try bundle.appendSlice(allocator, "// Generated by zdl build\n\n");

    // Bundle the entry file and its dependencies
    try bundleFile(allocator, project_dir, entry_file, &bundle, &visited);

    // Write bundled output
    const output_file = try output_dir.createFile("game.bundle.js", .{});
    defer output_file.close();
    try output_file.writeAll(bundle.items);

    std.debug.print("  → Bundled {s} to game.bundle.js\n", .{entry_file});
}

fn bundleFile(
    allocator: std.mem.Allocator,
    project_dir: std.fs.Dir,
    file_path: []const u8,
    bundle: *std.ArrayListUnmanaged(u8),
    visited: *std.StringHashMap(void),
) !void {
    // Avoid bundling the same file twice
    if (visited.contains(file_path)) return;
    try visited.put(try allocator.dupe(u8, file_path), {});

    // Read the file
    const file = try project_dir.openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    // Add file marker comment
    try bundle.writer(allocator).print("\n// === {s} ===\n", .{file_path});

    // Simple approach: scan for import statements and process them
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Check if this is an import statement
        if (std.mem.startsWith(u8, trimmed, "import ")) {
            // Extract the module path from 'import ... from "path"'
            if (std.mem.indexOf(u8, trimmed, " from ")) |from_pos| {
                const after_from = trimmed[from_pos + 6 ..]; // Skip " from "
                const quote_start = std.mem.indexOf(u8, after_from, "\"") orelse
                    std.mem.indexOf(u8, after_from, "'") orelse continue;
                const quote_char = after_from[quote_start];
                const path_start = quote_start + 1;
                const quote_end = std.mem.indexOfPos(u8, after_from, path_start, &[_]u8{quote_char}) orelse continue;
                const module_path = after_from[path_start..quote_end];

                // Check if it's a relative import (starts with ./ or ../)
                if (std.mem.startsWith(u8, module_path, "./") or std.mem.startsWith(u8, module_path, "../")) {
                    // Resolve relative path and bundle it
                    const resolved_path = try resolveRelativePath(allocator, file_path, module_path);
                    defer allocator.free(resolved_path);

                    try bundleFile(allocator, project_dir, resolved_path, bundle, visited);

                    // Add a comment instead of the import
                    try bundle.writer(allocator).print("// bundled: {s}\n", .{line});
                    continue;
                }
            }
        }

        // Not an import or external import - include as-is
        try bundle.appendSlice(allocator, line);
        try bundle.append(allocator, '\n');
    }
}

fn resolveRelativePath(allocator: std.mem.Allocator, current_file: []const u8, relative_path: []const u8) ![]const u8 {
    // Get the directory of the current file
    const dir = std.fs.path.dirname(current_file) orelse ".";

    // Join with the relative path
    const joined = try std.fs.path.join(allocator, &[_][]const u8{ dir, relative_path });

    // Normalize the path
    return joined;
}

fn processAssets(
    allocator: std.mem.Allocator,
    project_dir: std.fs.Dir,
    output_dir: std.fs.Dir,
    patterns: []const []const u8,
) !void {
    // Create assets directory in output
    output_dir.makePath("assets") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var output_assets = try output_dir.openDir("assets", .{});
    defer output_assets.close();

    // For each pattern, copy matching files
    for (patterns) |pattern| {
        // Simple pattern matching: if pattern is "assets/**/*", copy entire assets directory
        if (std.mem.eql(u8, pattern, "assets/**/*") or std.mem.eql(u8, pattern, "assets/")) {
            try copyDirectory(allocator, project_dir, output_assets, "assets");
        } else {
            // For other patterns, try to copy as literal paths
            std.debug.print("  Warning: Pattern '{s}' not fully supported, skipping\n", .{pattern});
        }
    }
}

fn copyDirectory(
    allocator: std.mem.Allocator,
    src_root: std.fs.Dir,
    dst_root: std.fs.Dir,
    dir_name: []const u8,
) !void {
    var src_dir = src_root.openDir(dir_name, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("  Warning: Directory '{s}' not found, skipping\n", .{dir_name});
            return;
        }
        return err;
    };
    defer src_dir.close();

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    var file_count: usize = 0;

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            // Create parent directories in destination
            if (std.fs.path.dirname(entry.path)) |parent| {
                dst_root.makePath(parent) catch |err| {
                    if (err != error.PathAlreadyExists) return err;
                };
            }

            // Copy the file
            try src_dir.copyFile(entry.path, dst_root, entry.path, .{});
            file_count += 1;
        }
    }

    std.debug.print("  → Copied {d} asset files from {s}/\n", .{ file_count, dir_name });
}

fn createRuntimeConfig(
    output_dir: std.fs.Dir,
    config: ProjectConfig,
) !void {
    const runtime_config =
        \\{{
        \\  "name": "{s}",
        \\  "version": "{s}",
        \\  "window": {{
        \\    "width": {d},
        \\    "height": {d},
        \\    "title": "{s}"
        \\  }}
        \\}}
        \\
    ;

    const file = try output_dir.createFile("config.json", .{});
    defer file.close();

    var buf: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(
        &buf,
        runtime_config,
        .{
            config.name,
            config.version,
            config.window.width,
            config.window.height,
            config.window.title,
        },
    );

    try file.writeAll(formatted);
    std.debug.print("  → Created config.json\n", .{});
}

fn createLauncher(
    output_dir: std.fs.Dir,
    config: ProjectConfig,
) !void {

    // Create a simple README with instructions
    const launcher_readme =
        \\# {s}
        \\
        \\## Running the Game
        \\
        \\To run this game, you need the ZDL engine installed.
        \\
        \\From this directory, run:
        \\
        \\```bash
        \\zdl run game.bundle.js
        \\```
        \\
        \\## Distribution
        \\
        \\For full distribution, package this directory with the ZDL runtime.
        \\Future versions of ZDL will support creating standalone executables.
        \\
    ;

    const file = try output_dir.createFile("README.md", .{});
    defer file.close();

    var buf: [2048]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, launcher_readme, .{config.name});
    try file.writeAll(formatted);

    std.debug.print("  → Created README.md\n", .{});
}
