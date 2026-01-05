const std = @import("std");
const engine = @import("engine");
const Engine = engine.Engine;
const Scene = engine.Scene;
const Entity = engine.Entity;
const Input = engine.Input;
const Vec3 = engine.Vec3;
const Mat4 = engine.Mat4;
const Quat = engine.Quat;
const Color = engine.Color;
const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const MeshRendererComponent = engine.MeshRendererComponent;
const FpvCameraController = engine.FpvCameraController;
const primitives = engine.primitives;
const Mesh = engine.Mesh;

// Animation imports
const Skeleton = engine.Skeleton;
const AnimationClip = engine.AnimationClip;
const AnimationChannel = engine.animation.AnimationChannel;
const Animator = engine.Animator;
const Transform = engine.animation.Transform;

// Debug imports
const Profiler = engine.Profiler;
const DebugDraw = engine.DebugDraw;
const scopedZone = engine.scopedZone;

var cube_mesh: Mesh = undefined;
var show_debug_draw: bool = true;

// Animation state
var skeleton: *Skeleton = undefined;
var animator: *Animator = undefined;
var walk_clip: *AnimationClip = undefined;
var idle_clip: *AnimationClip = undefined;
var current_animation: []const u8 = "walk";

// Debug systems
var profiler: Profiler = undefined;
var debug_draw: DebugDraw = undefined;

// Bone entities for visualization
var bone_entities: [3]Entity = undefined;

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

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Animation Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 60,
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

    // Create cube mesh for bone visualization
    cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    // Create camera entity with FPV controller
    const camera_entity = scene.createEntity();
    const camera_transform = TransformComponent.withPosition(Vec3.init(5, 3, 5));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());

    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 5.0,
        .capture_on_click = true,
    });
    const look_dir = Vec3.init(0, 1, 0).sub(Vec3.init(5, 3, 5)).normalize();
    fpv_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fpv_controller);
    scene.setActiveCamera(camera_entity);

    // Create skeleton and animation
    skeleton = try createSimpleSkeleton(allocator);
    defer {
        skeleton.deinit();
        allocator.destroy(skeleton);
    }

    // Create animation clips
    walk_clip = try createWalkAnimation(allocator);
    defer {
        walk_clip.deinit();
        allocator.destroy(walk_clip);
    }

    idle_clip = try createIdleAnimation(allocator);
    defer {
        idle_clip.deinit();
        allocator.destroy(idle_clip);
    }

    // Create animator
    animator = try allocator.create(Animator);
    animator.* = try Animator.init(allocator, skeleton);
    defer {
        animator.deinit();
        allocator.destroy(animator);
    }

    try animator.addClip("walk", walk_clip);
    try animator.addClip("idle", idle_clip);
    _ = animator.play("walk");

    // Create bone visualization entities
    for (0..3) |i| {
        bone_entities[i] = scene.createEntity();
        var transform = TransformComponent.init();
        transform.setScale(Vec3.init(0.2, 0.2, 0.2));
        scene.addComponent(bone_entities[i], transform);
        scene.addComponent(bone_entities[i], MeshRendererComponent.init(&cube_mesh));
    }

    std.debug.print("\n=== ZDL Animation Demo ===\n", .{});
    std.debug.print("Demonstrating skeletal animation system\n\n", .{});
    std.debug.print("Created skeleton with {} bones:\n", .{skeleton.boneCount()});
    for (skeleton.bones, 0..) |bone, i| {
        std.debug.print("  Bone {}: '{s}'\n", .{ i, bone.name });
    }
    std.debug.print("\nControls:\n", .{});
    std.debug.print("  Click to capture mouse\n", .{});
    std.debug.print("  WASD - Move camera\n", .{});
    std.debug.print("  Space/Shift - Move up/down\n", .{});
    std.debug.print("  Mouse - Look around\n", .{});
    std.debug.print("  1 - Play 'walk' animation\n", .{});
    std.debug.print("  2 - Play 'idle' animation\n", .{});
    std.debug.print("  F1 - Toggle debug draw\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n\n", .{});

    // Run custom game loop
    try runLoop(&eng, &scene, allocator);
}

fn createSimpleSkeleton(allocator: std.mem.Allocator) !*Skeleton {
    // Create a simple 3-bone arm skeleton
    var skel = try allocator.create(Skeleton);
    skel.* = try Skeleton.init(allocator, 3);

    const NO_BONE = @import("engine").animation.NO_BONE;

    // Root bone (shoulder)
    try skel.setBone(0, "shoulder", NO_BONE, Transform.init());

    // Upper arm
    var upper_arm_transform = Transform.init();
    upper_arm_transform.position = Vec3.init(1.0, 0, 0);
    try skel.setBone(1, "upper_arm", 0, upper_arm_transform);

    // Lower arm
    var lower_arm_transform = Transform.init();
    lower_arm_transform.position = Vec3.init(1.0, 0, 0);
    try skel.setBone(2, "lower_arm", 1, lower_arm_transform);

    try skel.computeRootBones();

    // Set identity inverse bind matrices (for visualization, not actual skinning)
    for (0..3) |i| {
        skel.setInverseBindMatrix(@intCast(i), Mat4.identity());
    }

    return skel;
}

