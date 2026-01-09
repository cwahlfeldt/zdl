const std = @import("std");
const engine = @import("engine");
const Engine = engine.Engine;
const Scene = engine.Scene;
const Entity = engine.Entity;
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

// Debug imports
const Profiler = engine.Profiler;
const DebugDraw = engine.DebugDraw;
const StatsOverlay = engine.StatsOverlay;
const scopedZone = engine.scopedZone;

var cube_mesh: Mesh = undefined;
var plane_mesh: Mesh = undefined;
var cube_entity: Entity = Entity.invalid;
var rotation: f32 = 0;

// Debug systems
var profiler: Profiler = undefined;
var debug_draw: DebugDraw = undefined;
var stats_overlay: StatsOverlay = undefined;
var show_debug_draw: bool = true;
var show_stats: bool = true;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize profiler
    profiler = try Profiler.init(allocator);
    defer profiler.deinit();

    // Initialize debug draw
    debug_draw = DebugDraw.init(allocator);
    defer debug_draw.deinit(null);

    // Initialize stats overlay
    stats_overlay = StatsOverlay.init(&profiler);

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Debug Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 100,
    });
    defer eng.deinit();

    // Initialize debug draw GPU resources
    const swapchain_format = try eng.device.getSwapchainTextureFormat(eng.window);
    debug_draw.initGpu(&eng.device, swapchain_format) catch |err| {
        std.debug.print("Warning: Failed to initialize DebugDraw GPU: {}\n", .{err});
    };

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

    // Create camera entity with FPV controller
    const camera_entity = scene.createEntity();
    const camera_transform = TransformComponent.withPosition(Vec3.init(0, 3, 8));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());

    // Add FPV controller and initialize looking at origin
    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 5.0,
        .capture_on_click = true,
    });
    // Set initial look direction toward origin
    const look_dir = Vec3.init(0, 0, 0).sub(Vec3.init(0, 0.5, 8)).normalize();
    fpv_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fpv_controller);
    scene.setActiveCamera(camera_entity);

    // Create cube entity
    cube_entity = scene.createEntity();
    const cube_transform = TransformComponent.withPosition(Vec3.init(0, 0.5, 0));
    scene.addComponent(cube_entity, cube_transform);
    scene.addComponent(cube_entity, MeshRendererComponent.fromMeshPtr(&cube_mesh));

    // Create plane entity
    const plane_entity = scene.createEntity();
    var plane_transform = TransformComponent.withPosition(Vec3.init(0, -0.5, 0));
    plane_transform.setScale(Vec3.init(10, 1, 10));
    scene.addComponent(plane_entity, plane_transform);
    scene.addComponent(plane_entity, MeshRendererComponent.fromMeshPtr(&plane_mesh));

    std.debug.print("\n=== ZDL Debug Demo ===\n", .{});
    std.debug.print("Demonstrating debug and profiling tools.\n\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Click to capture mouse\n", .{});
    std.debug.print("  WASD - Move camera\n", .{});
    std.debug.print("  Space/Shift - Move up/down\n", .{});
    std.debug.print("  Mouse - Look around\n", .{});
    std.debug.print("  F1 - Toggle debug draw\n", .{});
    std.debug.print("  F2 - Toggle stats display\n", .{});
    std.debug.print("  F3 - Toggle FPS in title\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n\n", .{});

    // Run custom game loop
    try runLoop(&eng, &scene);
}

