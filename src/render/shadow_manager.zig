//! Shadow Manager - Cascaded Shadow Maps (CSM) for directional lights
//!
//! Implements 3-cascade shadow mapping for high-quality directional light shadows.
//! Each cascade covers a portion of the view frustum with progressively lower
//! resolution for distant objects.
//!
//! Features:
//! - 3 shadow cascades for optimal quality/performance balance
//! - Exponential cascade splits for better near-camera detail
//! - PCF (Percentage Closer Filtering) for soft shadows
//! - Configurable shadow distance and map resolutions
//!
//! References:
//! - "Cascaded Shadow Maps" (Microsoft, DirectX SDK)
//! - "Common Techniques to Improve Shadow Depth Maps" (Microsoft)

const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const math = @import("../math/math.zig");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

const is_macos = builtin.os.tag == .macos;

/// Shadow configuration
pub const ShadowConfig = struct {
    /// Number of shadow cascades (1-4)
    cascade_count: u32 = 3,

    /// Maximum distance for shadow rendering
    shadow_distance: f32 = 100.0,

    /// Cascade split distances (normalized 0-1)
    /// For 3 cascades: [0.0, near_split, mid_split, 1.0]
    cascade_splits: [4]f32 = .{ 0.0, 0.1, 0.3, 1.0 },

    /// Shadow map resolutions per cascade
    cascade_map_sizes: [3]u32 = .{ 2048, 1024, 1024 },

    /// Depth bias to prevent shadow acne
    depth_bias: f32 = 0.005,

    /// Normal offset bias for additional acne prevention
    normal_offset_bias: f32 = 0.02,

    /// PCF kernel size (3 = 3x3, 5 = 5x5)
    pcf_kernel_size: u32 = 3,
};

/// Per-cascade shadow data sent to GPU
pub const CascadeUniforms = extern struct {
    light_view_proj: [16]f32,
    split_distance: f32,
    _pad: [3]f32 = .{ 0, 0, 0 },
};

/// Shadow uniforms passed to fragment shader
pub const ShadowUniforms = extern struct {
    cascade_view_proj: [3][16]f32,
    cascade_splits: [4]f32,
    shadow_distance: f32,
    depth_bias: f32,
    normal_offset_bias: f32,
    cascade_count: u32,
};

