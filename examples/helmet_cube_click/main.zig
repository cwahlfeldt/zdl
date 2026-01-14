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
const StickValue = engine.StickValue;

const Ray = struct {
    origin: Vec3,
    direction: Vec3,
};

const helmet_move_speed: f32 = 2.4;
const cube_scale = Vec3.init(1.5, 1.5, 1.5);

var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;
var cube_entity: Entity = Entity.invalid;
var helmet_root: Entity = Entity.invalid;
var helmet_target: Vec3 = Vec3.zero();
var helmet_moving: bool = false;
var prev_mouse_left: bool = false;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Helmet Cube Click",
        .window_width = 1440,
        .window_height = 900,
        .target_fps = 100,
        .clear_color = .{ .r = 0.02, .g = 0.02, .b = 0.05, .a = 1.0 },
    });
    defer eng.deinit();

    try eng.initForwardPlus();
    try eng.initIBL();

    const hdr_rel_path = "assets/textures/kloppenheim_06_1k.hdr";
    const hdr_path = try std.fs.cwd().realpathAlloc(allocator, hdr_rel_path);
    defer allocator.free(hdr_path);
    if (eng.loadHDREnvironment(hdr_path)) |_| {} else |_| {}

    eng.light_uniforms.setIBLSpecularIntensity(0.35);
    eng.light_uniforms.setIBLParams(1.0, eng.light_uniforms.ibl_params[1]);

    var scene = Scene.init(allocator);
    defer scene.deinit();

    var asset_manager = AssetManager.init(allocator, &eng.device);
    defer asset_manager.deinit();

    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    // Camera
    const camera_entity = scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(0, 1.8, 7.5));
    camera_transform.lookAt(Vec3.init(0, 1.0, 0), Vec3.init(0, 1, 0));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());
    scene.setActiveCamera(camera_entity);

    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 4.0,
        .capture_on_click = true,
    });
    const look_dir = Vec3.init(0, 1.0, 0).sub(Vec3.init(0, 1.8, 7.5)).normalize();
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

    // Ground
    const floor_entity = scene.createEntity();
    var floor_transform = TransformComponent.withPosition(Vec3.init(0.0, 0.0, 0.0));
    floor_transform.setScale(Vec3.init(18.0, 1.0, 18.0));
    scene.addComponent(floor_entity, floor_transform);
    const floor_material = Material.dielectric(0.18, 0.2, 0.24, 0.9);
    scene.addComponent(floor_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&plane_mesh, floor_material));

    // Cube target
    cube_entity = scene.createEntity();
    var cube_transform = TransformComponent.withPosition(Vec3.init(3.0, cube_scale.y * 0.5, 0.0));
    cube_transform.setScale(cube_scale);
    scene.addComponent(cube_entity, cube_transform);
    const cube_material = Material.metal(0.9, 0.2, 0.1, 0.2);
    scene.addComponent(cube_entity, MeshRendererComponent.fromMeshPtrWithMaterial(&cube_mesh, cube_material));

    // Helmet
    const glb_path = "assets/models/DamagedHelmet.glb";
    const roots = try asset_manager.importGLTFScene(glb_path, &scene, null);
    defer allocator.free(roots);

    helmet_root = scene.createEntity();
    var helmet_transform = TransformComponent.withPosition(Vec3.init(-3.0, 0.0, 0.0));
    helmet_transform.setScale(Vec3.init(2.2, 2.2, 2.2));
    scene.addComponent(helmet_root, helmet_transform);

    for (roots) |root| {
        scene.setParent(root, helmet_root);
    }

    helmet_target = helmet_transform.getPosition();

    std.debug.print("\n=== Helmet Cube Click ===\n", .{});
    std.debug.print("Click the cube to move the helmet to it.\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
    std.debug.print("  Q/E - Move camera up/down\n", .{});
    std.debug.print("  I - Toggle IBL\n", .{});
    std.debug.print("  [ / ] - Decrease/Increase IBL intensity\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n\n", .{});

    try eng.runScene(&scene, update);
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    const camera_entity = scene.getActiveCamera();
    const was_captured = input.mouse_captured;

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

    const mouse_down = input.isMouseButtonDown(.left);
    const mouse_clicked = mouse_down and !prev_mouse_left;
    prev_mouse_left = mouse_down;

    if (mouse_clicked) {
        if (scene.getComponent(TransformComponent, camera_entity)) |cam_transform| {
            if (scene.getComponent(CameraComponent, camera_entity)) |camera| {
                if (scene.getComponent(TransformComponent, cube_entity)) |cube_transform| {
                    const mouse_pos: StickValue = if (was_captured)
                        .{
                            .x = @as(f32, @floatFromInt(eng.window_width)) * 0.5,
                            .y = @as(f32, @floatFromInt(eng.window_height)) * 0.5,
                        }
                    else
                        input.getMousePosition();

                    const ray = buildMouseRay(eng, cam_transform, camera.*, mouse_pos.x, mouse_pos.y);
                    const cube_center = cube_transform.getPosition();
                    const cube_half_extents = cube_transform.getScale().mul(0.5);

                    if (rayIntersectsAabb(ray, cube_center, cube_half_extents)) {
                        helmet_target = cube_center;
                        helmet_moving = true;
                    }
                }
            }
        }
    }

    if (helmet_moving) {
        if (scene.getComponent(TransformComponent, helmet_root)) |helmet_transform| {
            const current = helmet_transform.getPosition();
            const to_target = helmet_target.sub(current);
            const distance = to_target.length();
            const step = helmet_move_speed * delta_time;

            if (distance <= step or distance < 0.01) {
                helmet_transform.setPosition(helmet_target);
                helmet_moving = false;
            } else {
                helmet_transform.translate(to_target.normalize().mul(step));
            }
        }
    }
}

