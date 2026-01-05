const std = @import("std");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Entity = engine.Entity;
const Vec3 = engine.Vec3;
const Input = engine.Input;
const Mesh = engine.Mesh;
const primitives = engine.primitives;

const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;
const FpvCameraController = engine.FpvCameraController;

// Game state stored externally (meshes need to outlive the scene)
var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;

// Entity references for animation
var cube_entity: Entity = Entity.invalid;
var child_entity: Entity = Entity.invalid;
var camera_entity: Entity = Entity.invalid;
var rotation: f32 = 0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize engine
    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Scene Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 100,
    });
    defer eng.deinit();

    // Create meshes
    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    // Create scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create camera entity with FPS controller
    camera_entity = scene.createEntity();
    scene.addComponent(camera_entity, CameraComponent.init());

    const cam_pos = Vec3.init(0, 3, 8);
    const look_target = Vec3.init(0, 0, 0);
    const look_dir = look_target.sub(cam_pos).normalize();

    var cam_transform = TransformComponent.withPosition(cam_pos);
    cam_transform.lookAt(look_target, Vec3.init(0, -1, 0));
    scene.addComponent(camera_entity, cam_transform);

    // Create FPS controller and sync its yaw/pitch with the lookAt direction
    var fps_controller = FpvCameraController.init();
    fps_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fps_controller);

    scene.setActiveCamera(camera_entity);

    std.debug.print("Scene Demo - FPS Controls\n", .{});
    std.debug.print("  Click window to capture mouse\n", .{});
    std.debug.print("  WASD - Move\n", .{});
    std.debug.print("  Mouse - Look around\n", .{});
    std.debug.print("  Space/Shift - Move up/down\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n", .{});

    // Create floor plane
    const floor = scene.createEntity();
    var floor_transform = TransformComponent.withPosition(Vec3.init(0, -10, 0));
    floor_transform.local.scale = Vec3.init(10, 1, 10);
    scene.addComponent(floor, floor_transform);
    scene.addComponent(floor, MeshRendererComponent.init(&plane_mesh));

    // Create parent cube
    cube_entity = scene.createEntity();
    var cube_transform = TransformComponent.init();
    cube_transform.local.scale = Vec3.init(2, 2, 2); // Make it bigger
    scene.addComponent(cube_entity, cube_transform);
    scene.addComponent(cube_entity, MeshRendererComponent.init(&cube_mesh));

    // Create child cube (orbits around parent)
    child_entity = scene.createEntity();
    scene.addComponent(child_entity, TransformComponent.withPosition(Vec3.init(2.5, 4, 0)));
    scene.addComponent(child_entity, MeshRendererComponent.init(&cube_mesh));

    // Set parent-child relationship
    scene.setParent(child_entity, cube_entity);

    // Scale down child cube
    if (scene.getComponent(TransformComponent, child_entity)) |child_transform| {
        child_transform.local.scale = Vec3.init(0.5, 0.5, 0.5);
    }

    // Run the scene with our update function
    try eng.runScene(&scene, update);
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    // Rotate parent cube (child rotates with it due to hierarchy)
    rotation += delta_time;
    if (scene.getComponent(TransformComponent, cube_entity)) |transform| {
        transform.setRotationEuler(0, rotation, 0);
    }

    // Rotate child cube on its own axis
    if (scene.getComponent(TransformComponent, child_entity)) |child_transform| {
        child_transform.rotateEuler(0, delta_time * 3, 0);
    }

    // FPS Camera controls via controller component
    if (scene.getComponent(FpvCameraController, camera_entity)) |controller| {
        if (scene.getComponent(TransformComponent, camera_entity)) |cam_transform| {
            if (controller.update(cam_transform, input, delta_time)) {
                eng.setMouseCapture(true);
            }
        }
    }
}
