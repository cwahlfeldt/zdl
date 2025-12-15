const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const math = @import("math/math.zig");
const Input = @import("input/input.zig").Input;
const Camera2D = @import("camera.zig").Camera2D;
const sprite = @import("renderer/sprite.zig");
const SpriteBatch = sprite.SpriteBatch;
const Color = sprite.Color;
const SpriteVertex = sprite.SpriteVertex;
const Vec2 = math.Vec2;
const Mat4 = math.Mat4;
const MVPUniforms = @import("gpu/uniforms.zig").MVPUniforms;

// Platform-specific shader configuration
const is_macos = builtin.os.tag == .macos;
const ShaderConfig = if (is_macos) struct {
    const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
    const vertex_path = "src/shaders/shaders.metal";
    const fragment_path = "src/shaders/shaders.metal";
    const vertex_entry = "vertex_main";
    const fragment_entry = "fragment_main";
} else struct {
    const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
    const vertex_path = "src/shaders/vertex.spv";
    const fragment_path = "src/shaders/fragment.spv";
    const vertex_entry = "main";
    const fragment_entry = "main";
};

// Simple AABB for collision detection
const AABB = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    fn intersects(self: AABB, other: AABB) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    fn fromCenter(x: f32, y: f32, width: f32, height: f32) AABB {
        return .{
            .x = x - width / 2.0,
            .y = y - height / 2.0,
            .width = width,
            .height = height,
        };
    }
};

