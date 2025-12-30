const std = @import("std");
const sdl = @import("sdl3");
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Mesh = @import("../resources/mesh.zig").Mesh;

/// Vertex format for skinned meshes
/// Extends Vertex3D with bone influences
pub const SkinnedVertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    color: [4]f32,
    joints: [4]u8,   // Bone indices (up to 4 influences)
    weights: [4]f32, // Bone weights (should sum to 1.0)

    pub fn init(pos: Vec3, normal: Vec3, uv: Vec2, color: Vec4) SkinnedVertex {
        return .{
            .position = .{ pos.x, pos.y, pos.z },
            .normal = .{ normal.x, normal.y, normal.z },
            .uv = .{ uv.x, uv.y },
            .color = .{ color.x, color.y, color.z, color.w },
            .joints = .{ 0, 0, 0, 0 },
            .weights = .{ 1.0, 0.0, 0.0, 0.0 },
        };
    }

    pub fn withBones(pos: Vec3, normal: Vec3, uv: Vec2, color: Vec4, joints: [4]u8, weights: [4]f32) SkinnedVertex {
        return .{
            .position = .{ pos.x, pos.y, pos.z },
            .normal = .{ normal.x, normal.y, normal.z },
            .uv = .{ uv.x, uv.y },
            .color = .{ color.x, color.y, color.z, color.w },
            .joints = joints,
            .weights = weights,
        };
    }
};

/// A mesh with skeletal animation support
pub const SkinnedMesh = struct {
    allocator: std.mem.Allocator,

    /// Vertex data
    vertices: []SkinnedVertex,

    /// Index data (optional)
    indices: ?[]u32,

    /// GPU vertex buffer
    vertex_buffer: ?*sdl.gpu.Buffer,

    /// GPU index buffer
    index_buffer: ?*sdl.gpu.Buffer,

    /// Number of vertices to draw
    vertex_count: u32,

    /// Number of indices to draw
    index_count: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, vertices: []const SkinnedVertex, indices: ?[]const u32) !Self {
        const verts = try allocator.dupe(SkinnedVertex, vertices);
        const inds = if (indices) |idx| try allocator.dupe(u32, idx) else null;

        return .{
            .allocator = allocator,
            .vertices = verts,
            .indices = inds,
            .vertex_buffer = null,
            .index_buffer = null,
            .vertex_count = @intCast(vertices.len),
            .index_count = if (indices) |idx| @intCast(idx.len) else 0,
        };
    }

    pub fn deinit(self: *Self, device: ?*sdl.gpu.Device) void {
        if (device) |dev| {
            if (self.vertex_buffer) |buf| {
                dev.releaseBuffer(buf);
            }
            if (self.index_buffer) |buf| {
                dev.releaseBuffer(buf);
            }
        }

        self.allocator.free(self.vertices);
        if (self.indices) |inds| {
            self.allocator.free(inds);
        }
    }

    /// Upload mesh data to GPU
    pub fn upload(self: *Self, device: *sdl.gpu.Device) !void {
        // Create vertex buffer
        const vertex_size = @sizeOf(SkinnedVertex) * self.vertices.len;
        self.vertex_buffer = device.createBuffer(.{
            .usage = .{ .vertex = true },
            .size = @intCast(vertex_size),
        }) orelse return error.BufferCreationFailed;

        // Create transfer buffer and upload
        const transfer_buf = device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(vertex_size),
        }) orelse return error.TransferBufferFailed;
        defer device.releaseTransferBuffer(transfer_buf);

        const mapped = transfer_buf.map(SkinnedVertex) orelse return error.MapFailed;
        @memcpy(mapped, self.vertices);
        transfer_buf.unmap();

        // Copy to GPU
        const cmd = device.acquireCommandBuffer() orelse return error.CommandBufferFailed;
        const copy_pass = cmd.beginCopyPass() orelse return error.CopyPassFailed;
        copy_pass.uploadToBuffer(.{
            .transfer_buffer = transfer_buf,
            .offset = 0,
        }, .{
            .buffer = self.vertex_buffer.?,
            .offset = 0,
            .size = @intCast(vertex_size),
        }, false);
        copy_pass.end();

        // Upload indices if present
        if (self.indices) |indices| {
            const index_size = @sizeOf(u32) * indices.len;
            self.index_buffer = device.createBuffer(.{
                .usage = .{ .index = true },
                .size = @intCast(index_size),
            }) orelse return error.BufferCreationFailed;

            const index_transfer = device.createTransferBuffer(.{
                .usage = .upload,
                .size = @intCast(index_size),
            }) orelse return error.TransferBufferFailed;
            defer device.releaseTransferBuffer(index_transfer);

            const index_mapped = index_transfer.map(u32) orelse return error.MapFailed;
            @memcpy(index_mapped, indices);
            index_transfer.unmap();

            const idx_copy_pass = cmd.beginCopyPass() orelse return error.CopyPassFailed;
            idx_copy_pass.uploadToBuffer(.{
                .transfer_buffer = index_transfer,
                .offset = 0,
            }, .{
                .buffer = self.index_buffer.?,
                .offset = 0,
                .size = @intCast(index_size),
            }, false);
            idx_copy_pass.end();
        }

        _ = device.submit(cmd);
    }

    /// Get vertex buffer binding for rendering
    pub fn getVertexBufferBinding(self: *const Self) sdl.gpu.BufferBinding {
        return .{
            .buffer = self.vertex_buffer.?,
            .offset = 0,
        };
    }

    /// Get index buffer binding for rendering
    pub fn getIndexBufferBinding(self: *const Self) ?sdl.gpu.BufferBinding {
        if (self.index_buffer) |buf| {
            return .{
                .buffer = buf,
                .offset = 0,
            };
        }
        return null;
    }
};

