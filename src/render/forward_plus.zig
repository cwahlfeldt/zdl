//! Forward+ Rendering System
//!
//! Implements clustered forward rendering for efficient many-light scenes.
//! The view frustum is divided into a 3D grid of clusters, and lights are
//! assigned to clusters via compute shader. During rendering, fragments
//! only process lights assigned to their cluster.
//!
//! Key components:
//! - Cluster grid: 16x9x24 (adjustable) clusters covering the view frustum
//! - Light culling compute shader: Tests light-cluster intersections
//! - Storage buffers: Light grid (offset+count) and global light index list
//!
//! References:
//! - "A Primer On Efficient Rendering Algorithms & Clustered Shading" (aortiz.me)
//! - DOOM 2016 GDC presentation on clustered shading
//! - Intel Forward Clustered Shading sample

const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

// Platform-specific shader configuration
const is_macos = builtin.os.tag == .macos;

/// Configuration for Forward+ clustering
pub const ForwardPlusConfig = struct {
    /// Number of clusters in X dimension (screen width)
    cluster_count_x: u32 = 16,
    /// Number of clusters in Y dimension (screen height)
    cluster_count_y: u32 = 9,
    /// Number of clusters in Z dimension (depth slices)
    cluster_count_z: u32 = 24,
    /// Maximum number of lights per cluster
    max_lights_per_cluster: u32 = 128,
    /// Maximum total lights in scene
    max_total_lights: u32 = 1024,
    /// Near plane for cluster depth subdivision
    near_plane: f32 = 0.1,
    /// Far plane for cluster depth subdivision
    far_plane: f32 = 1000.0,

    pub fn totalClusterCount(self: ForwardPlusConfig) u32 {
        return self.cluster_count_x * self.cluster_count_y * self.cluster_count_z;
    }

    pub fn maxLightIndices(self: ForwardPlusConfig) u32 {
        return self.totalClusterCount() * self.max_lights_per_cluster;
    }
};

/// GPU-side point light data for Forward+ (matches compute shader layout)
pub const GPUPointLight = extern struct {
    position: [4]f32, // xyz = position, w = range
    color: [4]f32, // rgb = color, a = intensity

    pub fn init(pos: Vec3, range: f32, color: Vec3, intensity: f32) GPUPointLight {
        return .{
            .position = .{ pos.x, pos.y, pos.z, range },
            .color = .{ color.x, color.y, color.z, intensity },
        };
    }
};

/// GPU-side spot light data for Forward+ (matches compute shader layout)
pub const GPUSpotLight = extern struct {
    position: [4]f32, // xyz = position, w = range
    direction: [4]f32, // xyz = direction, w = outer_cos
    color: [4]f32, // rgb = color, a = intensity
    inner_pad: [4]f32, // x = inner_cos, yzw = padding

    pub fn init(pos: Vec3, range: f32, dir: Vec3, outer_cos: f32, color: Vec3, intensity: f32, inner_cos: f32) GPUSpotLight {
        return .{
            .position = .{ pos.x, pos.y, pos.z, range },
            .direction = .{ dir.x, dir.y, dir.z, outer_cos },
            .color = .{ color.x, color.y, color.z, intensity },
            .inner_pad = .{ inner_cos, 0, 0, 0 },
        };
    }
};

/// Cluster AABB for light culling (computed on CPU or GPU)
pub const ClusterAABB = extern struct {
    min_point: [4]f32,
    max_point: [4]f32,
};

/// Per-cluster light list metadata
pub const LightGrid = extern struct {
    offset: u32, // Offset into global light index list
    count: u32, // Number of lights in this cluster
};

/// Cluster uniforms passed to compute shader
pub const ClusterUniforms = extern struct {
    // View-projection matrices
    view_matrix: [16]f32,
    inv_proj_matrix: [16]f32,

    // Screen and cluster dimensions
    screen_width: f32,
    screen_height: f32,
    cluster_count_x: u32,
    cluster_count_y: u32,

    cluster_count_z: u32,
    near_plane: f32,
    far_plane: f32,
    _pad0: f32 = 0,

    // Light counts
    point_light_count: u32,
    spot_light_count: u32,
    _pad1: [2]u32 = .{ 0, 0 },

    pub fn init(
        view: Mat4,
        inv_proj: Mat4,
        screen_width: f32,
        screen_height: f32,
        config: ForwardPlusConfig,
        point_count: u32,
        spot_count: u32,
    ) ClusterUniforms {
        return .{
            .view_matrix = view.data,
            .inv_proj_matrix = inv_proj.data,
            .screen_width = screen_width,
            .screen_height = screen_height,
            .cluster_count_x = config.cluster_count_x,
            .cluster_count_y = config.cluster_count_y,
            .cluster_count_z = config.cluster_count_z,
            .near_plane = config.near_plane,
            .far_plane = config.far_plane,
            .point_light_count = point_count,
            .spot_light_count = spot_count,
        };
    }
};

