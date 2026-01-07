const std = @import("std");
const types = @import("types.zig");
const GLTFError = types.GLTFError;
const GLTFAsset = types.GLTFAsset;
const AccessorData = types.AccessorData;
const BufferViewData = types.BufferViewData;
const ComponentType = types.ComponentType;
const ElementType = types.ElementType;
const Vec2 = @import("../../math/vec2.zig").Vec2;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Vec4 = @import("../../math/vec4.zig").Vec4;
const Mat4 = @import("../../math/mat4.zig").Mat4;

/// Utility for reading typed data from glTF accessors
pub const AccessorReader = struct {
    asset: *const GLTFAsset,

    const Self = @This();

    pub fn init(asset: *const GLTFAsset) Self {
        return .{ .asset = asset };
    }

    /// Read Vec3 data from an accessor
    pub fn readVec3(self: Self, allocator: std.mem.Allocator, accessor_index: usize) ![]Vec3 {
        const accessor = self.asset.accessors[accessor_index];
        if (accessor.element_type != .VEC3) {
            return GLTFError.InvalidAccessor;
        }

        const data = try self.getAccessorData(accessor);
        var result = try allocator.alloc(Vec3, accessor.count);
        errdefer allocator.free(result);

        const stride = self.getStride(accessor);

        for (0..accessor.count) |i| {
            const offset = i * stride;
            const values = self.readComponents(f32, 3, data, offset, accessor.component_type, accessor.normalized);
            result[i] = Vec3.init(values[0], values[1], values[2]);
        }

        return result;
    }

    /// Read Vec2 data from an accessor
    pub fn readVec2(self: Self, allocator: std.mem.Allocator, accessor_index: usize) ![]Vec2 {
        const accessor = self.asset.accessors[accessor_index];
        if (accessor.element_type != .VEC2) {
            return GLTFError.InvalidAccessor;
        }

        const data = try self.getAccessorData(accessor);
        var result = try allocator.alloc(Vec2, accessor.count);
        errdefer allocator.free(result);

        const stride = self.getStride(accessor);

        for (0..accessor.count) |i| {
            const offset = i * stride;
            const values = self.readComponents(f32, 2, data, offset, accessor.component_type, accessor.normalized);
            result[i] = Vec2.init(values[0], values[1]);
        }

        return result;
    }

    /// Read Vec4 data from an accessor
    pub fn readVec4(self: Self, allocator: std.mem.Allocator, accessor_index: usize) ![]Vec4 {
        const accessor = self.asset.accessors[accessor_index];
        if (accessor.element_type != .VEC4) {
            return GLTFError.InvalidAccessor;
        }

        const data = try self.getAccessorData(accessor);
        var result = try allocator.alloc(Vec4, accessor.count);
        errdefer allocator.free(result);

        const stride = self.getStride(accessor);

        for (0..accessor.count) |i| {
            const offset = i * stride;
            const values = self.readComponents(f32, 4, data, offset, accessor.component_type, accessor.normalized);
            result[i] = Vec4.init(values[0], values[1], values[2], values[3]);
        }

        return result;
    }

    /// Read scalar data from an accessor as u32
    pub fn readScalarU32(self: Self, allocator: std.mem.Allocator, accessor_index: usize) ![]u32 {
        const accessor = self.asset.accessors[accessor_index];
        if (accessor.element_type != .SCALAR) {
            return GLTFError.InvalidAccessor;
        }

        const data = try self.getAccessorData(accessor);
        var result = try allocator.alloc(u32, accessor.count);
        errdefer allocator.free(result);

        const stride = self.getStride(accessor);

        for (0..accessor.count) |i| {
            const offset = i * stride;
            result[i] = self.readScalar(u32, data, offset, accessor.component_type, accessor.normalized);
        }

        return result;
    }

    /// Read indices - handles u16 and u32 component types
    pub fn readIndices(self: Self, allocator: std.mem.Allocator, accessor_index: usize) ![]u32 {
        return self.readScalarU32(allocator, accessor_index);
    }

    /// Get raw byte slice for accessor data
    fn getAccessorData(self: Self, accessor: AccessorData) ![]const u8 {
        const bv_index = accessor.buffer_view orelse return GLTFError.InvalidAccessor;
        const buffer_view = self.asset.buffer_views[bv_index];

        if (buffer_view.buffer >= self.asset.buffers.len) {
            return GLTFError.BufferOutOfBounds;
        }

        const buffer = self.asset.buffers[buffer_view.buffer];
        const start = buffer_view.byte_offset + accessor.byte_offset;
        const element_size = accessor.component_type.byteSize() * accessor.element_type.componentCount();
        const stride = self.getStride(accessor);
        const end = if (accessor.count == 0)
            start
        else
            start + (accessor.count - 1) * stride + element_size;

        if (end > buffer.len) {
            return GLTFError.AccessorOutOfBounds;
        }

        return buffer[start..];
    }

    /// Get stride for accessor (uses buffer view stride or computed from type)
    fn getStride(self: Self, accessor: AccessorData) usize {
        if (accessor.buffer_view) |bv_index| {
            const buffer_view = self.asset.buffer_views[bv_index];
            if (buffer_view.byte_stride) |stride| {
                return stride;
            }
        }
        return accessor.component_type.byteSize() * accessor.element_type.componentCount();
    }

    /// Read N components from data at offset, converting to target type
    fn readComponents(
        self: Self,
        comptime T: type,
        comptime N: usize,
        data: []const u8,
        offset: usize,
        component_type: ComponentType,
        normalized: bool,
    ) [N]T {
        _ = self;
        var result: [N]T = undefined;

        for (0..N) |i| {
            const component_offset = offset + i * component_type.byteSize();
            result[i] = readComponent(T, data, component_offset, component_type, normalized);
        }

        return result;
    }

    /// Read a single scalar value from data at offset
    fn readScalar(
        self: Self,
        comptime T: type,
        data: []const u8,
        offset: usize,
        component_type: ComponentType,
        normalized: bool,
    ) T {
        _ = self;
        return readComponent(T, data, offset, component_type, normalized);
    }
};

