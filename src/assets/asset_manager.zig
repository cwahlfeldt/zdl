const std = @import("std");
const sdl = @import("sdl3");
const Mesh = @import("../resources/mesh.zig").Mesh;
const Texture = @import("../resources/texture.zig").Texture;
pub const gltf = @import("gltf/gltf.zig");
const GLTFAsset = gltf.GLTFAsset;
const GLTFLoader = gltf.GLTFLoader;
const Scene = @import("../ecs/scene.zig").Scene;
const Entity = @import("../ecs/entity.zig").Entity;

// Asset handle types
pub const asset_handle = @import("asset_handle.zig");
pub const MeshHandle = asset_handle.MeshHandle;
pub const TextureHandle = asset_handle.TextureHandle;
const AssetStorage = asset_handle.AssetStorage;

/// Runtime asset manager for loading and caching game assets.
/// Uses handle-based references for safe asset lifetime management.
/// Handles use generational indices to detect stale references.
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    device: *sdl.gpu.Device,

    /// Handle-based mesh storage with generation tracking
    mesh_storage: AssetStorage(Mesh, MeshHandle),

    /// Handle-based texture storage with generation tracking
    texture_storage: AssetStorage(Texture, TextureHandle),

    /// Cached glTF assets by path (these own their meshes/textures)
    gltf_assets: std.StringHashMap(*GLTFAsset),

    /// Base path for asset loading
    base_path: []const u8,

    const Self = @This();

    /// Initialize the asset manager
    pub fn init(allocator: std.mem.Allocator, device: *sdl.gpu.Device) Self {
        return .{
            .allocator = allocator,
            .device = device,
            .mesh_storage = AssetStorage(Mesh, MeshHandle).init(allocator),
            .texture_storage = AssetStorage(Texture, TextureHandle).init(allocator),
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
            .mesh_storage = AssetStorage(Mesh, MeshHandle).init(allocator),
            .texture_storage = AssetStorage(Texture, TextureHandle).init(allocator),
            .gltf_assets = std.StringHashMap(*GLTFAsset).init(allocator),
            .base_path = try allocator.dupe(u8, base_path),
        };
    }

    /// Deinitialize and free all cached assets
    pub fn deinit(self: *Self) void {
        // Free all cached glTF assets (these own their mesh/texture data)
        var gltf_it = self.gltf_assets.iterator();
        while (gltf_it.next()) |entry| {
            entry.value_ptr.*.deinit(self.device);
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.gltf_assets.deinit();

        // Free mesh storage (only free owned meshes - borrowed ones are freed by their owner e.g. GLTFAsset)
        for (self.mesh_storage.slots.items) |slot| {
            if (slot.asset) |mesh| {
                if (slot.owned) {
                    mesh.deinit(self.device);
                    self.allocator.destroy(mesh);
                }
            }
        }
        self.mesh_storage.deinit();

        // Free texture storage (only free owned textures)
        for (self.texture_storage.slots.items) |slot| {
            if (slot.asset) |texture| {
                if (slot.owned) {
                    texture.deinit(self.device);
                    self.allocator.destroy(texture);
                }
            }
        }
        self.texture_storage.deinit();

        if (self.base_path.len > 0) {
            self.allocator.free(self.base_path);
        }
    }

    // ============================================
    // Mesh Management (Handle-based)
    // ============================================

    /// Store a mesh and return a handle to it.
    /// The AssetManager takes ownership of the mesh data.
    pub fn storeMesh(self: *Self, name: []const u8, mesh: Mesh) !MeshHandle {
        // Check if already cached by name
        if (self.mesh_storage.getByName(name)) |existing| {
            self.mesh_storage.addRef(existing);
            return existing;
        }

        // Create heap-allocated mesh
        const stored = try self.allocator.create(Mesh);
        errdefer self.allocator.destroy(stored);
        stored.* = mesh;

        return try self.mesh_storage.insert(stored, name);
    }

    /// Store a mesh without a name (useful for procedural meshes)
    pub fn storeMeshAnonymous(self: *Self, mesh: Mesh) !MeshHandle {
        const stored = try self.allocator.create(Mesh);
        errdefer self.allocator.destroy(stored);
        stored.* = mesh;

        return try self.mesh_storage.insert(stored, null);
    }

    /// Get mesh by handle. Returns null if handle is stale or invalid.
    pub fn getMesh(self: *Self, handle: MeshHandle) ?*Mesh {
        return self.mesh_storage.get(handle);
    }

    /// Get mesh handle by name
    pub fn getMeshHandle(self: *Self, name: []const u8) ?MeshHandle {
        return self.mesh_storage.getByName(name);
    }

    /// Increment reference count for a mesh handle
    pub fn addMeshRef(self: *Self, handle: MeshHandle) void {
        self.mesh_storage.addRef(handle);
    }

    /// Release a mesh handle. Returns true if the mesh was freed.
    pub fn releaseMesh(self: *Self, handle: MeshHandle) bool {
        if (self.mesh_storage.release(handle)) {
            // Refcount hit zero, free the mesh
            if (self.mesh_storage.get(handle)) |mesh| {
                mesh.deinit(self.device);
                self.allocator.destroy(mesh);
            }
            self.mesh_storage.remove(handle);
            return true;
        }
        return false;
    }

    /// Check if a mesh handle is valid
    pub fn isMeshValid(self: *Self, handle: MeshHandle) bool {
        return self.mesh_storage.isValidHandle(handle);
    }

    /// Get the name of a mesh by handle
    pub fn getMeshName(self: *Self, handle: MeshHandle) ?[]const u8 {
        return self.mesh_storage.getName(handle);
    }

    /// Find handle for a mesh pointer (reverse lookup for serialization)
    pub fn findMeshHandle(self: *Self, mesh: *const Mesh) ?MeshHandle {
        return self.mesh_storage.findHandle(mesh);
    }

    // ============================================
    // Texture Management (Handle-based)
    // ============================================

    /// Load a texture from file, returning cached version if already loaded
    pub fn loadTexture(self: *Self, path: []const u8) !TextureHandle {
        // Check cache first
        if (self.texture_storage.getByName(path)) |existing| {
            self.texture_storage.addRef(existing);
            return existing;
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

        return try self.texture_storage.insert(texture, path);
    }

    /// Store a texture with a name
    pub fn storeTexture(self: *Self, name: []const u8, texture: Texture) !TextureHandle {
        // Check if already cached by name
        if (self.texture_storage.getByName(name)) |existing| {
            self.texture_storage.addRef(existing);
            return existing;
        }

        const stored = try self.allocator.create(Texture);
        errdefer self.allocator.destroy(stored);
        stored.* = texture;

        return try self.texture_storage.insert(stored, name);
    }

    /// Get texture by handle. Returns null if handle is stale or invalid.
    pub fn getTexture(self: *Self, handle: TextureHandle) ?*Texture {
        return self.texture_storage.get(handle);
    }

    /// Get texture handle by path/name
    pub fn getTextureHandle(self: *Self, path: []const u8) ?TextureHandle {
        return self.texture_storage.getByName(path);
    }

    /// Increment reference count for a texture handle
    pub fn addTextureRef(self: *Self, handle: TextureHandle) void {
        self.texture_storage.addRef(handle);
    }

    /// Release a texture handle. Returns true if the texture was freed.
    pub fn releaseTexture(self: *Self, handle: TextureHandle) bool {
        if (self.texture_storage.release(handle)) {
            if (self.texture_storage.get(handle)) |texture| {
                texture.deinit(self.device);
                self.allocator.destroy(texture);
            }
            self.texture_storage.remove(handle);
            return true;
        }
        return false;
    }

    /// Check if a texture handle is valid
    pub fn isTextureValid(self: *Self, handle: TextureHandle) bool {
        return self.texture_storage.isValidHandle(handle);
    }

    /// Get the path/name of a texture by handle
    pub fn getTexturePath(self: *Self, handle: TextureHandle) ?[]const u8 {
        return self.texture_storage.getName(handle);
    }

    /// Find handle for a texture pointer (reverse lookup for serialization)
    pub fn findTextureHandle(self: *Self, texture: *const Texture) ?TextureHandle {
        return self.texture_storage.findHandle(texture);
    }

    // ============================================
    // Legacy Pointer-based API (for compatibility)
    // ============================================

    /// Get a cached mesh by name (returns pointer for legacy code)
    /// DEPRECATED: Use getMeshHandle + getMesh instead
    pub fn getMeshPtr(self: *Self, name: []const u8) ?*Mesh {
        if (self.mesh_storage.getByName(name)) |handle| {
            return self.mesh_storage.get(handle);
        }
        return null;
    }

    /// Get a cached texture by path (returns pointer for legacy code)
    /// DEPRECATED: Use getTextureHandle + getTexture instead
    pub fn getTexturePtr(self: *Self, path: []const u8) ?*Texture {
        if (self.texture_storage.getByName(path)) |handle| {
            return self.texture_storage.get(handle);
        }
        return null;
    }

    /// Check if a texture is loaded
    pub fn hasTexture(self: *Self, path: []const u8) bool {
        return self.texture_storage.getByName(path) != null;
    }

    /// Check if a mesh is loaded
    pub fn hasMesh(self: *Self, name: []const u8) bool {
        return self.mesh_storage.getByName(name) != null;
    }

    /// Find the name/key for a mesh pointer (reverse lookup for serialization)
    /// DEPRECATED: Use findMeshHandle + getMeshName instead
    pub fn findMeshName(self: *Self, mesh: *const Mesh) ?[]const u8 {
        if (self.mesh_storage.findHandle(mesh)) |handle| {
            return self.mesh_storage.getName(handle);
        }
        return null;
    }

    /// Find the path/key for a texture pointer (reverse lookup for serialization)
    /// DEPRECATED: Use findTextureHandle + getTexturePath instead
    pub fn findTexturePath(self: *Self, texture: *const Texture) ?[]const u8 {
        if (self.texture_storage.findHandle(texture)) |handle| {
            return self.texture_storage.getName(handle);
        }
        return null;
    }

    // ============================================
    // Statistics
    // ============================================

    /// Get memory usage statistics
    pub fn getStats(self: *Self) Stats {
        return .{
            .texture_count = @intCast(self.texture_storage.count()),
            .mesh_count = @intCast(self.mesh_storage.count()),
            .gltf_count = @intCast(self.gltf_assets.count()),
        };
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

        // Register meshes and textures with handle storage
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
            kv.value.deinit(self.device);
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        }
    }

    /// Register glTF meshes and textures with handle storage for serialization support.
    /// These are registered as borrowed (not owned) since the GLTFAsset owns the actual data.
    fn registerGLTFAssets(self: *Self, asset: *GLTFAsset) !void {
        // Register meshes with qualified names (borrowed - GLTFAsset owns them)
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

                    // Register as borrowed - glTF asset owns the actual mesh data
                    _ = try self.mesh_storage.insertBorrowed(mesh, name);
                }
            }
        }

        // Register textures with qualified names (borrowed - GLTFAsset owns them)
        var tex_it = asset.texture_map.iterator();
        while (tex_it.next()) |entry| {
            const tex_idx = entry.key_ptr.*;
            const gpu_idx = entry.value_ptr.*;
            const texture = asset.gpu_textures.items[gpu_idx];
            const name = try asset.getTextureName(tex_idx);
            defer self.allocator.free(name);

            // Register as borrowed - glTF asset owns the actual texture data
            _ = try self.texture_storage.insertBorrowed(texture, name);
        }
    }
};
