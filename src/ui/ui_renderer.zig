// ZDL UI Renderer
// Batched 2D renderer for efficient UI drawing

const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const Vec2 = @import("../math/vec2.zig").Vec2;
const Color = @import("../render/render.zig").Color;
const Texture = @import("../resources/texture.zig").Texture;
const Rect = @import("ui.zig").Rect;

/// Vertex format for 2D UI rendering (position, UV, color)
pub const Vertex2D = struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn init(pos: Vec2, uv: Vec2, color: Color) Vertex2D {
        return .{
            .x = pos.x,
            .y = pos.y,
            .u = uv.x,
            .v = uv.y,
            .r = color.r,
            .g = color.g,
            .b = color.b,
            .a = color.a,
        };
    }
};

/// Uniforms for UI shader (orthographic projection)
pub const UIUniforms = struct {
    projection: [16]f32,
};

/// Platform-specific shader configuration
const is_macos = builtin.os.tag == .macos;
const ShaderConfig = if (is_macos) struct {
    const format = sdl.gpu.ShaderFormatFlags{ .msl = true };
    const vertex_path = "assets/shaders/ui.metal";
    const fragment_path = "assets/shaders/ui.metal";
    const vertex_entry = "ui_vertex_main";
    const fragment_entry = "ui_fragment_main";
} else struct {
    const format = sdl.gpu.ShaderFormatFlags{ .spirv = true };
    const vertex_path = "build/assets/shaders/ui_vertex.spv";
    const fragment_path = "build/assets/shaders/ui_fragment.spv";
    const vertex_entry = "main";
    const fragment_entry = "main";
};

/// Draw command for batching
const DrawCommand = struct {
    texture: sdl.gpu.Texture,
    sampler: sdl.gpu.Sampler,
    start_index: u32,
    index_count: u32,
};

