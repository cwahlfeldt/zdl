const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const Application = @import("application.zig").Application;
const Context = @import("application.zig").Context;
const Input = @import("../input/input.zig").Input;
const Camera2D = @import("../camera.zig").Camera2D;
const sprite = @import("../renderer/sprite.zig");
const SpriteBatch = sprite.SpriteBatch;
const SpriteVertex = sprite.SpriteVertex;
const MVPUniforms = @import("../gpu/uniforms.zig").MVPUniforms;
const Texture = @import("../resources/texture.zig").Texture;
const Audio = @import("../audio/audio.zig").Audio;

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

pub const EngineConfig = struct {
    window_title: [:0]const u8 = "ZDL Game",
    window_width: u32 = 960,
    window_height: u32 = 540,
    target_fps: u32 = 60,
};

/// Main engine that manages SDL, GPU, and the game loop
pub const Engine = struct {
    allocator: std.mem.Allocator,
    window: sdl.video.Window,
    device: sdl.gpu.Device,
    input: Input,
    camera: Camera2D,
    sprite_batch: SpriteBatch,
    audio: Audio,

    // GPU Resources
    vertex_buffer: sdl.gpu.Buffer,
    transfer_buffer: sdl.gpu.TransferBuffer,
    pipeline: sdl.gpu.GraphicsPipeline,
    white_texture: Texture,
    sampler: sdl.gpu.Sampler,

    // Timing
    last_time: u64,

    pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Engine {
        try sdl.init(.{ .video = true });
        errdefer sdl.quit(.{ .video = true });

        const window = try sdl.video.Window.init(
            config.window_title,
            config.window_width,
            config.window_height,
            .{ .resizable = true },
        );
        errdefer window.deinit();

        const device = try sdl.gpu.Device.init(
            ShaderConfig.format,
            true,
            null,
        );
        errdefer device.deinit();

        try device.claimWindow(window);

        var input = Input.init(allocator);
        errdefer input.deinit();

        const camera = Camera2D.init(
            @floatFromInt(config.window_width),
            @floatFromInt(config.window_height),
        );

        var sprite_batch = SpriteBatch.init(allocator, 1000);
        errdefer sprite_batch.deinit();

        var audio = try Audio.init(allocator);
        errdefer audio.deinit();

        // Create GPU resources
        const max_vertices = 6000;
        const vertex_buffer = try device.createBuffer(.{
            .usage = .{ .vertex = true },
            .size = @sizeOf(SpriteVertex) * max_vertices,
        });
        errdefer device.releaseBuffer(vertex_buffer);

        const transfer_buffer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = @sizeOf(SpriteVertex) * max_vertices,
        });
        errdefer device.releaseTransferBuffer(transfer_buffer);

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
            .num_uniform_buffers = 1,
        });
        defer device.releaseShader(vertex_shader);

        const fragment_shader = try device.createShader(.{
            .code = fragment_code,
            .entry_point = ShaderConfig.fragment_entry,
            .format = ShaderConfig.format,
            .stage = .fragment,
            .num_samplers = 1,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 0,
        });
        defer device.releaseShader(fragment_shader);

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
            .{
                .location = 2,
                .buffer_slot = 0,
                .format = .f32x2,
                .offset = @offsetOf(SpriteVertex, "u"),
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
        errdefer device.releaseGraphicsPipeline(pipeline);

        var mutable_device = device;
        const white_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 255, 255, 255, 255 });
        errdefer white_texture.deinit(&mutable_device);

        const sampler = try device.createSampler(.{
            .min_filter = .nearest,
            .mag_filter = .nearest,
            .mipmap_mode = .nearest,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
        });
        errdefer device.releaseSampler(sampler);

        const last_time = sdl.timer.getMillisecondsSinceInit();

        return .{
            .allocator = allocator,
            .window = window,
            .device = device,
            .input = input,
            .camera = camera,
            .sprite_batch = sprite_batch,
            .audio = audio,
            .vertex_buffer = vertex_buffer,
            .transfer_buffer = transfer_buffer,
            .pipeline = pipeline,
            .white_texture = white_texture,
            .sampler = sampler,
            .last_time = last_time,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.audio.deinit();
        self.device.releaseSampler(self.sampler);
        var mutable_device = self.device;
        self.white_texture.deinit(&mutable_device);
        self.device.releaseGraphicsPipeline(self.pipeline);
        self.device.releaseTransferBuffer(self.transfer_buffer);
        self.device.releaseBuffer(self.vertex_buffer);
        self.sprite_batch.deinit();
        self.input.deinit();
        self.device.deinit();
        self.window.deinit();
        sdl.quit(.{ .video = true });
    }

    /// Run the game loop with the provided application
    pub fn run(self: *Engine, app: Application) !void {
        var ctx = Context{
            .allocator = self.allocator,
            .input = &self.input,
            .camera = &self.camera,
            .sprite_batch = &self.sprite_batch,
            .audio = &self.audio,
            .device = &self.device,
            .window = &self.window,
            .vertex_buffer = &self.vertex_buffer,
            .transfer_buffer = &self.transfer_buffer,
            .pipeline = &self.pipeline,
            .white_texture = &self.white_texture,
            .sampler = &self.sampler,
        };

        try app.init(&ctx);
        defer app.deinit(&ctx);

        var running = true;
        while (running) {
            const current_time = sdl.timer.getMillisecondsSinceInit();
            const delta_time = @as(f32, @floatFromInt(current_time - self.last_time)) / 1000.0;
            self.last_time = current_time;

            self.input.update();

            while (sdl.events.poll()) |event| {
                switch (event) {
                    .quit => running = false,
                    .key_down => |key_event| {
                        if (key_event.scancode == .escape) running = false;
                        try self.input.processEvent(event);
                    },
                    .key_up => try self.input.processEvent(event),
                    else => {},
                }
            }

            try app.update(&ctx, delta_time);

            self.sprite_batch.clear();
            try app.render(&ctx);

            // try self.renderFrame();
        }
    }

    /// Get the sprite batch for rendering
    pub fn getSpriteBatch(self: *Engine) *SpriteBatch {
        return &self.sprite_batch;
    }

    fn renderFrame(self: *Engine) !void {
        // 1. Acquire the SINGLE command buffer for this frame
        const cmd = try self.device.acquireCommandBuffer();

        // 2. Handle Vertex Upload (ON THE SAME COMMAND BUFFER)
        const vertices = self.sprite_batch.getVertices();
        if (vertices.len > 0) {
            // Map/Unmap transfer buffer (CPU side)
            const data = try self.device.mapTransferBuffer(self.transfer_buffer, false);
            const vertex_data = @as([*]SpriteVertex, @ptrCast(@alignCast(data)));
            for (vertices, 0..) |v, i| {
                vertex_data[i] = v;
            }
            self.device.unmapTransferBuffer(self.transfer_buffer);

            // Encode Copy Pass (GPU side)
            const copy_pass = cmd.beginCopyPass();
            const size: u32 = @intCast(@sizeOf(SpriteVertex) * vertices.len);
            copy_pass.uploadToBuffer(
                .{ .transfer_buffer = self.transfer_buffer, .offset = 0 },
                .{ .buffer = self.vertex_buffer, .offset = 0, .size = size },
                true,
            );
            copy_pass.end();
            // The GPU now guarantees this copy finishes before subsequent commands on 'cmd' read this buffer.
        }

        // 3. Acquire Swapchain
        const swapchain_texture_opt, const width, const height = try cmd.waitAndAcquireSwapchainTexture(self.window);
        const swapchain_texture = swapchain_texture_opt orelse {
            try cmd.submit(); // Submit whatever we did (like uploads) even if we don't draw
            return;
        };

        // 4. Update Camera
        const w_f32: f32 = @floatFromInt(width);
        const h_f32: f32 = @floatFromInt(height);
        if (self.camera.width != w_f32 or self.camera.height != h_f32) {
            self.camera.resize(w_f32, h_f32);
        }

        const color_target = sdl.gpu.ColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 },
            .load = .clear,
            .store = .store,
        };

        // 5. Render Pass
        {
            const pass = cmd.beginRenderPass(&.{color_target}, null);
            defer pass.end();

            pass.bindGraphicsPipeline(self.pipeline);

            pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
                .texture = self.white_texture.gpu_texture,
                .sampler = self.sampler,
            }});

            pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
                .buffer = self.vertex_buffer,
                .offset = 0,
            }});

            // --- FIX 1: Push Uniforms INSIDE the pass ---
            const mvp = self.camera.getViewProjectionMatrix();
            const uniform_data = MVPUniforms.init(mvp);
            // Ensure MVPUniforms is an 'extern struct' in uniforms.zig!
            const uniform_bytes = std.mem.asBytes(&uniform_data);

            cmd.pushVertexUniformData(1, uniform_bytes);
            // --------------------------------------------

            const vertex_count = self.sprite_batch.getVertexCount();
            if (vertex_count > 0) {
                pass.drawPrimitives(vertex_count, 1, 0, 0);
            }
        }

        try cmd.submit();
    }
};
