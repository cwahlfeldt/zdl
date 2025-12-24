const std = @import("std");
const Mesh = @import("mesh.zig").Mesh;
const Vertex3D = @import("mesh.zig").Vertex3D;
const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec2 = @import("../math/vec2.zig").Vec2;

/// Create a cube mesh with proper normals (24 vertices for correct face normals)
/// Size: 1.0 (from -0.5 to 0.5 on each axis)
pub fn createCube(allocator: std.mem.Allocator) !Mesh {
    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    // 24 vertices (4 per face)
    const vertices = [_]Vertex3D{
        // Front (Z+) - Normal: 0, 0, 1
        Vertex3D.init(Vec3.init(-0.5, -0.5, 0.5), Vec3.init(0, 0, 1), Vec2.init(0, 1), white), // 0
        Vertex3D.init(Vec3.init(0.5, -0.5, 0.5), Vec3.init(0, 0, 1), Vec2.init(1, 1), white), // 1
        Vertex3D.init(Vec3.init(0.5, 0.5, 0.5), Vec3.init(0, 0, 1), Vec2.init(1, 0), white), // 2
        Vertex3D.init(Vec3.init(-0.5, 0.5, 0.5), Vec3.init(0, 0, 1), Vec2.init(0, 0), white), // 3

        // Back (Z-) - Normal: 0, 0, -1
        Vertex3D.init(Vec3.init(0.5, -0.5, -0.5), Vec3.init(0, 0, -1), Vec2.init(0, 1), white), // 4
        Vertex3D.init(Vec3.init(-0.5, -0.5, -0.5), Vec3.init(0, 0, -1), Vec2.init(1, 1), white), // 5
        Vertex3D.init(Vec3.init(-0.5, 0.5, -0.5), Vec3.init(0, 0, -1), Vec2.init(1, 0), white), // 6
        Vertex3D.init(Vec3.init(0.5, 0.5, -0.5), Vec3.init(0, 0, -1), Vec2.init(0, 0), white), // 7

        // Top (Y+) - Normal: 0, 1, 0
        Vertex3D.init(Vec3.init(-0.5, 0.5, 0.5), Vec3.init(0, 1, 0), Vec2.init(0, 1), white), // 8
        Vertex3D.init(Vec3.init(0.5, 0.5, 0.5), Vec3.init(0, 1, 0), Vec2.init(1, 1), white), // 9
        Vertex3D.init(Vec3.init(0.5, 0.5, -0.5), Vec3.init(0, 1, 0), Vec2.init(1, 0), white), // 10
        Vertex3D.init(Vec3.init(-0.5, 0.5, -0.5), Vec3.init(0, 1, 0), Vec2.init(0, 0), white), // 11

        // Bottom (Y-) - Normal: 0, -1, 0
        Vertex3D.init(Vec3.init(-0.5, -0.5, -0.5), Vec3.init(0, -1, 0), Vec2.init(0, 1), white), // 12
        Vertex3D.init(Vec3.init(0.5, -0.5, -0.5), Vec3.init(0, -1, 0), Vec2.init(1, 1), white), // 13
        Vertex3D.init(Vec3.init(0.5, -0.5, 0.5), Vec3.init(0, -1, 0), Vec2.init(1, 0), white), // 14
        Vertex3D.init(Vec3.init(-0.5, -0.5, 0.5), Vec3.init(0, -1, 0), Vec2.init(0, 0), white), // 15

        // Right (X+) - Normal: 1, 0, 0
        Vertex3D.init(Vec3.init(0.5, -0.5, 0.5), Vec3.init(1, 0, 0), Vec2.init(0, 1), white), // 16
        Vertex3D.init(Vec3.init(0.5, -0.5, -0.5), Vec3.init(1, 0, 0), Vec2.init(1, 1), white), // 17
        Vertex3D.init(Vec3.init(0.5, 0.5, -0.5), Vec3.init(1, 0, 0), Vec2.init(1, 0), white), // 18
        Vertex3D.init(Vec3.init(0.5, 0.5, 0.5), Vec3.init(1, 0, 0), Vec2.init(0, 0), white), // 19

        // Left (X-) - Normal: -1, 0, 0
        Vertex3D.init(Vec3.init(-0.5, -0.5, -0.5), Vec3.init(-1, 0, 0), Vec2.init(0, 1), white), // 20
        Vertex3D.init(Vec3.init(-0.5, -0.5, 0.5), Vec3.init(-1, 0, 0), Vec2.init(1, 1), white), // 21
        Vertex3D.init(Vec3.init(-0.5, 0.5, 0.5), Vec3.init(-1, 0, 0), Vec2.init(1, 0), white), // 22
        Vertex3D.init(Vec3.init(-0.5, 0.5, -0.5), Vec3.init(-1, 0, 0), Vec2.init(0, 0), white), // 23
    };

    // Every face now uses the exact same CCW pattern: 0->1->2 and 2->3->0
    const indices = [_]u32{
        0, 1, 2, 2, 3, 0, // Front
        4, 5, 6, 6, 7, 4, // Back
        8, 9, 10, 10, 11, 8, // Top
        12, 13, 14, 14, 15, 12, // Bottom
        16, 17, 18, 18, 19, 16, // Right
        20, 21, 22, 22, 23, 20, // Left
    };

    return try Mesh.init(allocator, &vertices, &indices);
}

