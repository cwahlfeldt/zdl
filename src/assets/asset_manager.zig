const std = @import("std");
const sdl = @import("sdl3");
const Mesh = @import("../resources/mesh.zig").Mesh;
const Texture = @import("../resources/texture.zig").Texture;
pub const gltf = @import("gltf/gltf.zig");
const GLTFAsset = gltf.GLTFAsset;
const GLTFLoader = gltf.GLTFLoader;
const Scene = @import("../ecs/scene.zig").Scene;
const Entity = @import("../ecs/entity.zig").Entity;

/// Runtime asset manager for loading and caching game assets
/// Provides a central point for asset lifecycle management and caching
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    device: *sdl.gpu.Device,

    /// Cached textures by path
    textures: std.StringHashMap(*Texture),

    /// Cached meshes by path
    meshes: std.StringHashMap(*Mesh),

    /// Cached glTF assets by path
    gltf_assets: std.StringHashMap(*GLTFAsset),

    /// Base path for asset loading
    base_path: []const u8,

    const Self = @This();

    /// Initialize the asset manager
    pub fn init(allocator: std.mem.Allocator, device: *sdl.gpu.Device) Self {
        return .{
            .allocator = allocator,
            .device = device,
            .textures = std.StringHashMap(*Texture).init(allocator),
            .meshes = std.StringHashMap(*Mesh).init(allocator),
            .gltf_assets = std.StringHashMap(*GLTFAsset).init(allocator),
            .base_path = "",
        };
    }

    /// Initialize with a base path for asset loading
    pub fn initWithBasePath(
        allocator: std.mem.Allocator,
        device: *sdl.gpu.Device,
        base_path: []const u8,
    ) !Self {
        return .{
            .allocator = allocator,
            .device = device,
            .textures = std.StringHashMap(*Texture).init(allocator),
            .meshes = std.StringHashMap(*Mesh).init(allocator),
            .gltf_assets = std.StringHashMap(*GLTFAsset).init(allocator),
            .base_path = try allocator.dupe(u8, base_path),
        };
    }

    /// Deinitialize and free all cached assets
    pub fn deinit(self: *Self) void {
        // Free all cached glTF assets
        var gltf_it = self.gltf_assets.iterator();
        while (gltf_it.next()) |entry| {
            entry.value_ptr.*.deinit(self.device);
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.gltf_assets.deinit();

        // Free all cached textures
        // Note: Textures registered from glTF assets are owned by those assets (freed above).
        // We only free the cache keys here, not the textures themselves.
        var tex_it = self.textures.iterator();
        while (tex_it.next()) |entry| {
            // Don't deinit/destroy - glTF assets own the textures
            self.allocator.free(entry.key_ptr.*);
        }
        self.textures.deinit();

        // Free all cached meshes
        // Note: Meshes registered from glTF assets are owned by those assets (freed above).
        // We only free the cache keys here, not the meshes themselves.
        var mesh_it = self.meshes.iterator();
        while (mesh_it.next()) |entry| {
            // Don't deinit/destroy - glTF assets own the meshes
            self.allocator.free(entry.key_ptr.*);
        }
        self.meshes.deinit();

        if (self.base_path.len > 0) {
            self.allocator.free(self.base_path);
        }
    }

    /// Load a texture from file, returning cached version if already loaded
    pub fn loadTexture(self: *Self, path: []const u8) !*Texture {
        // Check cache first
        if (self.textures.get(path)) |cached| {
            return cached;
        }

        // Build full path
        const full_path = if (self.base_path.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.base_path, path })
        else
            try self.allocator.dupe(u8, path);
        defer self.allocator.free(full_path);

        // Load the texture
        const texture = try self.allocator.create(Texture);
        errdefer self.allocator.destroy(texture);

        texture.* = try Texture.loadFromFile(self.device, full_path);
        errdefer texture.deinit(self.device);

        // Cache it
        const key = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(key);

        try self.textures.put(key, texture);

        return texture;
    }

    /// Store a mesh in the cache (takes ownership)
    pub fn storeMesh(self: *Self, name: []const u8, mesh: Mesh) !*Mesh {
        // Check if already cached
        if (self.meshes.get(name)) |existing| {
            return existing;
        }

        // Create heap-allocated mesh
        const stored = try self.allocator.create(Mesh);
        errdefer self.allocator.destroy(stored);

        stored.* = mesh;

        // Cache it
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);

        try self.meshes.put(key, stored);

        return stored;
    }

    /// Get a cached mesh by name
    pub fn getMesh(self: *Self, name: []const u8) ?*Mesh {
        return self.meshes.get(name);
    }

    /// Get a cached texture by path
    pub fn getTexture(self: *Self, path: []const u8) ?*Texture {
        return self.textures.get(path);
    }

    /// Check if a texture is loaded
    pub fn hasTexture(self: *Self, path: []const u8) bool {
        return self.textures.contains(path);
    }

    /// Check if a mesh is loaded
    pub fn hasMesh(self: *Self, name: []const u8) bool {
        return self.meshes.contains(name);
    }

    /// Unload a specific texture
    pub fn unloadTexture(self: *Self, path: []const u8) void {
        if (self.textures.fetchRemove(path)) |kv| {
            kv.value.deinit(self.device);
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        }
    }

    /// Unload a specific mesh
    pub fn unloadMesh(self: *Self, name: []const u8) void {
        if (self.meshes.fetchRemove(name)) |kv| {
            kv.value.deinit(self.device);
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        }
    }

    /// Unload all cached assets
    pub fn unloadAll(self: *Self) void {
        // Unload textures
        var tex_it = self.textures.iterator();
        while (tex_it.next()) |entry| {
            entry.value_ptr.*.deinit(self.device);
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.textures.clearRetainingCapacity();

        // Unload meshes
        var mesh_it = self.meshes.iterator();
        while (mesh_it.next()) |entry| {
            entry.value_ptr.*.deinit(self.device);
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.meshes.clearRetainingCapacity();
    }

    /// Get memory usage statistics
    pub fn getStats(self: *Self) Stats {
        return .{
            .texture_count = @intCast(self.textures.count()),
            .mesh_count = @intCast(self.meshes.count()),
            .gltf_count = @intCast(self.gltf_assets.count()),
        };
    }

    /// Find the name/key for a mesh pointer (reverse lookup for serialization)
    pub fn findMeshName(self: *Self, mesh: *const Mesh) ?[]const u8 {
        var it = self.meshes.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == mesh) {
                return entry.key_ptr.*;
            }
        }
        return null;
    }

    /// Find the path/key for a texture pointer (reverse lookup for serialization)
    pub fn findTexturePath(self: *Self, texture: *const Texture) ?[]const u8 {
        var it = self.textures.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == texture) {
                return entry.key_ptr.*;
            }
        }
        return null;
    }

    pub const Stats = struct {
        texture_count: u32,
        mesh_count: u32,
        gltf_count: u32,
    };

    // ============================================
    // glTF Loading Methods
    // ============================================

    /// Load a glTF asset from file (caches by path)
    pub fn loadGLTF(self: *Self, path: []const u8) !*GLTFAsset {
        // Check cache first
        if (self.gltf_assets.get(path)) |cached| {
            return cached;
        }

        // Build full path
        const full_path = if (self.base_path.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.base_path, path })
        else
            try self.allocator.dupe(u8, path);
        defer self.allocator.free(full_path);

        // Load using GLTFLoader
        var loader = GLTFLoader.init(self.allocator);
        const asset = try loader.load(full_path);
        errdefer {
            asset.deinit(self.device);
            self.allocator.destroy(asset);
        }

        // Upload to GPU
        try loader.uploadToGPU(asset, self.device);

        // Register meshes and textures with this asset manager for serialization
        try self.registerGLTFAssets(asset);

        // Cache the glTF asset
        const key = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(key);
        try self.gltf_assets.put(key, asset);

        return asset;
    }

    /// Load a glTF asset and import its scene into an ECS Scene
    /// Returns the root entities of the imported scene
    pub fn importGLTFScene(
        self: *Self,
        path: []const u8,
        ecs_scene: *Scene,
        scene_index: ?usize,
    ) ![]Entity {
        const asset = try self.loadGLTF(path);
        var loader = GLTFLoader.init(self.allocator);
        return try loader.importScene(asset, ecs_scene, scene_index);
    }

    /// Get a cached glTF asset by path
    pub fn getGLTF(self: *Self, path: []const u8) ?*GLTFAsset {
        return self.gltf_assets.get(path);
    }

    /// Check if a glTF asset is loaded
    pub fn hasGLTF(self: *Self, path: []const u8) bool {
        return self.gltf_assets.contains(path);
    }

    /// Unload a specific glTF asset
    pub fn unloadGLTF(self: *Self, path: []const u8) void {
        if (self.gltf_assets.fetchRemove(path)) |kv| {
            // Note: Don't unload individual meshes/textures as other code may reference them
            kv.value.deinit(self.device);
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        }
    }

    /// Register glTF meshes and textures with this asset manager for serialization support
    fn registerGLTFAssets(self: *Self, asset: *GLTFAsset) !void {
        // Register meshes with qualified names
        for (asset.meshes, 0..) |mesh_data, mesh_idx| {
            for (mesh_data.primitives, 0..) |_, prim_idx| {
                const key = gltf.types.MeshPrimitiveKey{
                    .mesh_index = mesh_idx,
                    .primitive_index = prim_idx,
                };
                if (asset.mesh_map.get(key)) |gpu_idx| {
                    const mesh = asset.gpu_meshes.items[gpu_idx];
                    const name = try asset.getMeshName(mesh_idx, prim_idx);
                    defer self.allocator.free(name);

                    // Store in meshes cache (don't take ownership - glTF asset owns it)
                    const cache_key = try self.allocator.dupe(u8, name);
                    try self.meshes.put(cache_key, mesh);
                }
            }
        }

        // Register textures with qualified names
        var tex_it = asset.texture_map.iterator();
        while (tex_it.next()) |entry| {
            const tex_idx = entry.key_ptr.*;
            const gpu_idx = entry.value_ptr.*;
            const texture = asset.gpu_textures.items[gpu_idx];
            const name = try asset.getTextureName(tex_idx);
            defer self.allocator.free(name);

            // Store in textures cache (don't take ownership - glTF asset owns it)
            const cache_key = try self.allocator.dupe(u8, name);
            try self.textures.put(cache_key, texture);
        }
    }
};
