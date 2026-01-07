const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const engine = @import("engine");

const Engine = engine.Engine;
const Scene = engine.Scene;
const Input = engine.Input;
const Vec3 = engine.Vec3;
const Mat4 = engine.Mat4;
const TransformComponent = engine.TransformComponent;
const CameraComponent = engine.CameraComponent;
const FpvCameraController = engine.FpvCameraController;
const Uniforms = engine.Uniforms;
const primitives = engine.primitives;
const Mesh = engine.Mesh;

const is_macos = builtin.os.tag == .macos;

const RaymarchShaderConfig = if (is_macos) struct {
    const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
    const vertex_path = "assets/shaders/raymarch_pbr.metal";
    const fragment_path = "assets/shaders/raymarch_pbr.metal";
    const vertex_entry = "raymarch_vertex_main";
    const fragment_entry = "raymarch_fragment_main";
} else struct {
    const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
    const vertex_path = "build/assets/shaders/raymarch_pbr.vert.spv";
    const fragment_path = "build/assets/shaders/raymarch_pbr.frag.spv";
    const vertex_entry = "main";
    const fragment_entry = "main";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var eng = try Engine.init(allocator, .{
        .window_title = "ZDL - Raymarch PBR + IBL Demo",
        .window_width = 1280,
        .window_height = 720,
        .target_fps = 100,
        .clear_color = .{ .r = 0.02, .g = 0.02, .b = 0.05, .a = 1.0 },
    });
    defer eng.deinit();

    // Initialize IBL + skybox
    std.debug.print("Generating BRDF LUT...\n", .{});
    try eng.initIBL();
    std.debug.print("IBL initialized: {}\n", .{eng.hasIBL()});

    std.debug.print("Loading HDR environment map...\n", .{});
    const hdr_rel_path = "assets/textures/kloppenheim_06_1k.hdr";
    const hdr_path = try std.fs.cwd().realpathAlloc(allocator, hdr_rel_path);
    defer allocator.free(hdr_path);
    if (eng.loadHDREnvironment(hdr_path)) |_| {
        std.debug.print("HDR environment loaded successfully!\n", .{});
    } else |err| {
        std.debug.print("Warning: Failed to load HDR environment: {}\n", .{err});
        std.debug.print("Falling back to default neutral environment\n", .{});
    }

    // Build raymarch pipeline
    const raymarch_pipeline = try createRaymarchPipeline(&eng, allocator);
    defer eng.device.releaseGraphicsPipeline(raymarch_pipeline);

    // Create a unit cube mesh as the raymarch bounds
    var cube_mesh = try primitives.createCube(allocator);
    defer cube_mesh.deinit(&eng.device);
    try cube_mesh.upload(&eng.device);

    // Set up a minimal scene for camera + controls
    var scene = Scene.init(allocator);
    defer scene.deinit();

    const camera_entity = scene.createEntity();
    var camera_transform = TransformComponent.withPosition(Vec3.init(4.5, 2.2, 4.5));
    camera_transform.lookAt(Vec3.init(0.25, 0.3, -0.5), Vec3.init(0, 1, 0));
    scene.addComponent(camera_entity, camera_transform);
    scene.addComponent(camera_entity, CameraComponent.init());
    scene.setActiveCamera(camera_entity);

    var fpv_controller = FpvCameraController.initWithConfig(.{
        .sensitivity = 0.003,
        .move_speed = 3.5,
        .capture_on_click = true,
    });
    const look_dir = Vec3.init(0.25, 0.3, -0.5).sub(Vec3.init(4.5, 2.2, 4.5)).normalize();
    fpv_controller.lookAt(look_dir);
    scene.addComponent(camera_entity, fpv_controller);

    // Set basic lighting
    eng.light_uniforms.setDirectionalLight(Vec3.init(0.5, 1.0, 0.3), Vec3.init(1.0, 1.0, 1.0), 4.0);
    eng.light_uniforms.setAmbient(Vec3.init(0.08, 0.08, 0.1), 1.0);
    eng.light_uniforms.setIBLEnabled(true);

    std.debug.print("\n=== Raymarch PBR + IBL Demo ===\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
    std.debug.print("  Q/E - Move camera up/down\n", .{});
    std.debug.print("  ESC - Release mouse / Quit\n\n", .{});

    try runLoop(&eng, &scene, raymarch_pipeline, &cube_mesh);
}

fn createRaymarchPipeline(eng: *Engine, allocator: std.mem.Allocator) !sdl.gpu.GraphicsPipeline {
    const vertex_code = try std.fs.cwd().readFileAlloc(
        allocator,
        RaymarchShaderConfig.vertex_path,
        1024 * 1024,
    );
    defer allocator.free(vertex_code);

    const fragment_code = if (is_macos)
        vertex_code
    else
        try std.fs.cwd().readFileAlloc(
            allocator,
            RaymarchShaderConfig.fragment_path,
            1024 * 1024,
        );
    defer if (!is_macos) allocator.free(fragment_code);

    const vertex_shader = try eng.device.createShader(.{
        .code = vertex_code,
        .entry_point = RaymarchShaderConfig.vertex_entry,
        .format = RaymarchShaderConfig.format,
        .stage = .vertex,
        .num_samplers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
        .num_uniform_buffers = 1,
    });
    defer eng.device.releaseShader(vertex_shader);

    const fragment_shader = try eng.device.createShader(.{
        .code = fragment_code,
        .entry_point = RaymarchShaderConfig.fragment_entry,
        .format = RaymarchShaderConfig.format,
        .stage = .fragment,
        .num_samplers = 8, // IBL textures are bound at slots 5-7
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
        .num_uniform_buffers = 2, // light uniforms at slot 1
    });
    defer eng.device.releaseShader(fragment_shader);

    const vertex_buffer_desc = Mesh.getVertexBufferDesc();
    const vertex_attributes = Mesh.getVertexAttributes();

    const color_target_desc = sdl.gpu.ColorTargetDescription{
        .format = try eng.device.getSwapchainTextureFormat(eng.window),
        .blend_state = .{
            .enable_blend = false,
            .color_blend = .add,
            .alpha_blend = .add,
            .source_color = .one,
            .source_alpha = .one,
            .destination_color = .zero,
            .destination_alpha = .zero,
            .enable_color_write_mask = true,
            .color_write_mask = .{ .red = true, .green = true, .blue = true, .alpha = true },
        },
    };

    return eng.device.createGraphicsPipeline(.{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .primitive_type = .triangle_list,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{vertex_buffer_desc},
            .vertex_attributes = &vertex_attributes,
        },
        .rasterizer_state = .{
            .cull_mode = .back,
            .front_face = .counter_clockwise,
        },
        .target_info = .{
            .color_target_descriptions = &[_]sdl.gpu.ColorTargetDescription{color_target_desc},
            .depth_stencil_format = .depth32_float,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare = .less,
            .enable_stencil_test = false,
        },
    });
}

