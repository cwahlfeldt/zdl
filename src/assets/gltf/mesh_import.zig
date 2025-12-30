const std = @import("std");
const types = @import("types.zig");
const accessor = @import("accessor.zig");
const GLTFError = types.GLTFError;
const GLTFAsset = types.GLTFAsset;
const MeshData = types.MeshData;
const PrimitiveData = types.PrimitiveData;
const PrimitiveMode = types.PrimitiveMode;
const MeshPrimitiveKey = types.MeshPrimitiveKey;
const AccessorReader = accessor.AccessorReader;
const Mesh = @import("../../resources/mesh.zig").Mesh;
const Vertex3D = @import("../../resources/mesh.zig").Vertex3D;
const Vec2 = @import("../../math/vec2.zig").Vec2;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Vec4 = @import("../../math/vec4.zig").Vec4;
const sdl = @import("sdl3");

/// Import all meshes from a glTF asset and upload to GPU
pub fn importMeshes(asset: *GLTFAsset, device: *sdl.gpu.Device) !void {
    const reader = AccessorReader.init(asset);

    for (asset.meshes, 0..) |mesh_data, mesh_idx| {
        for (mesh_data.primitives, 0..) |primitive, prim_idx| {
            const mesh = try importPrimitive(asset.allocator, reader, primitive);
            errdefer {
                mesh.deinit(device);
                asset.allocator.destroy(mesh);
            }

            // Upload to GPU
            try mesh.upload(device);

            // Store in asset
            const gpu_idx = asset.gpu_meshes.items.len;
            try asset.gpu_meshes.append(asset.allocator, mesh);

            // Map glTF indices to GPU mesh index
            try asset.mesh_map.put(.{
                .mesh_index = mesh_idx,
                .primitive_index = prim_idx,
            }, gpu_idx);
        }
    }
}

/// Import a single primitive as a ZDL Mesh
fn importPrimitive(
    allocator: std.mem.Allocator,
    reader: AccessorReader,
    primitive: PrimitiveData,
) !*Mesh {
    // Only support triangles for now
    if (primitive.mode != .triangles) {
        return GLTFError.UnsupportedPrimitiveMode;
    }

    // Position is required
    const position_idx = primitive.attributes.position orelse {
        return GLTFError.MissingPositionAttribute;
    };

    // Read positions
    const positions = try reader.readVec3(allocator, position_idx);
    defer allocator.free(positions);

    // Read or generate indices
    var indices: []u32 = undefined;
    var owns_indices = false;
    if (primitive.indices) |idx_accessor| {
        indices = try reader.readIndices(allocator, idx_accessor);
        owns_indices = true;
    } else {
        indices = try accessor.generateSequentialIndices(allocator, positions.len);
        owns_indices = true;
    }
    defer if (owns_indices) allocator.free(indices);

    // Read or generate normals
    var normals: []Vec3 = undefined;
    var owns_normals = false;
    if (primitive.attributes.normal) |normal_idx| {
        normals = try reader.readVec3(allocator, normal_idx);
        owns_normals = true;
    } else {
        normals = try accessor.generateFlatNormals(allocator, positions, indices);
        owns_normals = true;
    }
    defer if (owns_normals) allocator.free(normals);

    // Read UVs (optional)
    var uvs: ?[]Vec2 = null;
    if (primitive.attributes.texcoord_0) |uv_idx| {
        uvs = try reader.readVec2(allocator, uv_idx);
    }
    defer if (uvs) |u| allocator.free(u);

    // Read vertex colors (optional)
    var colors: ?[]Vec4 = null;
    if (primitive.attributes.color_0) |color_idx| {
        colors = try reader.readVec4(allocator, color_idx);
    }
    defer if (colors) |c| allocator.free(c);

    // Build Vertex3D array
    var vertices = try allocator.alloc(Vertex3D, positions.len);
    errdefer allocator.free(vertices);

    for (0..positions.len) |i| {
        const pos = positions[i];
        const normal = if (i < normals.len) normals[i] else Vec3.init(0, 1, 0);
        const uv = if (uvs) |u| (if (i < u.len) u[i] else Vec2.init(0, 0)) else Vec2.init(0, 0);
        const color = if (colors) |c| (if (i < c.len) c[i] else Vec4.init(1, 1, 1, 1)) else Vec4.init(1, 1, 1, 1);

        vertices[i] = Vertex3D.init(
            pos,
            normal,
            uv,
            .{ color.x, color.y, color.z, color.w },
        );
    }

    // Create mesh
    const mesh = try allocator.create(Mesh);
    errdefer allocator.destroy(mesh);

    // Copy indices
    const indices_copy = try allocator.dupe(u32, indices);
    errdefer allocator.free(indices_copy);

    mesh.* = .{
        .vertices = vertices,
        .indices = indices_copy,
        .vertex_buffer = null,
        .index_buffer = null,
        .allocator = allocator,
    };

    return mesh;
}

/// Get the GPU mesh for a glTF mesh/primitive pair
pub fn getGPUMesh(asset: *const GLTFAsset, mesh_index: usize, primitive_index: usize) ?*Mesh {
    const key = MeshPrimitiveKey{
        .mesh_index = mesh_index,
        .primitive_index = primitive_index,
    };

    if (asset.mesh_map.get(key)) |gpu_idx| {
        return asset.gpu_meshes.items[gpu_idx];
    }
    return null;
}