/// Batched 2D renderer for UI elements
pub const UIRenderer = struct {
    allocator: std.mem.Allocator,

    // Batched vertices and indices
    vertices: std.array_list.Managed(Vertex2D),
    indices: std.array_list.Managed(u32),
    commands: std.array_list.Managed(DrawCommand),

    // Current batch state
    current_texture: ?sdl.gpu.Texture,
    current_sampler: ?sdl.gpu.Sampler,
    current_start_index: u32,

    // GPU resources
    pipeline: ?sdl.gpu.GraphicsPipeline,
    vertex_buffer: ?sdl.gpu.Buffer,
    index_buffer: ?sdl.gpu.Buffer,
    vertex_buffer_size: usize,
    index_buffer_size: usize,

    // White texture for solid color drawing
    white_texture: ?Texture,

    // Screen dimensions for orthographic projection
    screen_width: f32,
    screen_height: f32,

    // Constants
    const MAX_VERTICES: usize = 65536;
    const MAX_INDICES: usize = MAX_VERTICES * 6 / 4; // Quads use 6 indices per 4 vertices
    const VERTEX_BUFFER_SIZE: usize = MAX_VERTICES * @sizeOf(Vertex2D);
    const INDEX_BUFFER_SIZE: usize = MAX_INDICES * @sizeOf(u32);

    pub fn init(allocator: std.mem.Allocator) UIRenderer {
        return .{
            .allocator = allocator,
            .vertices = std.array_list.Managed(Vertex2D).init(allocator),
            .indices = std.array_list.Managed(u32).init(allocator),
            .commands = std.array_list.Managed(DrawCommand).init(allocator),
            .current_texture = null,
            .current_sampler = null,
            .current_start_index = 0,
            .pipeline = null,
            .vertex_buffer = null,
            .index_buffer = null,
            .vertex_buffer_size = 0,
            .index_buffer_size = 0,
            .white_texture = null,
            .screen_width = 800,
            .screen_height = 600,
        };
    }

    pub fn deinit(self: *UIRenderer, device: *sdl.gpu.Device) void {
        if (self.pipeline) |p| device.releaseGraphicsPipeline(p);
        if (self.vertex_buffer) |vb| device.releaseBuffer(vb);
        if (self.index_buffer) |ib| device.releaseBuffer(ib);
        if (self.white_texture) |wt| {
            device.releaseTexture(wt.gpu_texture);
            if (wt.sampler) |s| device.releaseSampler(s);
        }
        self.vertices.deinit();
        self.indices.deinit();
        self.commands.deinit();
    }

    /// Initialize GPU resources
    pub fn initGpu(self: *UIRenderer, device: *sdl.gpu.Device, swapchain_format: sdl.gpu.TextureFormat) !void {
        // Load shaders
        const vertex_code = std.fs.cwd().readFileAlloc(
            self.allocator,
            ShaderConfig.vertex_path,
            1024 * 1024,
        ) catch |err| {
            std.debug.print("UIRenderer: Failed to load vertex shader from {s}: {}\n", .{ ShaderConfig.vertex_path, err });
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
                std.debug.print("UIRenderer: Failed to load fragment shader from {s}: {}\n", .{ ShaderConfig.fragment_path, err });
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
            .num_samplers = 1,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 0,
        });
        defer device.releaseShader(fragment_shader);

        // Vertex buffer description for Vertex2D
        const vertex_buffer_desc = sdl.gpu.VertexBufferDescription{
            .slot = 0,
            .pitch = @sizeOf(Vertex2D),
            .input_rate = .vertex,
            .instance_step_rate = 0,
        };

        const vertex_attributes = [_]sdl.gpu.VertexAttribute{
            // Position (xy)
            .{
                .location = 0,
                .buffer_slot = 0,
                .format = .f32x2,
                .offset = 0,
            },
            // UV
            .{
                .location = 1,
                .buffer_slot = 0,
                .format = .f32x2,
                .offset = @offsetOf(Vertex2D, "u"),
            },
            // Color
            .{
                .location = 2,
                .buffer_slot = 0,
                .format = .f32x4,
                .offset = @offsetOf(Vertex2D, "r"),
            },
        };

        // Enable alpha blending for UI
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
            .primitive_type = .triangle_list,
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
                .enable_depth_test = false, // UI renders on top
                .enable_depth_write = false,
                .compare = .always,
                .enable_stencil_test = false,
            },
        });

        // Create vertex and index buffers
        self.vertex_buffer = try device.createBuffer(.{
            .usage = .{ .vertex = true },
            .size = VERTEX_BUFFER_SIZE,
        });
        self.vertex_buffer_size = VERTEX_BUFFER_SIZE;

        self.index_buffer = try device.createBuffer(.{
            .usage = .{ .index = true },
            .size = INDEX_BUFFER_SIZE,
        });
        self.index_buffer_size = INDEX_BUFFER_SIZE;

        // Create 1x1 white texture for solid color drawing
        self.white_texture = try Texture.createSolid(device, 1, 1, Color.init(1, 1, 1, 1));
    }

    /// Set screen dimensions for orthographic projection
    pub fn setScreenSize(self: *UIRenderer, width: f32, height: f32) void {
        self.screen_width = width;
        self.screen_height = height;
    }

    /// Check if GPU resources are initialized
    pub fn isGpuInitialized(self: *const UIRenderer) bool {
        return self.pipeline != null and self.vertex_buffer != null and self.index_buffer != null;
    }

    // ==================== Drawing Functions ====================

    /// Draw a solid color rectangle
    pub fn drawRect(self: *UIRenderer, rect: Rect, color: Color) void {
        if (self.white_texture) |wt| {
            if (wt.sampler) |sampler| {
                self.drawTexturedRectRaw(rect, wt.gpu_texture, sampler, Rect.init(0, 0, 1, 1), color);
            }
        }
    }

    /// Draw a textured rectangle using a Texture struct
    pub fn drawTexturedRect(
        self: *UIRenderer,
        rect: Rect,
        tex: Texture,
        uv: Rect,
        color: Color,
    ) void {
        if (tex.sampler) |sampler| {
            self.drawTexturedRectRaw(rect, tex.gpu_texture, sampler, uv, color);
        }
    }

    /// Draw a textured rectangle with raw GPU texture and sampler
    pub fn drawTexturedRectRaw(
        self: *UIRenderer,
        rect: Rect,
        texture: sdl.gpu.Texture,
        sampler: sdl.gpu.Sampler,
        uv: Rect,
        color: Color,
    ) void {
        // Check if we need to start a new batch (simple pointer comparison)
        const needs_new_batch = if (self.current_texture == null or self.current_sampler == null)
            true
        else
            // Compare the internal pointers of the GPU handles
            @intFromPtr(self.current_texture.?.value) != @intFromPtr(texture.value) or
                @intFromPtr(self.current_sampler.?.value) != @intFromPtr(sampler.value);

        if (needs_new_batch) {
            self.flushBatch();
            self.current_texture = texture;
            self.current_sampler = sampler;
        }

        // Add quad vertices
        const base_index: u32 = @intCast(self.vertices.items.len);

        // Top-left
        self.vertices.append(Vertex2D.init(
            Vec2.init(rect.x, rect.y),
            Vec2.init(uv.x, uv.y),
            color,
        )) catch return;

        // Top-right
        self.vertices.append(Vertex2D.init(
            Vec2.init(rect.x + rect.width, rect.y),
            Vec2.init(uv.x + uv.width, uv.y),
            color,
        )) catch return;

        // Bottom-right
        self.vertices.append(Vertex2D.init(
            Vec2.init(rect.x + rect.width, rect.y + rect.height),
            Vec2.init(uv.x + uv.width, uv.y + uv.height),
            color,
        )) catch return;

        // Bottom-left
        self.vertices.append(Vertex2D.init(
            Vec2.init(rect.x, rect.y + rect.height),
            Vec2.init(uv.x, uv.y + uv.height),
            color,
        )) catch return;

        // Add indices for two triangles
        self.indices.append(base_index + 0) catch return;
        self.indices.append(base_index + 1) catch return;
        self.indices.append(base_index + 2) catch return;
        self.indices.append(base_index + 0) catch return;
        self.indices.append(base_index + 2) catch return;
        self.indices.append(base_index + 3) catch return;
    }

    /// Draw a rectangle border (outline only)
    pub fn drawRectBorder(self: *UIRenderer, rect: Rect, color: Color, thickness: f32) void {
        // Top
        self.drawRect(Rect.init(rect.x, rect.y, rect.width, thickness), color);
        // Bottom
        self.drawRect(Rect.init(rect.x, rect.y + rect.height - thickness, rect.width, thickness), color);
        // Left
        self.drawRect(Rect.init(rect.x, rect.y + thickness, thickness, rect.height - thickness * 2), color);
        // Right
        self.drawRect(Rect.init(rect.x + rect.width - thickness, rect.y + thickness, thickness, rect.height - thickness * 2), color);
    }

    /// Flush current batch to commands list
    fn flushBatch(self: *UIRenderer) void {
        const index_count = @as(u32, @intCast(self.indices.items.len)) - self.current_start_index;
        if (index_count > 0 and self.current_texture != null and self.current_sampler != null) {
            self.commands.append(.{
                .texture = self.current_texture.?,
                .sampler = self.current_sampler.?,
                .start_index = self.current_start_index,
                .index_count = index_count,
            }) catch return;
        }
        self.current_start_index = @intCast(self.indices.items.len);
    }

    /// Upload vertex and index data to GPU (call before render pass)
    pub fn uploadData(self: *UIRenderer, device: *sdl.gpu.Device) !void {
        if (self.vertices.items.len == 0) return;
        if (!self.isGpuInitialized()) return;

        // Flush final batch
        self.flushBatch();

        const vertex_data = std.mem.sliceAsBytes(self.vertices.items);
        const index_data = std.mem.sliceAsBytes(self.indices.items);

        if (vertex_data.len == 0 or index_data.len == 0) return;

        // Ensure vertex buffer is large enough
        if (vertex_data.len > self.vertex_buffer_size) {
            if (self.vertex_buffer) |vb| device.releaseBuffer(vb);
            self.vertex_buffer = try device.createBuffer(.{
                .usage = .{ .vertex = true },
                .size = @intCast(vertex_data.len),
            });
            self.vertex_buffer_size = vertex_data.len;
        }

        // Ensure index buffer is large enough
        if (index_data.len > self.index_buffer_size) {
            if (self.index_buffer) |ib| device.releaseBuffer(ib);
            self.index_buffer = try device.createBuffer(.{
                .usage = .{ .index = true },
                .size = @intCast(index_data.len),
            });
            self.index_buffer_size = index_data.len;
        }

        // Create transfer buffers and upload
        const vertex_transfer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(vertex_data.len),
        });
        defer device.releaseTransferBuffer(vertex_transfer);

        const index_transfer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(index_data.len),
        });
        defer device.releaseTransferBuffer(index_transfer);

        // Map and copy vertex data
        const vertex_map = try device.mapTransferBuffer(vertex_transfer, false);
        const vertex_dest: []u8 = @as([*]u8, @ptrCast(vertex_map))[0..vertex_data.len];
        @memcpy(vertex_dest, vertex_data);
        device.unmapTransferBuffer(vertex_transfer);

        // Map and copy index data
        const index_map = try device.mapTransferBuffer(index_transfer, false);
        const index_dest: []u8 = @as([*]u8, @ptrCast(index_map))[0..index_data.len];
        @memcpy(index_dest, index_data);
        device.unmapTransferBuffer(index_transfer);

        // Submit copy commands
        const cmd = try device.acquireCommandBuffer();
        const copy_pass = cmd.beginCopyPass();

        copy_pass.uploadToBuffer(
            .{ .transfer_buffer = vertex_transfer, .offset = 0 },
            .{ .buffer = self.vertex_buffer.?, .offset = 0, .size = @intCast(vertex_data.len) },
            false,
        );

        copy_pass.uploadToBuffer(
            .{ .transfer_buffer = index_transfer, .offset = 0 },
            .{ .buffer = self.index_buffer.?, .offset = 0, .size = @intCast(index_data.len) },
            false,
        );

        copy_pass.end();
        try cmd.submit();
    }

    /// Render all batched UI elements
    pub fn render(
        self: *UIRenderer,
        cmd: sdl.gpu.CommandBuffer,
        pass: sdl.gpu.RenderPass,
    ) void {
        if (self.commands.items.len == 0) return;
        if (!self.isGpuInitialized()) return;

        // Build orthographic projection matrix (screen space, Y down)
        const projection = createOrthoMatrix(0, self.screen_width, self.screen_height, 0, -1, 1);
        const uniforms = UIUniforms{ .projection = projection };

        // Bind pipeline
        pass.bindGraphicsPipeline(self.pipeline.?);

        // Push uniforms
        cmd.pushVertexUniformData(0, std.mem.asBytes(&uniforms));

        // Bind vertex buffer
        pass.bindVertexBuffers(0, &[_]sdl.gpu.BufferBinding{.{
            .buffer = self.vertex_buffer.?,
            .offset = 0,
        }});

        // Bind index buffer
        pass.bindIndexBuffer(.{
            .buffer = self.index_buffer.?,
            .offset = 0,
        }, .indices_32bit);

        // Draw each batch
        for (self.commands.items) |command| {
            // Bind texture and sampler
            pass.bindFragmentSamplers(0, &[_]sdl.gpu.TextureSamplerBinding{.{
                .texture = command.texture,
                .sampler = command.sampler,
            }});

            // Draw indexed primitives
            pass.drawIndexedPrimitives(command.index_count, 1, command.start_index, 0, 0);
        }
    }

    /// Clear all batched data (call at end of frame)
    pub fn clear(self: *UIRenderer) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
        self.commands.clearRetainingCapacity();
        self.current_texture = null;
        self.current_sampler = null;
        self.current_start_index = 0;
    }
};

/// Create orthographic projection matrix
fn createOrthoMatrix(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    const width = right - left;
    const height = top - bottom;
    const depth = far - near;

    return .{
        2.0 / width,
        0,
        0,
        0,
        0,
        2.0 / height,
        0,
        0,
        0,
        0,
        -2.0 / depth,
        0,
        -(right + left) / width,
        -(top + bottom) / height,
        -(far + near) / depth,
        1.0,
    };
}
