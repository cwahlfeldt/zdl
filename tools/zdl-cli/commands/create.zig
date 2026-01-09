const std = @import("std");

pub fn execute(allocator: std.mem.Allocator, path: []const u8) !void {
    _ = allocator;

    std.debug.print("Creating ZDL project at: {s}\n", .{path});

    // Create directory structure
    const cwd = std.fs.cwd();
    try cwd.makePath(path);

    // Create subdirectories
    var project_dir = try cwd.openDir(path, .{});
    defer project_dir.close();

    try project_dir.makePath("assets");
    try project_dir.makePath("scripts");

    // Create game.js template
    const game_js_content =
        \\// {s} - ZDL Game
        \\//
        \\// This is your game's main entry point.
        \\// Run with: zdl run
        \\
        \\import zdl from "zdl";
        \\
        \\/* ============================
        \\ * Components
        \\ * ============================ */
        \\
        \\const Player = () => ({{
        \\  type: "Player",
        \\  name: "Player",
        \\}});
        \\
        \\const Position = (x = 0, y = 0, z = 0) => ({{
        \\  type: "Position",
        \\  position: {{ x, y, z }},
        \\}});
        \\
        \\const Camera = ({{ fov = 60, near = 0.1, far = 1000, active = true }} = {{}}) => ({{
        \\  type: "Camera",
        \\  fov,
        \\  near,
        \\  far,
        \\  active,
        \\}});
        \\
        \\const Mesh = (path = "assets/cube.glb") => ({{
        \\  type: "Mesh",
        \\  path,
        \\}});
        \\
        \\/* ============================
        \\ * Systems
        \\ * ============================ */
        \\
        \\function moveSystem(world) {{
        \\  const results = world.query(Player, Position);
        \\
        \\  for (const entity of results) {{
        \\    if (world.hasComponent(entity, Position)) {{
        \\      const pos = world.getComponent(entity, Position);
        \\
        \\      world.updateComponent(
        \\        entity,
        \\        Position(pos.position.x + 0.01, pos.position.y, pos.position.z)
        \\      );
        \\    }}
        \\  }}
        \\}}
        \\
        \\function initSystem(world) {{
        \\  console.log("Game initialized!");
        \\}}
        \\
        \\function destroySystem(world) {{
        \\  console.log("Game shutting down");
        \\}}
        \\
        \\/* ============================
        \\ * Scene Setup
        \\ * ============================ */
        \\
        \\export function main() {{
        \\  // Initialize the window
        \\  const window = zdl.createWindow({{
        \\    size: "1280x720",
        \\    title: "{s}",
        \\  }});
        \\
        \\  // Create the world (ECS + render world)
        \\  const world = zdl.createWorld(window);
        \\
        \\  // Register components with the world
        \\  world.addComponents([Player, Position, Camera, Mesh]);
        \\
        \\  // Create player entity
        \\  const player = world.addEntity((ctx) => ({{
        \\    description: "Main player entity",
        \\    name: "player",
        \\  }}))(Player(), Position(0, 0, 0), Mesh("assets/player.glb"));
        \\
        \\  // Create camera entity
        \\  const camera = world.addEntity((ctx) => ({{
        \\    description: "Main camera",
        \\    name: "camera",
        \\  }}))(Camera({{ fov: 75 }}), Position(0, 2, 5));
        \\
        \\  // Create a cube mesh entity
        \\  const cubeMesh = world.addEntity((ctx) => ({{
        \\    description: "Test cube",
        \\    name: "cube",
        \\  }}))(Position(2, 0, 0), Mesh("assets/cube.glb"));
        \\
        \\  // Register systems
        \\  world.addSystem(moveSystem, "update");
        \\  world.addSystem(initSystem, "init");
        \\  world.addSystem(destroySystem, "destroy");
        \\
        \\  console.log("World populated with entities");
        \\  console.log("Run with `zdl run` in the project directory");
        \\}}
        \\
    ;

    const game_js_file = try project_dir.createFile("game.js", .{});
    defer game_js_file.close();

    var buf: [4096]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, game_js_content, .{ path, path });
    try game_js_file.writeAll(formatted);

    // Create project.json
    const project_json_content =
        \\{{
        \\  "name": "{s}",
        \\  "version": "1.0.0",
        \\  "entry": "game.js",
        \\  "output": "dist/",
        \\  "window": {{
        \\    "width": 1280,
        \\    "height": 720,
        \\    "title": "{s}"
        \\  }},
        \\  "assets": {{
        \\    "include": ["assets/**/*"]
        \\  }}
        \\}}
        \\
    ;

    const project_json_file = try project_dir.createFile("project.json", .{});
    defer project_json_file.close();

    var json_buf: [1024]u8 = undefined;
    const formatted_json = try std.fmt.bufPrint(&json_buf, project_json_content, .{ path, path });
    try project_json_file.writeAll(formatted_json);

    // Create README.md
    const readme_content =
        \\# {s}
        \\
        \\A game built with the ZDL engine.
        \\
        \\## Getting Started
        \\
        \\Run the game in development mode:
        \\
        \\```bash
        \\zdl run
        \\```
        \\
        \\Build for distribution:
        \\
        \\```bash
        \\zdl build
        \\```
        \\
        \\## Project Structure
        \\
        \\- `game.js` - Main game entry point
        \\- `assets/` - Game assets (models, textures, etc.)
        \\- `scripts/` - Additional game scripts
        \\- `project.json` - Project configuration
        \\
    ;

    const readme_file = try project_dir.createFile("README.md", .{});
    defer readme_file.close();

    var readme_buf: [2048]u8 = undefined;
    const formatted_readme = try std.fmt.bufPrint(&readme_buf, readme_content, .{path});
    try readme_file.writeAll(formatted_readme);

    std.debug.print("\n✓ Project created successfully!\n", .{});
    std.debug.print("\nNext steps:\n", .{});
    std.debug.print("  cd {s}\n", .{path});
    std.debug.print("  zdl run\n", .{});
    std.debug.print("\n", .{});
}