fn runLoop(eng: *Engine, scene: *Scene, raymarch_pipeline: sdl.gpu.GraphicsPipeline, cube_mesh: *Mesh) !void {
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
                    try eng.input.processEvent(event);
                },
                .key_up => try eng.input.processEvent(event),
                .mouse_motion, .mouse_button_down, .mouse_button_up => try eng.input.processEvent(event),
                else => {},
            }
        }

        try update(eng, scene, &eng.input, delta_time);
        scene.updateWorldTransforms();

        // Render
        if (try eng.beginFrame()) |frame_value| {
            var frame = frame_value;

            const camera_entity = scene.getActiveCamera();
            const camera = scene.getComponent(CameraComponent, camera_entity) orelse {
                try frame.end();
                continue;
            };
            const camera_transform = scene.getComponent(TransformComponent, camera_entity) orelse {
                try frame.end();
                continue;
            };

            const width: f32 = @floatFromInt(eng.window_width);
            const height: f32 = @floatFromInt(eng.window_height);
            const aspect = width / height;

            const cam_pos = Vec3.init(
                camera_transform.world_matrix.data[12],
                camera_transform.world_matrix.data[13],
                camera_transform.world_matrix.data[14],
            );
            const cam_forward = Vec3.init(
                -camera_transform.world_matrix.data[8],
                -camera_transform.world_matrix.data[9],
                -camera_transform.world_matrix.data[10],
            );
            const cam_target = cam_pos.add(cam_forward);
            const view = Mat4.lookAt(cam_pos, cam_target, Vec3.init(0, 1, 0));
            const projection = camera.getProjectionMatrix(aspect);

            eng.light_uniforms.setCameraPosition(cam_pos);

            // Draw skybox for IBL
            frame.drawSkybox(view, projection);

            // Draw raymarched bounds cube
            frame.pass.bindGraphicsPipeline(raymarch_pipeline);
            const model = Mat4.scale(6.0, 3.0, 6.0);
            const uniforms = Uniforms.init(model, view, projection);
            frame.pushUniforms(uniforms);
            frame.pushLightUniforms(eng.light_uniforms);
            frame.bindDefaultPBRTextures();
            frame.bindIBLTextures();
            frame.drawMesh(cube_mesh.*);

            try frame.end();
        }

        // Frame rate limiting
        const frame_end = sdl.timer.getMillisecondsSinceInit();
        const frame_time = frame_end - frame_start;
        if (frame_time < eng.target_frame_time) {
            sdl.timer.delayMilliseconds(@intCast(eng.target_frame_time - frame_time));
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
}
