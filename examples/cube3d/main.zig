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
const primitives = engine.primitives;
const Mesh = engine.Mesh;

var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;
var cube_entity: Entity = Entity.invalid;
var rotation: f32 = 0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - 3D Cube Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 60,
    });
    defer eng.deinit();

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

    // Create camera entity
    const camera_entity = scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(0, 2, 5));
    camera_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());
    scene.setActiveCamera(camera_entity);

    // Create cube entity
    cube_entity = scene.createEntity();
    var cube_transform = TransformComponent.withPosition(Vec3.init(0, 0, 0));
    cube_transform.setScale(Vec3.init(2, 2, 2));
    scene.addComponent(cube_entity, cube_transform);
    scene.addComponent(cube_entity, MeshRendererComponent.fromMeshPtr(&cube_mesh));

    // Create plane entity
    const plane_entity = scene.createEntity();
    var plane_transform = TransformComponent.withPosition(Vec3.init(0, -2, 0));
    plane_transform.setScale(Vec3.init(10, 1, 10));
    scene.addComponent(plane_entity, plane_transform);
    scene.addComponent(plane_entity, MeshRendererComponent.fromMeshPtr(&plane_mesh));

    std.debug.print("3D Cube Demo initialized!\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
    std.debug.print("  Q/E - Move camera up/down\n", .{});
    std.debug.print("  F3 - Toggle FPS counter\n", .{});
    std.debug.print("  ESC - Quit\n", .{});

    // Run game loop with scene
    try eng.runScene(&scene, update);
}

fn update(_: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    const speed: f32 = 5.0;
    const move_dist = speed * delta_time;

    // Get camera transform
    const camera_entity = scene.getActiveCamera();
    if (scene.getComponent(TransformComponent, camera_entity)) |camera_transform| {
        // Camera movement
        if (input.isKeyDown(.w) or input.isKeyDown(.up)) {
            const fwd = camera_transform.forward();
            camera_transform.translate(fwd.mul(move_dist));
        }
        if (input.isKeyDown(.s) or input.isKeyDown(.down)) {
            const fwd = camera_transform.forward();
            camera_transform.translate(fwd.mul(-move_dist));
        }
        if (input.isKeyDown(.a) or input.isKeyDown(.left)) {
            const r = camera_transform.right();
            camera_transform.translate(r.mul(-move_dist));
        }
        if (input.isKeyDown(.d) or input.isKeyDown(.right)) {
            const r = camera_transform.right();
            camera_transform.translate(r.mul(move_dist));
        }
        if (input.isKeyDown(.q)) {
            camera_transform.translate(Vec3.init(0, -move_dist, 0));
        }
        if (input.isKeyDown(.e)) {
            camera_transform.translate(Vec3.init(0, move_dist, 0));
        }
    }

    // Rotate cube
    rotation += delta_time;
    if (scene.getComponent(TransformComponent, cube_entity)) |cube_transform| {
        cube_transform.setRotationEuler(rotation * 0.7, rotation, rotation * 0.5);
    }
}