fn createWalkAnimation(allocator: std.mem.Allocator) !*AnimationClip {
    var clip = try allocator.create(AnimationClip);
    clip.* = try AnimationClip.init(allocator, "walk", 2);

    // Shoulder rotation channel - swinging motion
    clip.channels[0] = try AnimationChannel.init(allocator, 0, .rotation, 5);
    clip.channels[0].times[0] = 0.0;
    clip.channels[0].times[1] = 0.25;
    clip.channels[0].times[2] = 0.5;
    clip.channels[0].times[3] = 0.75;
    clip.channels[0].times[4] = 1.0;

    // Swing back and forth
    clip.channels[0].rotation_values.?[0] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), -0.5);
    clip.channels[0].rotation_values.?[1] = Quat.identity();
    clip.channels[0].rotation_values.?[2] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), 0.5);
    clip.channels[0].rotation_values.?[3] = Quat.identity();
    clip.channels[0].rotation_values.?[4] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), -0.5);

    // Upper arm rotation channel - bend at elbow
    clip.channels[1] = try AnimationChannel.init(allocator, 1, .rotation, 3);
    clip.channels[1].times[0] = 0.0;
    clip.channels[1].times[1] = 0.5;
    clip.channels[1].times[2] = 1.0;

    clip.channels[1].rotation_values.?[0] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), -0.3);
    clip.channels[1].rotation_values.?[1] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), 0.3);
    clip.channels[1].rotation_values.?[2] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), -0.3);

    clip.computeDuration();
    return clip;
}

fn createIdleAnimation(allocator: std.mem.Allocator) !*AnimationClip {
    var clip = try allocator.create(AnimationClip);
    clip.* = try AnimationClip.init(allocator, "idle", 1);

    // Subtle breathing motion on shoulder
    clip.channels[0] = try AnimationChannel.init(allocator, 0, .rotation, 3);
    clip.channels[0].times[0] = 0.0;
    clip.channels[0].times[1] = 1.0;
    clip.channels[0].times[2] = 2.0;

    clip.channels[0].rotation_values.?[0] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), 0.05);
    clip.channels[0].rotation_values.?[1] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), -0.05);
    clip.channels[0].rotation_values.?[2] = Quat.fromAxisAngle(Vec3.init(0, 0, 1), 0.05);

    clip.computeDuration();
    return clip;
}

fn runLoop(eng: *Engine, scene: *Scene, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const sdl = @import("sdl3");

    var running = true;
    while (running) {
        profiler.beginFrame();
        defer profiler.endFrame();

        const frame_start = sdl.timer.getMillisecondsSinceInit();
        const delta_time = @as(f32, @floatFromInt(frame_start - eng.last_time)) / 1000.0;
        eng.last_time = frame_start;

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
                        // Animation controls
                        if (key_event.scancode == .one) {
                            _ = animator.crossFade("walk", 0.3);
                            current_animation = "walk";
                            std.debug.print("Playing: walk\n", .{});
                        }
                        if (key_event.scancode == .two) {
                            _ = animator.crossFade("idle", 0.3);
                            current_animation = "idle";
                            std.debug.print("Playing: idle\n", .{});
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

            var title_buffer: [256]u8 = undefined;
            const title = std.fmt.bufPrintZ(&title_buffer, "ZDL Animation Demo - FPS: {d:.1} | Animation: {s}", .{ eng.fps_current, current_animation }) catch "ZDL";
            eng.window.setTitle(title) catch {};
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

                // Render debug draw
                if (show_debug_draw and debug_draw.isGpuInitialized()) {
                    const camera = scene.getActiveCamera();
                    if (scene.getComponent(CameraComponent, camera)) |cam| {
                        if (scene.getComponent(TransformComponent, camera)) |cam_transform| {
                            const aspect = @as(f32, @floatFromInt(eng.window_width)) / @as(f32, @floatFromInt(eng.window_height));
                            const proj = Mat4.perspective(cam.fov, aspect, cam.near, cam.far);

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

    // Update animator
    animator.update(delta_time);

    // Get world transforms for bone visualization
    const world_transforms = animator.world_transforms;

    // Update bone entity positions based on skeleton
    for (0..3) |i| {
        if (scene.getComponent(TransformComponent, bone_entities[i])) |transform| {
            // Extract position from world transform matrix
            const world_mat = world_transforms[i];
            transform.setPosition(Vec3.init(
                world_mat.data[12],
                world_mat.data[13],
                world_mat.data[14],
            ));
        }
    }

    // Draw debug visualization
    if (show_debug_draw) {
        // Draw skeleton bones as lines
        for (skeleton.bones, 0..) |bone, i| {
            const world_pos = Vec3.init(
                world_transforms[i].data[12],
                world_transforms[i].data[13],
                world_transforms[i].data[14],
            );

            // Draw joint sphere
            debug_draw.wireSphere(world_pos, 0.1, Color.init(1, 1, 0, 1));

            // Draw bone to parent
            if (bone.parent != 255) { // NO_BONE
                const parent_pos = Vec3.init(
                    world_transforms[bone.parent].data[12],
                    world_transforms[bone.parent].data[13],
                    world_transforms[bone.parent].data[14],
                );
                debug_draw.line(parent_pos, world_pos, Color.init(0, 1, 1, 1));
            }

            // Draw local axes at each bone
            debug_draw.axes(world_pos, 0.3);
        }

        // Draw grid
        debug_draw.grid(Vec3.init(0, 0, 0), 10, 10, Color.init(0.3, 0.3, 0.3, 0.5));

        // Draw origin axes
        debug_draw.axes(Vec3.zero(), 1.0);
    }

    debug_draw.update(delta_time);
}
