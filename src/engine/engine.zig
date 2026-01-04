const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const Input = @import("../input/input.zig").Input;
const Mesh = @import("../resources/mesh.zig").Mesh;
const Vertex3D = @import("../resources/mesh.zig").Vertex3D;
const Uniforms = @import("../gpu/uniforms.zig").Uniforms;
const LightUniforms = @import("../gpu/uniforms.zig").LightUniforms;
const Texture = @import("../resources/texture.zig").Texture;
const Material = @import("../resources/material.zig").Material;
const MaterialUniforms = @import("../resources/material.zig").MaterialUniforms;
const Audio = @import("../audio/audio.zig").Audio;

// ECS imports
const Scene = @import("../ecs/scene.zig").Scene;
const RenderSystem = @import("../ecs/systems/render_system.zig").RenderSystem;

// Scripting imports
const ScriptSystem = @import("../scripting/script_system.zig").ScriptSystem;

// Platform-specific shader configuration
const is_macos = builtin.os.tag == .macos;
const ShaderConfig = if (is_macos) struct {
    const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
    const vertex_path = "assets/shaders/shaders.metal";
    const fragment_path = "assets/shaders/shaders.metal";
    const vertex_entry = "vertex_main";
    const fragment_entry = "fragment_main";
} else struct {
    const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
    const vertex_path = "build/assets/shaders/vertex.spv";
    const fragment_path = "build/assets/shaders/fragment.spv";
    const vertex_entry = "main";
    const fragment_entry = "main";
};

// PBR shader configuration
const PBRShaderConfig = if (is_macos) struct {
    const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
    const vertex_path = "assets/shaders/pbr.metal";
    const fragment_path = "assets/shaders/pbr.metal";
    const vertex_entry = "pbr_vertex_main";
    const fragment_entry = "pbr_fragment_main";
} else struct {
    const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
    const vertex_path = "build/assets/shaders/pbr.vert.spv";
    const fragment_path = "build/assets/shaders/pbr.frag.spv";
    const vertex_entry = "main";
    const fragment_entry = "main";
};

/// RGBA color with floating point components (0.0 to 1.0)
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn init(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: f32, g: f32, b: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = 1.0 };
    }

    pub fn white() Color {
        return .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    }

    pub fn black() Color {
        return .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    }
};

pub const EngineConfig = struct {
    window_title: [:0]const u8 = "ZDL Game",
    window_width: u32 = 1280,
    window_height: u32 = 720,
    target_fps: u32 = 60,
    clear_color: Color = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 },
};

