const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");

const Mesh = @import("../resources/mesh.zig").Mesh;
const Texture = @import("../resources/texture.zig").Texture;
const Material = @import("../resources/material.zig").Material;
const MaterialUniforms = @import("../resources/material.zig").MaterialUniforms;
const Uniforms = @import("../gpu/uniforms.zig").Uniforms;
const LightUniforms = @import("../gpu/uniforms.zig").LightUniforms;
const primitives = @import("../resources/primitives.zig");
const Mat4 = @import("../math/math.zig").Mat4;

// IBL imports
const BrdfLut = @import("../ibl/brdf_lut.zig").BrdfLut;
const EnvironmentMap = @import("../ibl/environment_map.zig").EnvironmentMap;

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

/// Manages all rendering resources: GPU device, pipelines, textures, and frame lifecycle.
pub const RenderManager = struct {
    allocator: std.mem.Allocator,
    device: sdl.gpu.Device,
    window: sdl.video.Window,

    // Legacy pipeline
    pipeline: sdl.gpu.GraphicsPipeline,
    depth_texture: ?sdl.gpu.Texture,
    white_texture: Texture,
    sampler: sdl.gpu.Sampler,

    // PBR pipeline resources
    pbr_pipeline: ?sdl.gpu.GraphicsPipeline,
    default_normal_texture: ?Texture,
    default_mr_texture: ?Texture,
    default_ao_texture: ?Texture,
    default_emissive_texture: ?Texture,

    // Skybox resources
    skybox_pipeline: ?sdl.gpu.GraphicsPipeline,
    skybox_mesh: ?Mesh,

    // IBL resources
    brdf_lut: ?*BrdfLut,
    current_environment: ?*EnvironmentMap,
    default_environment: ?*EnvironmentMap,
    ibl_enabled: bool,

    // Light uniforms (shared state for rendering)
    light_uniforms: LightUniforms,

    // Window state
    window_width: u32,
    window_height: u32,
    clear_color: Color,

    /// Initialize the render manager with GPU device and basic pipeline
    pub fn init(allocator: std.mem.Allocator, window: sdl.video.Window, width: u32, height: u32) !RenderManager {
        const device = try sdl.gpu.Device.init(
            ShaderConfig.format,
            true,
            null,
        );
        errdefer device.deinit();

        try device.claimWindow(window);

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
            .width = width,
            .height = height,
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

        return .{
            .allocator = allocator,
            .device = device,
            .window = window,
            .pipeline = pipeline,
            .depth_texture = depth_texture,
            .white_texture = white_texture,
            .sampler = sampler,
            .pbr_pipeline = null,
            .default_normal_texture = null,
            .default_mr_texture = null,
            .default_ao_texture = null,
            .default_emissive_texture = null,
            .skybox_pipeline = null,
            .skybox_mesh = null,
            .brdf_lut = null,
            .current_environment = null,
            .default_environment = null,
            .ibl_enabled = false,
            .light_uniforms = LightUniforms.default(),
            .window_width = width,
            .window_height = height,
            .clear_color = Color.init(0.1, 0.1, 0.15, 1.0),
        };
    }

    pub fn deinit(self: *RenderManager) void {
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
        self.device.deinit();
    }

    /// Initialize PBR pipeline and default textures
    pub fn initPBR(self: *RenderManager) !void {
        if (self.pbr_pipeline != null) return;

        var mutable_device = self.device;

        // Create default PBR textures
        self.default_normal_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 128, 128, 255, 255 });
        errdefer if (self.default_normal_texture) |t| t.deinit(&mutable_device);

        self.default_mr_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 0, 128, 0, 255 });
        errdefer if (self.default_mr_texture) |t| t.deinit(&mutable_device);

        self.default_ao_texture = try Texture.createColored(&mutable_device, 1, 1, .{ 255, 255, 255, 255 });
        errdefer if (self.default_ao_texture) |t| t.deinit(&mutable_device);

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
            .num_uniform_buffers = 1,
        });
        defer self.device.releaseShader(pbr_vertex_shader);

        const pbr_fragment_shader = try self.device.createShader(.{
            .code = pbr_fragment_code,
            .entry_point = PBRShaderConfig.fragment_entry,
            .format = PBRShaderConfig.format,
            .stage = .fragment,
            .num_samplers = 8,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 2,
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

    /// Check if PBR rendering is available
    pub fn hasPBR(self: *RenderManager) bool {
        return self.pbr_pipeline != null;
    }

    /// Initialize Image-Based Lighting support
    pub fn initIBL(self: *RenderManager) !void {
        if (self.brdf_lut != null) return;

        var mutable_device = self.device;

        const brdf_lut = try self.allocator.create(BrdfLut);
        errdefer self.allocator.destroy(brdf_lut);
        brdf_lut.* = try BrdfLut.generateCPU(self.allocator, &mutable_device, 128);
        self.brdf_lut = brdf_lut;

        const default_env = try self.allocator.create(EnvironmentMap);
        errdefer self.allocator.destroy(default_env);
        default_env.* = try EnvironmentMap.createDefault(&mutable_device);
        self.default_environment = default_env;

        self.current_environment = default_env;
        self.ibl_enabled = true;

        self.light_uniforms.setIBLEnabled(true);
        self.light_uniforms.setIBLParams(1.0, default_env.max_mip_level);
        self.light_uniforms.setIBLSpecularIntensity(0.2);

        try self.initSkybox();
    }

    /// Check if IBL is available
    pub fn hasIBL(self: *RenderManager) bool {
        return self.brdf_lut != null and self.ibl_enabled;
    }

    /// Set the active environment map
    pub fn setEnvironmentMap(self: *RenderManager, env: *EnvironmentMap) void {
        self.current_environment = env;
        self.light_uniforms.setIBLParams(self.light_uniforms.ibl_params[0], env.max_mip_level);
    }

    /// Load HDR environment map from equirectangular .hdr file
    pub fn loadHDREnvironment(self: *RenderManager, path: []const u8) !*EnvironmentMap {
        if (self.brdf_lut == null) {
            return error.IBLNotInitialized;
        }

        var mutable_device = self.device;

        const env = try self.allocator.create(EnvironmentMap);
        errdefer self.allocator.destroy(env);

        env.* = try EnvironmentMap.loadFromHDR(self.allocator, &mutable_device, path);

        if (self.current_environment) |old_env| {
            if (self.default_environment == null or old_env != self.default_environment.?) {
                var mutable_env = old_env;
                mutable_env.deinit(&mutable_device);
                self.allocator.destroy(old_env);
            }
        }

        self.current_environment = env;
        self.light_uniforms.setIBLParams(1.0, env.max_mip_level);
        if (self.light_uniforms.ibl_params[3] == 0.0) {
            self.light_uniforms.setIBLSpecularIntensity(0.2);
        }

        return env;
    }

    /// Initialize skybox rendering pipeline and mesh
    pub fn initSkybox(self: *RenderManager) !void {
        if (self.skybox_pipeline != null) return;

        var mutable_device = self.device;

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
            .num_uniform_buffers = 1,
        });
        defer self.device.releaseShader(skybox_vertex_shader);

        const skybox_fragment_shader = try self.device.createShader(.{
            .code = skybox_fragment_code,
            .entry_point = SkyboxShaderConfig.fragment_entry,
            .format = SkyboxShaderConfig.format,
            .stage = .fragment,
            .num_samplers = 1,
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
                .cull_mode = .front,
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

    /// Set the clear color for rendering
    pub fn setClearColor(self: *RenderManager, color: Color) void {
        self.clear_color = color;
    }

    /// Handle window resize - recreates depth texture
    pub fn handleResize(self: *RenderManager, width: u32, height: u32) !void {
        if (width == self.window_width and height == self.window_height) return;

        self.window_width = width;
        self.window_height = height;

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

    /// Begin a render frame
    pub fn beginFrame(self: *RenderManager) !?RenderFrame {
        const cmd = try self.device.acquireCommandBuffer();

        const swapchain_texture_opt, const width, const height = try cmd.waitAndAcquireSwapchainTexture(self.window);
        const swapchain_texture = swapchain_texture_opt orelse {
            try cmd.submit();
            return null;
        };

        // Handle window resize
        if (width != self.window_width or height != self.window_height) {
            try self.handleResize(width, height);
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
            .manager = self,
        };
    }

    /// Get the GPU device (for external resource creation)
    pub fn getDevice(self: *RenderManager) *sdl.gpu.Device {
        return &self.device;
    }
};

/// Represents an active render frame with rendering operations.
/// References RenderManager instead of Engine for decoupling.
pub const RenderFrame = struct {
    cmd: sdl.gpu.CommandBuffer,
    pass: sdl.gpu.RenderPass,
    manager: *RenderManager,

    /// End the render pass and submit the frame
    pub fn end(self: *RenderFrame) !void {
        self.pass.end();
        try self.cmd.submit();
    }

    /// Bind the default pipeline
    pub fn bindPipeline(self: *RenderFrame) void {
        self.pass.bindGraphicsPipeline(self.manager.pipeline);
    }

    /// Bind default texture and sampler
    pub fn bindDefaultTexture(self: *RenderFrame) void {
        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
            .texture = self.manager.white_texture.gpu_texture,
            .sampler = self.manager.sampler,
        }});
    }

    /// Bind a specific texture
    pub fn bindTexture(self: *RenderFrame, texture: Texture) void {
        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
            .texture = texture.gpu_texture,
            .sampler = self.manager.sampler,
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
        if (self.manager.pbr_pipeline) |pbr| {
            self.pass.bindGraphicsPipeline(pbr);
            return true;
        }
        return false;
    }

    /// Draw the skybox if available
    pub fn drawSkybox(self: *RenderFrame, view: Mat4, projection: Mat4) void {
        const skybox = self.manager.skybox_pipeline orelse return;
        const mesh = self.manager.skybox_mesh orelse return;
        const env = if (self.manager.current_environment) |e|
            e
        else if (self.manager.default_environment) |e|
            e
        else
            return;

        self.pass.bindGraphicsPipeline(skybox);

        var view_no_translation = view;
        view_no_translation.data[12] = 0.0;
        view_no_translation.data[13] = 0.0;
        view_no_translation.data[14] = 0.0;

        const uniforms = Uniforms.init(Mat4.identity(), view_no_translation, projection);
        self.pushUniforms(uniforms);

        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
            .texture = env.prefiltered.texture,
            .sampler = self.manager.sampler,
        }});

        self.drawMesh(mesh);
    }

    /// Push material uniforms for PBR rendering
    pub fn pushMaterialUniforms(self: *RenderFrame, material_uniforms: MaterialUniforms) void {
        self.cmd.pushFragmentUniformData(0, std.mem.asBytes(&material_uniforms));
    }

    /// Push light uniforms for PBR rendering
    pub fn pushLightUniforms(self: *RenderFrame, light_uniforms: LightUniforms) void {
        self.cmd.pushFragmentUniformData(1, std.mem.asBytes(&light_uniforms));
    }

    /// Bind PBR textures for a material
    pub fn bindPBRTextures(self: *RenderFrame, material: Material) void {
        const mgr = self.manager;

        const base_color_tex = if (material.base_color_texture) |t|
            t.gpu_texture
        else
            mgr.white_texture.gpu_texture;

        const normal_tex = if (material.normal_texture) |t|
            t.gpu_texture
        else if (mgr.default_normal_texture) |t|
            t.gpu_texture
        else
            mgr.white_texture.gpu_texture;

        const mr_tex = if (material.metallic_roughness_texture) |t|
            t.gpu_texture
        else if (mgr.default_mr_texture) |t|
            t.gpu_texture
        else
            mgr.white_texture.gpu_texture;

        const ao_tex = if (material.ao_texture) |t|
            t.gpu_texture
        else if (mgr.default_ao_texture) |t|
            t.gpu_texture
        else
            mgr.white_texture.gpu_texture;

        const emissive_tex = if (material.emissive_texture) |t|
            t.gpu_texture
        else if (mgr.default_emissive_texture) |t|
            t.gpu_texture
        else
            mgr.white_texture.gpu_texture;

        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{
            .{ .texture = base_color_tex, .sampler = mgr.sampler },
            .{ .texture = normal_tex, .sampler = mgr.sampler },
            .{ .texture = mr_tex, .sampler = mgr.sampler },
            .{ .texture = ao_tex, .sampler = mgr.sampler },
            .{ .texture = emissive_tex, .sampler = mgr.sampler },
        });
    }

    /// Bind default PBR textures
    pub fn bindDefaultPBRTextures(self: *RenderFrame) void {
        const mgr = self.manager;

        const normal_tex = if (mgr.default_normal_texture) |t| t.gpu_texture else mgr.white_texture.gpu_texture;
        const mr_tex = if (mgr.default_mr_texture) |t| t.gpu_texture else mgr.white_texture.gpu_texture;
        const ao_tex = if (mgr.default_ao_texture) |t| t.gpu_texture else mgr.white_texture.gpu_texture;
        const emissive_tex = if (mgr.default_emissive_texture) |t| t.gpu_texture else mgr.white_texture.gpu_texture;

        self.pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{
            .{ .texture = mgr.white_texture.gpu_texture, .sampler = mgr.sampler },
            .{ .texture = normal_tex, .sampler = mgr.sampler },
            .{ .texture = mr_tex, .sampler = mgr.sampler },
            .{ .texture = ao_tex, .sampler = mgr.sampler },
            .{ .texture = emissive_tex, .sampler = mgr.sampler },
        });
    }

    /// Bind IBL textures (irradiance, pre-filtered environment, BRDF LUT)
    pub fn bindIBLTextures(self: *RenderFrame) void {
        const mgr = self.manager;

        const irradiance_tex = if (mgr.current_environment) |env|
            env.irradiance.texture
        else
            mgr.white_texture.gpu_texture;

        const prefiltered_tex = if (mgr.current_environment) |env|
            env.prefiltered.texture
        else
            mgr.white_texture.gpu_texture;

        const brdf_lut_tex = if (mgr.brdf_lut) |lut|
            lut.texture.gpu_texture
        else
            mgr.white_texture.gpu_texture;

        self.pass.bindFragmentSamplers(5, &[_]sdl.gpu.TextureSamplerBinding{
            .{ .texture = irradiance_tex, .sampler = mgr.sampler },
            .{ .texture = prefiltered_tex, .sampler = mgr.sampler },
            .{ .texture = brdf_lut_tex, .sampler = mgr.sampler },
        });
    }

    /// Draw a mesh with PBR material
    pub fn drawMeshPBR(self: *RenderFrame, mesh: Mesh, material: Material, model_matrix: Mat4, view: Mat4, projection: Mat4) void {
        const uniforms = Uniforms.init(model_matrix, view, projection);
        self.pushUniforms(uniforms);

        const mat_uniforms = MaterialUniforms.fromMaterial(material);
        self.pushMaterialUniforms(mat_uniforms);

        self.pushLightUniforms(self.manager.light_uniforms);

        self.bindPBRTextures(material);
        self.bindIBLTextures();

        self.drawMesh(mesh);
    }
};
