const std = @import("std");
const sdl = @import("sdl3");
const Mesh = @import("../resources/mesh.zig").Mesh;
const Texture = @import("../resources/texture.zig").Texture;

/// Runtime asset manager for loading and caching game assets
/// Provides a central point for asset lifecycle management and caching
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    device: *sdl.gpu.Device,

    /// Cached textures by path
    textures: std.StringHashMap(*Texture),

    /// Cached meshes by path
    meshes: std.StringHashMap(*Mesh),

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
            .base_path = try allocator.dupe(u8, base_path),
        };
    }

    /// Deinitialize and free all cached assets
    pub fn deinit(self: *Self) void {
        // Free all cached textures
        var tex_it = self.textures.iterator();
        while (tex_it.next()) |entry| {
            entry.value_ptr.*.deinit(self.device);
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.textures.deinit();

        // Free all cached meshes
        var mesh_it = self.meshes.iterator();
        while (mesh_it.next()) |entry| {
            entry.value_ptr.*.deinit(self.device);
            self.allocator.destroy(entry.value_ptr.*);
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
        };
    }

    pub const Stats = struct {
        texture_count: u32,
        mesh_count: u32,
    };
};
