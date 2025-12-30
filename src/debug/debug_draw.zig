const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Mat4 = @import("../math/mat4.zig").Mat4;
const Color = @import("../engine/engine.zig").Color;

/// Vertex format for debug line rendering (position + color)
pub const LineVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn init(pos: Vec3, color: Color) LineVertex {
        return .{
            .x = pos.x,
            .y = pos.y,
            .z = pos.z,
            .r = color.r,
            .g = color.g,
            .b = color.b,
            .a = color.a,
        };
    }
};

/// Persistent line with duration
const PersistentLine = struct {
    from: Vec3,
    to: Vec3,
    color: Color,
    remaining_time: f32,
};

/// Debug uniforms for line shader
pub const DebugUniforms = struct {
    view_projection: [16]f32,
};

/// Platform-specific shader configuration
const is_macos = builtin.os.tag == .macos;
const ShaderConfig = if (is_macos) struct {
    const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
    const vertex_path = "assets/shaders/debug_line.metal";
    const fragment_path = "assets/shaders/debug_line.metal";
    const vertex_entry = "debug_vertex_main";
    const fragment_entry = "debug_fragment_main";
} else struct {
    const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
    const vertex_path = "build/assets/shaders/debug_line_vertex.spv";
    const fragment_path = "build/assets/shaders/debug_line_fragment.spv";
    const vertex_entry = "main";
    const fragment_entry = "main";
};

