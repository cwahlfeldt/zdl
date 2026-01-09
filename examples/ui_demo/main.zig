const std = @import("std");
const sdl = @import("sdl3");
const engine = @import("engine");
const Engine = engine.Engine;
const Scene = engine.Scene;
const Input = engine.Input;
const Vec3 = engine.Vec3;
const Mat4 = engine.Mat4;
const Color = engine.Color;
const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;
const FpvCameraController = engine.FpvCameraController;
const primitives = engine.primitives;
const Mesh = engine.Mesh;
const Quat = engine.Quat;

// UI imports
const UIContext = engine.UIContext;
const Theme = engine.Theme;

// Entity import
const Entity = engine.Entity;

// Demo state
var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;
var rotation: f32 = 0;
var rotation_speed: f32 = 1.0;
var auto_rotate: bool = true;
var cube_scale: f32 = 1.0;
var show_ui: bool = true;
var cube_entity: Entity = Entity.invalid;

// UI context
var ui: UIContext = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize UI context
    ui = UIContext.init(allocator);

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - UI Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 100,
    });
    defer eng.deinit();
    defer ui.deinit(&eng.device);

    // Initialize UI GPU resources
    const swapchain_format = try eng.device.getSwapchainTextureFormat(eng.window);
    try ui.initGpu(&eng.device, swapchain_format);
    ui.setScreenSize(1280, 720);

    // Create scene
    var scene = Scene.init(allocator);
    defer scene.deinit();

    // Create cube mesh
    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    // Create plane mesh
    plane_mesh = try primitives.createPlane(allocator);
    defer plane_mesh.deinit(&eng.device);
    try plane_mesh.upload(&eng.device);

    // Create camera entity with FPV controller
    const camera_entity = scene.createEntity();
    const camera_transform = TransformComponent.withPosition(Vec3.init(0, 2, 5));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());

    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 5.0,
        .capture_on_click = true,
    });
    const look_dir = Vec3.init(0, 0, 0).sub(Vec3.init(0, 2, 5)).normalize();
    fpv_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fpv_controller);
    scene.setActiveCamera(camera_entity);

    // Create cube entity
    cube_entity = scene.createEntity();
    scene.addComponent(cube_entity, TransformComponent.withPosition(Vec3.init(0, 0.5, 0)));
    scene.addComponent(cube_entity, MeshRendererComponent.fromMeshPtr(&cube_mesh));

    // Create ground plane
    const ground_entity = scene.createEntity();
    var ground_transform = TransformComponent.init();
    ground_transform.local.scale = Vec3.init(5, 1, 5);
    scene.addComponent(ground_entity, ground_transform);
    scene.addComponent(ground_entity, MeshRendererComponent.fromMeshPtr(&plane_mesh));

    std.debug.print("\n=== ZDL UI Demo ===\n", .{});
    std.debug.print("Demonstrating the UI system.\n\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Click to capture mouse\n", .{});
    std.debug.print("  WASD - Move camera\n", .{});
    std.debug.print("  Space/Shift - Move up/down\n", .{});
    std.debug.print("  Mouse - Look around\n", .{});
    std.debug.print("  F1 - Toggle UI\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n\n", .{});

    // Run custom game loop
    try runLoop(&eng, &scene);
}

fn runLoop(eng: *Engine, scene: *Scene) !void {
    var running = true;
    while (running) {
        const frame_start = sdl.timer.getMillisecondsSinceInit();
        const delta_time = @as(f32, @floatFromInt(frame_start - eng.last_time)) / 1000.0;
        eng.last_time = frame_start;

        // Input handling
        eng.input.update();

        while (sdl.events.poll()) |event| {
            switch (event) {
                .quit => running = false,
                .key_down => |key_event| {
                    if (key_event.scancode == .escape) {
                        if (eng.input.mouse_captured) {
                            eng.setMouseCapture(false);
                        } else {
                            running = false;
                        }
                    }
                    if (key_event.scancode == .func1) {
                        show_ui = !show_ui;
                        std.debug.print("UI: {s}\n", .{if (show_ui) "ON" else "OFF"});
                    }
                    try eng.input.processEvent(event);
                },
                .key_up => try eng.input.processEvent(event),
                .mouse_motion, .mouse_button_down, .mouse_button_up => try eng.input.processEvent(event),
                else => {},
            }
        }

        // Update UI input
        ui.updateInput(&eng.input);

        // Update game logic
        try update(eng, scene, &eng.input, delta_time);

        // Update transforms
        scene.updateWorldTransforms();

        // Update FPS counter
        eng.fps_frame_count += 1;
        if (frame_start - eng.fps_last_update >= 1000) {
            eng.fps_current = @as(f32, @floatFromInt(eng.fps_frame_count)) * 1000.0 / @as(f32, @floatFromInt(frame_start - eng.fps_last_update));
            eng.fps_frame_count = 0;
            eng.fps_last_update = frame_start;

            var title_buffer: [256]u8 = undefined;
            const title = std.fmt.bufPrintZ(&title_buffer, "ZDL UI Demo - FPS: {d:.1}", .{eng.fps_current}) catch "ZDL";
            eng.window.setTitle(title) catch {};
        }

        // Build UI
        if (show_ui) {
            buildUI();
        }

        // Upload UI data before render pass
        if (show_ui) {
            try ui.uploadData(&eng.device);
        }

        // Render
        if (try eng.beginFrame()) |frame_value| {
            var frame = frame_value;

            // Render scene entities
            const RenderSystem = engine.ecs.RenderSystem;
            RenderSystem.render(scene, &frame);

            // Render UI on top
            if (show_ui) {
                ui.render(frame.cmd, frame.pass);
            }

            try frame.end();
        }

        // Clear UI for next frame
        ui.clear();

        // Frame timing
        const frame_end = sdl.timer.getMillisecondsSinceInit();
        const frame_time = frame_end - frame_start;
        if (frame_time < eng.target_frame_time) {
            sdl.timer.delayMilliseconds(@intCast(eng.target_frame_time - frame_time));
        }
    }
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    _ = eng;
    _ = input;

    // Update cube rotation
    if (auto_rotate) {
        rotation += delta_time * rotation_speed;
    }

    // Update cube transform using getComponent
    if (scene.getComponent(TransformComponent, cube_entity)) |transform| {
        transform.setRotation(Quat.fromAxisAngle(Vec3.init(0, 1, 0), rotation));
        transform.setScale(Vec3.init(cube_scale, cube_scale, cube_scale));
    }
}

fn buildUI() void {
    // Begin UI frame
    ui.begin();

    // Draw a control panel
    if (ui.beginPanel("Controls", 10, 10, 220)) {
        ui.label("Press F1 to toggle UI");
        ui.separator();

        ui.labelFmt("Rotation: {d:.2}", .{rotation});

        if (ui.checkbox("Auto Rotate", &auto_rotate)) {
            // Checkbox was toggled
        }

        if (ui.slider("Speed", &rotation_speed, 0.0, 5.0)) {
            // Slider was changed
        }

        if (ui.slider("Scale", &cube_scale, 0.5, 2.0)) {
            // Slider was changed
        }

        ui.spacing(8);

        if (ui.button("Reset")) {
            rotation = 0;
            rotation_speed = 1.0;
            cube_scale = 1.0;
        }

        if (ui.button("Dark Theme")) {
            ui.setTheme(Theme.dark());
        }

        if (ui.button("Light Theme")) {
            ui.setTheme(Theme.light());
        }

        ui.endPanel();
    }

    // End UI frame
    ui.end();
}
