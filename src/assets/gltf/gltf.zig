// glTF 2.0 Asset Loading Module
//
// Provides support for loading glTF 2.0 files (.gltf and .glb) into the ZDL engine.
// Supports meshes, textures, materials (base color), and scene hierarchies.

const std = @import("std");
const sdl = @import("sdl3");

// Types
pub const types = @import("types.zig");
pub const GLTFAsset = types.GLTFAsset;
pub const GLTFError = types.GLTFError;
pub const NodeData = types.NodeData;
pub const SceneData = types.SceneData;
pub const MeshData = types.MeshData;
pub const MaterialData = types.MaterialData;
pub const PrimitiveMode = types.PrimitiveMode;

// Sub-modules
pub const binary = @import("binary.zig");
pub const parser = @import("parser.zig");
pub const accessor = @import("accessor.zig");
pub const mesh_import = @import("mesh_import.zig");
pub const texture_import = @import("texture_import.zig");
pub const scene_import = @import("scene_import.zig");

const Scene = @import("../../ecs/scene.zig").Scene;
const Entity = @import("../../ecs/entity.zig").Entity;

/// Main glTF loader interface
pub const GLTFLoader = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Load a glTF file from disk (auto-detects .gltf vs .glb)
    pub fn load(self: Self, path: []const u8) !*GLTFAsset {
        const asset = try self.allocator.create(GLTFAsset);
        errdefer self.allocator.destroy(asset);

        asset.* = GLTFAsset.init(self.allocator);
        errdefer asset.deinit(null);

        // Store source path
        asset.source_path = try self.allocator.dupe(u8, path);

        // Get base directory for resolving relative URIs
        if (std.fs.path.dirname(path)) |dir| {
            asset.base_path = try self.allocator.dupe(u8, dir);
        } else {
            asset.base_path = try self.allocator.dupe(u8, ".");
        }

        // Read file
        const file_data = try std.fs.cwd().readFileAlloc(self.allocator, path, 100 * 1024 * 1024); // 100MB max
        defer self.allocator.free(file_data);

        // Check if GLB or glTF
        if (binary.isGLB(file_data)) {
            try self.loadGLB(asset, file_data);
        } else {
            try self.loadGLTF(asset, file_data, path);
        }

        return asset;
    }

    /// Load from GLB binary data
    fn loadGLB(self: Self, asset: *GLTFAsset, data: []const u8) !void {
        const result = try binary.parseGLB(data);

        // Parse JSON
        try parser.parseJSON(self.allocator, result.json_data, asset);

        // Store binary chunk if present
        if (result.bin_data) |bin| {
            if (asset.buffers.len > 0) {
                // GLB binary chunk is buffer 0
                asset.buffers[0] = bin;
                asset.owns_buffers[0] = false; // Don't free - it's a slice into the file data

                // Actually, we need to copy since file_data is freed
                const bin_copy = try self.allocator.dupe(u8, bin);
                asset.buffers[0] = bin_copy;
                asset.owns_buffers[0] = true;
            }
        }

        // Load any additional external buffers (rare in GLB but possible)
        try self.loadExternalBuffers(asset);
    }

    /// Load from glTF JSON + external files
    fn loadGLTF(self: Self, asset: *GLTFAsset, json_data: []const u8, path: []const u8) !void {
        _ = path;

        // Parse JSON
        try parser.parseJSON(self.allocator, json_data, asset);

        // Load external buffers
        try self.loadExternalBuffers(asset);
    }

    /// Load external buffer files referenced by URI
    fn loadExternalBuffers(self: Self, asset: *GLTFAsset) !void {
        // Re-parse JSON to get buffer URIs
        const json_data = try std.fs.cwd().readFileAlloc(self.allocator, asset.source_path, 100 * 1024 * 1024);
        defer self.allocator.free(json_data);

        // Skip if file is GLB (we already handled the binary chunk)
        if (binary.isGLB(json_data)) return;

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch return;
        defer parsed.deinit();

        const root = parsed.value;
        const buffers_json = root.object.get("buffers") orelse return;

        for (buffers_json.array.items, 0..) |buffer_obj, i| {
            // Skip if already loaded
            if (asset.buffers[i].len > 0) continue;

            const uri = buffer_obj.object.get("uri") orelse continue;
            const uri_str = uri.string;

            if (std.mem.startsWith(u8, uri_str, "data:")) {
                // Base64 data URI
                const decoded = try decodeDataURI(self.allocator, uri_str);
                asset.buffers[i] = decoded;
                asset.owns_buffers[i] = true;
            } else {
                // External file
                const full_path = try std.fs.path.join(self.allocator, &.{ asset.base_path, uri_str });
                defer self.allocator.free(full_path);

                const buffer_data = try std.fs.cwd().readFileAlloc(self.allocator, full_path, 100 * 1024 * 1024);
                asset.buffers[i] = buffer_data;
                asset.owns_buffers[i] = true;
            }
        }
    }

    /// Upload all meshes and textures to GPU
    pub fn uploadToGPU(self: Self, asset: *GLTFAsset, device: *sdl.gpu.Device) !void {
        _ = self;

        // Import meshes
        try mesh_import.importMeshes(asset, device);

        // Import textures
        try texture_import.importTextures(asset, device);
    }

    /// Import a glTF scene into an ECS Scene
    /// Returns array of root entities (caller owns slice)
    pub fn importScene(
        self: Self,
        asset: *const GLTFAsset,
        ecs_scene: *Scene,
        scene_index: ?usize,
    ) ![]Entity {
        _ = self;
        return scene_import.importScene(asset, ecs_scene, scene_index);
    }

    /// Convenience method: load, upload, and import in one call
    pub fn loadAndImport(
        self: Self,
        path: []const u8,
        device: *sdl.gpu.Device,
        ecs_scene: *Scene,
        scene_index: ?usize,
    ) !struct { asset: *GLTFAsset, entities: []Entity } {
        const asset = try self.load(path);
        errdefer {
            asset.deinit(device);
            self.allocator.destroy(asset);
        }

        try self.uploadToGPU(asset, device);

        const entities = try self.importScene(asset, ecs_scene, scene_index);

        return .{
            .asset = asset,
            .entities = entities,
        };
    }
};

/// Decode a base64 data URI
fn decodeDataURI(allocator: std.mem.Allocator, uri: []const u8) ![]u8 {
    const comma_pos = std.mem.indexOf(u8, uri, ",") orelse return GLTFError.InvalidImageSource;
    const data = uri[comma_pos + 1 ..];

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(data) catch {
        return GLTFError.InvalidImageSource;
    };
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    std.base64.standard.Decoder.decode(decoded, data) catch {
        allocator.free(decoded);
        return GLTFError.InvalidImageSource;
    };

    return decoded;
}

test "GLTFLoader initialization" {
    const allocator = std.testing.allocator;
    const loader = GLTFLoader.init(allocator);
    _ = loader;
}