/// Visual debug rendering system for lines, boxes, spheres, etc.
pub const DebugDraw = struct {
    allocator: std.mem.Allocator,

    // Batched line vertices (pairs of vertices form lines)
    lines: std.array_list.Managed(LineVertex),

    // Persistent draws
    persistent_lines: std.array_list.Managed(PersistentLine),

    // GPU resources (initialized lazily)
    pipeline: ?sdl.gpu.GraphicsPipeline,
    vertex_buffer: ?sdl.gpu.Buffer,
    vertex_buffer_size: usize,

    // Settings
    enabled: bool,
    depth_test: bool,

    // Maximum vertices before flush
    const MAX_VERTICES: usize = 65536;
    const VERTEX_BUFFER_SIZE: usize = MAX_VERTICES * @sizeOf(LineVertex);

    pub fn init(allocator: std.mem.Allocator) DebugDraw {
        return .{
            .allocator = allocator,
            .lines = std.array_list.Managed(LineVertex).init(allocator),
            .persistent_lines = std.array_list.Managed(PersistentLine).init(allocator),
            .pipeline = null,
            .vertex_buffer = null,
            .vertex_buffer_size = 0,
            .enabled = true,
            .depth_test = true,
        };
    }

    pub fn deinit(self: *DebugDraw, device: ?*sdl.gpu.Device) void {
        if (device) |dev| {
            if (self.pipeline) |p| dev.releaseGraphicsPipeline(p);
            if (self.vertex_buffer) |vb| dev.releaseBuffer(vb);
        }
        self.lines.deinit();
        self.persistent_lines.deinit();
    }

    /// Initialize GPU resources (must be called with device after engine init)
    pub fn initGpu(self: *DebugDraw, device: *sdl.gpu.Device, swapchain_format: sdl.gpu.TextureFormat) !void {
        // Load shaders
        const vertex_code = std.fs.cwd().readFileAlloc(
            self.allocator,
            ShaderConfig.vertex_path,
            1024 * 1024,
        ) catch |err| {
            std.debug.print("DebugDraw: Failed to load vertex shader: {}\n", .{err});
            return err;
        };
        defer self.allocator.free(vertex_code);

        const fragment_code = if (is_macos)
            vertex_code
        else
            std.fs.cwd().readFileAlloc(
                self.allocator,
                ShaderConfig.fragment_path,
                1024 * 1024,
            ) catch |err| {
                std.debug.print("DebugDraw: Failed to load fragment shader: {}\n", .{err});
                return err;
            };
        defer if (!is_macos) self.allocator.free(fragment_code);

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
            .num_samplers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 0,
        });
        defer device.releaseShader(fragment_shader);

        // Vertex buffer description for LineVertex
        const vertex_buffer_desc = sdl.gpu.VertexBufferDescription{
            .slot = 0,
            .pitch = @sizeOf(LineVertex),
            .input_rate = .vertex,
            .instance_step_rate = 0,
        };

        const vertex_attributes = [_]sdl.gpu.VertexAttribute{
            // Position
            .{
                .location = 0,
                .buffer_slot = 0,
                .format = .f32x3,
                .offset = 0,
            },
            // Color
            .{
                .location = 1,
                .buffer_slot = 0,
                .format = .f32x4,
                .offset = @offsetOf(LineVertex, "r"),
            },
        };

        const color_target_desc = sdl.gpu.ColorTargetDescription{
            .format = swapchain_format,
            .blend_state = .{
                .enable_blend = true,
                .color_blend = .add,
                .alpha_blend = .add,
                .source_color = .src_alpha,
                .source_alpha = .one,
                .destination_color = .one_minus_src_alpha,
                .destination_alpha = .one_minus_src_alpha,
                .enable_color_write_mask = true,
                .color_write_mask = .{ .red = true, .green = true, .blue = true, .alpha = true },
            },
        };

        self.pipeline = try device.createGraphicsPipeline(.{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .primitive_type = .line_list,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{vertex_buffer_desc},
                .vertex_attributes = &vertex_attributes,
            },
            .rasterizer_state = .{
                .cull_mode = .none,
                .front_face = .counter_clockwise,
            },
            .target_info = .{
                .color_target_descriptions = &[_]sdl.gpu.ColorTargetDescription{color_target_desc},
                .depth_stencil_format = .depth32_float,
            },
            .depth_stencil_state = .{
                .enable_depth_test = self.depth_test,
                .enable_depth_write = false, // Don't write to depth buffer
                .compare = .less_or_equal,
                .enable_stencil_test = false,
            },
        });

        // Create vertex buffer
        self.vertex_buffer = try device.createBuffer(.{
            .usage = .{ .vertex = true },
            .size = VERTEX_BUFFER_SIZE,
        });
        self.vertex_buffer_size = VERTEX_BUFFER_SIZE;
    }

    /// Check if GPU resources are initialized
    pub fn isGpuInitialized(self: *const DebugDraw) bool {
        return self.pipeline != null and self.vertex_buffer != null;
    }

    // ==================== 3D Primitives ====================

    /// Draw a line from point A to point B
    pub fn line(self: *DebugDraw, from: Vec3, to: Vec3, color: Color) void {
        if (!self.enabled) return;
        self.lines.append(LineVertex.init(from, color)) catch return;
        self.lines.append(LineVertex.init(to, color)) catch return;
    }

    /// Draw a ray from origin in a direction
    pub fn ray(self: *DebugDraw, origin: Vec3, direction: Vec3, length: f32, color: Color) void {
        const end = origin.add(direction.normalize().mul(length));
        self.line(origin, end, color);
    }

    /// Draw a wireframe box
    pub fn wireBox(self: *DebugDraw, center: Vec3, size: Vec3, color: Color) void {
        const half = size.mul(0.5);

        // 8 corners of the box
        const corners = [8]Vec3{
            Vec3.init(center.x - half.x, center.y - half.y, center.z - half.z),
            Vec3.init(center.x + half.x, center.y - half.y, center.z - half.z),
            Vec3.init(center.x + half.x, center.y + half.y, center.z - half.z),
            Vec3.init(center.x - half.x, center.y + half.y, center.z - half.z),
            Vec3.init(center.x - half.x, center.y - half.y, center.z + half.z),
            Vec3.init(center.x + half.x, center.y - half.y, center.z + half.z),
            Vec3.init(center.x + half.x, center.y + half.y, center.z + half.z),
            Vec3.init(center.x - half.x, center.y + half.y, center.z + half.z),
        };

        // Bottom face
        self.line(corners[0], corners[1], color);
        self.line(corners[1], corners[2], color);
        self.line(corners[2], corners[3], color);
        self.line(corners[3], corners[0], color);

        // Top face
        self.line(corners[4], corners[5], color);
        self.line(corners[5], corners[6], color);
        self.line(corners[6], corners[7], color);
        self.line(corners[7], corners[4], color);

        // Vertical edges
        self.line(corners[0], corners[4], color);
        self.line(corners[1], corners[5], color);
        self.line(corners[2], corners[6], color);
        self.line(corners[3], corners[7], color);
    }

    /// Draw a wireframe sphere
    pub fn wireSphere(self: *DebugDraw, center: Vec3, radius: f32, color: Color) void {
        const segments: u32 = 16;
        const seg_f: f32 = @floatFromInt(segments);

        // Draw three circles (XY, XZ, YZ planes)
        var i: u32 = 0;
        while (i < segments) : (i += 1) {
            const angle1 = (@as(f32, @floatFromInt(i)) / seg_f) * std.math.pi * 2.0;
            const angle2 = (@as(f32, @floatFromInt(i + 1)) / seg_f) * std.math.pi * 2.0;

            const c1 = @cos(angle1);
            const s1 = @sin(angle1);
            const c2 = @cos(angle2);
            const s2 = @sin(angle2);

            // XY plane circle
            self.line(
                Vec3.init(center.x + c1 * radius, center.y + s1 * radius, center.z),
                Vec3.init(center.x + c2 * radius, center.y + s2 * radius, center.z),
                color,
            );

            // XZ plane circle
            self.line(
                Vec3.init(center.x + c1 * radius, center.y, center.z + s1 * radius),
                Vec3.init(center.x + c2 * radius, center.y, center.z + s2 * radius),
                color,
            );

            // YZ plane circle
            self.line(
                Vec3.init(center.x, center.y + c1 * radius, center.z + s1 * radius),
                Vec3.init(center.x, center.y + c2 * radius, center.z + s2 * radius),
                color,
            );
        }
    }

    /// Draw an arrow from point A to point B
    pub fn arrow(self: *DebugDraw, from: Vec3, to: Vec3, color: Color) void {
        self.line(from, to, color);

        // Arrow head
        const dir = to.sub(from).normalize();
        const length = to.sub(from).length();
        const head_size = @min(length * 0.2, 0.3);

        // Find perpendicular vectors
        var up = Vec3.init(0, 1, 0);
        if (@abs(dir.dot(up)) > 0.99) {
            up = Vec3.init(1, 0, 0);
        }
        const right = dir.cross(up).normalize();
        const actual_up = right.cross(dir).normalize();

        const head_base = to.sub(dir.mul(head_size));

        // Four arrow head lines
        self.line(to, head_base.add(right.mul(head_size * 0.3)), color);
        self.line(to, head_base.sub(right.mul(head_size * 0.3)), color);
        self.line(to, head_base.add(actual_up.mul(head_size * 0.3)), color);
        self.line(to, head_base.sub(actual_up.mul(head_size * 0.3)), color);
    }

    /// Draw coordinate axes at a position
    pub fn axes(self: *DebugDraw, position: Vec3, size: f32) void {
        // X axis - red
        self.arrow(position, position.add(Vec3.init(size, 0, 0)), Color.init(1, 0, 0, 1));
        // Y axis - green
        self.arrow(position, position.add(Vec3.init(0, size, 0)), Color.init(0, 1, 0, 1));
        // Z axis - blue
        self.arrow(position, position.add(Vec3.init(0, 0, size)), Color.init(0, 0, 1, 1));
    }

    /// Draw a grid on the XZ plane
    pub fn grid(self: *DebugDraw, center: Vec3, size: f32, divisions: u32, color: Color) void {
        const half = size / 2.0;
        const step = size / @as(f32, @floatFromInt(divisions));

        var i: u32 = 0;
        while (i <= divisions) : (i += 1) {
            const offset = -half + step * @as(f32, @floatFromInt(i));

            // Lines along X
            self.line(
                Vec3.init(center.x - half, center.y, center.z + offset),
                Vec3.init(center.x + half, center.y, center.z + offset),
                color,
            );

            // Lines along Z
            self.line(
                Vec3.init(center.x + offset, center.y, center.z - half),
                Vec3.init(center.x + offset, center.y, center.z + half),
                color,
            );
        }
    }

    /// Draw a point (small cross)
    pub fn point(self: *DebugDraw, position: Vec3, size: f32, color: Color) void {
        const half = size / 2.0;
        self.line(position.sub(Vec3.init(half, 0, 0)), position.add(Vec3.init(half, 0, 0)), color);
        self.line(position.sub(Vec3.init(0, half, 0)), position.add(Vec3.init(0, half, 0)), color);
        self.line(position.sub(Vec3.init(0, 0, half)), position.add(Vec3.init(0, 0, half)), color);
    }

    // ==================== Persistent Draws ====================

    /// Draw a persistent line that stays visible for a duration
    pub fn persistentLine(self: *DebugDraw, from: Vec3, to: Vec3, color: Color, duration: f32) void {
        self.persistent_lines.append(.{
            .from = from,
            .to = to,
            .color = color,
            .remaining_time = duration,
        }) catch return;
    }

    /// Update persistent draws (call each frame with delta time)
    pub fn update(self: *DebugDraw, delta_time: f32) void {
        // Update persistent lines
        var i: usize = 0;
        while (i < self.persistent_lines.items.len) {
            self.persistent_lines.items[i].remaining_time -= delta_time;
            if (self.persistent_lines.items[i].remaining_time <= 0) {
                _ = self.persistent_lines.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Add persistent lines to the draw list
        for (self.persistent_lines.items) |pl| {
            self.line(pl.from, pl.to, pl.color);
        }
    }

    // ==================== Rendering ====================

    /// Render all queued debug draws
    pub fn render(
        self: *DebugDraw,
        device: *sdl.gpu.Device,
        cmd: sdl.gpu.CommandBuffer,
        pass: sdl.gpu.RenderPass,
        view_proj: Mat4,
    ) void {
        if (!self.enabled) return;
        if (self.lines.items.len == 0) return;
        if (!self.isGpuInitialized()) return;

        const vertex_data = std.mem.sliceAsBytes(self.lines.items);
        if (vertex_data.len == 0) return;

        // Upload vertex data
        const transfer = device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(vertex_data.len),
        }) catch return;
        defer device.releaseTransferBuffer(transfer);

        const map_ptr = device.mapTransferBuffer(transfer, false) catch return;
        const dest_slice: []u8 = @as([*]u8, @ptrCast(map_ptr))[0..vertex_data.len];
        @memcpy(dest_slice, vertex_data);
        device.unmapTransferBuffer(transfer);

        // We need to use a copy pass to upload the data, but we're in a render pass
        // So we'll upload directly to the vertex buffer using the command buffer
        // Actually, SDL3 requires copy passes for uploads, so we need to end render pass first
        // For simplicity, we'll use a separate upload before rendering

        // For now, let's use push constants style approach - actually SDL3 doesn't have that
        // We need to restructure to do the upload before the render pass

        // Bind pipeline and draw
        pass.bindGraphicsPipeline(self.pipeline.?);

        // Push uniforms
        const uniforms = DebugUniforms{ .view_projection = view_proj.data };
        cmd.pushVertexUniformData(0, std.mem.asBytes(&uniforms));

        pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
            .buffer = self.vertex_buffer.?,
            .offset = 0,
        }});

        pass.drawPrimitives(@intCast(self.lines.items.len), 1, 0, 0);
    }

    /// Upload vertex data (call before render pass begins)
    pub fn uploadVertexData(self: *DebugDraw, device: *sdl.gpu.Device) !void {
        if (self.lines.items.len == 0) return;
        if (!self.isGpuInitialized()) return;

        const vertex_data = std.mem.sliceAsBytes(self.lines.items);
        if (vertex_data.len == 0) return;

        // Ensure buffer is large enough
        if (vertex_data.len > self.vertex_buffer_size) {
            if (self.vertex_buffer) |vb| device.releaseBuffer(vb);
            self.vertex_buffer = try device.createBuffer(.{
                .usage = .{ .vertex = true },
                .size = @intCast(vertex_data.len),
            });
            self.vertex_buffer_size = vertex_data.len;
        }

        const transfer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(vertex_data.len),
        });
        defer device.releaseTransferBuffer(transfer);

        const map_ptr = try device.mapTransferBuffer(transfer, false);
        const dest_slice: []u8 = @as([*]u8, @ptrCast(map_ptr))[0..vertex_data.len];
        @memcpy(dest_slice, vertex_data);
        device.unmapTransferBuffer(transfer);

        const cmd = try device.acquireCommandBuffer();
        const copy_pass = cmd.beginCopyPass();
        copy_pass.uploadToBuffer(
            .{ .transfer_buffer = transfer, .offset = 0 },
            .{ .buffer = self.vertex_buffer.?, .offset = 0, .size = @intCast(vertex_data.len) },
            false,
        );
        copy_pass.end();
        try cmd.submit();
    }

    /// Clear all queued debug draws (call at end of frame)
    pub fn clear(self: *DebugDraw) void {
        self.lines.clearRetainingCapacity();
    }
};
