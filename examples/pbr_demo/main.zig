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
var plane_mesh: Mesh = undefined;
var rotation: f32 = 0;
var point_light_entity: Entity = Entity.invalid;
var ibl_enabled: bool = true;
var env_intensity: f32 = 1.0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - PBR Rendering Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 100,
        .clear_color = .{ .r = 0.02, .g = 0.02, .b = 0.05, .a = 1.0 },
    });
    defer eng.deinit();

    // Initialize PBR rendering
    try eng.initPBR();
    std.debug.print("PBR rendering initialized: {}\n", .{eng.hasPBR()});

    // Initialize IBL (Image-Based Lighting)
    std.debug.print("Generating BRDF LUT...\n", .{});
    try eng.initIBL();
    std.debug.print("IBL initialized: {}\n", .{eng.hasIBL()});

    // Load HDR environment map
    std.debug.print("Loading HDR environment map...\n", .{});
    const hdr_path = "/Users/chriswahlfeldt/code/zdl/assets/textures/kloppenheim_06_1k.hdr";
    if (eng.loadHDREnvironment(hdr_path)) |_| {
        std.debug.print("HDR environment loaded successfully!\n", .{});
    } else |err| {
        std.debug.print("Warning: Failed to load HDR environment: {}\n", .{err});
        std.debug.print("Falling back to default neutral environment\n", .{});
    }

    // Set up ambient lighting for fallback (when IBL is disabled)
    eng.light_uniforms.setAmbient(Vec3.init(0.15, 0.15, 0.2), 1.0);

    // Create scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create asset manager
    var asset_manager = AssetManager.init(allocator, &eng.device);
    defer asset_manager.deinit();

    // Create meshes
    sphere_mesh = try primitives.createSphere(allocator, 24);
    defer sphere_mesh.deinit(&eng.device);
    try sphere_mesh.upload(&eng.device);

    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    // Create camera entity
    const camera_entity = scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(0, 4, 12));
    camera_transform.lookAt(Vec3.init(0, 0, 0), Vec3.init(0, 1, 0));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());
    scene.setActiveCamera(camera_entity);

    // Add FPV controller and initialize looking at origin
    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 5.0,
        .capture_on_click = true,
    });
    // Set initial look direction toward origin
    const look_dir = Vec3.init(0, 0, 0).sub(Vec3.init(0, 2, 5)).normalize();
    fpv_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fpv_controller);
    scene.setActiveCamera(camera_entity);

    // Create a grid of spheres with varying materials
    // Rows: varying roughness (0.0 to 1.0)
    // Columns: varying metallic (0.0 to 1.0)
    const grid_size: usize = 5;
    const spacing: f32 = 2.5;
    const offset: f32 = @as(f32, @floatFromInt(grid_size - 1)) * spacing * 0.5;

    for (0..grid_size) |row| {
        for (0..grid_size) |col| {
            const metallic = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(grid_size - 1));
            const roughness = @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(grid_size - 1));

            const x = @as(f32, @floatFromInt(col)) * spacing - offset;
            const y = @as(f32, @floatFromInt(row)) * spacing - offset + 2.0;

            const sphere_entity = scene.createEntity();
            const transform = TransformComponent.withPosition(Vec3.init(x, y, 0));
            scene.addComponent(sphere_entity, transform);

            // Create PBR material with varying properties
            var material = Material.init();
            material.base_color = engine.Vec4.init(0.9, 0.1, 0.1, 1.0); // Red base color
            material.metallic = metallic;
            material.roughness = roughness;

            scene.addComponent(sphere_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, material));
        }
    }

    // Add some colored spheres with different base colors
    {
        // Gold (metallic)
        const gold_entity = scene.createEntity();
        scene.addComponent(gold_entity, TransformComponent.withPosition(Vec3.init(-6, 2, 0)));
        const gold_mat = Material.metal(1.0, 0.766, 0.336, 0.3);
        scene.addComponent(gold_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, gold_mat));
    }

    {
        // Silver (metallic)
        const silver_entity = scene.createEntity();
        scene.addComponent(silver_entity, TransformComponent.withPosition(Vec3.init(-6, 5, 0)));
        const silver_mat = Material.metal(0.972, 0.960, 0.915, 0.2);
        scene.addComponent(silver_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, silver_mat));
    }

    {
        // Copper (metallic)
        const copper_entity = scene.createEntity();
        scene.addComponent(copper_entity, TransformComponent.withPosition(Vec3.init(-6, 8, 0)));
        const copper_mat = Material.metal(0.955, 0.637, 0.538, 0.4);
        scene.addComponent(copper_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, copper_mat));
    }

    {
        // Plastic (dielectric)
        const plastic_entity = scene.createEntity();
        scene.addComponent(plastic_entity, TransformComponent.withPosition(Vec3.init(6, 2, 0)));
        const plastic_mat = Material.dielectric(0.2, 0.6, 0.9, 0.3);
        scene.addComponent(plastic_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, plastic_mat));
    }

    {
        // Emissive sphere
        const emissive_entity = scene.createEntity();
        scene.addComponent(emissive_entity, TransformComponent.withPosition(Vec3.init(6, 5, 0)));
        const emissive_mat = Material.withEmissive(0.1, 0.1, 0.1, 2.0, 1.0, 0.5);
        scene.addComponent(emissive_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&sphere_mesh, emissive_mat));
    }

    // Create floor plane
    const floor_entity = scene.createEntity();
    var floor_transform = TransformComponent.withPosition(Vec3.init(0, -2, 0));
    floor_transform.setScale(Vec3.init(20, 1, 20));
    scene.addComponent(floor_entity, floor_transform);
    const floor_mat = Material.dielectric(0.3, 0.3, 0.35, 0.8);
    scene.addComponent(floor_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&plane_mesh, floor_mat));

    // Load a textured glTF model and promote its textures to PBR materials.
    std.debug.print("Loading textured glTF model...\n", .{});
    const glb_path = "assets/models/DamagedHelmet.glb";
    const imported_entities = asset_manager.importGLTFScene(glb_path, &scene, null) catch |err| {
        std.debug.print("Failed to load glTF: {}\n", .{err});
        return err;
    };
    defer allocator.free(imported_entities);

    std.debug.print("Loaded glTF with {} root entities\n", .{imported_entities.len});
    for (imported_entities) |entity| {
        if (scene.getComponent(TransformComponent, entity)) |transform| {
            transform.setPosition(Vec3.init(8, -1, 0));
            transform.setScale(Vec3.init(2, 2, 2));
        }
    }

    var material_ctx: u8 = 0;
    scene.iterateMeshRenderers(applyPbrMaterialToTexturedMeshes, &material_ctx);
    logMaterialStats(&scene);

    // Create directional light (sun) - pointing straight down for clear top lighting
    const sun_entity = scene.createEntity();
    var sun_transform = TransformComponent.init();
    // Point straight down (negative Y direction)
    sun_transform.setRotationEuler(-std.math.pi / 2.0, 0, 0);
    scene.addComponent(sun_entity, sun_transform);
    // Strong white sunlight
    scene.addComponent(sun_entity, LightComponent.directional(Vec3.init(1.0, 1.0, 1.0), 5.0));

    // Create point lights - very bright and close for visible effect
    point_light_entity = scene.createEntity();
    scene.addComponent(point_light_entity, TransformComponent.withPosition(Vec3.init(0, 5, 8)));
    // Very bright white point light in front
    scene.addComponent(point_light_entity, LightComponent.point(Vec3.init(1.0, 1.0, 1.0), 30.0, 30.0));

    const point_light2 = scene.createEntity();
    scene.addComponent(point_light2, TransformComponent.withPosition(Vec3.init(-6, 4, 6)));
    // Bright blue point light
    scene.addComponent(point_light2, LightComponent.point(Vec3.init(0.3, 0.5, 1.0), 20.0, 25.0));

    const point_light3 = scene.createEntity();
    scene.addComponent(point_light3, TransformComponent.withPosition(Vec3.init(6, 4, 6)));
    // Bright orange point light
    scene.addComponent(point_light3, LightComponent.point(Vec3.init(1.0, 0.5, 0.2), 20.0, 25.0));

    std.debug.print("\n=== PBR + IBL Demo ===\n", .{});
    std.debug.print("Scene shows {d}x{d} sphere grid with varying metallic/roughness\n", .{ grid_size, grid_size });
    std.debug.print("\nControls:\n", .{});
    std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
    std.debug.print("  Q/E - Move camera up/down\n", .{});
    std.debug.print("  I - Toggle IBL (Image-Based Lighting) on/off\n", .{});
    std.debug.print("  [ / ] - Decrease/Increase IBL intensity\n", .{});
    std.debug.print("  F3 - Toggle FPS counter\n", .{});
    std.debug.print("  ESC - Quit\n", .{});
    std.debug.print("\nSphere Grid:\n", .{});
    std.debug.print("  Columns (left to right): Increasing metallic (0.0 to 1.0)\n", .{});
    std.debug.print("  Rows (bottom to top): Increasing roughness (0.0 to 1.0)\n", .{});
    std.debug.print("\nSide Spheres:\n", .{});
    std.debug.print("  Left: Gold, Silver, Copper (metals)\n", .{});
    std.debug.print("  Right: Blue plastic, Emissive orange\n", .{});
    std.debug.print("\nIBL Status: ENABLED (intensity: {d:.2})\n", .{env_intensity});

    // Run game loop with scene
    try eng.runScene(&scene, update);
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    // Get camera transform
    const camera_entity = scene.getActiveCamera();
    // FPS Camera controls via controller component
    if (scene.getComponent(FpvCameraController, camera_entity)) |controller| {
        if (scene.getComponent(TransformComponent, camera_entity)) |cam_transform| {
            if (controller.update(cam_transform, input, delta_time)) {
                eng.setMouseCapture(true);
            }
        }
    }

    // IBL controls
    if (input.isKeyJustPressed(Scancode.i)) {
        ibl_enabled = !ibl_enabled;
        eng.light_uniforms.setIBLEnabled(ibl_enabled);
        std.debug.print("IBL: {s} (intensity: {d:.2})\n", .{ if (ibl_enabled) "ENABLED" else "DISABLED", env_intensity });
    }

    // IBL intensity controls
    if (input.isKeyDown(Scancode.left_bracket)) {
        env_intensity = @max(0.0, env_intensity - delta_time * 0.5);
        eng.light_uniforms.setIBLParams(env_intensity, 4.0);
        std.debug.print("IBL intensity: {d:.2}\n", .{env_intensity});
    }
    if (input.isKeyDown(Scancode.right_bracket)) {
        env_intensity = @min(3.0, env_intensity + delta_time * 0.5);
        eng.light_uniforms.setIBLParams(env_intensity, 4.0);
        std.debug.print("IBL intensity: {d:.2}\n", .{env_intensity});
    }

    // Animate point light
    rotation += delta_time;
    if (scene.getComponent(TransformComponent, point_light_entity)) |light_transform| {
        const radius: f32 = 6.0;
        light_transform.setPosition(Vec3.init(
            @cos(rotation) * radius,
            3.0 + @sin(rotation * 2.0),
            @sin(rotation) * radius + 5.0,
        ));
    }
}

