const std = @import("std");
const engine = @import("engine");
const Context = engine.Context;
const Camera = engine.Camera;
const Transform = engine.Transform;
const Vec3 = engine.Vec3;
const Mat4 = engine.Mat4;
const Mesh = engine.Mesh;
const primitives = engine.primitives;
const Texture = engine.Texture;
const Uniforms = engine.Uniforms;

pub const Cube3D = struct {
    camera: Camera = undefined,
    cube_mesh: ?Mesh = null,
    plane_mesh: ?Mesh = null,
    cube_transform: Transform = undefined,
    plane_transform: Transform = undefined,
    rotation: f32 = 0,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *Cube3D, ctx: *Context) !void {
        self.allocator = ctx.allocator;

        // Initialize 3D camera
        const size = ctx.getWindowSize();
        self.camera = Camera.init(size.width, size.height);
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
        self.cube_transform.scale = Vec3.init(2, 2, 2);
        self.plane_transform = Transform.withPosition(Vec3.init(0, -2, 0));
        self.plane_transform.scale = Vec3.init(10, 1, 10);

        std.debug.print("3D Cube Demo initialized!\n", .{});
        std.debug.print("Controls:\n", .{});
        std.debug.print("  WASD/Arrow Keys - Move camera\n", .{});
        std.debug.print("  Q/E - Move camera up/down\n", .{});
        std.debug.print("  F3 - Toggle FPS counter\n", .{});
        std.debug.print("  ESC - Quit\n", .{});
    }

    pub fn deinit(self: *Cube3D, ctx: *Context) void {
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

        // Update aspect ratio if window resized
        const size = ctx.getWindowSize();
        if (self.camera.aspect != size.width / size.height) {
            self.camera.resize(size.width, size.height);
        }
    }

    pub fn render(self: *Cube3D, ctx: *Context) !void {
        const sdl = @import("sdl3");

        // Acquire command buffer and swapchain
        const cmd = try ctx.device.acquireCommandBuffer();

        const swapchain_texture_opt, const width, const height = try cmd.waitAndAcquireSwapchainTexture(ctx.window.*);
        const swapchain_texture = swapchain_texture_opt orelse {
            try cmd.submit();
            return;
        };

        // Handle depth texture resize
        if (ctx.depth_texture.* == null or
            width != ctx.window_width.* or height != ctx.window_height.*)
        {
            if (ctx.depth_texture.*) |dt| ctx.device.releaseTexture(dt);
            ctx.depth_texture.* = try ctx.device.createTexture(.{
                .texture_type = .two_dimensional,
                .format = .depth32_float,
                .width = width,
                .height = height,
                .layer_count_or_depth = 1,
                .num_levels = 1,
                .usage = .{ .depth_stencil_target = true },
            });
            ctx.window_width.* = width;
            ctx.window_height.* = height;
        }

        const color_target = sdl.gpu.ColorTargetInfo{
            .texture = swapchain_texture,
            .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 },
            .load = .clear,
            .store = .store,
        };

        const depth_target = sdl.gpu.DepthStencilTargetInfo{
            .texture = ctx.depth_texture.*.?,
            .clear_depth = 1.0,
            .clear_stencil = 0,
            .load = .clear,
            .store = .do_not_care,
            .stencil_load = .do_not_care,
            .stencil_store = .do_not_care,
            .cycle = true,
        };

        {
            const pass = cmd.beginRenderPass(&.{color_target}, depth_target);
            defer pass.end();

            pass.bindGraphicsPipeline(ctx.pipeline.*);
            pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
                .texture = ctx.white_texture.gpu_texture,
                .sampler = ctx.sampler.*,
            }});

            // Draw cube
            if (self.cube_mesh) |mesh| {
                const uniforms = Uniforms.init(
                    self.cube_transform.getMatrix(),
                    self.camera.getViewMatrix(),
                    self.camera.getProjectionMatrix(),
                );
                cmd.pushVertexUniformData(1, std.mem.asBytes(&uniforms));

                pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
                    .buffer = mesh.vertex_buffer.?,
                    .offset = 0,
                }});
                pass.bindIndexBuffer(.{ .buffer = mesh.index_buffer.?, .offset = 0 }, .indices_32bit);
                pass.drawIndexedPrimitives(@intCast(mesh.indices.len), 1, 0, 0, 0);
            }

            // Draw plane
            if (self.plane_mesh) |mesh| {
                const uniforms = Uniforms.init(
                    self.plane_transform.getMatrix(),
                    self.camera.getViewMatrix(),
                    self.camera.getProjectionMatrix(),
                );
                cmd.pushVertexUniformData(1, std.mem.asBytes(&uniforms));

                pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
                    .buffer = mesh.vertex_buffer.?,
                    .offset = 0,
                }});
                pass.bindIndexBuffer(.{ .buffer = mesh.index_buffer.?, .offset = 0 }, .indices_32bit);
                pass.drawIndexedPrimitives(@intCast(mesh.indices.len), 1, 0, 0, 0);
            }
        }

        try cmd.submit();
    }
};