comptime {
    if (@sizeOf(ClusterUniforms) != 176) {
        @compileError("ClusterUniforms size must match std140 layout.");
    }
}

/// Manages Forward+ rendering resources and light culling
pub const ForwardPlusManager = struct {
    allocator: std.mem.Allocator,
    config: ForwardPlusConfig,

    // Compute pipeline for light culling
    light_cull_pipeline: ?sdl.gpu.ComputePipeline,

    // Storage buffers
    cluster_aabb_buffer: ?sdl.gpu.Buffer, // ClusterAABB per cluster
    light_grid_buffer: ?sdl.gpu.Buffer, // LightGrid per cluster
    light_index_buffer: ?sdl.gpu.Buffer, // Global light index list
    point_light_buffer: ?sdl.gpu.Buffer, // All point lights
    spot_light_buffer: ?sdl.gpu.Buffer, // All spot lights

    // CPU-side light arrays for upload
    point_lights: std.ArrayListUnmanaged(GPUPointLight),
    spot_lights: std.ArrayListUnmanaged(GPUSpotLight),

    // Cluster AABBs (computed once per frame when view changes)
    cluster_aabbs: []ClusterAABB,
    aabbs_dirty: bool,

    // Current frame state
    current_view: Mat4,
    current_proj: Mat4,
    screen_width: u32,
    screen_height: u32,

    // Initialization state
    initialized: bool,

    // CPU-only mode (fallback when compute shaders unavailable)
    cpu_mode: bool,

    // CPU-side light grid and indices (for CPU culling mode)
    cpu_light_grid: []LightGrid,
    cpu_light_indices: []u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ForwardPlusConfig) Self {
        const total_clusters = config.totalClusterCount();
        const max_indices = config.maxLightIndices();

        return .{
            .allocator = allocator,
            .config = config,
            .light_cull_pipeline = null,
            .cluster_aabb_buffer = null,
            .light_grid_buffer = null,
            .light_index_buffer = null,
            .point_light_buffer = null,
            .spot_light_buffer = null,
            .point_lights = .{},
            .spot_lights = .{},
            .cluster_aabbs = allocator.alloc(ClusterAABB, total_clusters) catch &[_]ClusterAABB{},
            .aabbs_dirty = true,
            .current_view = Mat4.identity(),
            .current_proj = Mat4.identity(),
            .screen_width = 1280,
            .screen_height = 720,
            .initialized = false,
            .cpu_mode = false,
            .cpu_light_grid = allocator.alloc(LightGrid, total_clusters) catch &[_]LightGrid{},
            .cpu_light_indices = allocator.alloc(u32, max_indices) catch &[_]u32{},
        };
    }

    pub fn deinit(self: *Self, device: *sdl.gpu.Device) void {
        if (self.light_cull_pipeline) |p| device.releaseComputePipeline(p);
        if (self.cluster_aabb_buffer) |b| device.releaseBuffer(b);
        if (self.light_grid_buffer) |b| device.releaseBuffer(b);
        if (self.light_index_buffer) |b| device.releaseBuffer(b);
        if (self.point_light_buffer) |b| device.releaseBuffer(b);
        if (self.spot_light_buffer) |b| device.releaseBuffer(b);

        self.point_lights.deinit(self.allocator);
        self.spot_lights.deinit(self.allocator);

        if (self.cluster_aabbs.len > 0) {
            self.allocator.free(self.cluster_aabbs);
        }
        if (self.cpu_light_grid.len > 0) {
            self.allocator.free(self.cpu_light_grid);
        }
        if (self.cpu_light_indices.len > 0) {
            self.allocator.free(self.cpu_light_indices);
        }
    }

    /// Initialize GPU resources for Forward+ (CPU culling mode)
    /// This uses CPU-based light culling which is more compatible but less performant.
    pub fn initGPU(self: *Self, allocator: std.mem.Allocator, device: *sdl.gpu.Device) !void {
        _ = allocator;
        if (self.initialized) return;

        const total_clusters = self.config.totalClusterCount();
        const max_indices = self.config.maxLightIndices();

        // Use CPU mode - more compatible, avoids compute shader driver issues
        self.cpu_mode = true;

        // Create light grid buffer (written by CPU, read by fragment)
        self.light_grid_buffer = try device.createBuffer(.{
            .size = total_clusters * @sizeOf(LightGrid),
            .usage = .{
                .graphics_storage_read = true,
            },
        });

        // Create light index buffer (written by CPU, read by fragment)
        self.light_index_buffer = try device.createBuffer(.{
            .size = max_indices * @sizeOf(u32),
            .usage = .{
                .graphics_storage_read = true,
            },
        });

        // Create point light buffer (written by CPU, read by fragment)
        self.point_light_buffer = try device.createBuffer(.{
            .size = self.config.max_total_lights * @sizeOf(GPUPointLight),
            .usage = .{
                .graphics_storage_read = true,
            },
        });

        // Create spot light buffer (written by CPU, read by fragment)
        self.spot_light_buffer = try device.createBuffer(.{
            .size = self.config.max_total_lights * @sizeOf(GPUSpotLight),
            .usage = .{
                .graphics_storage_read = true,
            },
        });

        self.initialized = true;
    }

    /// Initialize GPU resources for Forward+ with GPU compute culling
    /// This uses a compute shader for light culling - more performant but requires proper driver support.
    pub fn initGPUCompute(self: *Self, allocator: std.mem.Allocator, device: *sdl.gpu.Device) !void {
        if (self.initialized) return;

        const total_clusters = self.config.totalClusterCount();
        const max_indices = self.config.maxLightIndices();

        // GPU compute mode
        self.cpu_mode = false;

        // Create compute pipeline
        try self.createComputePipeline(allocator, device);

        // Create cluster AABB buffer (written by CPU once per view change, read by compute)
        self.cluster_aabb_buffer = try device.createBuffer(.{
            .size = total_clusters * @sizeOf(ClusterAABB),
            .usage = .{
                .compute_storage_read = true,
            },
        });

        // Create light grid buffer (written by compute, read by fragment)
        self.light_grid_buffer = try device.createBuffer(.{
            .size = total_clusters * @sizeOf(LightGrid),
            .usage = .{
                .compute_storage_write = true,
                .graphics_storage_read = true,
            },
        });

        // Create light index buffer (written by compute, read by fragment)
        self.light_index_buffer = try device.createBuffer(.{
            .size = max_indices * @sizeOf(u32),
            .usage = .{
                .compute_storage_write = true,
                .graphics_storage_read = true,
            },
        });

        // Create point light buffer (written by CPU, read by compute and fragment)
        self.point_light_buffer = try device.createBuffer(.{
            .size = self.config.max_total_lights * @sizeOf(GPUPointLight),
            .usage = .{
                .compute_storage_read = true,
                .graphics_storage_read = true,
            },
        });

        // Create spot light buffer (written by CPU, read by compute and fragment)
        self.spot_light_buffer = try device.createBuffer(.{
            .size = self.config.max_total_lights * @sizeOf(GPUSpotLight),
            .usage = .{
                .compute_storage_read = true,
                .graphics_storage_read = true,
            },
        });

        self.initialized = true;
    }

    fn createComputePipeline(self: *Self, allocator: std.mem.Allocator, device: *sdl.gpu.Device) !void {
        const shader_path = if (is_macos)
            "assets/shaders/light_cull.metal"
        else
            "build/assets/shaders/light_cull.comp.spv";

        const shader_code = try std.fs.cwd().readFileAlloc(
            allocator,
            shader_path,
            1024 * 1024,
        );
        defer allocator.free(shader_code);

        const shader_format = if (is_macos)
            sdl.gpu.ShaderFormatFlags{ .msl = true }
        else
            sdl.gpu.ShaderFormatFlags{ .spirv = true };

        const entry_point = if (is_macos) "light_cull_main" else "main";

        self.light_cull_pipeline = try device.createComputePipeline(.{
            .code = shader_code,
            .entry_point = entry_point,
            .format = shader_format,
            .num_readonly_storage_buffers = 3, // cluster AABBs, point lights, spot lights
            .num_readwrite_storage_buffers = 2, // light grid, light indices
            .num_uniform_buffers = 1, // cluster uniforms
            .thread_count_x = 16,
            .thread_count_y = 9,
            .thread_count_z = 1,
        });
    }

    /// Clear lights for new frame
    pub fn clearLights(self: *Self) void {
        self.point_lights.clearRetainingCapacity();
        self.spot_lights.clearRetainingCapacity();
    }

    /// Add a point light
    pub fn addPointLight(self: *Self, position: Vec3, range: f32, color: Vec3, intensity: f32) !void {
        if (self.point_lights.items.len >= self.config.max_total_lights) return;
        try self.point_lights.append(self.allocator, GPUPointLight.init(position, range, color, intensity));
    }

    /// Add a spot light
    pub fn addSpotLight(
        self: *Self,
        position: Vec3,
        range: f32,
        direction: Vec3,
        outer_angle: f32,
        inner_angle: f32,
        color: Vec3,
        intensity: f32,
    ) !void {
        if (self.spot_lights.items.len >= self.config.max_total_lights) return;
        const outer_cos = @cos(outer_angle);
        const inner_cos = @cos(inner_angle);
        try self.spot_lights.append(self.allocator, GPUSpotLight.init(
            position,
            range,
            direction.normalize(),
            outer_cos,
            color,
            intensity,
            inner_cos,
        ));
    }

    /// Update view/projection matrices
    pub fn setViewProjection(self: *Self, view: Mat4, projection: Mat4, width: u32, height: u32) void {
        // Check if view changed significantly
        const view_changed = !std.mem.eql(f32, &self.current_view.data, &view.data);
        const proj_changed = !std.mem.eql(f32, &self.current_proj.data, &projection.data);
        const size_changed = self.screen_width != width or self.screen_height != height;

        if (view_changed or proj_changed or size_changed) {
            self.aabbs_dirty = true;
            self.current_view = view;
            self.current_proj = projection;
            self.screen_width = width;
            self.screen_height = height;
        }
    }

    /// Compute cluster AABBs on CPU
    /// Uses exponential depth slicing from DOOM 2016
    pub fn computeClusterAABBs(self: *Self) void {
        if (!self.aabbs_dirty) return;

        const inv_proj = self.current_proj.inverse() orelse Mat4.identity();
        const near = self.config.near_plane;
        const far = self.config.far_plane;

        const cluster_x = self.config.cluster_count_x;
        const cluster_y = self.config.cluster_count_y;
        const cluster_z = self.config.cluster_count_z;

        const screen_w: f32 = @floatFromInt(self.screen_width);
        const screen_h: f32 = @floatFromInt(self.screen_height);

        // Tile size in screen space
        const tile_w = screen_w / @as(f32, @floatFromInt(cluster_x));
        const tile_h = screen_h / @as(f32, @floatFromInt(cluster_y));

        for (0..cluster_z) |z| {
            // Exponential depth slicing: z_near * (z_far/z_near)^(slice/num_slices)
            const z_near_slice = near * std.math.pow(f32, far / near, @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(cluster_z)));
            const z_far_slice = near * std.math.pow(f32, far / near, @as(f32, @floatFromInt(z + 1)) / @as(f32, @floatFromInt(cluster_z)));

            for (0..cluster_y) |y| {
                for (0..cluster_x) |x| {
                    const cluster_idx = z * cluster_y * cluster_x + y * cluster_x + x;

                    // Screen-space bounds for this tile
                    const screen_min_x = @as(f32, @floatFromInt(x)) * tile_w;
                    const screen_max_x = @as(f32, @floatFromInt(x + 1)) * tile_w;
                    const screen_min_y = @as(f32, @floatFromInt(y)) * tile_h;
                    const screen_max_y = @as(f32, @floatFromInt(y + 1)) * tile_h;

                    // Convert screen corners to NDC
                    const ndc_min_x = (screen_min_x / screen_w) * 2.0 - 1.0;
                    const ndc_max_x = (screen_max_x / screen_w) * 2.0 - 1.0;
                    const ndc_min_y = 1.0 - (screen_max_y / screen_h) * 2.0; // Y flipped
                    const ndc_max_y = 1.0 - (screen_min_y / screen_h) * 2.0;

                    // Compute 8 corners of the cluster frustum in view space
                    var min_point = Vec3.init(std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32));
                    var max_point = Vec3.init(-std.math.floatMax(f32), -std.math.floatMax(f32), -std.math.floatMax(f32));

                    const corners = [_][3]f32{
                        .{ ndc_min_x, ndc_min_y, 0 },
                        .{ ndc_max_x, ndc_min_y, 0 },
                        .{ ndc_min_x, ndc_max_y, 0 },
                        .{ ndc_max_x, ndc_max_y, 0 },
                    };

                    for (corners) |ndc| {
                        // Unproject to view space at near and far depths
                        for ([_]f32{ z_near_slice, z_far_slice }) |depth| {
                            const view_pos = self.unprojectToView(inv_proj, ndc[0], ndc[1], depth);
                            min_point = Vec3.init(
                                @min(min_point.x, view_pos.x),
                                @min(min_point.y, view_pos.y),
                                @min(min_point.z, view_pos.z),
                            );
                            max_point = Vec3.init(
                                @max(max_point.x, view_pos.x),
                                @max(max_point.y, view_pos.y),
                                @max(max_point.z, view_pos.z),
                            );
                        }
                    }

                    self.cluster_aabbs[cluster_idx] = .{
                        .min_point = .{ min_point.x, min_point.y, min_point.z, 1.0 },
                        .max_point = .{ max_point.x, max_point.y, max_point.z, 1.0 },
                    };
                }
            }
        }

        self.aabbs_dirty = false;
    }

    fn unprojectToView(self: *Self, inv_proj: Mat4, ndc_x: f32, ndc_y: f32, view_z: f32) Vec3 {
        _ = self;
        // For perspective projection, we need to find the point at view_z
        // that projects to the given NDC coordinates

        // Start with a point in clip space
        const clip = Vec4.init(ndc_x, ndc_y, 0, 1);

        // Unproject to view space (at z=1)
        var view = inv_proj.multiplyVec4(clip);
        view.x /= view.w;
        view.y /= view.w;
        view.z /= view.w;

        // Scale to the desired depth
        // For perspective, points on the same ray scale linearly with depth
        const scale = -view_z / view.z; // Negative because view space Z is negative
        return Vec3.init(view.x * scale, view.y * scale, -view_z);
    }

    /// Upload light data to GPU and perform light culling
    /// In CPU mode, culling is done on CPU and results are uploaded.
    /// In GPU mode, a compute shader performs the culling.
    pub fn cullLights(self: *Self, device: *sdl.gpu.Device, cmd: sdl.gpu.CommandBuffer) !void {
        if (!self.initialized) return;
        if (self.point_lights.items.len == 0 and self.spot_lights.items.len == 0) return;

        // Compute cluster AABBs if needed (always done on CPU)
        self.computeClusterAABBs();

        if (self.cpu_mode) {
            // CPU-based light culling
            try self.cullLightsCPU(device, cmd);
        } else {
            // GPU compute-based light culling
            try self.cullLightsGPU(device, cmd);
        }
    }

    /// CPU-based culling path - uploads pre-culled results
    fn cullLightsCPU(self: *Self, device: *sdl.gpu.Device, cmd: sdl.gpu.CommandBuffer) !void {
        // Perform CPU culling
        self.cpuCullLights();

        // Create a copy pass to upload data
        const copy_pass = cmd.beginCopyPass();

        // Upload light grid
        const grid_size = self.cpu_light_grid.len * @sizeOf(LightGrid);
        const grid_transfer = try device.createTransferBuffer(.{
            .size = @intCast(grid_size),
            .usage = .upload,
        });
        defer device.releaseTransferBuffer(grid_transfer);

        const grid_ptr: [*]LightGrid = @ptrCast(@alignCast(try device.mapTransferBuffer(grid_transfer, true)));
        @memcpy(grid_ptr[0..self.cpu_light_grid.len], self.cpu_light_grid);
        device.unmapTransferBuffer(grid_transfer);

        copy_pass.uploadToBuffer(.{
            .transfer_buffer = grid_transfer,
            .offset = 0,
        }, .{
            .buffer = self.light_grid_buffer.?,
            .offset = 0,
            .size = @intCast(grid_size),
        }, false);

        // Calculate total light indices used
        var total_indices: usize = 0;
        for (self.cpu_light_grid) |grid| {
            total_indices = @max(total_indices, grid.offset + grid.count);
        }

        // Upload light indices if any
        if (total_indices > 0) {
            const indices_size = total_indices * @sizeOf(u32);
            const indices_transfer = try device.createTransferBuffer(.{
                .size = @intCast(indices_size),
                .usage = .upload,
            });
            defer device.releaseTransferBuffer(indices_transfer);

            const indices_ptr: [*]u32 = @ptrCast(@alignCast(try device.mapTransferBuffer(indices_transfer, true)));
            @memcpy(indices_ptr[0..total_indices], self.cpu_light_indices[0..total_indices]);
            device.unmapTransferBuffer(indices_transfer);

            copy_pass.uploadToBuffer(.{
                .transfer_buffer = indices_transfer,
                .offset = 0,
            }, .{
                .buffer = self.light_index_buffer.?,
                .offset = 0,
                .size = @intCast(indices_size),
            }, false);
        }

        // Upload point lights
        if (self.point_lights.items.len > 0) {
            const point_size = self.point_lights.items.len * @sizeOf(GPUPointLight);
            const point_transfer = try device.createTransferBuffer(.{
                .size = @intCast(point_size),
                .usage = .upload,
            });
            defer device.releaseTransferBuffer(point_transfer);

            const point_ptr: [*]GPUPointLight = @ptrCast(@alignCast(try device.mapTransferBuffer(point_transfer, true)));
            @memcpy(point_ptr[0..self.point_lights.items.len], self.point_lights.items);
            device.unmapTransferBuffer(point_transfer);

            copy_pass.uploadToBuffer(.{
                .transfer_buffer = point_transfer,
                .offset = 0,
            }, .{
                .buffer = self.point_light_buffer.?,
                .offset = 0,
                .size = @intCast(point_size),
            }, false);
        }

        // Upload spot lights
        if (self.spot_lights.items.len > 0) {
            const spot_size = self.spot_lights.items.len * @sizeOf(GPUSpotLight);
            const spot_transfer = try device.createTransferBuffer(.{
                .size = @intCast(spot_size),
                .usage = .upload,
            });
            defer device.releaseTransferBuffer(spot_transfer);

            const spot_ptr: [*]GPUSpotLight = @ptrCast(@alignCast(try device.mapTransferBuffer(spot_transfer, true)));
            @memcpy(spot_ptr[0..self.spot_lights.items.len], self.spot_lights.items);
            device.unmapTransferBuffer(spot_transfer);

            copy_pass.uploadToBuffer(.{
                .transfer_buffer = spot_transfer,
                .offset = 0,
            }, .{
                .buffer = self.spot_light_buffer.?,
                .offset = 0,
                .size = @intCast(spot_size),
            }, false);
        }

        copy_pass.end();
    }

    /// GPU compute-based culling path - dispatches compute shader
    fn cullLightsGPU(self: *Self, device: *sdl.gpu.Device, cmd: sdl.gpu.CommandBuffer) !void {
        const total_clusters = self.config.totalClusterCount();

        // First, upload data via copy pass
        const copy_pass = cmd.beginCopyPass();

        // Upload cluster AABBs (if dirty)
        if (self.aabbs_dirty or true) { // Always upload for now to ensure correctness
            const aabb_size = total_clusters * @sizeOf(ClusterAABB);
            const aabb_transfer = try device.createTransferBuffer(.{
                .size = @intCast(aabb_size),
                .usage = .upload,
            });
            defer device.releaseTransferBuffer(aabb_transfer);

            const aabb_ptr: [*]ClusterAABB = @ptrCast(@alignCast(try device.mapTransferBuffer(aabb_transfer, true)));
            @memcpy(aabb_ptr[0..total_clusters], self.cluster_aabbs);
            device.unmapTransferBuffer(aabb_transfer);

            copy_pass.uploadToBuffer(.{
                .transfer_buffer = aabb_transfer,
                .offset = 0,
            }, .{
                .buffer = self.cluster_aabb_buffer.?,
                .offset = 0,
                .size = @intCast(aabb_size),
            }, false);
        }

        // Upload point lights
        if (self.point_lights.items.len > 0) {
            const point_size = self.point_lights.items.len * @sizeOf(GPUPointLight);
            const point_transfer = try device.createTransferBuffer(.{
                .size = @intCast(point_size),
                .usage = .upload,
            });
            defer device.releaseTransferBuffer(point_transfer);

            const point_ptr: [*]GPUPointLight = @ptrCast(@alignCast(try device.mapTransferBuffer(point_transfer, true)));
            @memcpy(point_ptr[0..self.point_lights.items.len], self.point_lights.items);
            device.unmapTransferBuffer(point_transfer);

            copy_pass.uploadToBuffer(.{
                .transfer_buffer = point_transfer,
                .offset = 0,
            }, .{
                .buffer = self.point_light_buffer.?,
                .offset = 0,
                .size = @intCast(point_size),
            }, false);
        }

        // Upload spot lights
        if (self.spot_lights.items.len > 0) {
            const spot_size = self.spot_lights.items.len * @sizeOf(GPUSpotLight);
            const spot_transfer = try device.createTransferBuffer(.{
                .size = @intCast(spot_size),
                .usage = .upload,
            });
            defer device.releaseTransferBuffer(spot_transfer);

            const spot_ptr: [*]GPUSpotLight = @ptrCast(@alignCast(try device.mapTransferBuffer(spot_transfer, true)));
            @memcpy(spot_ptr[0..self.spot_lights.items.len], self.spot_lights.items);
            device.unmapTransferBuffer(spot_transfer);

            copy_pass.uploadToBuffer(.{
                .transfer_buffer = spot_transfer,
                .offset = 0,
            }, .{
                .buffer = self.spot_light_buffer.?,
                .offset = 0,
                .size = @intCast(spot_size),
            }, false);
        }

        copy_pass.end();

        // Now dispatch compute shader
        const compute_pass = cmd.beginComputePass(
            // No storage textures
            &[_]sdl.gpu.StorageTextureReadWriteBinding{},
            // Read-write storage buffers bound at pass start
            &[_]sdl.gpu.StorageBufferReadWriteBinding{
                .{ .buffer = self.light_grid_buffer.?, .cycle = false },
                .{ .buffer = self.light_index_buffer.?, .cycle = false },
            },
        );

        compute_pass.bindPipeline(self.light_cull_pipeline.?);

        // Bind read-only storage buffers (set 0: cluster AABBs, point lights, spot lights)
        compute_pass.bindStorageBuffers(0, &[_]sdl.gpu.Buffer{
            self.cluster_aabb_buffer.?,
            self.point_light_buffer.?,
            self.spot_light_buffer.?,
        });

        // Push uniform data
        const inv_proj = self.current_proj.inverse() orelse Mat4.identity();
        const uniforms = ClusterUniforms.init(
            self.current_view,
            inv_proj,
            @floatFromInt(self.screen_width),
            @floatFromInt(self.screen_height),
            self.config,
            @intCast(self.point_lights.items.len),
            @intCast(self.spot_lights.items.len),
        );
        cmd.pushComputeUniformData(0, std.mem.asBytes(&uniforms));

        // Dispatch: one workgroup per Z slice
        // Each workgroup is 16x9x1 threads (one thread per cluster in that slice)
        compute_pass.dispatch(1, 1, self.config.cluster_count_z);

        compute_pass.end();
    }

    /// CPU-based light culling - assigns lights to clusters
    fn cpuCullLights(self: *Self) void {
        const total_clusters = self.config.totalClusterCount();
        const max_per_cluster = self.config.max_lights_per_cluster;

        // Reset grid
        for (0..total_clusters) |i| {
            self.cpu_light_grid[i] = .{ .offset = 0, .count = 0 };
        }

        var global_index: u32 = 0;

        // For each cluster, test all lights
        for (0..total_clusters) |cluster_idx| {
            const aabb = self.cluster_aabbs[cluster_idx];
            const aabb_min = Vec3.init(aabb.min_point[0], aabb.min_point[1], aabb.min_point[2]);
            const aabb_max = Vec3.init(aabb.max_point[0], aabb.max_point[1], aabb.max_point[2]);

            const start_index = global_index;
            var count: u32 = 0;

            // Test point lights
            for (self.point_lights.items, 0..) |light, light_idx| {
                if (count >= max_per_cluster) break;

                const world_pos = Vec3.init(light.position[0], light.position[1], light.position[2]);
                const range = light.position[3];

                // Transform to view space
                const view_pos = self.current_view.multiplyPoint(world_pos);

                if (self.sphereAABBIntersect(view_pos, range, aabb_min, aabb_max)) {
                    if (global_index < self.cpu_light_indices.len) {
                        self.cpu_light_indices[global_index] = @intCast(light_idx);
                        global_index += 1;
                        count += 1;
                    }
                }
            }

            // Test spot lights
            for (self.spot_lights.items, 0..) |light, light_idx| {
                if (count >= max_per_cluster) break;

                const world_pos = Vec3.init(light.position[0], light.position[1], light.position[2]);
                const world_dir = Vec3.init(light.direction[0], light.direction[1], light.direction[2]);
                const range = light.position[3];
                const outer_cos = light.direction[3];

                // Transform to view space
                const view_pos = self.current_view.multiplyPoint(world_pos);
                const view_dir = self.current_view.multiplyDirection(world_dir).normalize();

                if (self.coneAABBIntersect(view_pos, view_dir, range, outer_cos, aabb_min, aabb_max)) {
                    if (global_index < self.cpu_light_indices.len) {
                        // High bit indicates spot light
                        self.cpu_light_indices[global_index] = @as(u32, @intCast(light_idx)) | 0x80000000;
                        global_index += 1;
                        count += 1;
                    }
                }
            }

            self.cpu_light_grid[cluster_idx] = .{
                .offset = start_index,
                .count = count,
            };
        }
    }

    /// Test sphere-AABB intersection
    fn sphereAABBIntersect(self: *Self, center: Vec3, radius: f32, aabb_min: Vec3, aabb_max: Vec3) bool {
        _ = self;
        // Find closest point on AABB to sphere center
        const closest = Vec3.init(
            @max(aabb_min.x, @min(center.x, aabb_max.x)),
            @max(aabb_min.y, @min(center.y, aabb_max.y)),
            @max(aabb_min.z, @min(center.z, aabb_max.z)),
        );

        // Check if closest point is within sphere radius
        const diff = center.sub(closest);
        const dist_sq = diff.dot(diff);

        return dist_sq <= (radius * radius);
    }

    /// Test cone-AABB intersection (simplified using bounding sphere)
    fn coneAABBIntersect(self: *Self, apex: Vec3, direction: Vec3, range: f32, outer_cos: f32, aabb_min: Vec3, aabb_max: Vec3) bool {
        // Use bounding sphere approximation
        const center = apex.add(direction.mul(range * 0.5));
        var radius = range * 0.5 / @max(outer_cos, 0.001);
        radius = @min(radius, range * 2.0);

        return self.sphereAABBIntersect(center, radius, aabb_min, aabb_max);
    }

    /// Get the light grid buffer for binding in fragment shader
    pub fn getLightGridBuffer(self: *Self) ?sdl.gpu.Buffer {
        return self.light_grid_buffer;
    }

    /// Get the light index buffer for binding in fragment shader
    pub fn getLightIndexBuffer(self: *Self) ?sdl.gpu.Buffer {
        return self.light_index_buffer;
    }

    /// Get the point light buffer for binding in fragment shader
    pub fn getPointLightBuffer(self: *Self) ?sdl.gpu.Buffer {
        return self.point_light_buffer;
    }

    /// Get the spot light buffer for binding in fragment shader
    pub fn getSpotLightBuffer(self: *Self) ?sdl.gpu.Buffer {
        return self.spot_light_buffer;
    }

    /// Get current point light count
    pub fn getPointLightCount(self: *Self) u32 {
        return @intCast(self.point_lights.items.len);
    }

    /// Get current spot light count
    pub fn getSpotLightCount(self: *Self) u32 {
        return @intCast(self.spot_lights.items.len);
    }

    /// Get the configuration
    pub fn getConfig(self: *Self) ForwardPlusConfig {
        return self.config;
    }
};

// Size verification
comptime {
    // Ensure GPU structures are properly sized for std430 layout
    std.debug.assert(@sizeOf(GPUPointLight) == 32);
    std.debug.assert(@sizeOf(GPUSpotLight) == 64);
    std.debug.assert(@sizeOf(ClusterAABB) == 32);
    std.debug.assert(@sizeOf(LightGrid) == 8);
}