fn applyPbrMaterialToTexturedMeshes(
    entity: Entity,
    transform: *TransformComponent,
    renderer: *MeshRendererComponent,
    userdata: *anyopaque,
) void {
    _ = entity;
    _ = transform;
    _ = userdata;
    if (renderer.material == null and renderer.getTexture() != null) {
        var mat = Material.init();
        mat.base_color_texture = renderer.getTexture();
        renderer.material = mat;
    }
}

const MaterialStats = struct {
    total: u32 = 0,
    with_material: u32 = 0,
    with_base_color: u32 = 0,
    with_mr: u32 = 0,
    with_normal: u32 = 0,
    sample_printed: bool = false,
};

fn logMaterialStats(scene: *Scene) void {
    var stats = MaterialStats{};
    scene.iterateMeshRenderers(collectMaterialStats, &stats);
    std.debug.print(
        "PBR material stats: total={d} with_material={d} base_color_tex={d} mr_tex={d} normal_tex={d}\n",
        .{ stats.total, stats.with_material, stats.with_base_color, stats.with_mr, stats.with_normal },
    );
}

fn collectMaterialStats(
    entity: Entity,
    transform: *TransformComponent,
    renderer: *MeshRendererComponent,
    userdata: *anyopaque,
) void {
    _ = entity;
    _ = transform;
    const stats: *MaterialStats = @ptrCast(@alignCast(userdata));
    stats.total += 1;

    if (renderer.material) |mat| {
        stats.with_material += 1;
        if (mat.base_color_texture != null) stats.with_base_color += 1;
        if (mat.metallic_roughness_texture != null) stats.with_mr += 1;
        if (mat.normal_texture != null) stats.with_normal += 1;

        if (!stats.sample_printed and mat.base_color_texture != null) {
            if (renderer.getMesh()) |mesh| {
                if (mesh.vertices.len > 0) {
                    stats.sample_printed = true;
                    const v0 = mesh.vertices[0];
                    std.debug.print(
                        "Sample mesh vertex: uv=({d:.3},{d:.3}) normal=({d:.3},{d:.3},{d:.3}) color=({d:.3},{d:.3},{d:.3},{d:.3})\n",
                        .{ v0.u, v0.v, v0.nx, v0.ny, v0.nz, v0.r, v0.g, v0.b, v0.a },
                    );
                }
            }
        }
    }
}
