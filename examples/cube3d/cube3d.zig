const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const engine = @import("engine");
const Application = engine.Application;
const Context = engine.Context;

const Camera3D = engine.Camera3D;
const Transform = engine.Transform;
const Vec3 = engine.Vec3;
const Mat4 = engine.Mat4;
const Quat = engine.Quat;
const Mesh = engine.Mesh;
const primitives = engine.primitives;
const Texture = engine.Texture;

const is_macos = builtin.os.tag == .macos;

/// 3D uniforms for model-view-projection
const Uniforms3D = struct {
    model: Mat4,
    view: Mat4,
    projection: Mat4,
};

pub const Cube3D = struct {
    camera: Camera3D = undefined,
    cube_mesh: ?Mesh = null,
    plane_mesh: ?Mesh = null,
    cube_transform: Transform = undefined,
    plane_transform: Transform = undefined,
    rotation: f32 = 0,

    // 3D rendering resources
    pipeline_3d: ?sdl.gpu.GraphicsPipeline = null,
    depth_texture: ?sdl.gpu.Texture = null,
    sampler: ?sdl.gpu.Sampler = null,
    texture: ?Texture = null,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *Cube3D, ctx: *Context) !void {
        self.allocator = ctx.allocator;
        // Initialize 3D camera (will be resized on first render)
        self.camera = Camera3D.init(1280, 720);
        self.camera.position = Vec3.init(0, 2, 5);
        self.camera.target = Vec3.init(0, 0, 0);

        // Create meshes
        self.cube_mesh = try primitives.createCube(self.allocator);
        self.plane_mesh = try primitives.createPlane(self.allocator);

        // Upload meshes to GPU
        try self.cube_mesh.?.upload(ctx.device);
        try self.plane_mesh.?.upload(ctx.device);

        // Setup transforms
        self.cube_transform = Transform.withPosition(Vec3.init(0, 0, 0));
        self.cube_transform.scale = Vec3.init(2, 2, 2); // Make cube bigger
        self.plane_transform = Transform.withPosition(Vec3.init(0, -2, 0));
        self.plane_transform.scale = Vec3.init(10, 1, 10);

        // Create white texture for meshes
        self.texture = try Texture.createColored(ctx.device, 1, 1, .{ 255, 255, 255, 255 });

        // Create sampler
        self.sampler = try ctx.device.createSampler(.{
            .min_filter = .nearest,
            .mag_filter = .nearest,
            .mipmap_mode = .nearest,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
        });

        // Create depth texture (will be recreated on first render with actual size)
        self.depth_texture = try ctx.device.createTexture(.{
            .texture_type = .two_dimensional,
            .format = .depth32_float,
            .width = 1280,
            .height = 720,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .usage = .{ .depth_stencil_target = true },
        });

        // Load and create 3D shaders
        const ShaderConfig = if (is_macos) struct {
            const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
            const vertex_path = "src/shaders/shaders_3d.metal";
            const fragment_path = "src/shaders/shaders_3d.metal";
            const vertex_entry = "vertex_3d_main";
            const fragment_entry = "fragment_3d_main";
        } else struct {
            const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
            const vertex_path = "src/shaders/vertex_3d.spv";
            const fragment_path = "src/shaders/fragment_3d.spv";
            const vertex_entry = "main";
            const fragment_entry = "main";
        };

        const vertex_code = try std.fs.cwd().readFileAlloc(
            self.allocator,
            ShaderConfig.vertex_path,
            1024 * 1024,
        );
        defer self.allocator.free(vertex_code);

        const fragment_code = if (is_macos)
            vertex_code
        else
            try std.fs.cwd().readFileAlloc(
                self.allocator,
                ShaderConfig.fragment_path,
                1024 * 1024,
            );
        defer if (!is_macos) self.allocator.free(fragment_code);

        const vertex_shader = try ctx.device.createShader(.{
            .code = vertex_code,
            .entry_point = ShaderConfig.vertex_entry,
            .format = ShaderConfig.format,
            .stage = .vertex,
            .num_samplers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 1,
        });
        defer ctx.device.releaseShader(vertex_shader);

        const fragment_shader = try ctx.device.createShader(.{
            .code = fragment_code,
            .entry_point = ShaderConfig.fragment_entry,
            .format = ShaderConfig.format,
            .stage = .fragment,
            .num_samplers = 1,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 0,
        });
        defer ctx.device.releaseShader(fragment_shader);

        const vertex_buffer_desc = Mesh.getVertexBufferDesc();
        const vertex_attributes = Mesh.getVertexAttributes();

        const color_target_desc = sdl.gpu.ColorTargetDescription{
            .format = try ctx.device.getSwapchainTextureFormat(ctx.window.*),
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

        // Create 3D pipeline with depth testing
        self.pipeline_3d = try ctx.device.createGraphicsPipeline(.{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .primitive_type = .triangle_list,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{vertex_buffer_desc},
                .vertex_attributes = &vertex_attributes,
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

        std.debug.print("3D Cube Demo initialized!\n", .{});
        std.debug.print("Controls:\n", .{});
        std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
        std.debug.print("  Q/E - Move camera up/down\n", .{});
        std.debug.print("  ESC - Quit\n", .{});
    }

    pub fn deinit(self: *Cube3D, ctx: *Context) void {
        if (self.pipeline_3d) |p| ctx.device.releaseGraphicsPipeline(p);
        if (self.depth_texture) |dt| ctx.device.releaseTexture(dt);
        if (self.sampler) |s| ctx.device.releaseSampler(s);
        if (self.texture) |*t| t.deinit(ctx.device);
        if (self.cube_mesh) |*m| m.deinit(ctx.device);
        if (self.plane_mesh) |*m| m.deinit(ctx.device);
    }

    pub fn update(self: *Cube3D, ctx: *Context, delta_time: f32) !void {
        const speed: f32 = 5.0;
        const move_dist = speed * delta_time;

        // Camera movement
        if (ctx.input.isKeyDown(.w) or ctx.input.isKeyDown(.up)) {
            self.camera.moveForward(move_dist);
        }
        if (ctx.input.isKeyDown(.s) or ctx.input.isKeyDown(.down)) {
            self.camera.moveForward(-move_dist);
        }
        if (ctx.input.isKeyDown(.a) or ctx.input.isKeyDown(.left)) {
            self.camera.moveRight(-move_dist);
        }
        if (ctx.input.isKeyDown(.d) or ctx.input.isKeyDown(.right)) {
            self.camera.moveRight(move_dist);
        }
        if (ctx.input.isKeyDown(.q)) {
            self.camera.moveUp(-move_dist);
        }
        if (ctx.input.isKeyDown(.e)) {
            self.camera.moveUp(move_dist);
        }

        // Rotate cube
        self.rotation += delta_time;
        self.cube_transform.setRotationEuler(self.rotation * 0.7, self.rotation, self.rotation * 0.5);
    }

    pub fn render(self: *Cube3D, ctx: *Context) !void {
        // Get swapchain
        const cmd = try ctx.device.acquireCommandBuffer();

        const swapchain_texture_opt, const width, const height = try cmd.waitAndAcquireSwapchainTexture(ctx.window.*);
        const swapchain_texture = swapchain_texture_opt orelse {
            try cmd.submit();
            return;
        };

        // Update camera aspect ratio if window resized
        const w_f32: f32 = @floatFromInt(width);
        const h_f32: f32 = @floatFromInt(height);
        if (self.camera.aspect != w_f32 / h_f32) {
            self.camera.resize(w_f32, h_f32);

            // Recreate depth texture with new size
            if (self.depth_texture) |dt| ctx.device.releaseTexture(dt);
            self.depth_texture = try ctx.device.createTexture(.{
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
            .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 }, // Darker background
            .load = .clear,
            .store = .store,
        };

        const depth_target = sdl.gpu.DepthStencilTargetInfo{
            .texture = self.depth_texture.?,
            .clear_depth = 1.0,
            .clear_stencil = 0,
            .load = .clear,
            .store = .store,
            .stencil_load = .do_not_care,
            .stencil_store = .do_not_care,
            .cycle = false,
        };

        // Set uniforms for cube (for now just use cube's transform)
        const uniforms = Uniforms3D{
            .model = self.cube_transform.getMatrix(),
            .view = self.camera.getViewMatrix(),
            .projection = self.camera.getProjectionMatrix(),
        };
        cmd.pushVertexUniformData(0, std.mem.asBytes(&uniforms));

        {
            const pass = cmd.beginRenderPass(&.{color_target}, depth_target);
            defer pass.end();

            pass.bindGraphicsPipeline(self.pipeline_3d.?);
            pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
                .texture = self.texture.?.gpu_texture,
                .sampler = self.sampler.?,
            }});

            // Draw cube
            if (self.cube_mesh) |cube_mesh| {
                if (cube_mesh.vertex_buffer) |cube_vb| {
                    if (cube_mesh.index_buffer) |cube_ib| {
                        pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
                            .buffer = cube_vb,
                            .offset = 0,
                        }});
                        pass.bindIndexBuffer(.{
                            .buffer = cube_ib,
                            .offset = 0,
                        }, .indices_32bit);
                        pass.drawIndexedPrimitives(@intCast(cube_mesh.indices.len), 1, 0, 0, 0);
                    }
                }
            }
        }

        try cmd.submit();
    }
};
