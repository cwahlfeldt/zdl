const std = @import("std");
const sdl = @import("sdl3");
const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec2 = @import("../math/vec2.zig").Vec2;

/// Vertex format for 3D rendering
pub const Vertex3D = struct {
    // Position (location 0)
    x: f32,
    y: f32,
    z: f32,

    // Normal (location 1)
    nx: f32,
    ny: f32,
    nz: f32,

    // Texture coordinates (location 2)
    u: f32,
    v: f32,

    // Color tint (location 3)
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn init(position: Vec3, normal: Vec3, uv: Vec2, color: [4]f32) Vertex3D {
        return .{
            .x = position.x,
            .y = position.y,
            .z = position.z,
            .nx = normal.x,
            .ny = normal.y,
            .nz = normal.z,
            .u = uv.x,
            .v = uv.y,
            .r = color[0],
            .g = color[1],
            .b = color[2],
            .a = color[3],
        };
    }
};

/// 3D Mesh containing vertex and index data
pub const Mesh = struct {
    vertices: []Vertex3D,
    indices: []u32,
    vertex_buffer: ?sdl.gpu.Buffer,
    index_buffer: ?sdl.gpu.Buffer,
    allocator: std.mem.Allocator,

    /// Create a new mesh from vertex and index data
    pub fn init(allocator: std.mem.Allocator, vertices: []const Vertex3D, indices: []const u32) !Mesh {
        const vertex_copy = try allocator.dupe(Vertex3D, vertices);
        errdefer allocator.free(vertex_copy);

        const index_copy = try allocator.dupe(u32, indices);
        errdefer allocator.free(index_copy);

        return .{
            .vertices = vertex_copy,
            .indices = index_copy,
            .vertex_buffer = null,
            .index_buffer = null,
            .allocator = allocator,
        };
    }

    /// Free mesh resources
    pub fn deinit(self: *Mesh, device: ?*sdl.gpu.Device) void {
        if (device) |dev| {
            if (self.vertex_buffer) |vb| {
                dev.releaseBuffer(vb);
            }
            if (self.index_buffer) |ib| {
                dev.releaseBuffer(ib);
            }
        }
        self.allocator.free(self.vertices);
        self.allocator.free(self.indices);
    }

    /// Upload mesh data to GPU
    pub fn upload(self: *Mesh, device: *sdl.gpu.Device) !void {
        // Create vertex buffer
        const vertex_size: u32 = @intCast(@sizeOf(Vertex3D) * self.vertices.len);
        const vb = try device.createBuffer(.{
            .usage = .{ .vertex = true },
            .size = vertex_size,
        });
        errdefer device.releaseBuffer(vb);

        // Create index buffer
        const index_size: u32 = @intCast(@sizeOf(u32) * self.indices.len);
        const ib = try device.createBuffer(.{
            .usage = .{ .index = true },
            .size = index_size,
        });
        errdefer device.releaseBuffer(ib);

        // Create transfer buffer large enough for both
        const transfer_size = @max(vertex_size, index_size);
        const transfer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = transfer_size,
        });
        defer device.releaseTransferBuffer(transfer);

        // Upload vertices
        {
            const data = try device.mapTransferBuffer(transfer, false);
            const vertex_data = @as([*]Vertex3D, @ptrCast(@alignCast(data)));
            for (self.vertices, 0..) |v, i| {
                vertex_data[i] = v;
            }
            device.unmapTransferBuffer(transfer);

            const cmd = try device.acquireCommandBuffer();
            {
                const copy_pass = cmd.beginCopyPass();
                defer copy_pass.end();
                copy_pass.uploadToBuffer(
                    .{ .transfer_buffer = transfer, .offset = 0 },
                    .{ .buffer = vb, .offset = 0, .size = @intCast(vertex_size) },
                    false,
                );
            }
            try cmd.submit();
        }

        // Upload indices
        {
            const data = try device.mapTransferBuffer(transfer, false);
            const index_data = @as([*]u32, @ptrCast(@alignCast(data)));
            for (self.indices, 0..) |idx, i| {
                index_data[i] = idx;
            }
            device.unmapTransferBuffer(transfer);

            const cmd = try device.acquireCommandBuffer();
            {
                const copy_pass = cmd.beginCopyPass();
                defer copy_pass.end();
                copy_pass.uploadToBuffer(
                    .{ .transfer_buffer = transfer, .offset = 0 },
                    .{ .buffer = ib, .offset = 0, .size = @intCast(index_size) },
                    false,
                );
            }
            try cmd.submit();
        }

        // Store buffers
        self.vertex_buffer = vb;
        self.index_buffer = ib;
    }

    /// Get vertex buffer descriptor for pipeline creation
    pub fn getVertexBufferDesc() sdl.gpu.VertexBufferDescription {
        return .{
            .slot = 0,
            .pitch = @sizeOf(Vertex3D),
            .input_rate = .vertex,
            .instance_step_rate = 0,
        };
    }

    /// Get vertex attributes for pipeline creation
    pub fn getVertexAttributes() [4]sdl.gpu.VertexAttribute {
        return [_]sdl.gpu.VertexAttribute{
            // Position
            .{
                .location = 0,
                .buffer_slot = 0,
                .format = .f32x3,
                .offset = 0,
            },
            // Normal
            .{
                .location = 1,
                .buffer_slot = 0,
                .format = .f32x3,
                .offset = @offsetOf(Vertex3D, "nx"),
            },
            // UV
            .{
                .location = 2,
                .buffer_slot = 0,
                .format = .f32x2,
                .offset = @offsetOf(Vertex3D, "u"),
            },
            // Color
            .{
                .location = 3,
                .buffer_slot = 0,
                .format = .f32x4,
                .offset = @offsetOf(Vertex3D, "r"),
            },
        };
    }
};
