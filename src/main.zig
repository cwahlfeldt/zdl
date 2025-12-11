const std = @import("std");
const sdl = @import("sdl3");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try sdl.init(.{ .video = true });
    defer sdl.quit(.{ .video = true });

    const window = try sdl.video.Window.init(
        "Hello, Triangle!",
        960,
        540,
        .{ .resizable = true },
    );
    defer window.deinit();

    const device = try sdl.gpu.Device.init(
        .{ .msl = true }, // Metal on macOS (use .spirv on Linux/Windows)
        false,
        null,
    );
    defer device.deinit();

    try device.claimWindow(window);

    // Vertex structure: position (vec3) + color (vec4)
    const Vertex = struct {
        x: f32,
        y: f32,
        z: f32, // Position
        r: f32,
        g: f32,
        b: f32,
        a: f32, // Color
    };

    // Triangle vertices in NDC (Normalized Device Coordinates)
    // (0,0) is center, (1,1) is top-right, (-1,-1) is bottom-left
    const vertices = [_]Vertex{
        .{ .x = 0.0, .y = 0.5, .z = 0.0, .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 }, // Top (red)
        .{ .x = -0.5, .y = -0.5, .z = 0.0, .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 }, // Bottom-left (yellow)
        .{ .x = 0.5, .y = -0.5, .z = 0.0, .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 }, // Bottom-right (magenta)
    };

    // Create vertex buffer (once, outside the loop)
    const vertex_buffer = try device.createBuffer(.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(@TypeOf(vertices)),
    });
    defer device.releaseBuffer(vertex_buffer);

    const metal_source = try std.fs.cwd().readFileAlloc(
        allocator,
        "src/shaders/shaders.metal",
        1024 * 1024,
    );
    defer allocator.free(metal_source);

    // Create shaders from Metal source
    const vertex_shader = try device.createShader(.{
        .code = metal_source,
        .entry_point = "vertex_main",
        .format = .{ .msl = true },
        .stage = .vertex,
        .num_samplers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
        .num_uniform_buffers = 0,
    });
    defer device.releaseShader(vertex_shader);

    const fragment_shader = try device.createShader(.{
        .code = metal_source,
        .entry_point = "fragment_main",
        .format = .{ .msl = true },
        .stage = .fragment,
        .num_samplers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
        .num_uniform_buffers = 0,
    });
    defer device.releaseShader(fragment_shader);

    // Upload vertex data to GPU
    const transfer_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = @sizeOf(@TypeOf(vertices)),
    });
    defer device.releaseTransferBuffer(transfer_buffer);

    // Map and fill transfer buffer
    const data = try device.mapTransferBuffer(transfer_buffer, false);
    const vertex_data = @as([*]Vertex, @ptrCast(@alignCast(data)));
    for (vertices, 0..) |v, i| {
        vertex_data[i] = v;
    }
    device.unmapTransferBuffer(transfer_buffer);

    // Upload to GPU using copy pass
    const upload_cmd = try device.acquireCommandBuffer();
    {
        const copy_pass = upload_cmd.beginCopyPass();
        defer copy_pass.end();

        copy_pass.uploadToBuffer(
            .{ .transfer_buffer = transfer_buffer, .offset = 0 },
            .{ .buffer = vertex_buffer, .offset = 0, .size = @sizeOf(@TypeOf(vertices)) },
            false,
        );
    }
    try upload_cmd.submit();

    // Vertex buffer description
    const vertex_buffer_desc = sdl.gpu.VertexBufferDescription{
        .slot = 0,
        .pitch = @sizeOf(Vertex),
        .input_rate = .vertex,
        .instance_step_rate = 0,
    };

    // Vertex attributes
    const vertex_attributes = [_]sdl.gpu.VertexAttribute{
        // Position at location 0
        .{
            .location = 0,
            .buffer_slot = 0,
            .format = .f32x3,
            .offset = 0,
        },
        // Color at location 1
        .{
            .location = 1,
            .buffer_slot = 0,
            .format = .f32x4,
            .offset = @offsetOf(Vertex, "r"),
        },
    };

    // Color target description
    const color_target_desc = sdl.gpu.ColorTargetDescription{
        .format = try device.getSwapchainTextureFormat(window),
        .blend_state = .{
            .enable_blend = true,
            .color_blend = .add,
            .alpha_blend = .add,
            .source_color = .src_alpha,
            .source_alpha = .src_alpha,
            .destination_color = .one_minus_src_alpha,
            .destination_alpha = .one_minus_src_alpha,
            .enable_color_write_mask = true,
            .color_write_mask = .{ .red = true, .green = true, .blue = true, .alpha = true },
        },
    };

    // Create graphics pipeline
    const pipeline = try device.createGraphicsPipeline(.{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .primitive_type = .triangle_list,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{vertex_buffer_desc},
            .vertex_attributes = &vertex_attributes,
        },
        .target_info = .{
            .color_target_descriptions = &[_]sdl.gpu.ColorTargetDescription{color_target_desc},
            .depth_stencil_format = null,
        },
    });
    defer device.releaseGraphicsPipeline(pipeline);

    var running = true;
    while (running) {
        while (sdl.events.poll()) |event| {
            switch (event) {
                .quit, .key_down => running = false,
                else => {},
            }
        }

        // Acquire command buffer
        const cmd = try device.acquireCommandBuffer();

        // Get swapchain texture (returns tuple: ?texture, width, height)
        const swapchain_texture_opt, const width, const height = try cmd.waitAndAcquireSwapchainTexture(window);
        const swapchain_texture = swapchain_texture_opt orelse {
            try cmd.submit();
            continue;
        };
        _ = width;
        _ = height;

        // Create color target
        const color_target = sdl.gpu.ColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{ .r = 0.94, .g = 0.94, .b = 0.94, .a = 1.0 },
            .load = .clear,
            .store = .store,
        };

        // Render pass
        {
            const pass = cmd.beginRenderPass(&.{color_target}, null);
            defer pass.end();

            // Bind pipeline
            pass.bindGraphicsPipeline(pipeline);

            // Bind vertex buffer
            pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
                .buffer = vertex_buffer,
                .offset = 0,
            }});

            // Draw 3 vertices in 1 instance
            pass.drawPrimitives(3, 1, 0, 0);
        }

        try cmd.submit();

        sdl.timer.delayMilliseconds(16); // ~60 FPS
    }
}
