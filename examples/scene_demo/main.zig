const std = @import("std");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Entity = engine.Entity;
const Vec3 = engine.Vec3;
const Quat = engine.Quat;
const Input = engine.Input;
const Mesh = engine.Mesh;
const primitives = engine.primitives;

const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;

// Game state stored externally (meshes need to outlive the scene)
var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;

// Entity references for animation
var cube_entity: Entity = Entity.invalid;
var child_entity: Entity = Entity.invalid;
var rotation: f32 = 0;

// Camera angles for FPS-style look (stored separately from transform)
var camera_yaw: f32 = 0;
var camera_pitch: f32 = 0;

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

    // Create camera entity
    const camera = try scene.createEntity();
    try scene.addComponent(camera, CameraComponent.init());
    // Position camera at positive Z, looking toward origin
    const cam_transform = TransformComponent.withPosition(Vec3.init(0, 3, 8));
    try scene.addComponent(camera, cam_transform);
    scene.setActiveCamera(camera);

    // Initialize camera angles (looking toward negative Z, slightly down)
    // At yaw=0, camera faces -Z direction (OpenGL/standard convention)
    camera_yaw = 0;
    camera_pitch = -0.3; // Look slightly down

    std.debug.print("Scene Demo - FPS Controls\n", .{});
    std.debug.print("  Click window to capture mouse\n", .{});
    std.debug.print("  WASD - Move\n", .{});
    std.debug.print("  Mouse - Look around\n", .{});
    std.debug.print("  Space/Shift - Move up/down\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n", .{});

    // Create floor plane
    const floor = try scene.createEntity();
    var floor_transform = TransformComponent.withPosition(Vec3.init(0, -1, 0));
    floor_transform.local.scale = Vec3.init(10, 1, 10);
    try scene.addComponent(floor, floor_transform);
    try scene.addComponent(floor, MeshRendererComponent.init(&plane_mesh));

    // Create parent cube
    cube_entity = try scene.createEntity();
    try scene.addComponent(cube_entity, TransformComponent.init());
    try scene.addComponent(cube_entity, MeshRendererComponent.init(&cube_mesh));

    // Create child cube (orbits around parent)
    child_entity = try scene.createEntity();
    try scene.addComponent(child_entity, TransformComponent.withPosition(Vec3.init(2.5, 0, 0)));
    try scene.addComponent(child_entity, MeshRendererComponent.init(&cube_mesh));

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

    // Click to capture mouse
    if (input.isMouseButtonDown(.left) and !input.mouse_captured) {
        eng.setMouseCapture(true);
    }

    // FPS Camera controls
    const camera_entity = scene.getActiveCamera();
    if (scene.getComponent(TransformComponent, camera_entity)) |cam_transform| {
        // Mouse look (only when captured)
        if (input.mouse_captured) {
            const mouse_delta = input.getMouseDelta();
            const sensitivity: f32 = 0.003;

            camera_yaw -= mouse_delta.x * sensitivity;
            camera_pitch -= mouse_delta.y * sensitivity;

            // Clamp pitch to avoid gimbal lock
            const max_pitch = std.math.pi / 2.0 - 0.1;
            camera_pitch = @max(-max_pitch, @min(max_pitch, camera_pitch));
        }

        // Update camera rotation from yaw/pitch
        // Yaw rotates around Y axis, pitch rotates around X axis
        const yaw_quat = Quat.fromAxisAngle(Vec3.init(0, 1, 0), camera_yaw);
        const pitch_quat = Quat.fromAxisAngle(Vec3.init(1, 0, 0), camera_pitch);
        cam_transform.local.rotation = yaw_quat.mul(pitch_quat);

        // Calculate forward and right vectors from yaw (for movement)
        // At yaw=0, camera faces -Z. Positive yaw rotates left (counter-clockwise from above)
        const forward = Vec3.init(
            -@sin(camera_yaw),
            0,
            -@cos(camera_yaw),
        );
        const right_dir = Vec3.init(
            @cos(camera_yaw),
            0,
            -@sin(camera_yaw),
        );

        // WASD movement relative to camera direction
        const speed: f32 = 5.0;
        const wasd = input.getWASD();

        if (wasd.x != 0 or wasd.y != 0) {
            // W/S moves along forward, A/D moves along right
            const move_forward = forward.mul(-wasd.y * speed * delta_time);
            const move_right = right_dir.mul(wasd.x * speed * delta_time);
            cam_transform.translate(move_forward.add(move_right));
        }

        // Up/down movement with Space/Shift
        if (input.isKeyDown(.space)) {
            cam_transform.translate(Vec3.init(0, speed * delta_time, 0));
        }
        if (input.isKeyDown(.left_shift) or input.isKeyDown(.right_shift)) {
            cam_transform.translate(Vec3.init(0, -speed * delta_time, 0));
        }

        cam_transform.markDirty();
    }
}