/// GPU buffer for bone matrices
pub const BoneMatrixBuffer = struct {
    allocator: std.mem.Allocator,
    buffer: ?*sdl.gpu.Buffer,
    max_bones: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_bones: usize) Self {
        return .{
            .allocator = allocator,
            .buffer = null,
            .max_bones = max_bones,
        };
    }

    pub fn deinit(self: *Self, device: *sdl.gpu.Device) void {
        if (self.buffer) |buf| {
            device.releaseBuffer(buf);
        }
    }

    /// Create the GPU buffer
    pub fn create(self: *Self, device: *sdl.gpu.Device) !void {
        const size = @sizeOf(Mat4) * self.max_bones;
        self.buffer = device.createBuffer(.{
            .usage = .{ .graphics_storage_read = true },
            .size = @intCast(size),
        }) orelse return error.BufferCreationFailed;
    }

    /// Update bone matrices on GPU
    pub fn update(self: *Self, device: *sdl.gpu.Device, matrices: []const Mat4) !void {
        if (self.buffer == null) return error.BufferNotCreated;

        const upload_count = @min(matrices.len, self.max_bones);
        const size = @sizeOf(Mat4) * upload_count;

        const transfer_buf = device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(size),
        }) orelse return error.TransferBufferFailed;
        defer device.releaseTransferBuffer(transfer_buf);

        const mapped = transfer_buf.map(Mat4) orelse return error.MapFailed;
        @memcpy(mapped[0..upload_count], matrices[0..upload_count]);
        transfer_buf.unmap();

        const cmd = device.acquireCommandBuffer() orelse return error.CommandBufferFailed;
        const copy_pass = cmd.beginCopyPass() orelse return error.CopyPassFailed;
        copy_pass.uploadToBuffer(.{
            .transfer_buffer = transfer_buf,
            .offset = 0,
        }, .{
            .buffer = self.buffer.?,
            .offset = 0,
            .size = @intCast(size),
        }, false);
        copy_pass.end();

        _ = device.submit(cmd);
    }
};