fn runLoop(eng: *Engine, scene: *Scene) !void {
    const sdl = @import("sdl3");

    var running = true;
    while (running) {
        profiler.beginFrame();
        defer profiler.endFrame();

        const frame_start = sdl.timer.getMillisecondsSinceInit();
        const delta_time = @as(f32, @floatFromInt(frame_start - eng.last_time)) / 1000.0;
        eng.last_time = frame_start;

        // Reset stats
        stats_overlay.resetFrameStats();

        // Input handling
        {
            const zone = scopedZone(&profiler, "Input");
            defer zone.end();

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
                            show_debug_draw = !show_debug_draw;
                            std.debug.print("Debug draw: {s}\n", .{if (show_debug_draw) "ON" else "OFF"});
                        }
                        if (key_event.scancode == .func2) {
                            show_stats = !show_stats;
                            std.debug.print("Stats display: {s}\n", .{if (show_stats) "ON" else "OFF"});
                        }
                        if (key_event.scancode == .func3) {
                            eng.show_fps = !eng.show_fps;
                            if (!eng.show_fps) {
                                eng.window.setTitle(eng.original_window_title) catch {};
                            }
                        }
                        try eng.input.processEvent(event);
                    },
                    .key_up => try eng.input.processEvent(event),
                    .mouse_motion, .mouse_button_down, .mouse_button_up => try eng.input.processEvent(event),
                    else => {},
                }
            }
        }

        // Update
        {
            const zone = scopedZone(&profiler, "Update");
            defer zone.end();

            try update(eng, scene, &eng.input, delta_time);
        }

        // Update transforms
        scene.updateWorldTransforms();

        // Update FPS counter
        eng.fps_frame_count += 1;
        if (frame_start - eng.fps_last_update >= 1000) {
            eng.fps_current = @as(f32, @floatFromInt(eng.fps_frame_count)) * 1000.0 / @as(f32, @floatFromInt(frame_start - eng.fps_last_update));
            eng.fps_frame_count = 0;
            eng.fps_last_update = frame_start;

            if (eng.show_fps) {
                var title_buffer: [256]u8 = undefined;
                const title = std.fmt.bufPrintZ(&title_buffer, "ZDL Debug Demo - FPS: {d:.1}", .{eng.fps_current}) catch "ZDL";
                eng.window.setTitle(title) catch {};
            }

            // Print stats to console
            if (show_stats) {
                stats_overlay.updateEntityCount(scene.entityCount());
                var buffer: [256]u8 = undefined;
                const stats_str = stats_overlay.formatTitleString(&buffer);
                std.debug.print("\r{s}                    ", .{stats_str});
            }
        }

        // Render
        {
            const zone = scopedZone(&profiler, "Render");
            defer zone.end();

            // Upload debug draw data before render pass
            if (show_debug_draw and debug_draw.isGpuInitialized()) {
                debug_draw.uploadVertexData(&eng.device) catch {};
            }

            if (try eng.beginFrame()) |frame_value| {
                var frame = frame_value;

                // Render scene entities
                const RenderSystem = @import("engine").ecs.RenderSystem;
                RenderSystem.render(scene, &frame);

                // Record draw calls for stats
                stats_overlay.render_stats.draw_calls = 2; // plane + cube

                // Render debug draw
                if (show_debug_draw and debug_draw.isGpuInitialized()) {
                    const camera = scene.getActiveCamera();
                    if (scene.getComponent(CameraComponent, camera)) |cam| {
                        if (scene.getComponent(TransformComponent, camera)) |cam_transform| {
                            const aspect = @as(f32, @floatFromInt(eng.window_width)) / @as(f32, @floatFromInt(eng.window_height));
                            const proj = Mat4.perspective(cam.fov, aspect, cam.near, cam.far);

                            // Compute view matrix from camera world matrix
                            const cam_pos = Vec3.init(
                                cam_transform.world_matrix.data[12],
                                cam_transform.world_matrix.data[13],
                                cam_transform.world_matrix.data[14],
                            );
                            const cam_forward = Vec3.init(
                                -cam_transform.world_matrix.data[8],
                                -cam_transform.world_matrix.data[9],
                                -cam_transform.world_matrix.data[10],
                            );
                            const cam_target = cam_pos.add(cam_forward);
                            const view = Mat4.lookAt(cam_pos, cam_target, Vec3.init(0, 1, 0));
                            const view_proj = Mat4.mul(proj, view);

                            debug_draw.render(&eng.device, frame.cmd, frame.pass, view_proj);
                        }
                    }
                }

                try frame.end();
            }
        }

        // Clear debug draw for next frame
        debug_draw.clear();

        // Frame rate limiting
        const frame_end = sdl.timer.getMillisecondsSinceInit();
        const frame_time = frame_end - frame_start;
        if (frame_time < eng.target_frame_time) {
            sdl.timer.delayMilliseconds(@intCast(eng.target_frame_time - frame_time));
        }
    }

    std.debug.print("\n\n", .{}); // Clean up console output
}

fn update(eng: *Engine, scene: *Scene, input: *Input, delta_time: f32) !void {
    // Update FPV camera controller
    const camera_entity = scene.getActiveCamera();
    if (scene.getComponent(FpvCameraController, camera_entity)) |controller| {
        if (scene.getComponent(TransformComponent, camera_entity)) |camera_transform| {
            const should_capture = controller.update(camera_transform, input, delta_time);
            if (should_capture) {
                eng.setMouseCapture(true);
            }
        }
    }

    // Rotate cube
    rotation += delta_time;
    if (scene.getComponent(TransformComponent, cube_entity)) |cube_transform| {
        cube_transform.setRotationEuler(rotation * 0.7, rotation, rotation * 0.5);

        // Draw debug visualization around the cube
        if (show_debug_draw) {
            const pos = cube_transform.getPosition();

            // Draw coordinate axes at cube position
            debug_draw.axes(pos, 1.5);

            // Draw wireframe box around the cube
            debug_draw.wireBox(pos, Vec3.init(1.2, 1.2, 1.2), Color.init(1, 1, 0, 1));

            // Draw a sphere around the cube
            debug_draw.wireSphere(pos, 1.0, Color.init(0, 1, 1, 0.5));

            // Draw grid on the ground
            debug_draw.grid(Vec3.init(0, -0.49, 0), 10, 10, Color.init(0.5, 0.5, 0.5, 0.5));

            // Draw some debug points
            debug_draw.point(Vec3.init(2, 0, 0), 0.2, Color.init(1, 0, 0, 1));
            debug_draw.point(Vec3.init(-2, 0, 0), 0.2, Color.init(0, 1, 0, 1));
            debug_draw.point(Vec3.init(0, 0, 2), 0.2, Color.init(0, 0, 1, 1));

            // Draw an arrow showing movement direction
            const forward = cube_transform.forward();
            debug_draw.arrow(pos, pos.add(forward.mul(2)), Color.init(1, 0.5, 0, 1));
        }
    }

    // Update persistent draws
    debug_draw.update(delta_time);
}