/// Main engine that manages SDL, GPU, and the game loop
pub const Engine = struct {
    allocator: std.mem.Allocator,
    window: sdl.video.Window,
    device: sdl.gpu.Device,
    input: Input,
    audio: Audio,

    // GPU Resources - Legacy pipeline
    pipeline: sdl.gpu.GraphicsPipeline,
    depth_texture: ?sdl.gpu.Texture,
    white_texture: Texture,
    sampler: sdl.gpu.Sampler,

    // GPU Resources - PBR pipeline
    pbr_pipeline: ?sdl.gpu.GraphicsPipeline,
    default_normal_texture: ?Texture, // Flat normal map (128, 128, 255)
    default_mr_texture: ?Texture, // Default metallic-roughness (0, 0.5, 0)
    default_ao_texture: ?Texture, // White AO texture
    default_emissive_texture: ?Texture, // Black emissive texture

    // Scene lighting (updated per frame for PBR)
    light_uniforms: LightUniforms,

    // Window state
    window_width: u32,
    window_height: u32,
    clear_color: Color,

    // Timing
    last_time: u64,
    target_frame_time: u64,

    // FPS Counter
    show_fps: bool,
    fps_frame_count: u32,
    fps_last_update: u64,
    fps_current: f32,
    original_window_title: [:0]const u8,

    // Scripting
    script_system: ?*ScriptSystem,

    // Quit flag (can be set by scripts)
    should_quit: bool,

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

        var audio = try Audio.init(allocator);
        errdefer audio.deinit();

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

        const vertex_buffer_desc = Mesh.getVertexBufferDesc();
        const vertex_attributes = Mesh.getVertexAttributes();

        const color_target_desc = sdl.gpu.ColorTargetDescription{
            .format = try device.getSwapchainTextureFormat(window),
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

        const pipeline = try device.createGraphicsPipeline(.{
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
        errdefer device.releaseGraphicsPipeline(pipeline);

        // Create depth texture
        const depth_texture = try device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .depth32_float,
            .width = config.window_width,
            .height = config.window_height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .usage = .{ .depth_stencil_target = true },
        });
        errdefer device.releaseTexture(depth_texture);

        var mutable_device = device;
        const white_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 255, 255, 255, 255 });
        errdefer white_texture.deinit(&mutable_device);

        const sampler = try device.createSampler(.{
            .min_filter = .linear,
            .mag_filter = .linear,
            .mipmap_mode = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
        });
        errdefer device.releaseSampler(sampler);

        const last_time = sdl.timer.getMillisecondsSinceInit();
        const target_frame_time = 1000 / config.target_fps;

        return .{
            .allocator = allocator,
            .window = window,
            .device = device,
            .input = input,
            .audio = audio,
            .pipeline = pipeline,
            .depth_texture = depth_texture,
            .white_texture = white_texture,
            .sampler = sampler,
            // PBR resources initialized lazily via initPBR()
            .pbr_pipeline = null,
            .default_normal_texture = null,
            .default_mr_texture = null,
            .default_ao_texture = null,
            .default_emissive_texture = null,
            .light_uniforms = LightUniforms.default(),
            .window_width = config.window_width,
            .window_height = config.window_height,
            .clear_color = config.clear_color,
            .last_time = last_time,
            .target_frame_time = target_frame_time,
            .show_fps = false,
            .fps_frame_count = 0,
            .fps_last_update = last_time,
            .fps_current = 0.0,
            .original_window_title = config.window_title,
            .script_system = null,
            .should_quit = false,
        };
    }

    /// Initialize the scripting system.
    /// Call this to enable JavaScript scripting support.
    pub fn initScripting(self: *Engine) !void {
        if (self.script_system != null) return; // Already initialized

        const script_sys = try self.allocator.create(ScriptSystem);
        script_sys.* = try ScriptSystem.init(self.allocator);
        self.script_system = script_sys;
    }

    /// Check if scripting is available.
    pub fn hasScripting(self: *Engine) bool {
        return self.script_system != null;
    }

    /// Initialize the PBR rendering pipeline and default textures.
    /// Call this before using PBR materials. Safe to call multiple times.
    pub fn initPBR(self: *Engine) !void {
        if (self.pbr_pipeline != null) return; // Already initialized

        var mutable_device = self.device;

        // Create default PBR textures
        // Flat normal map (pointing straight up in tangent space)
        self.default_normal_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 128, 128, 255, 255 });
        errdefer if (self.default_normal_texture) |t| t.deinit(&mutable_device);

        // Default metallic-roughness (non-metallic, medium roughness)
        // B=metallic, G=roughness following glTF convention
        self.default_mr_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 0, 128, 0, 255 });
        errdefer if (self.default_mr_texture) |t| t.deinit(&mutable_device);

        // White AO texture (no occlusion)
        self.default_ao_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 255, 255, 255, 255 });
        errdefer if (self.default_ao_texture) |t| t.deinit(&mutable_device);

        // Black emissive texture (no emission)
        self.default_emissive_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 0, 0, 0, 255 });
        errdefer if (self.default_emissive_texture) |t| t.deinit(&mutable_device);

        // Load PBR shaders
        const pbr_vertex_code = try std.fs.cwd().readFileAlloc(
            self.allocator,
            PBRShaderConfig.vertex_path,
            1024 * 1024,
        );
        defer self.allocator.free(pbr_vertex_code);

        const pbr_fragment_code = if (is_macos)
            pbr_vertex_code
        else
            try std.fs.cwd().readFileAlloc(
                self.allocator,
                PBRShaderConfig.fragment_path,
                1024 * 1024,
            );
        defer if (!is_macos) self.allocator.free(pbr_fragment_code);

        const pbr_vertex_shader = try self.device.createShader(.{
            .code = pbr_vertex_code,
            .entry_point = PBRShaderConfig.vertex_entry,
            .format = PBRShaderConfig.format,
            .stage = .vertex,
            .num_samplers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 1, // MVP uniforms
        });
        defer self.device.releaseShader(pbr_vertex_shader);

        const pbr_fragment_shader = try self.device.createShader(.{
            .code = pbr_fragment_code,
            .entry_point = PBRShaderConfig.fragment_entry,
            .format = PBRShaderConfig.format,
            .stage = .fragment,
            .num_samplers = 5, // base_color, normal, metallic_roughness, ao, emissive
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 2, // material + lights
        });
        defer self.device.releaseShader(pbr_fragment_shader);

        const vertex_buffer_desc = Mesh.getVertexBufferDesc();
        const vertex_attributes = Mesh.getVertexAttributes();

        const color_target_desc = sdl.gpu.ColorTargetDescription{
            .format = try self.device.getSwapchainTextureFormat(self.window),
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

        self.pbr_pipeline = try self.device.createGraphicsPipeline(.{
            .vertex_shader = pbr_vertex_shader,
            .fragment_shader = pbr_fragment_shader,
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

    /// Check if PBR rendering is available.
    pub fn hasPBR(self: *Engine) bool {
        return self.pbr_pipeline != null;
    }

    pub fn deinit(self: *Engine) void {
        // Clean up scripting
        if (self.script_system) |script_sys| {
            script_sys.deinit();
            self.allocator.destroy(script_sys);
        }

        self.audio.deinit();
        self.device.releaseSampler(self.sampler);
        var mutable_device = self.device;
        self.white_texture.deinit(&mutable_device);

        // Clean up PBR resources
        if (self.pbr_pipeline) |p| self.device.releaseGraphicsPipeline(p);
        if (self.default_normal_texture) |t| t.deinit(&mutable_device);
        if (self.default_mr_texture) |t| t.deinit(&mutable_device);
        if (self.default_ao_texture) |t| t.deinit(&mutable_device);
        if (self.default_emissive_texture) |t| t.deinit(&mutable_device);

        if (self.depth_texture) |dt| self.device.releaseTexture(dt);
        self.device.releaseGraphicsPipeline(self.pipeline);
        self.input.deinit();
        self.device.deinit();
        self.window.deinit();
        sdl.quit(.{ .video = true });
    }

    /// Set mouse capture mode (hides cursor and captures relative motion)
    pub fn setMouseCapture(self: *Engine, captured: bool) void {
        self.input.mouse_captured = captured;
        sdl.mouse.setWindowRelativeMode(self.window, captured) catch {};
    }

    /// Run the game loop with a scene and optional update callback.
    /// The scene handles all entity management and rendering automatically.
    pub fn runScene(
        self: *Engine,
        scene: *Scene,
        update_fn: ?*const fn (*Engine, *Scene, *Input, f32) anyerror!void,
    ) !void {
        var running = true;
        while (running) {
            const frame_start = sdl.timer.getMillisecondsSinceInit();
            const delta_time = @as(f32, @floatFromInt(frame_start - self.last_time)) / 1000.0;
            self.last_time = frame_start;

            self.input.update();

            while (sdl.events.poll()) |event| {
                switch (event) {
                    .quit => running = false,
                    .key_down => |key_event| {
                        if (key_event.scancode == .escape) {
                            // If mouse is captured, release it first; otherwise quit
                            if (self.input.mouse_captured) {
                                self.setMouseCapture(false);
                            } else {
                                running = false;
                            }
                        }
                        if (key_event.scancode == .func3) {
                            self.show_fps = !self.show_fps;
                            std.debug.print("FPS counter: {s}\n", .{if (self.show_fps) "ON" else "OFF"});

                            if (!self.show_fps) {
                                self.window.setTitle(self.original_window_title) catch {};
                            }
                        }
                        try self.input.processEvent(event);
                    },
                    .key_up => try self.input.processEvent(event),
                    .mouse_motion, .mouse_button_down, .mouse_button_up => try self.input.processEvent(event),
                    // Gamepad events
                    .gamepad_added,
                    .gamepad_removed,
                    .gamepad_button_down,
                    .gamepad_button_up,
                    .gamepad_axis_motion,
                    => try self.input.processEvent(event),
                    else => {},
                }
            }

            // Update FPS counter
            self.fps_frame_count += 1;
            if (frame_start - self.fps_last_update >= 1000) {
                self.fps_current = @as(f32, @floatFromInt(self.fps_frame_count)) * 1000.0 / @as(f32, @floatFromInt(frame_start - self.fps_last_update));
                self.fps_frame_count = 0;
                self.fps_last_update = frame_start;

                if (self.show_fps) {
                    var title_buffer: [256]u8 = undefined;
                    const title = std.fmt.bufPrintZ(&title_buffer, "ZDL - FPS: {d:.1}", .{self.fps_current}) catch "ZDL";
                    self.window.setTitle(title) catch {};
                }
            }

            // Call user update function if provided
            if (update_fn) |update_callback| {
                try update_callback(self, scene, &self.input, delta_time);
            }

            // Update scripts
            if (self.script_system) |script_sys| {
                script_sys.update(scene, self, &self.input, delta_time);
            }

            // Check if script requested quit
            if (self.should_quit) {
                running = false;
            }

            // Update world transforms
            scene.updateWorldTransforms();

            // Render scene
            if (try self.beginFrame()) |frame_value| {
                var frame = frame_value;
                RenderSystem.render(scene, &frame);
                try frame.end();
            }

            // Frame rate limiting
            const frame_end = sdl.timer.getMillisecondsSinceInit();
            const frame_time = frame_end - frame_start;
            if (frame_time < self.target_frame_time) {
                sdl.timer.delayMilliseconds(@intCast(self.target_frame_time - frame_time));
            }
        }

        // Shutdown scripts before scene cleanup
        if (self.script_system) |script_sys| {
            script_sys.shutdown(scene);
        }
    }

    /// Begin a render frame - returns command buffer and render pass if successful
    pub fn beginFrame(self: *Engine) !?RenderFrame {
        const cmd = try self.device.acquireCommandBuffer();

        const swapchain_texture_opt, const width, const height = try cmd.waitAndAcquireSwapchainTexture(self.window);
        const swapchain_texture = swapchain_texture_opt orelse {
            try cmd.submit();
            return null;
        };

        // Handle window resize
        if (width != self.window_width or height != self.window_height) {
            self.window_width = width;
            self.window_height = height;

            // Recreate depth texture
            if (self.depth_texture) |dt| self.device.releaseTexture(dt);
            self.depth_texture = try self.device.createTexture(.{
                .texture_type = .two_dimensional,
                .format = .depth32_float,
                .width = width,
                .height = height,
                .layer_count_or_depth = 1,
                .num_levels = 1,
                .usage = .{ .depth_stencil_target = true },
            });
        }

        const color_target = sdl.gpu.ColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{
                .r = self.clear_color.r,
                .g = self.clear_color.g,
                .b = self.clear_color.b,
                .a = self.clear_color.a,
            },
            .load = .clear,
            .store = .store,
        };

        const depth_target = sdl.gpu.DepthStencilTargetInfo{
            .texture = self.depth_texture.?,
            .clear_depth = 1.0,
            .clear_stencil = 0,
            .load = .clear,
            .store = .do_not_care,
            .stencil_load = .do_not_care,
            .stencil_store = .do_not_care,
            .cycle = true,
        };

        const pass = cmd.beginRenderPass(&.{color_target}, depth_target);

        return RenderFrame{
            .cmd = cmd,
            .pass = pass,
            .engine = self,
        };
    }
};

/// Represents an active render frame
pub const RenderFrame = struct {
    cmd: sdl.gpu.CommandBuffer,
    pass: sdl.gpu.RenderPass,
    engine: *Engine,

    /// End the render pass and submit the frame
    pub fn end(self: *RenderFrame) !void {
        self.pass.end();
        try self.cmd.submit();
    }

    /// Bind the default pipeline
    pub fn bindPipeline(self: *RenderFrame) void {
        self.pass.bindGraphicsPipeline(self.engine.pipeline);
    }

    /// Bind default texture and sampler
    pub fn bindDefaultTexture(self: *RenderFrame) void {
        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
            .texture = self.engine.white_texture.gpu_texture,
            .sampler = self.engine.sampler,
        }});
    }

    /// Bind a specific texture
    pub fn bindTexture(self: *RenderFrame, texture: Texture) void {
        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
            .texture = texture.gpu_texture,
            .sampler = self.engine.sampler,
        }});
    }

    /// Push uniforms for rendering
    pub fn pushUniforms(self: *RenderFrame, uniforms: Uniforms) void {
        self.cmd.pushVertexUniformData(0, std.mem.asBytes(&uniforms));
    }

    /// Draw a mesh
    pub fn drawMesh(self: *RenderFrame, mesh: Mesh) void {
        self.pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
            .buffer = mesh.vertex_buffer.?,
            .offset = 0,
        }});
        self.pass.bindIndexBuffer(.{ .buffer = mesh.index_buffer.?, .offset = 0 }, .indices_32bit);
        self.pass.drawIndexedPrimitives(@intCast(mesh.indices.len), 1, 0, 0, 0);
    }

    // ========================================================================
    // PBR Rendering Methods
    // ========================================================================

    /// Bind the PBR pipeline. Returns false if PBR is not initialized.
    pub fn bindPBRPipeline(self: *RenderFrame) bool {
        if (self.engine.pbr_pipeline) |pbr| {
            self.pass.bindGraphicsPipeline(pbr);
            return true;
        }
        return false;
    }

    /// Push material uniforms for PBR rendering.
    pub fn pushMaterialUniforms(self: *RenderFrame, material_uniforms: MaterialUniforms) void {
        self.cmd.pushFragmentUniformData(0, std.mem.asBytes(&material_uniforms));
    }

    /// Push light uniforms for PBR rendering.
    pub fn pushLightUniforms(self: *RenderFrame, light_uniforms: LightUniforms) void {
        self.cmd.pushFragmentUniformData(1, std.mem.asBytes(&light_uniforms));
    }

    /// Bind PBR textures for a material.
    /// Uses default textures for any missing material textures.
    pub fn bindPBRTextures(self: *RenderFrame, material: Material) void {
        const eng = self.engine;

        // Get texture for each slot, falling back to defaults
        const base_color_tex = if (material.base_color_texture) |t|
            t.gpu_texture
        else
            eng.white_texture.gpu_texture;

        const normal_tex = if (material.normal_texture) |t|
            t.gpu_texture
        else if (eng.default_normal_texture) |t|
            t.gpu_texture
        else
            eng.white_texture.gpu_texture;

        const mr_tex = if (material.metallic_roughness_texture) |t|
            t.gpu_texture
        else if (eng.default_mr_texture) |t|
            t.gpu_texture
        else
            eng.white_texture.gpu_texture;

        const ao_tex = if (material.ao_texture) |t|
            t.gpu_texture
        else if (eng.default_ao_texture) |t|
            t.gpu_texture
        else
            eng.white_texture.gpu_texture;

        const emissive_tex = if (material.emissive_texture) |t|
            t.gpu_texture
        else if (eng.default_emissive_texture) |t|
            t.gpu_texture
        else
            eng.white_texture.gpu_texture;

        // Bind all 5 texture slots
        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{
            .{ .texture = base_color_tex, .sampler = eng.sampler },
            .{ .texture = normal_tex, .sampler = eng.sampler },
            .{ .texture = mr_tex, .sampler = eng.sampler },
            .{ .texture = ao_tex, .sampler = eng.sampler },
            .{ .texture = emissive_tex, .sampler = eng.sampler },
        });
    }

    /// Bind default PBR textures (white base color, flat normal, etc.)
    pub fn bindDefaultPBRTextures(self: *RenderFrame) void {
        const eng = self.engine;

        const normal_tex = if (eng.default_normal_texture) |t| t.gpu_texture else eng.white_texture.gpu_texture;
        const mr_tex = if (eng.default_mr_texture) |t| t.gpu_texture else eng.white_texture.gpu_texture;
        const ao_tex = if (eng.default_ao_texture) |t| t.gpu_texture else eng.white_texture.gpu_texture;
        const emissive_tex = if (eng.default_emissive_texture) |t| t.gpu_texture else eng.white_texture.gpu_texture;

        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{
            .{ .texture = eng.white_texture.gpu_texture, .sampler = eng.sampler },
            .{ .texture = normal_tex, .sampler = eng.sampler },
            .{ .texture = mr_tex, .sampler = eng.sampler },
            .{ .texture = ao_tex, .sampler = eng.sampler },
            .{ .texture = emissive_tex, .sampler = eng.sampler },
        });
    }

    /// Draw a mesh with PBR material.
    /// Binds textures, pushes uniforms, and draws the mesh.
    pub fn drawMeshPBR(self: *RenderFrame, mesh: Mesh, material: Material, model_matrix: @import("../math/math.zig").Mat4, view: @import("../math/math.zig").Mat4, projection: @import("../math/math.zig").Mat4) void {
        // Push MVP uniforms
        const uniforms = Uniforms.init(model_matrix, view, projection);
        self.pushUniforms(uniforms);

        // Push material uniforms
        const mat_uniforms = MaterialUniforms.fromMaterial(material);
        self.pushMaterialUniforms(mat_uniforms);

        // Push light uniforms
        self.pushLightUniforms(self.engine.light_uniforms);

        // Bind textures
        self.bindPBRTextures(material);

        // Draw
        self.drawMesh(mesh);
    }
};