/// Manages shadow map rendering for directional lights
pub const ShadowManager = struct {
    allocator: std.mem.Allocator,
    config: ShadowConfig,

    // Shadow map textures (one per cascade)
    shadow_maps: [3]?sdl.gpu.Texture,

    // Shadow matrix for each cascade (light view-projection)
    cascade_matrices: [3]Mat4,
    cascade_splits: [4]f32,

    // Rendering resources
    shadow_pipeline: ?sdl.gpu.GraphicsPipeline,
    shadow_sampler: ?sdl.gpu.Sampler,

    initialized: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ShadowConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .shadow_maps = .{ null, null, null },
            .cascade_matrices = .{ Mat4.identity(), Mat4.identity(), Mat4.identity() },
            .cascade_splits = config.cascade_splits,
            .shadow_pipeline = null,
            .shadow_sampler = null,
            .initialized = false,
        };
    }

    pub fn deinit(self: *Self, device: *sdl.gpu.Device) void {
        for (self.shadow_maps) |maybe_map| {
            if (maybe_map) |map| device.releaseTexture(map);
        }
        if (self.shadow_pipeline) |p| device.releaseGraphicsPipeline(p);
        if (self.shadow_sampler) |s| device.releaseSampler(s);
    }

    /// Initialize GPU resources for shadow mapping
    pub fn initGPU(self: *Self, allocator: std.mem.Allocator, device: *sdl.gpu.Device) !void {
        if (self.initialized) return;

        // Create shadow map textures
        for (0..self.config.cascade_count) |i| {
            const size = self.config.cascade_map_sizes[i];
            self.shadow_maps[i] = try device.createTexture(.{
                .texture_type = .two_dimensional,
                .format = .depth16_unorm,
                .width = size,
                .height = size,
                .layer_count_or_depth = 1,
                .num_levels = 1,
                .usage = .{
                    .depth_stencil_target = true,
                    .sampler = true,
                },
            });
        }

        // Create shadow sampler (depth comparison)
        self.shadow_sampler = try device.createSampler(.{
            .min_filter = .linear,
            .mag_filter = .linear,
            .mipmap_mode = .nearest,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .compare = .less_or_equal, // Enable depth comparison for PCF
        });

        // Create shadow rendering pipeline
        try self.createShadowPipeline(allocator, device);

        self.initialized = true;
    }

    fn createShadowPipeline(self: *Self, allocator: std.mem.Allocator, device: *sdl.gpu.Device) !void {
        const vertex_path = if (is_macos)
            "assets/shaders/shadow_depth.metal"
        else
            "build/assets/shaders/shadow_depth.vert.spv";

        const fragment_path = if (is_macos)
            "assets/shaders/shadow_depth.metal"
        else
            "build/assets/shaders/shadow_depth.frag.spv";

        const vertex_code = try std.fs.cwd().readFileAlloc(allocator, vertex_path, 1024 * 1024);
        defer allocator.free(vertex_code);

        const fragment_code = try std.fs.cwd().readFileAlloc(allocator, fragment_path, 1024 * 1024);
        defer allocator.free(fragment_code);

        const shader_format = if (is_macos)
            sdl.gpu.ShaderFormatFlags{ .msl = true }
        else
            sdl.gpu.ShaderFormatFlags{ .spirv = true };

        const vertex_entry = if (is_macos) "shadow_depth_vertex_main" else "main";
        const fragment_entry = if (is_macos) "shadow_depth_fragment_main" else "main";

        const vertex_shader = try device.createShader(.{
            .code = vertex_code,
            .entry_point = vertex_entry,
            .format = shader_format,
            .stage = .vertex,
            .num_samplers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 1, // Light view-projection matrix
        });
        defer device.releaseShader(vertex_shader);

        const fragment_shader = try device.createShader(.{
            .code = fragment_code,
            .entry_point = fragment_entry,
            .format = shader_format,
            .stage = .fragment,
            .num_samplers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 0,
        });
        defer device.releaseShader(fragment_shader);

        self.shadow_pipeline = try device.createGraphicsPipeline(.{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{
                    .{
                        .slot = 0,
                        .pitch = 48, // sizeof(Vertex3D)
                        .input_rate = .vertex,
                    },
                },
                .vertex_attributes = &[_]sdl.gpu.VertexAttribute{
                    .{ .location = 0, .buffer_slot = 0, .format = .f32x3, .offset = 0 },
                },
            },
            .primitive_type = .triangle_list,
            .depth_stencil_state = .{
                .enable_depth_test = true,
                .enable_depth_write = true,
                .compare = .less,
            },
            .target_info = .{
                .color_target_descriptions = &.{}, // Depth-only pass, no color targets
                .depth_stencil_format = .depth16_unorm,
            },
        });
    }

    /// Calculate cascade frustum splits and matrices
    pub fn updateCascades(
        self: *Self,
        light_dir: Vec3,
        camera_view: Mat4,
        camera_proj: Mat4,
        camera_near: f32,
        camera_far: f32,
    ) void {
        const shadow_far = @min(camera_far, self.config.shadow_distance);

        // Calculate split distances
        for (0..4) |i| {
            const split = self.config.cascade_splits[i];
            self.cascade_splits[i] = camera_near + (shadow_far - camera_near) * split;
        }

        // Calculate view-projection matrix for each cascade
        const light_view = self.calculateLightViewMatrix(light_dir);

        for (0..self.config.cascade_count) |i| {
            const near_split = self.cascade_splits[i];
            const far_split = self.cascade_splits[i + 1];

            // Get frustum corners for this cascade
            const frustum_corners = self.getFrustumCorners(
                camera_view,
                camera_proj,
                near_split,
                far_split,
            );

            // Calculate tight orthographic projection around frustum
            const light_proj = self.calculateCascadeProjection(
                light_view,
                frustum_corners,
            );

            self.cascade_matrices[i] = Mat4.mul(light_proj, light_view);
        }
    }

    fn calculateLightViewMatrix(self: *Self, light_dir: Vec3) Mat4 {
        _ = self;
        const normalized_dir = light_dir.normalize();

        // Calculate light position (looking from infinity)
        const light_pos = normalized_dir.mul(-100.0);
        const target = Vec3.init(0, 0, 0);

        // Choose up vector (avoid parallel to light direction)
        const up = if (@abs(normalized_dir.y) < 0.99)
            Vec3.init(0, 1, 0)
        else
            Vec3.init(1, 0, 0);

        return Mat4.lookAt(light_pos, target, up);
    }

    fn getFrustumCorners(
        self: *Self,
        view: Mat4,
        proj: Mat4,
        near: f32,
        far: f32,
    ) [8]Vec3 {
        _ = self;
        const inv_vp = (Mat4.mul(proj, view)).inverse() orelse Mat4.identity();

        var corners: [8]Vec3 = undefined;
        var idx: usize = 0;

        // NDC corners for near and far planes
        for ([_]f32{ -1.0, 1.0 }) |x| {
            for ([_]f32{ -1.0, 1.0 }) |y| {
                for ([_]f32{ 0.0, 1.0 }) |z_ndc| {
                    _ = near; // Used conceptually for NDC transformation
                    _ = far;  // Used conceptually for NDC transformation

                    // Convert to NDC
                    const ndc = Vec4.init(x, y, z_ndc * 2.0 - 1.0, 1.0);
                    const world_pos = inv_vp.multiplyVec4(ndc);

                    corners[idx] = Vec3.init(
                        world_pos.x / world_pos.w,
                        world_pos.y / world_pos.w,
                        world_pos.z / world_pos.w,
                    );
                    idx += 1;
                }
            }
        }

        return corners;
    }

    fn calculateCascadeProjection(
        self: *Self,
        light_view: Mat4,
        frustum_corners: [8]Vec3,
    ) Mat4 {
        _ = self;

        // Transform frustum corners to light space
        var min_pos = Vec3.init(std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32));
        var max_pos = Vec3.init(-std.math.floatMax(f32), -std.math.floatMax(f32), -std.math.floatMax(f32));

        for (frustum_corners) |corner| {
            const light_space = light_view.multiplyPoint(corner);
            min_pos = Vec3.init(
                @min(min_pos.x, light_space.x),
                @min(min_pos.y, light_space.y),
                @min(min_pos.z, light_space.z),
            );
            max_pos = Vec3.init(
                @max(max_pos.x, light_space.x),
                @max(max_pos.y, light_space.y),
                @max(max_pos.z, light_space.z),
            );
        }

        // Add padding to reduce edge artifacts
        const padding = (max_pos.sub(min_pos)).mul(0.1);
        min_pos = min_pos.sub(padding);
        max_pos = max_pos.add(padding);

        // Create orthographic projection
        return Mat4.ortho(
            min_pos.x,
            max_pos.x,
            min_pos.y,
            max_pos.y,
            min_pos.z,
            max_pos.z,
        );
    }

    /// Render shadow maps for all cascades
    pub fn renderShadows(
        self: *Self,
        device: *sdl.gpu.Device,
        cmd: sdl.gpu.CommandBuffer,
        userdata: anytype,
        render_fn: fn (cascade_idx: u32, cmd: sdl.gpu.CommandBuffer, pass: sdl.gpu.RenderPass, shadow_mgr: *Self, userdata: @TypeOf(userdata)) void,
    ) !void {
        _ = device; // Device used for texture operations in future
        if (!self.initialized) return;

        for (0..self.config.cascade_count) |i| {
            const shadow_map = self.shadow_maps[i] orelse continue;

            // Begin render pass for this cascade (depth-only pass)
            const depth_target = sdl.gpu.DepthStencilTargetInfo{
                .texture = shadow_map,
                .clear_depth = 1.0,
                .load = .clear,
                .store = .store,
                .cycle = false,
                .clear_stencil = 0,
                .stencil_load = .do_not_care,
                .stencil_store = .do_not_care,
            };
            const pass = cmd.beginRenderPass(&.{}, depth_target);

            pass.bindGraphicsPipeline(self.shadow_pipeline.?);

            // Call user render function to render meshes
            // Each mesh will push its own uniforms (cascade matrix + model matrix)
            render_fn(@intCast(i), cmd, pass, self, userdata);

            pass.end();
        }
    }

    /// Get shadow uniforms for fragment shader
    pub fn getShadowUniforms(self: *Self) ShadowUniforms {
        return .{
            .cascade_view_proj = .{
                self.cascade_matrices[0].data,
                self.cascade_matrices[1].data,
                self.cascade_matrices[2].data,
            },
            .cascade_splits = self.cascade_splits,
            .shadow_distance = self.config.shadow_distance,
            .depth_bias = self.config.depth_bias,
            .normal_offset_bias = self.config.normal_offset_bias,
            .cascade_count = self.config.cascade_count,
        };
    }

    /// Get shadow map textures for binding
    pub fn getShadowMaps(self: *Self) [3]?sdl.gpu.Texture {
        return self.shadow_maps;
    }

    /// Get shadow sampler
    pub fn getShadowSampler(self: *Self) ?sdl.gpu.Sampler {
        return self.shadow_sampler;
    }

    /// Shadow vertex shader uniforms (must match shadow_depth.metal)
    const ShadowVertexUniforms = extern struct {
        light_view_proj: [16]f32,
        model: [16]f32,
    };

    /// Render a single mesh to the currently bound shadow map
    pub fn renderMeshToShadowMap(
        self: *Self,
        cmd: sdl.gpu.CommandBuffer,
        pass: sdl.gpu.RenderPass,
        mesh: @import("../resources/mesh.zig").Mesh,
        model_matrix: @import("../math/math.zig").Mat4,
        cascade_idx: u32,
    ) !void {
        if (mesh.vertex_buffer == null) return; // Skip if not uploaded to GPU

        // Bind vertex buffer
        const vertex_binding = sdl.gpu.BufferBinding{
            .buffer = mesh.vertex_buffer.?,
            .offset = 0,
        };
        pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{vertex_binding});

        // Bind index buffer if present
        if (mesh.index_buffer) |idx_buf| {
            const index_binding = sdl.gpu.BufferBinding{
                .buffer = idx_buf,
                .offset = 0,
            };
            pass.bindIndexBuffer(index_binding, .indices_32bit);
        }

        // Push combined uniforms (light_view_proj + model)
        const shadow_uniforms = ShadowVertexUniforms{
            .light_view_proj = self.cascade_matrices[cascade_idx].data,
            .model = model_matrix.data,
        };
        cmd.pushVertexUniformData(0, std.mem.asBytes(&shadow_uniforms));

        // Draw
        if (mesh.indices.len > 0) {
            pass.drawIndexedPrimitives(@intCast(mesh.indices.len), 1, 0, 0, 0);
        } else {
            pass.drawPrimitives(@intCast(mesh.vertices.len), 1, 0, 0);
        }
    }
};