/// Read a single component value and convert to target type
fn readComponent(comptime T: type, data: []const u8, offset: usize, component_type: ComponentType, normalized: bool) T {
    if (T == f32 and normalized) {
        return switch (component_type) {
            .byte => clampNormalized(@as(f32, @floatFromInt(@as(i8, @bitCast(data[offset])))), 127.0),
            .unsigned_byte => @as(f32, @floatFromInt(data[offset])) / 255.0,
            .short => blk: {
                const bytes = data[offset..][0..2];
                const value = std.mem.readInt(i16, bytes, .little);
                break :blk clampNormalized(@as(f32, @floatFromInt(value)), 32767.0);
            },
            .unsigned_short => blk: {
                const bytes = data[offset..][0..2];
                const value = std.mem.readInt(u16, bytes, .little);
                break :blk @as(f32, @floatFromInt(value)) / 65535.0;
            },
            .unsigned_int => blk: {
                const bytes = data[offset..][0..4];
                const value = std.mem.readInt(u32, bytes, .little);
                break :blk @as(f32, @floatFromInt(value)) / 4294967295.0;
            },
            .float => blk: {
                const bytes = data[offset..][0..4];
                const bits = std.mem.readInt(u32, bytes, .little);
                break :blk @as(f32, @bitCast(bits));
            },
        };
    }

    return switch (component_type) {
        .byte => convertToType(T, @as(i8, @bitCast(data[offset]))),
        .unsigned_byte => convertToType(T, data[offset]),
        .short => blk: {
            const bytes = data[offset..][0..2];
            break :blk convertToType(T, std.mem.readInt(i16, bytes, .little));
        },
        .unsigned_short => blk: {
            const bytes = data[offset..][0..2];
            break :blk convertToType(T, std.mem.readInt(u16, bytes, .little));
        },
        .unsigned_int => blk: {
            const bytes = data[offset..][0..4];
            break :blk convertToType(T, std.mem.readInt(u32, bytes, .little));
        },
        .float => blk: {
            const bytes = data[offset..][0..4];
            const bits = std.mem.readInt(u32, bytes, .little);
            break :blk convertToType(T, @as(f32, @bitCast(bits)));
        },
    };
}

fn clampNormalized(value: f32, max_value: f32) f32 {
    const scaled = value / max_value;
    return std.math.clamp(scaled, -1.0, 1.0);
}

/// Convert any numeric type to target type
fn convertToType(comptime T: type, value: anytype) T {
    const V = @TypeOf(value);

    if (T == f32) {
        return switch (@typeInfo(V)) {
            .int => @floatFromInt(value),
            .float => @floatCast(value),
            else => @compileError("Unsupported type"),
        };
    } else if (T == u32) {
        return switch (@typeInfo(V)) {
            .int => @intCast(value),
            .float => @intFromFloat(value),
            else => @compileError("Unsupported type"),
        };
    } else {
        @compileError("Unsupported target type");
    }
}

/// Generate flat normals for triangles (when normals aren't provided)
pub fn generateFlatNormals(allocator: std.mem.Allocator, positions: []const Vec3, indices: []const u32) ![]Vec3 {
    var normals = try allocator.alloc(Vec3, positions.len);
    @memset(normals, Vec3.zero());

    // Calculate face normals and accumulate to vertices
    var idx: usize = 0;
    while (idx + 2 < indices.len) : (idx += 3) {
        const idx0 = indices[idx];
        const idx1 = indices[idx + 1];
        const idx2 = indices[idx + 2];

        const v0 = positions[idx0];
        const v1 = positions[idx1];
        const v2 = positions[idx2];

        const edge1 = v1.sub(v0);
        const edge2 = v2.sub(v0);
        const normal = edge1.cross(edge2).normalize();

        normals[idx0] = normals[idx0].add(normal);
        normals[idx1] = normals[idx1].add(normal);
        normals[idx2] = normals[idx2].add(normal);
    }

    // Normalize accumulated normals
    for (normals) |*n| {
        const len = n.length();
        if (len > 0.0001) {
            n.* = n.mul(1.0 / len);
        } else {
            n.* = Vec3.init(0, 1, 0); // Default up if degenerate
        }
    }

    return normals;
}

/// Generate sequential indices for non-indexed geometry
pub fn generateSequentialIndices(allocator: std.mem.Allocator, vertex_count: usize) ![]u32 {
    const indices = try allocator.alloc(u32, vertex_count);
    for (indices, 0..) |*idx_ptr, i| {
        idx_ptr.* = @intCast(i);
    }
    return indices;
}
