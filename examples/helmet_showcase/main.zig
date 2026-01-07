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

const HelmetVariant = enum {
    hero,
    matte,
    chrome,
    unlit,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Damaged Helmet Showcase",
        .window_width = 1440,
        .window_height = 900,
        .target_fps = 100,
        .clear_color = .{ .r = 0.02, .g = 0.02, .b = 0.05, .a = 1.0 },
    });
    defer eng.deinit();

    try eng.initPBR();
    try eng.initIBL();

    const hdr_rel_path = "assets/textures/kloppenheim_06_1k.hdr";
    const hdr_path = try std.fs.cwd().realpathAlloc(allocator, hdr_rel_path);
    defer allocator.free(hdr_path);
    if (eng.loadHDREnvironment(hdr_path)) |_| {} else |_| {}

    eng.light_uniforms.setIBLSpecularIntensity(0.28);
    eng.light_uniforms.setIBLParams(1.15, eng.light_uniforms.ibl_params[1]);

    var scene = Scene.init(allocator);
    defer scene.deinit();

    var asset_manager = AssetManager.init(allocator, &eng.device);
    defer asset_manager.deinit();

    // Camera
    const camera_entity = scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(0, 2.1, 8.5));
    camera_transform.lookAt(Vec3.init(0, 1.2, 0), Vec3.init(0, 1, 0));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());
    scene.setActiveCamera(camera_entity);

    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 4.0,
        .capture_on_click = true,
    });
    const look_dir = Vec3.init(0, 1.2, 0).sub(Vec3.init(0, 2.1, 8.5)).normalize();
    fpv_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fpv_controller);

    // Lights
    const sun_entity = scene.createEntity();
    var sun_transform = TransformComponent.init();
    sun_transform.setRotationEuler(-0.85, 0.4, 0.0);
    scene.addComponent(sun_entity, sun_transform);
    scene.addComponent(sun_entity, LightComponent.directional(Vec3.init(1.0, 0.98, 0.93), 2.0));

    const rim_light = scene.createEntity();
    scene.addComponent(rim_light, TransformComponent.withPosition(Vec3.init(-4.0, 3.5, 3.5)));
    scene.addComponent(rim_light, LightComponent.point(Vec3.init(0.4, 0.6, 1.0), 18.0, 25.0));

    const warm_light = scene.createEntity();
    scene.addComponent(warm_light, TransformComponent.withPosition(Vec3.init(4.5, 2.2, 2.0)));
    scene.addComponent(warm_light, LightComponent.point(Vec3.init(1.0, 0.6, 0.35), 14.0, 22.0));

    // Helmets
    const glb_path = "assets/models/DamagedHelmet.glb";
    try addHelmetVariant(&scene, &asset_manager, allocator, glb_path, Vec3.init(-6.0, 0.0, 0.0), 0.35, 2.2, .matte);
    // try addHelmetVariant(&scene, &asset_manager, allocator, glb_path, Vec3.init(-2.0, 0.0, 0.0), 0.25, 2.2, .hero);
    // try addHelmetVariant(&scene, &asset_manager, allocator, glb_path, Vec3.init(2.0, 0.0, 0.0), -0.25, 2.2, .chrome);
    // try addHelmetVariant(&scene, &asset_manager, allocator, glb_path, Vec3.init(6.0, 0.0, 0.0), -0.35, 2.2, .unlit);

    std.debug.print("\n=== Damaged Helmet Showcase ===\n", .{});
    std.debug.print("1) Matte PBR  2) Hero PBR  3) Chrome PBR  4) Unlit Albedo\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
    std.debug.print("  Q/E - Move camera up/down\n", .{});
    std.debug.print("  I - Toggle IBL\n", .{});
    std.debug.print("  [ / ] - Decrease/Increase IBL intensity\n", .{});
    std.debug.print("  ESC - Quit\n\n", .{});

    try eng.runScene(&scene, update);
}

fn addHelmetVariant(
    scene: *Scene,
    asset_manager: *AssetManager,
    allocator: std.mem.Allocator,
    glb_path: []const u8,
    position: Vec3,
    yaw: f32,
    scale: f32,
    variant: HelmetVariant,
) !void {
    const roots = try asset_manager.importGLTFScene(glb_path, scene, null);
    defer allocator.free(roots);

    for (roots) |root| {
        if (scene.getComponent(TransformComponent, root)) |transform| {
            transform.setPosition(position);
            transform.setRotationEuler(0.0, yaw, 0.0);
            transform.setScale(Vec3.init(scale, scale, scale));
        }
        try applyVariantToSubtree(scene, allocator, root, variant);
    }
}

fn applyVariantToSubtree(scene: *Scene, allocator: std.mem.Allocator, root: Entity, variant: HelmetVariant) !void {
    var stack = std.ArrayList(Entity).empty;
    defer stack.deinit(allocator);

    try stack.append(allocator, root);

    while (stack.items.len > 0) {
        const entity = stack.pop().?;

        if (scene.getComponent(MeshRendererComponent, entity)) |renderer| {
            switch (variant) {
                .hero => {},
                .matte => if (renderer.material) |*mat| {
                    mat.metallic = 0.0;
                    mat.roughness = 1.0;
                    mat.normal_scale = 0.8;
                },
                .chrome => if (renderer.material) |*mat| {
                    mat.metallic = 1.0;
                    mat.roughness = 0.08;
                    mat.normal_scale = 0.6;
                },
                .unlit => {
                    if (renderer.material) |mat| {
                        if (mat.base_color_texture) |tex| {
                            renderer.texture = tex;
                        }
                    }
                    renderer.material = null;
                },
            }
        }

        const children = try scene.getChildren(entity, allocator);
        defer allocator.free(children);
        for (children) |child| {
            try stack.append(allocator, child);
        }
    }
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    const camera_entity = scene.getActiveCamera();
    if (scene.getComponent(FpvCameraController, camera_entity)) |controller| {
        if (scene.getComponent(TransformComponent, camera_entity)) |cam_transform| {
            if (controller.update(cam_transform, input, delta_time)) {
                eng.setMouseCapture(true);
            }
        }
    }

    if (input.isKeyJustPressed(Scancode.i)) {
        const enabled = eng.light_uniforms.ibl_params[2] < 0.5;
        eng.light_uniforms.setIBLEnabled(enabled);
    }

    if (input.isKeyDown(Scancode.left_bracket)) {
        const intensity = @max(0.0, eng.light_uniforms.ibl_params[0] - delta_time * 0.5);
        eng.light_uniforms.setIBLParams(intensity, eng.light_uniforms.ibl_params[1]);
    }
    if (input.isKeyDown(Scancode.right_bracket)) {
        const intensity = @min(3.0, eng.light_uniforms.ibl_params[0] + delta_time * 0.5);
        eng.light_uniforms.setIBLParams(intensity, eng.light_uniforms.ibl_params[1]);
    }
}
