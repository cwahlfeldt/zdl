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
const primitives = @import("../resources/primitives.zig");

// IBL imports
const BrdfLut = @import("../ibl/brdf_lut.zig").BrdfLut;
const EnvironmentMap = @import("../ibl/environment_map.zig").EnvironmentMap;

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

// Skybox shader configuration
const SkyboxShaderConfig = if (is_macos) struct {
    const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
    const vertex_path = "assets/shaders/skybox.metal";
    const fragment_path = "assets/shaders/skybox.metal";
    const vertex_entry = "skybox_vertex_main";
    const fragment_entry = "skybox_fragment_main";
} else struct {
    const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
    const vertex_path = "build/assets/shaders/skybox.vert.spv";
    const fragment_path = "build/assets/shaders/skybox.frag.spv";
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
    app_name: ?[:0]const u8 = null,
    app_version: ?[:0]const u8 = null,
    app_identifier: ?[:0]const u8 = "com.zdl.engine",
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
    skybox_pipeline: ?sdl.gpu.GraphicsPipeline,
    skybox_mesh: ?Mesh,

    // IBL resources
    brdf_lut: ?*BrdfLut, // BRDF integration lookup table
    current_environment: ?*EnvironmentMap, // Active environment map
    default_environment: ?*EnvironmentMap, // Fallback neutral environment
    ibl_enabled: bool, // Whether IBL is active

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
        const app_name = config.app_name orelse config.window_title;
        try sdl.setAppMetadata(app_name, config.app_version, config.app_identifier);
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
            .skybox_pipeline = null,
            .skybox_mesh = null,
            // IBL resources initialized lazily via initIBL()
            .brdf_lut = null,
            .current_environment = null,
            .default_environment = null,
            .ibl_enabled = false,
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
            .num_samplers = 8, // base_color, normal, metallic_roughness, ao, emissive + irradiance, prefiltered, brdf_lut
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

    /// Initialize Image-Based Lighting support
    pub fn initIBL(self: *Engine) !void {
        if (self.brdf_lut != null) return; // Already initialized

        var mutable_device = self.device;

        // Generate BRDF lookup table (CPU-based for now)
        // Using 128x128 for reasonable startup time (~2-3 seconds)
        const brdf_lut = try self.allocator.create(BrdfLut);
        errdefer self.allocator.destroy(brdf_lut);
        brdf_lut.* = try BrdfLut.generateCPU(self.allocator, &mutable_device, 128);
        self.brdf_lut = brdf_lut;

        // Create default neutral environment
        const default_env = try self.allocator.create(EnvironmentMap);
        errdefer self.allocator.destroy(default_env);
        default_env.* = try EnvironmentMap.createDefault(&mutable_device);
        self.default_environment = default_env;

        // Set default as current environment
        self.current_environment = default_env;
        self.ibl_enabled = true;

        // Update light uniforms with IBL parameters
        self.light_uniforms.setIBLEnabled(true);
        self.light_uniforms.setIBLParams(1.0, default_env.max_mip_level);
        self.light_uniforms.setIBLSpecularIntensity(0.2);

        try self.initSkybox();
    }

    /// Set the active environment map
    pub fn setEnvironmentMap(self: *Engine, env: *EnvironmentMap) void {
        self.current_environment = env;
        // Update max LOD when changing environments
        self.light_uniforms.setIBLParams(self.light_uniforms.ibl_params[0], env.max_mip_level);
    }

    /// Check if IBL is available
    pub fn hasIBL(self: *Engine) bool {
        return self.brdf_lut != null and self.ibl_enabled;
    }

    /// Load HDR environment map from equirectangular .hdr file
    pub fn loadHDREnvironment(self: *Engine, path: []const u8) !*EnvironmentMap {
        if (self.brdf_lut == null) {
            return error.IBLNotInitialized;
        }

        var mutable_device = self.device;

        // Load environment from HDR file
        const env = try self.allocator.create(EnvironmentMap);
        errdefer self.allocator.destroy(env);

        env.* = try EnvironmentMap.loadFromHDR(self.allocator, &mutable_device, path);

        // Free previous non-default environment if present.
        if (self.current_environment) |old_env| {
            if (self.default_environment == null or old_env != self.default_environment.?) {
                var mutable_env = old_env;
                mutable_env.deinit(&mutable_device);
                self.allocator.destroy(old_env);
            }
        }

        // Set as current environment
        self.current_environment = env;
        self.light_uniforms.setIBLParams(1.0, env.max_mip_level);
        if (self.light_uniforms.ibl_params[3] == 0.0) {
            self.light_uniforms.setIBLSpecularIntensity(0.2);
        }

        return env;
    }

    pub fn deinit(self: *Engine) void {
        // Clean up scripting
        if (self.script_system) |script_sys| {
            script_sys.deinit(&self.device);
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
        if (self.skybox_pipeline) |p| self.device.releaseGraphicsPipeline(p);
        if (self.skybox_mesh) |m| {
            var mutable_mesh = m;
            mutable_mesh.deinit(&mutable_device);
        }

        // Clean up IBL resources
        if (self.brdf_lut) |lut| {
            var mutable_lut = lut;
            mutable_lut.deinit(&mutable_device);
            self.allocator.destroy(lut);
        }
        if (self.current_environment) |env| {
            if (self.default_environment == null or env != self.default_environment.?) {
                var mutable_env = env;
                mutable_env.deinit(&mutable_device);
                self.allocator.destroy(env);
            }
        }
        if (self.default_environment) |env| {
            var mutable_env = env;
            mutable_env.deinit(&mutable_device);
            self.allocator.destroy(env);
        }

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

    /// Initialize skybox rendering pipeline and mesh.
    pub fn initSkybox(self: *Engine) !void {
        if (self.skybox_pipeline != null) return;

        var mutable_device = self.device;

        // Load skybox shaders
        const skybox_vertex_code = try std.fs.cwd().readFileAlloc(
            self.allocator,
            SkyboxShaderConfig.vertex_path,
            1024 * 1024,
        );
        defer self.allocator.free(skybox_vertex_code);

        const skybox_fragment_code = if (is_macos)
            skybox_vertex_code
        else
            try std.fs.cwd().readFileAlloc(
                self.allocator,
                SkyboxShaderConfig.fragment_path,
                1024 * 1024,
            );
        defer if (!is_macos) self.allocator.free(skybox_fragment_code);

        const skybox_vertex_shader = try self.device.createShader(.{
            .code = skybox_vertex_code,
            .entry_point = SkyboxShaderConfig.vertex_entry,
            .format = SkyboxShaderConfig.format,
            .stage = .vertex,
            .num_samplers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 1, // MVP uniforms
        });
        defer self.device.releaseShader(skybox_vertex_shader);

        const skybox_fragment_shader = try self.device.createShader(.{
            .code = skybox_fragment_code,
            .entry_point = SkyboxShaderConfig.fragment_entry,
            .format = SkyboxShaderConfig.format,
            .stage = .fragment,
            .num_samplers = 1, // cubemap
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 0,
        });
        defer self.device.releaseShader(skybox_fragment_shader);

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

        self.skybox_pipeline = try self.device.createGraphicsPipeline(.{
            .vertex_shader = skybox_vertex_shader,
            .fragment_shader = skybox_fragment_shader,
            .primitive_type = .triangle_list,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{vertex_buffer_desc},
                .vertex_attributes = &vertex_attributes,
            },
            .rasterizer_state = .{
                .cull_mode = .front, // Render inside of cube
                .front_face = .counter_clockwise,
            },
            .target_info = .{
                .color_target_descriptions = &[_]sdl.gpu.ColorTargetDescription{color_target_desc},
                .depth_stencil_format = .depth32_float,
            },
            .depth_stencil_state = .{
                .enable_depth_test = true,
                .enable_depth_write = false,
                .compare = .less_or_equal,
                .enable_stencil_test = false,
            },
        });

        if (self.skybox_mesh == null) {
            var cube_mesh = try primitives.createCube(self.allocator);
            errdefer cube_mesh.deinit(&mutable_device);
            try cube_mesh.upload(&mutable_device);
            self.skybox_mesh = cube_mesh;
        }
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

    /// Draw the skybox if available.
    pub fn drawSkybox(self: *RenderFrame, view: @import("../math/math.zig").Mat4, projection: @import("../math/math.zig").Mat4) void {
        const skybox = self.engine.skybox_pipeline orelse return;
        const mesh = self.engine.skybox_mesh orelse return;
        const env = if (self.engine.current_environment) |e|
            e
        else if (self.engine.default_environment) |e|
            e
        else
            return;

        self.pass.bindGraphicsPipeline(skybox);

        var view_no_translation = view;
        view_no_translation.data[12] = 0.0;
        view_no_translation.data[13] = 0.0;
        view_no_translation.data[14] = 0.0;

        const uniforms = Uniforms.init(@import("../math/math.zig").Mat4.identity(), view_no_translation, projection);
        self.pushUniforms(uniforms);

        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
            .texture = env.prefiltered.texture,
            .sampler = self.engine.sampler,
        }});

        self.drawMesh(mesh);
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

    /// Bind IBL textures (irradiance, pre-filtered environment, BRDF LUT).
    /// Binds to slots 5, 6, 7 respectively. Falls back to white texture if IBL not available.
    pub fn bindIBLTextures(self: *RenderFrame) void {
        const eng = self.engine;

        // Get IBL textures or fallback to white
        const irradiance_tex = if (eng.current_environment) |env|
            env.irradiance.texture
        else
            eng.white_texture.gpu_texture;

        const prefiltered_tex = if (eng.current_environment) |env|
            env.prefiltered.texture
        else
            eng.white_texture.gpu_texture;

        const brdf_lut_tex = if (eng.brdf_lut) |lut|
            lut.texture.gpu_texture
        else
            eng.white_texture.gpu_texture;

        // Bind IBL textures to slots 5, 6, 7
        self.pass.bindFragmentSamplers(5, &[_]sdl.gpu.TextureSamplerBinding{
            .{ .texture = irradiance_tex, .sampler = eng.sampler },
            .{ .texture = prefiltered_tex, .sampler = eng.sampler },
            .{ .texture = brdf_lut_tex, .sampler = eng.sampler },
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

        // Bind PBR material textures (slots 0-4)
        self.bindPBRTextures(material);

        // Bind IBL textures (slots 5-7)
        self.bindIBLTextures();

        // Draw
        self.drawMesh(mesh);
    }
};