// Player entity
const Player = struct {
    position: Vec2,
    velocity: Vec2,
    width: f32,
    height: f32,
    speed: f32,

    fn init() Player {
        return .{
            .position = Vec2.init(0, 0),
            .velocity = Vec2.zero(),
            .width = 50,
            .height = 50,
            .speed = 200,
        };
    }

    fn update(self: *Player, input: *Input, delta_time: f32, platforms: []const AABB) void {
        // Get input (support both WASD and arrow keys)
        const wasd = input.getWASD();
        const arrows = input.getArrowKeys();
        const move_input = .{
            .x = wasd.x + arrows.x,
            .y = wasd.y + arrows.y,
        };

        // Update velocity based on input
        self.velocity.x = move_input.x * self.speed;
        self.velocity.y = move_input.y * self.speed;

        // Apply movement
        const next_pos = Vec2.add(self.position, self.velocity.mul(delta_time));

        // Check collision with platforms
        const player_aabb = AABB.fromCenter(next_pos.x, next_pos.y, self.width, self.height);

        var collided = false;
        for (platforms) |platform| {
            if (player_aabb.intersects(platform)) {
                collided = true;
                break;
            }
        }

        // Only update position if no collision
        if (!collided) {
            self.position = next_pos;
        }
    }

    fn getAABB(self: Player) AABB {
        return AABB.fromCenter(self.position.x, self.position.y, self.width, self.height);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try sdl.init(.{ .video = true });
    defer sdl.quit(.{ .video = true });

    const window = try sdl.video.Window.init(
        "Phase 1: Moving Player",
        960,
        540,
        .{ .resizable = true },
    );
    defer window.deinit();

    const device = try sdl.gpu.Device.init(
        ShaderConfig.format,
        true,
        null,
    );
    defer device.deinit();

    try device.claimWindow(window);

    // Initialize game systems
    var input = Input.init(allocator);
    defer input.deinit();

    var camera = Camera2D.init(960, 540);
    var player = Player.init();

    // Create platforms for collision testing
    const platforms = [_]AABB{
        .{ .x = -200, .y = 100, .width = 400, .height = 50 }, // Top platform
        .{ .x = -200, .y = -150, .width = 400, .height = 50 }, // Bottom platform
        .{ .x = -250, .y = -100, .width = 50, .height = 200 }, // Left wall
        .{ .x = 200, .y = -100, .width = 50, .height = 200 }, // Right wall
    };

    var sprite_batch = SpriteBatch.init(allocator, 1000);
    defer sprite_batch.deinit();

    // Create vertex buffer for sprites
    const max_vertices = 6000; // 1000 quads * 6 vertices
    const vertex_buffer = try device.createBuffer(.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(SpriteVertex) * max_vertices,
    });
    defer device.releaseBuffer(vertex_buffer);

    // Create transfer buffer for uploading sprite data
    const transfer_buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = @sizeOf(SpriteVertex) * max_vertices,
    });
    defer device.releaseTransferBuffer(transfer_buffer);

    // Load shaders
    const vertex_code = try std.fs.cwd().readFileAlloc(
        allocator,
        ShaderConfig.vertex_path,
        1024 * 1024,
    );
    defer allocator.free(vertex_code);

    const fragment_code = if (is_macos)
        vertex_code
    else
        try std.fs.cwd().readFileAlloc(
            allocator,
            ShaderConfig.fragment_path,
            1024 * 1024,
        );
    defer if (!is_macos) allocator.free(fragment_code);

    const vertex_shader = try device.createShader(.{
        .code = vertex_code,
        .entry_point = ShaderConfig.vertex_entry,
        .format = ShaderConfig.format,
        .stage = .vertex,
        .num_samplers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
        .num_uniform_buffers = 1, // MVP matrix uniform
    });
    defer device.releaseShader(vertex_shader);

    const fragment_shader = try device.createShader(.{
        .code = fragment_code,
        .entry_point = ShaderConfig.fragment_entry,
        .format = ShaderConfig.format,
        .stage = .fragment,
        .num_samplers = 0,
        .num_storage_buffers = 0,
        .num_storage_textures = 0,
        .num_uniform_buffers = 0,
    });
    defer device.releaseShader(fragment_shader);

    // Vertex buffer description
    const vertex_buffer_desc = sdl.gpu.VertexBufferDescription{
        .slot = 0,
        .pitch = @sizeOf(SpriteVertex),
        .input_rate = .vertex,
        .instance_step_rate = 0,
    };

    const vertex_attributes = [_]sdl.gpu.VertexAttribute{
        .{
            .location = 0,
            .buffer_slot = 0,
            .format = .f32x3,
            .offset = 0,
        },
        .{
            .location = 1,
            .buffer_slot = 0,
            .format = .f32x4,
            .offset = @offsetOf(SpriteVertex, "r"),
        },
    };

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

    // Timing
    var last_time = sdl.timer.getMillisecondsSinceInit();

    var running = true;
    while (running) {
        // Update timing
        const current_time = sdl.timer.getMillisecondsSinceInit();
        const delta_time = @as(f32, @floatFromInt(current_time - last_time)) / 1000.0;
        last_time = current_time;

        // Update input
        input.update();

        // Process events
        while (sdl.events.poll()) |event| {
            switch (event) {
                .quit => running = false,
                .key_down => |key_event| {
                    if (key_event.scancode == .escape) running = false;
                    try input.processEvent(event);
                },
                .key_up => try input.processEvent(event),
                else => {},
            }
        }

        // Update game
        player.update(&input, delta_time, &platforms);

        // Render
        sprite_batch.clear();

        // Draw platforms
        for (platforms) |platform| {
            try sprite_batch.addQuad(
                platform.x + platform.width / 2.0,
                platform.y + platform.height / 2.0,
                platform.width,
                platform.height,
                Color.blue(),
            );
        }

        // Draw player
        try sprite_batch.addQuad(
            player.position.x,
            player.position.y,
            player.width,
            player.height,
            Color.red(),
        );

        // Upload sprite data to GPU
        const vertices = sprite_batch.getVertices();
        if (vertices.len > 0) {
            const data = try device.mapTransferBuffer(transfer_buffer, false);
            const vertex_data = @as([*]SpriteVertex, @ptrCast(@alignCast(data)));
            for (vertices, 0..) |v, i| {
                vertex_data[i] = v;
            }
            device.unmapTransferBuffer(transfer_buffer);

            const upload_cmd = try device.acquireCommandBuffer();
            {
                const copy_pass = upload_cmd.beginCopyPass();
                defer copy_pass.end();

                const size: u32 = @intCast(@sizeOf(SpriteVertex) * vertices.len);
                copy_pass.uploadToBuffer(
                    .{ .transfer_buffer = transfer_buffer, .offset = 0 },
                    .{ .buffer = vertex_buffer, .offset = 0, .size = size },
                    false,
                );
            }
            try upload_cmd.submit();
        }

        // Render
        const cmd = try device.acquireCommandBuffer();

        const swapchain_texture_opt, const width, const height = try cmd.waitAndAcquireSwapchainTexture(window);
        const swapchain_texture = swapchain_texture_opt orelse {
            try cmd.submit();
            continue;
        };

        // Update camera size if window was resized
        const w_f32: f32 = @floatFromInt(width);
        const h_f32: f32 = @floatFromInt(height);
        if (camera.width != w_f32 or camera.height != h_f32) {
            camera.resize(w_f32, h_f32);
        }

        const color_target = sdl.gpu.ColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 },
            .load = .clear,
            .store = .store,
        };

        // Prepare uniform data
        const mvp = camera.getViewProjectionMatrix();

        // Debug: Print matrix once at startup
        {
            const frame_count_static = struct {
                var count: u32 = 0;
            };
            if (frame_count_static.count == 0) {
                std.debug.print("MVP Matrix:\n", .{});
                std.debug.print("  [{d:.4}, {d:.4}, {d:.4}, {d:.4}]\n", .{mvp.data[0], mvp.data[1], mvp.data[2], mvp.data[3]});
                std.debug.print("  [{d:.4}, {d:.4}, {d:.4}, {d:.4}]\n", .{mvp.data[4], mvp.data[5], mvp.data[6], mvp.data[7]});
                std.debug.print("  [{d:.4}, {d:.4}, {d:.4}, {d:.4}]\n", .{mvp.data[8], mvp.data[9], mvp.data[10], mvp.data[11]});
                std.debug.print("  [{d:.4}, {d:.4}, {d:.4}, {d:.4}]\n", .{mvp.data[12], mvp.data[13], mvp.data[14], mvp.data[15]});
                std.debug.print("Camera: pos=({d:.2}, {d:.2}), size=({d:.2}x{d:.2})\n", .{camera.position.x, camera.position.y, camera.width, camera.height});
                std.debug.print("Player: pos=({d:.2}, {d:.2})\n", .{player.position.x, player.position.y});
                frame_count_static.count += 1;
            }
        }

        const uniform_data = MVPUniforms.init(mvp);
        const uniform_bytes = std.mem.asBytes(&uniform_data);

        // Push uniform data before render pass
        cmd.pushVertexUniformData(0, uniform_bytes);

        {
            const pass = cmd.beginRenderPass(&.{color_target}, null);
            defer pass.end();

            pass.bindGraphicsPipeline(pipeline);

            pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
                .buffer = vertex_buffer,
                .offset = 0,
            }});

            const vertex_count = sprite_batch.getVertexCount();
            if (vertex_count > 0) {
                pass.drawPrimitives(vertex_count, 1, 0, 0);
            }
        }

        try cmd.submit();

        sdl.timer.delayMilliseconds(10);
    }
}