/// Create a plane mesh (XZ plane, facing up)
/// Size: 1.0 (from -0.5 to 0.5 on X and Z axes, Y = 0)
pub fn createPlane(allocator: std.mem.Allocator) !Mesh {
    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    const vertices = [_]Vertex3D{
        Vertex3D.init(Vec3.init(-0.5, 0, 0.5), Vec3.init(0, 1, 0), Vec2.init(0, 0), white),
        Vertex3D.init(Vec3.init(0.5, 0, 0.5), Vec3.init(0, 1, 0), Vec2.init(1, 0), white),
        Vertex3D.init(Vec3.init(0.5, 0, -0.5), Vec3.init(0, 1, 0), Vec2.init(1, 1), white),
        Vertex3D.init(Vec3.init(-0.5, 0, -0.5), Vec3.init(0, 1, 0), Vec2.init(0, 1), white),
    };

    const indices = [_]u32{
        0, 1, 2,
        2, 3, 0,
    };

    return try Mesh.init(allocator, &vertices, &indices);
}

/// Create a quad mesh (XY plane, facing camera)
/// Size: 1.0 (from -0.5 to 0.5 on X and Y axes, Z = 0)
pub fn createQuad(allocator: std.mem.Allocator) !Mesh {
    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    const vertices = [_]Vertex3D{
        Vertex3D.init(Vec3.init(-0.5, -0.5, 0), Vec3.init(0, 0, 1), Vec2.init(0, 1), white),
        Vertex3D.init(Vec3.init(0.5, -0.5, 0), Vec3.init(0, 0, 1), Vec2.init(1, 1), white),
        Vertex3D.init(Vec3.init(0.5, 0.5, 0), Vec3.init(0, 0, 1), Vec2.init(1, 0), white),
        Vertex3D.init(Vec3.init(-0.5, 0.5, 0), Vec3.init(0, 0, 1), Vec2.init(0, 0), white),
    };

    const indices = [_]u32{
        0, 1, 2,
        2, 3, 0,
    };

    return try Mesh.init(allocator, &vertices, &indices);
}

/// Create a sphere mesh using UV sphere algorithm
/// Resolution: number of latitude and longitude segments
pub fn createSphere(allocator: std.mem.Allocator, resolution: u32) !Mesh {
    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    var vertices = std.ArrayList(Vertex3D).init(allocator);
    defer vertices.deinit();

    var indices = std.ArrayList(u32).init(allocator);
    defer indices.deinit();

    const lat_segments = resolution;
    const lon_segments = resolution * 2;

    // Generate vertices
    var lat: u32 = 0;
    while (lat <= lat_segments) : (lat += 1) {
        const theta = @as(f32, @floatFromInt(lat)) * std.math.pi / @as(f32, @floatFromInt(lat_segments));
        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);

        var lon: u32 = 0;
        while (lon <= lon_segments) : (lon += 1) {
            const phi = @as(f32, @floatFromInt(lon)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(lon_segments));
            const sin_phi = @sin(phi);
            const cos_phi = @cos(phi);

            const x = cos_phi * sin_theta;
            const y = cos_theta;
            const z = sin_phi * sin_theta;

            const position = Vec3.init(x * 0.5, y * 0.5, z * 0.5);
            const normal = Vec3.init(x, y, z);
            const u = @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(lon_segments));
            const v = @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(lat_segments));

            try vertices.append(Vertex3D.init(position, normal, Vec2.init(u, v), white));
        }
    }

    // Generate indices
    lat = 0;
    while (lat < lat_segments) : (lat += 1) {
        var lon: u32 = 0;
        while (lon < lon_segments) : (lon += 1) {
            const first = lat * (lon_segments + 1) + lon;
            const second = first + lon_segments + 1;

            try indices.append(first);
            try indices.append(second);
            try indices.append(first + 1);

            try indices.append(second);
            try indices.append(second + 1);
            try indices.append(first + 1);
        }
    }

    return try Mesh.init(allocator, vertices.items, indices.items);
}