fn buildMouseRay(
    eng: *Engine,
    cam_transform: *TransformComponent,
    camera: CameraComponent,
    mouse_x: f32,
    mouse_y: f32,
) Ray {
    const width = @as(f32, @floatFromInt(eng.window_width));
    const height = @as(f32, @floatFromInt(eng.window_height));
    const aspect = width / height;
    const ndc_x = (mouse_x / width) * 2.0 - 1.0;
    const ndc_y = 1.0 - (mouse_y / height) * 2.0;
    const tan_half_fov = @tan(camera.fov * 0.5);

    const dir_camera = Vec3.init(
        ndc_x * aspect * tan_half_fov,
        ndc_y * tan_half_fov,
        -1.0,
    ).normalize();

    const origin = cam_transform.getPosition();
    const dir_world = cam_transform.getRotation().rotateVec3(dir_camera).normalize();

    return .{
        .origin = origin,
        .direction = dir_world,
    };
}

fn rayIntersectsAabb(ray: Ray, center: Vec3, half_extents: Vec3) bool {
    const min = center.sub(half_extents);
    const max = center.add(half_extents);

    var tmin = -std.math.inf(f32);
    var tmax = std.math.inf(f32);

    if (!updateSlab(ray.origin.x, ray.direction.x, min.x, max.x, &tmin, &tmax)) return false;
    if (!updateSlab(ray.origin.y, ray.direction.y, min.y, max.y, &tmin, &tmax)) return false;
    if (!updateSlab(ray.origin.z, ray.direction.z, min.z, max.z, &tmin, &tmax)) return false;

    return tmax >= @max(tmin, 0.0);
}

fn updateSlab(origin: f32, dir: f32, min: f32, max: f32, tmin: *f32, tmax: *f32) bool {
    if (@abs(dir) < 0.0001) {
        return origin >= min and origin <= max;
    }

    const inv_dir = 1.0 / dir;
    var t1 = (min - origin) * inv_dir;
    var t2 = (max - origin) * inv_dir;
    if (t1 > t2) {
        std.mem.swap(f32, &t1, &t2);
    }

    if (t1 > tmin.*) tmin.* = t1;
    if (t2 < tmax.*) tmax.* = t2;

    return tmax.* >= tmin.*;
}
