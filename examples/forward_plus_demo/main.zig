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
const AssetManager = engine.AssetManager;
const Material = engine.Material;
const primitives = engine.primitives;
const Mesh = engine.Mesh;

// Scene data
var sphere_mesh: Mesh = undefined;
var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;
var time: f32 = 0;
var forward_plus_enabled: bool = true;
var show_debug_info: bool = true;

// Light entities for animation
// Forward+ with GPU compute enables hundreds of dynamic lights!
const NUM_POINT_LIGHTS: usize = 128;
const NUM_SPOT_LIGHTS: usize = 32;
var point_light_entities: [NUM_POINT_LIGHTS]Entity = undefined;
var spot_light_entities: [NUM_SPOT_LIGHTS]Entity = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Forward+ Clustered Rendering Demo",
        .window_width = 1920,
        .window_height = 1080,
        .target_fps = 144,
        .clear_color = .{ .r = 0.02, .g = 0.02, .b = 0.05, .a = 1.0 },
    });
    defer eng.deinit();

    // Initialize PBR + IBL (skybox/environment) like helmet_showcase.
    try eng.initPBR();
    try eng.initIBL();

    const hdr_rel_path = "assets/textures/kloppenheim_06_1k.hdr";
    const hdr_path = try std.fs.cwd().realpathAlloc(allocator, hdr_rel_path);
    defer allocator.free(hdr_path);
    if (eng.loadHDREnvironment(hdr_path)) |_| {} else |_| {}

    eng.light_uniforms.setIBLSpecularIntensity(0.35);
    eng.light_uniforms.setIBLParams(1.0, eng.light_uniforms.ibl_params[1]);

    // Initialize Forward+ with GPU compute culling
    // This uses a compute shader for light culling, enabling hundreds of dynamic lights
    try eng.initForwardPlusGPU();
    forward_plus_enabled = true;
    std.debug.print("Forward+ with GPU compute initialized\n", .{});

    // Set up ambient lighting
    eng.light_uniforms.setAmbient(Vec3.init(0.05, 0.05, 0.08), 1.0);

    // Create scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create asset manager
    var asset_manager = AssetManager.init(allocator, &eng.device);
    defer asset_manager.deinit();

    // Create meshes
    sphere_mesh = try primitives.createSphere(allocator, 16);
    defer sphere_mesh.deinit(&eng.device);
    try sphere_mesh.upload(&eng.device);

    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    // Create camera entity
    const camera_entity = scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(0, 15, 40));
    camera_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());
    scene.setActiveCamera(camera_entity);

    // Add FPV controller
    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 15.0,
        .capture_on_click = true,
    });
    const look_dir = Vec3.init(0, 0, 0).sub(Vec3.init(0, 15, 40)).normalize();
    fpv_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fpv_controller);

    // Create a large grid of objects to demonstrate many-light rendering
    const grid_size: i32 = 8;
    const spacing: f32 = 5.0;
    const grid_radius_u: usize = @intCast(grid_size);

    for (0..@intCast(grid_size * 2 + 1)) |i| {
        for (0..@intCast(grid_size * 2 + 1)) |j| {
            if (i == grid_radius_u and j == grid_radius_u) {
                continue;
            }
            const x = (@as(f32, @floatFromInt(i)) - @as(f32, @floatFromInt(grid_size))) * spacing;
            const z = (@as(f32, @floatFromInt(j)) - @as(f32, @floatFromInt(grid_size))) * spacing;

            // Alternate between spheres and cubes
            const is_sphere = (i + j) % 2 == 0;

            const obj_entity = scene.createEntity();
            var transform = TransformComponent.withPosition(Vec3.init(x, 0.5, z));

            // Create varied PBR materials
            var material = Material.init();
            const metallic = @as(f32, @floatFromInt(i % 5)) / 4.0;
            const roughness = @as(f32, @floatFromInt(j % 5)) / 4.0;
            material.metallic = metallic;
            material.roughness = 0.1 + roughness * 0.8;

            // Vary colors based on position
            const r = 0.5 + 0.5 * @sin(@as(f32, @floatFromInt(i)) * 0.5);
            const g = 0.5 + 0.5 * @cos(@as(f32, @floatFromInt(j)) * 0.5);
            const b = 0.5 + 0.5 * @sin(@as(f32, @floatFromInt(i + j)) * 0.3);
            material.base_color = engine.Vec4.init(r, g, b, 1.0);

            scene.addComponent(obj_entity, transform);
            if (is_sphere) {
                scene.addComponent(obj_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, material));
            } else {
                transform.setScale(Vec3.init(0.8, 0.8, 0.8));
                scene.addComponent(obj_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&cube_mesh, material));
            }
        }
    }

    // Create floor plane
    const floor_entity = scene.createEntity();
    var floor_transform = TransformComponent.withPosition(Vec3.init(0, -0.5, 0));
    floor_transform.setScale(Vec3.init(100, 1, 100));
    scene.addComponent(floor_entity, floor_transform);
    const floor_mat = Material.dielectric(0.2, 0.2, 0.25, 0.9);
    scene.addComponent(floor_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&plane_mesh, floor_mat));

    // Add Damaged Helmet glTF model
    const helmet_roots = try asset_manager.importGLTFScene(
        "assets/models/DamagedHelmet.glb",
        &scene,
        null,
    );
    defer allocator.free(helmet_roots);
    for (helmet_roots) |root| {
        if (scene.getComponent(TransformComponent, root)) |transform| {
            transform.setPosition(Vec3.init(0, 0.15, 0));
            transform.setRotationEuler(0.0, std.math.pi * 0.25, 0.0);
            transform.setScale(Vec3.init(0.3, 0.3, 0.3));
        }
    }

    // Create directional light (sun) - dimmed since we have many point lights
    const sun_entity = scene.createEntity();
    var sun_transform = TransformComponent.init();
    sun_transform.setRotationEuler(-std.math.pi / 3.0, std.math.pi / 4.0, 0);
    scene.addComponent(sun_entity, sun_transform);
    scene.addComponent(sun_entity, LightComponent.directional(Vec3.init(1.0, 0.95, 0.9), 0.5));

    // Create many point lights in a circular pattern
    std.debug.print("Creating {} point lights...\n", .{NUM_POINT_LIGHTS});
    for (0..NUM_POINT_LIGHTS) |i| {
        const angle = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(NUM_POINT_LIGHTS)));
        const radius = 15.0 + @sin(angle * 3.0) * 8.0;
        const height = 3.0 + @cos(angle * 5.0) * 2.0;

        const light_entity = scene.createEntity();
        point_light_entities[i] = light_entity;

        scene.addComponent(light_entity, TransformComponent.withPosition(Vec3.init(
            @cos(angle) * radius,
            height,
            @sin(angle) * radius,
        )));

        // Create colorful lights with smooth color transitions
        const hue = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(NUM_POINT_LIGHTS));
        const color = hueToRgb(hue);
        scene.addComponent(light_entity, LightComponent.point(color, 5.0, 15.0));
    }

    // Create spot lights pointing at the center
    std.debug.print("Creating {} spot lights...\n", .{NUM_SPOT_LIGHTS});
    for (0..NUM_SPOT_LIGHTS) |i| {
        const angle = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(NUM_SPOT_LIGHTS)));
        const radius = 25.0;

        const light_entity = scene.createEntity();
        spot_light_entities[i] = light_entity;

        var spot_transform = TransformComponent.withPosition(Vec3.init(
            @cos(angle) * radius,
            12.0,
            @sin(angle) * radius,
        ));
        // Point toward center
        spot_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
        scene.addComponent(light_entity, spot_transform);

        const hue = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(NUM_SPOT_LIGHTS)) + 0.5;
        const color = hueToRgb(@mod(hue, 1.0));
        scene.addComponent(light_entity, LightComponent.spot(color, 10.0, 35.0, 0.9, 0.8));
    }

    std.debug.print("\n=== Forward+ Clustered Rendering Demo ===\n", .{});
    std.debug.print("Total dynamic lights: {} point + {} spot = {}\n", .{ NUM_POINT_LIGHTS, NUM_SPOT_LIGHTS, NUM_POINT_LIGHTS + NUM_SPOT_LIGHTS });
    std.debug.print("\nThis demo showcases efficient rendering of many dynamic lights\n", .{});
    std.debug.print("using Forward+ (clustered forward) rendering.\n", .{});
    std.debug.print("\nControls:\n", .{});
    std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
    std.debug.print("  Q/E - Move camera up/down\n", .{});
    std.debug.print("  Mouse - Look around (click to capture)\n", .{});
    std.debug.print("  F - Toggle Forward+ on/off (compare performance)\n", .{});
    std.debug.print("  F3 - Toggle FPS counter\n", .{});
    std.debug.print("  ESC - Quit\n", .{});
    std.debug.print("\nForward+ Status: ENABLED\n", .{});

    // Run game loop with scene
    try eng.runScene(&scene, update);
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    time += delta_time;

    // Get camera transform
    const camera_entity = scene.getActiveCamera();
    if (scene.getComponent(FpvCameraController, camera_entity)) |controller| {
        if (scene.getComponent(TransformComponent, camera_entity)) |cam_transform| {
            if (controller.update(cam_transform, input, delta_time)) {
                eng.setMouseCapture(true);
            }
        }
    }

    // Toggle Forward+ info
    if (input.isKeyJustPressed(Scancode.f)) {
        forward_plus_enabled = !forward_plus_enabled;
        eng.setForwardPlusEnabled(forward_plus_enabled);
        if (forward_plus_enabled) {
            std.debug.print("Forward+ GPU compute: ENABLED\n", .{});
        } else {
            std.debug.print("Forward+ GPU compute: DISABLED (using standard PBR)\n", .{});
        }
    }

    // Animate point lights - circular motion
    for (0..NUM_POINT_LIGHTS) |i| {
        if (scene.getComponent(TransformComponent, point_light_entities[i])) |light_transform| {
            const base_angle = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(NUM_POINT_LIGHTS)));
            const angle = base_angle + time * 0.3;
            const radius = 15.0 + @sin(angle * 3.0 + time) * 8.0;
            const height = 3.0 + @cos(angle * 5.0 + time * 0.5) * 2.0 + @sin(time + @as(f32, @floatFromInt(i)) * 0.1) * 1.5;

            light_transform.setPosition(Vec3.init(
                @cos(angle) * radius,
                height,
                @sin(angle) * radius,
            ));
        }
    }

    // Animate spot lights - slow rotation
    for (0..NUM_SPOT_LIGHTS) |i| {
        if (scene.getComponent(TransformComponent, spot_light_entities[i])) |light_transform| {
            const base_angle = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(NUM_SPOT_LIGHTS)));
            const angle = base_angle + time * 0.1;
            const radius = 25.0;
            const height = 12.0 + @sin(time * 0.5 + @as(f32, @floatFromInt(i))) * 3.0;

            light_transform.setPosition(Vec3.init(
                @cos(angle) * radius,
                height,
                @sin(angle) * radius,
            ));
            light_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
        }
    }
}

/// Convert HSV hue (0-1) to RGB color
fn hueToRgb(hue: f32) Vec3 {
    const h = hue * 6.0;
    const i = @floor(h);
    const f = h - i;
    const q = 1.0 - f;

    const sector = @as(u32, @intFromFloat(@mod(i, 6.0)));

    return switch (sector) {
        0 => Vec3.init(1.0, f, 0.0),
        1 => Vec3.init(q, 1.0, 0.0),
        2 => Vec3.init(0.0, 1.0, f),
        3 => Vec3.init(0.0, q, 1.0),
        4 => Vec3.init(f, 0.0, 1.0),
        5 => Vec3.init(1.0, 0.0, q),
        else => Vec3.init(1.0, 1.0, 1.0),
    };
}
