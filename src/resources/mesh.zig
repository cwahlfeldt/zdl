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
        const vertex_byte_slice = std.mem.sliceAsBytes(self.vertices);
        const index_byte_slice = std.mem.sliceAsBytes(self.indices);
        const total_size = vertex_byte_slice.len + index_byte_slice.len;

        // 1. Create GPU Buffers
        self.vertex_buffer = try device.createBuffer(.{
            .usage = .{ .vertex = true },
            .size = @intCast(vertex_byte_slice.len),
        });
        errdefer device.releaseBuffer(self.vertex_buffer.?);

        self.index_buffer = try device.createBuffer(.{
            .usage = .{ .index = true },
            .size = @intCast(index_byte_slice.len),
        });
        errdefer device.releaseBuffer(self.index_buffer.?);

        // 2. Map Transfer Buffer once for both data sets
        const transfer = try device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(total_size),
        });
        defer device.releaseTransferBuffer(transfer);

        const map_ptr = try device.mapTransferBuffer(transfer, false);
        // Cast the raw pointer to a many-item slice for safe @memcpy
        const dest_slice: []u8 = @as([*]u8, @ptrCast(map_ptr))[0..total_size];

        @memcpy(dest_slice[0..vertex_byte_slice.len], vertex_byte_slice);
        @memcpy(dest_slice[vertex_byte_slice.len..], index_byte_slice);

        device.unmapTransferBuffer(transfer);

        // 3. Batch the upload commands into a single submission
        const cmd = try device.acquireCommandBuffer();
        const copy_pass = cmd.beginCopyPass();

        // Copy Vertices from start of transfer buffer
        copy_pass.uploadToBuffer(
            .{ .transfer_buffer = transfer, .offset = 0 },
            .{ .buffer = self.vertex_buffer.?, .offset = 0, .size = @intCast(vertex_byte_slice.len) },
            false,
        );

        // Copy Indices from the offset in transfer buffer
        copy_pass.uploadToBuffer(
            .{ .transfer_buffer = transfer, .offset = @intCast(vertex_byte_slice.len) },
            .{ .buffer = self.index_buffer.?, .offset = 0, .size = @intCast(index_byte_slice.len) },
            false,
        );

        copy_pass.end();
        try cmd.submit();
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
