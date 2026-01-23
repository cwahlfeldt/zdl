const std = @import("std");
const engine = @import("engine");
const Engine = engine.Engine;
const Scene = engine.Scene;
const Entity = engine.Entity;
const Input = engine.Input;
const Scancode = engine.Scancode;
const Vec3 = engine.Vec3;
const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;
const LightComponent = engine.LightComponent;
const FpvCameraController = engine.FpvCameraController;
const Material = engine.Material;
const primitives = engine.primitives;
const Mesh = engine.Mesh;

// Scene data
var cube_mesh: Mesh = undefined;
var sphere_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;
var sun_entity: Entity = Entity.invalid;
var sun_rotation: f32 = 0;
var auto_rotate: bool = true;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Cascaded Shadow Maps Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 100,
        .clear_color = .{ .r = 0.52, .g = 0.80, .b = 0.92, .a = 1.0 }, // Sky blue
    });
    defer eng.deinit();

    // Initialize PBR rendering (shadows are automatically initialized)
    try eng.initForwardPlus();
    std.debug.print("Forward+ rendering initialized: {}\n", .{eng.hasForwardPlus()});
    std.debug.print("Shadow system initialized: {}\n", .{eng.hasShadows()});

    // Create scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create meshes
    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    sphere_mesh = try primitives.createSphere(allocator, 24);
    defer sphere_mesh.deinit(&eng.device);
    try sphere_mesh.upload(&eng.device);

    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    // Create camera entity
    const camera_entity = scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(8, 6, 15));
    camera_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());

    // Add FPV controller
    const fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 8.0,
        .capture_on_click = true,
    });
    scene.addComponent(camera_entity, fpv_controller);
    scene.setActiveCamera(camera_entity);

    // Create ground plane (large)
    const ground = scene.createEntity();
    var ground_transform = TransformComponent.withPosition(Vec3.init(0, 0, 0));
    ground_transform.setScale(Vec3.init(50, 1, 50));
    scene.addComponent(ground, ground_transform);
    const ground_mat = Material.dielectric(0.4, 0.45, 0.4, 0.9); // Green grass-like
    scene.addComponent(ground, MeshRendererComponent.fromMeshPtrWithMaterial(&plane_mesh, ground_mat));

    // Create a grid of cubes and spheres at various heights
    const grid_size: usize = 5;
    const spacing: f32 = 4.0;
    const offset: f32 = @as(f32, @floatFromInt(grid_size - 1)) * spacing * 0.5;

    for (0..grid_size) |row| {
        for (0..grid_size) |col| {
            const x = @as(f32, @floatFromInt(col)) * spacing - offset;
            const z = @as(f32, @floatFromInt(row)) * spacing - offset;

            // Alternate between cubes and spheres
            const is_cube = (row + col) % 2 == 0;
            const height = 1.0 + @as(f32, @floatFromInt((row * grid_size + col) % 3)) * 0.5;

            const entity = scene.createEntity();
            const transform = TransformComponent.withPosition(Vec3.init(x, height, z));
            scene.addComponent(entity, transform);

            // Create colorful materials
            const hue = @as(f32, @floatFromInt(row * grid_size + col)) / @as(f32, @floatFromInt(grid_size * grid_size));
            var material = Material.init();
            material.base_color = engine.Vec4.init(
                0.5 + 0.5 * @sin(hue * 6.28),
                0.5 + 0.5 * @sin((hue + 0.33) * 6.28),
                0.5 + 0.5 * @sin((hue + 0.66) * 6.28),
                1.0,
            );
            material.metallic = if (is_cube) 0.2 else 0.7;
            material.roughness = 0.5;

            if (is_cube) {
                scene.addComponent(entity, MeshRendererComponent.fromMeshPtrWithMaterial(&cube_mesh, material));
            } else {
                scene.addComponent(entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, material));
            }
        }
    }

    // Create tall structures to showcase shadow cascades at different distances
    {
        const tower1 = scene.createEntity();
        var tower_transform = TransformComponent.withPosition(Vec3.init(15, 4, 0));
        tower_transform.setScale(Vec3.init(2, 8, 2));
        scene.addComponent(tower1, tower_transform);
        const tower_mat = Material.dielectric(0.7, 0.7, 0.8, 0.3);
        scene.addComponent(tower1, MeshRendererComponent.fromMeshPtrWithMaterial(&cube_mesh, tower_mat));
    }

    {
        const tower2 = scene.createEntity();
        var tower_transform = TransformComponent.withPosition(Vec3.init(-15, 3, -15));
        tower_transform.setScale(Vec3.init(1.5, 6, 1.5));
        scene.addComponent(tower2, tower_transform);
        const tower_mat = Material.dielectric(0.8, 0.6, 0.5, 0.4);
        scene.addComponent(tower2, MeshRendererComponent.fromMeshPtrWithMaterial(&cube_mesh, tower_mat));
    }

    // Create directional light (sun)
    sun_entity = scene.createEntity();
    var sun_transform = TransformComponent.init();
    // Start at 45 degrees elevation
    sun_rotation = 0.785; // 45 degrees in radians
    const light_dir = Vec3.init(
        @cos(sun_rotation),
        -@sin(sun_rotation),
        0.3,
    ).normalize();
    sun_transform.lookAt(sun_transform.getPosition().add(light_dir), Vec3.init(0, 1, 0));
    scene.addComponent(sun_entity, sun_transform);
    scene.addComponent(sun_entity, LightComponent.directional(
        Vec3.init(1.0, 0.95, 0.85), // Warm sunlight
        3.0, // Intensity
    ));

    // Add some point lights for variety
    {
        const point_light1 = scene.createEntity();
        scene.addComponent(point_light1, TransformComponent.withPosition(Vec3.init(10, 3, 10)));
        scene.addComponent(point_light1, LightComponent.point(
            Vec3.init(1.0, 0.3, 0.3), // Red
            15.0, // Intensity
            20.0, // Range
        ));
    }

    {
        const point_light2 = scene.createEntity();
        scene.addComponent(point_light2, TransformComponent.withPosition(Vec3.init(-10, 3, -10)));
        scene.addComponent(point_light2, LightComponent.point(
            Vec3.init(0.3, 0.3, 1.0), // Blue
            15.0, // Intensity
            20.0, // Range
        ));
    }

    std.debug.print("\n=== Cascaded Shadow Maps Demo ===\n", .{});
    std.debug.print("This demo showcases real-time cascaded shadow mapping with 3 cascades.\n\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  WASD - Move camera\n", .{});
    std.debug.print("  Mouse - Look around (click to capture)\n", .{});
    std.debug.print("  Q/E - Move camera up/down\n", .{});
    std.debug.print("  Space - Toggle sun auto-rotation\n", .{});
    std.debug.print("  Left/Right Arrow - Manually rotate sun\n", .{});
    std.debug.print("  F3 - Toggle FPS counter\n", .{});
    std.debug.print("  ESC - Quit\n", .{});
    std.debug.print("\nShadow Info:\n", .{});
    std.debug.print("  3 cascades: 2048x2048, 1024x1024, 1024x1024\n", .{});
    std.debug.print("  PCF filtering for soft shadows\n", .{});
    std.debug.print("  Shadow distance: 100 units (default)\n\n", .{});

    // Run game loop
    try eng.runScene(&scene, update);
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    // FPS Camera controls
    const camera_entity = scene.getActiveCamera();
    if (scene.getComponent(FpvCameraController, camera_entity)) |controller| {
        if (scene.getComponent(TransformComponent, camera_entity)) |cam_transform| {
            if (controller.update(cam_transform, input, delta_time)) {
                eng.setMouseCapture(true);
            }
        }
    }

    // Toggle auto-rotation
    if (input.isKeyJustPressed(Scancode.space)) {
        auto_rotate = !auto_rotate;
        std.debug.print("Sun auto-rotation: {s}\n", .{if (auto_rotate) "ON" else "OFF"});
    }

    // Manual sun rotation
    if (input.isKeyDown(Scancode.left)) {
        sun_rotation -= delta_time * 0.5;
    }
    if (input.isKeyDown(Scancode.right)) {
        sun_rotation += delta_time * 0.5;
    }

    // Auto-rotate sun
    if (auto_rotate) {
        sun_rotation += delta_time * 0.2;
    }

    // Clamp sun rotation to reasonable range (0 to PI, never below horizon)
    sun_rotation = @mod(sun_rotation, std.math.pi);
    if (sun_rotation < 0.1) sun_rotation = 0.1; // Keep sun above horizon

    // Update sun direction
    if (scene.getComponent(TransformComponent, sun_entity)) |sun_transform| {
        const light_dir = Vec3.init(
            @cos(sun_rotation),
            -@sin(sun_rotation),
            0.3,
        ).normalize();
        sun_transform.lookAt(sun_transform.getPosition().add(light_dir), Vec3.init(0, 1, 0));
    }

}
