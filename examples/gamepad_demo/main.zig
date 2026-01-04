const std = @import("std");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Input = engine.Input;
const Gamepad = engine.Gamepad;
const GamepadButton = engine.GamepadButton;
const HapticPresets = engine.HapticPresets;
const Vec3 = engine.Vec3;
const Quat = engine.Quat;
const primitives = engine.primitives;
const TransformComponent = engine.TransformComponent;
const MeshRendererComponent = engine.MeshRendererComponent;
const CameraComponent = engine.CameraComponent;
const Mesh = engine.Mesh;

var cube_mesh: Mesh = undefined;
var sphere_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;

var player_entity: engine.Entity = undefined;
var indicator_entity: engine.Entity = undefined;

// Player state
var player_position: Vec3 = Vec3.init(0, 0.5, 0);
var player_rotation: f32 = 0;
var player_velocity: Vec3 = Vec3.init(0, 0, 0);

const PLAYER_SPEED: f32 = 5.0;
const ROTATION_SPEED: f32 = 3.0;

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    _ = eng;

    // Get gamepad if connected
    const gamepad = input.getGamepad();

    // Get movement input (works with keyboard WASD or gamepad left stick)
    const move = input.getMoveVector();

    // Get rotation from right stick (gamepad) or Q/E keys (keyboard)
    var rotation_input: f32 = 0;
    if (gamepad) |gp| {
        const right_stick = gp.getRightStick();
        rotation_input = right_stick.x;
    }
    if (input.isKeyDown(.q)) rotation_input -= 1;
    if (input.isKeyDown(.e)) rotation_input += 1;

    // Update player rotation
    player_rotation += rotation_input * ROTATION_SPEED * delta_time;

    // Calculate movement direction relative to player rotation
    const cos_rot = @cos(player_rotation);
    const sin_rot = @sin(player_rotation);

    // Transform movement input by player rotation
    const forward = Vec3.init(sin_rot, 0, cos_rot);
    const right = Vec3.init(cos_rot, 0, -sin_rot);

    player_velocity = forward.mul(-move.y * PLAYER_SPEED)
        .add(right.mul(move.x * PLAYER_SPEED));

    // Apply velocity
    player_position = player_position.add(player_velocity.mul(delta_time));

    // Clamp to play area
    player_position.x = @max(-8, @min(8, player_position.x));
    player_position.z = @max(-8, @min(8, player_position.z));

    // Update player entity transform
    if (scene.getComponent(TransformComponent, player_entity)) |transform| {
        transform.local.position = player_position;
        transform.setRotation(Quat.fromAxisAngle(Vec3.init(0, 1, 0), player_rotation));
    }

    // Handle gamepad buttons for haptic feedback demo
    if (gamepad) |gp| {
        // South button (A/Cross) - light tap
        if (gp.isButtonJustPressed(.south)) {
            HapticPresets.lightTap(gp);
            std.debug.print("Light tap rumble\n", .{});
        }

        // East button (B/Circle) - medium impact
        if (gp.isButtonJustPressed(.east)) {
            HapticPresets.mediumImpact(gp);
            std.debug.print("Medium impact rumble\n", .{});
        }

        // West button (X/Square) - heavy impact
        if (gp.isButtonJustPressed(.west)) {
            HapticPresets.heavyImpact(gp);
            std.debug.print("Heavy impact rumble\n", .{});
        }

        // North button (Y/Triangle) - explosion
        if (gp.isButtonJustPressed(.north)) {
            HapticPresets.explosion(gp);
            std.debug.print("Explosion rumble\n", .{});
        }

        // Triggers - proportional rumble
        const left_trigger = gp.getLeftTrigger();
        const right_trigger = gp.getRightTrigger();
        if (left_trigger > 0 or right_trigger > 0) {
            gp.rumble(left_trigger, right_trigger, 50);
        }

        // Shoulders - start/back
        if (gp.isButtonJustPressed(.start)) {
            std.debug.print("Start pressed\n", .{});
        }
        if (gp.isButtonJustPressed(.back)) {
            std.debug.print("Back/Select pressed\n", .{});
        }

        // D-pad
        if (gp.isButtonJustPressed(.dpad_up)) std.debug.print("D-pad Up\n", .{});
        if (gp.isButtonJustPressed(.dpad_down)) std.debug.print("D-pad Down\n", .{});
        if (gp.isButtonJustPressed(.dpad_left)) std.debug.print("D-pad Left\n", .{});
        if (gp.isButtonJustPressed(.dpad_right)) std.debug.print("D-pad Right\n", .{});
    }

    // Update indicator position based on analog sticks
    if (gamepad) |gp| {
        const left_stick = gp.getLeftStick();
        const indicator_pos = Vec3.init(
            left_stick.x * 3,
            0.2,
            left_stick.y * 3,
        );
        if (scene.getComponent(TransformComponent, indicator_entity)) |transform| {
            transform.local.position = player_position.add(indicator_pos);
            transform.markDirty();
        }
    }

    // Print gamepad state on pressing shoulder buttons
    if (gamepad) |gp| {
        if (gp.isButtonJustPressed(.left_shoulder) or gp.isButtonJustPressed(.right_shoulder)) {
            const left_stick = gp.getLeftStick();
            const right_stick = gp.getRightStick();
            std.debug.print("Sticks - L: ({d:.2}, {d:.2}) R: ({d:.2}, {d:.2})\n", .{
                left_stick.x,
                left_stick.y,
                right_stick.x,
                right_stick.y,
            });
            std.debug.print("Triggers - L: {d:.2} R: {d:.2}\n", .{
                gp.getLeftTrigger(),
                gp.getRightTrigger(),
            });
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL Gamepad Demo - Connect a controller!",
        .window_width = 1280,
        .window_height = 720,
    });
    defer eng.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create meshes
    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    sphere_mesh = try primitives.createSphere(allocator, 12);
    defer sphere_mesh.deinit(&eng.device);
    try sphere_mesh.upload(&eng.device);

    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    // Create camera
    const camera = try scene.createEntity();
    try scene.addComponent(camera, CameraComponent.init());
    try scene.addComponent(camera, TransformComponent.withPosition(Vec3.init(0, 10, 12)));
    if (scene.getComponent(TransformComponent, camera)) |transform| {
        transform.setRotation(Quat.fromAxisAngle(Vec3.init(1, 0, 0), -0.6));
    }
    scene.setActiveCamera(camera);

    // Create ground plane
    const ground = try scene.createEntity();
    try scene.addComponent(ground, TransformComponent.withPosition(Vec3.init(0, 0, 0)));
    try scene.addComponent(ground, MeshRendererComponent.init(&plane_mesh));

    // Create player (cube)
    player_entity = try scene.createEntity();
    try scene.addComponent(player_entity, TransformComponent.withPosition(player_position));
    try scene.addComponent(player_entity, MeshRendererComponent.init(&cube_mesh));

    // Create stick position indicator (small sphere)
    indicator_entity = try scene.createEntity();
    try scene.addComponent(indicator_entity, TransformComponent.withPosition(Vec3.init(0, 0.2, 0)));
    try scene.addComponent(indicator_entity, MeshRendererComponent.init(&sphere_mesh));

    // Print instructions
    std.debug.print(
        \\
        \\=== ZDL Gamepad Demo ===
        \\
        \\Connect a gamepad and try the following:
        \\
        \\Movement:
        \\  Left Stick / WASD - Move player
        \\  Right Stick / Q/E - Rotate player
        \\
        \\Haptic Feedback (Face Buttons):
        \\  South (A/Cross) - Light tap
        \\  East (B/Circle) - Medium impact
        \\  West (X/Square) - Heavy impact
        \\  North (Y/Triangle) - Explosion
        \\
        \\Triggers:
        \\  LT/RT - Proportional rumble
        \\
        \\Debug:
        \\  Shoulders (LB/RB) - Print stick/trigger values
        \\
        \\Press ESC to quit
        \\
    , .{});

    // Check initial gamepad state
    const gamepad_count = eng.input.getGamepadCount();
    if (gamepad_count > 0) {
        std.debug.print("Found {d} gamepad(s) connected!\n", .{gamepad_count});
        if (eng.input.getGamepad()) |gp| {
            std.debug.print("Primary gamepad: {s} ({s})\n", .{
                gp.name,
                @tagName(gp.gamepad_type),
            });
        }
    } else {
        std.debug.print("No gamepads connected. Plug one in to test!\n", .{});
        std.debug.print("Using keyboard: WASD to move, Q/E to rotate\n", .{});
    }

    try eng.runScene(&scene, update);
}
