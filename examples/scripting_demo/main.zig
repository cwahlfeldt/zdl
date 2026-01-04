const std = @import("std");
const engine = @import("engine");
const Engine = engine.Engine;
const Scene = engine.Scene;
const Entity = engine.Entity;
const Input = engine.Input;
const Vec3 = engine.Vec3;
const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;
const ScriptComponent = engine.ScriptComponent;
const primitives = engine.primitives;
const Mesh = engine.Mesh;

var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;
var sphere_mesh: Mesh = undefined;

pub fn main() !void {
    std.debug.print("Starting scripting demo...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Initializing engine...\n", .{});
    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - JavaScript Scripting Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 60,
    });
    defer eng.deinit();
    std.debug.print("Engine initialized\n", .{});

    // Initialize scripting
    std.debug.print("Initializing scripting...\n", .{});
    try eng.initScripting();
    std.debug.print("Scripting initialized\n", .{});

    // Create scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create meshes
    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    sphere_mesh = try primitives.createSphere(allocator, 16);
    defer sphere_mesh.deinit(&eng.device);
    try sphere_mesh.upload(&eng.device);

    // Create camera entity with FPS controller script
    const camera_entity = try scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(0, 2, 8));
    camera_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    try scene.addComponent(camera_entity, camera_transform);
    try scene.addComponent(camera_entity, CameraComponent.init());
    try scene.addComponent(camera_entity, ScriptComponent.init("examples/scripting_demo/scripts/player.js"));
    scene.setActiveCamera(camera_entity);

    // Create rotating cube entity
    const cube_entity = try scene.createEntity();
    var cube_transform = TransformComponent.withPosition(Vec3.init(0, 1, 0));
    cube_transform.setScale(Vec3.init(1.5, 1.5, 1.5));
    try scene.addComponent(cube_entity, cube_transform);
    try scene.addComponent(cube_entity, MeshRendererComponent.init(&cube_mesh));
    try scene.addComponent(cube_entity, ScriptComponent.init("examples/scripting_demo/scripts/rotator.js"));

    // Create orbiting sphere entity
    const sphere_entity = try scene.createEntity();
    const sphere_transform = TransformComponent.withPosition(Vec3.init(3, 1, 0));
    try scene.addComponent(sphere_entity, sphere_transform);
    try scene.addComponent(sphere_entity, MeshRendererComponent.init(&sphere_mesh));
    try scene.addComponent(sphere_entity, ScriptComponent.init("examples/scripting_demo/scripts/orbiter.js"));

    // Create floor plane
    const plane_entity = try scene.createEntity();
    var plane_transform = TransformComponent.withPosition(Vec3.init(0, -1, 0));
    plane_transform.setScale(Vec3.init(20, 1, 20));
    try scene.addComponent(plane_entity, plane_transform);
    try scene.addComponent(plane_entity, MeshRendererComponent.init(&plane_mesh));

    std.debug.print("\n=== JavaScript Scripting Demo ===\n", .{});
    std.debug.print("This demo showcases JavaScript scripting with hot-reload!\n\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  WASD - Move camera\n", .{});
    std.debug.print("  Mouse - Look around (click to capture)\n", .{});
    std.debug.print("  Space - Jump\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n", .{});
    std.debug.print("\nTry editing the scripts in examples/scripting_demo/scripts/\n", .{});
    std.debug.print("They will hot-reload automatically!\n\n", .{});

    // Run game loop with scene
    try eng.runScene(&scene, update);
}

fn update(_: *Engine, _: *Scene, _: *Input, _: f32) !void {
    // All game logic is handled by JavaScript scripts!
}
