const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");

/// Platform-specific shader format and paths
pub const is_macos = builtin.os.tag == .macos;

pub const ShaderFormat = if (is_macos)
    sdl.gpu.ShaderFormatFlags{ .msl = true }
else
    sdl.gpu.ShaderFormatFlags{ .spirv = true };

/// Shader stage type
pub const ShaderStage = enum {
    vertex,
    fragment,
};

/// Shader resource counts for pipeline creation
pub const ShaderResourceCounts = struct {
    num_samplers: u32 = 0,
    num_storage_buffers: u32 = 0,
    num_storage_textures: u32 = 0,
    num_uniform_buffers: u32 = 0,
};

/// Shader definition with paths and entry points
pub const ShaderDef = struct {
    name: []const u8,
    vertex_path: []const u8,
    fragment_path: []const u8,
    vertex_entry: [:0]const u8,
    fragment_entry: [:0]const u8,
    vertex_resources: ShaderResourceCounts,
    fragment_resources: ShaderResourceCounts,
};

/// Built-in shader definitions
pub const BuiltinShaders = struct {
    pub const legacy = ShaderDef{
        .name = "legacy",
        .vertex_path = if (is_macos) "assets/shaders/shaders.metal" else "build/assets/shaders/vertex.spv",
        .fragment_path = if (is_macos) "assets/shaders/shaders.metal" else "build/assets/shaders/fragment.spv",
        .vertex_entry = if (is_macos) "vertex_main" else "main",
        .fragment_entry = if (is_macos) "fragment_main" else "main",
        .vertex_resources = .{ .num_uniform_buffers = 1 },
        .fragment_resources = .{ .num_samplers = 1 },
    };

    pub const pbr = ShaderDef{
        .name = "pbr",
        .vertex_path = if (is_macos) "assets/shaders/pbr.metal" else "build/assets/shaders/pbr.vert.spv",
        .fragment_path = if (is_macos) "assets/shaders/pbr.metal" else "build/assets/shaders/pbr.frag.spv",
        .vertex_entry = if (is_macos) "pbr_vertex_main" else "main",
        .fragment_entry = if (is_macos) "pbr_fragment_main" else "main",
        .vertex_resources = .{ .num_uniform_buffers = 1 },
        .fragment_resources = .{ .num_samplers = 8, .num_uniform_buffers = 2 },
    };

    pub const skybox = ShaderDef{
        .name = "skybox",
        .vertex_path = if (is_macos) "assets/shaders/skybox.metal" else "build/assets/shaders/skybox.vert.spv",
        .fragment_path = if (is_macos) "assets/shaders/skybox.metal" else "build/assets/shaders/skybox.frag.spv",
        .vertex_entry = if (is_macos) "skybox_vertex_main" else "main",
        .fragment_entry = if (is_macos) "skybox_fragment_main" else "main",
        .vertex_resources = .{ .num_uniform_buffers = 1 },
        .fragment_resources = .{ .num_samplers = 1 },
    };
};

/// Loaded shader pair (vertex + fragment)
pub const LoadedShader = struct {
    vertex: sdl.gpu.Shader,
    fragment: sdl.gpu.Shader,
    def: ShaderDef,
};

/// Manages shader loading and caching.
/// Provides a central location for all shader operations.
pub const ShaderLibrary = struct {
    allocator: std.mem.Allocator,
    device: *sdl.gpu.Device,
    shaders: std.StringHashMap(LoadedShader),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device: *sdl.gpu.Device) Self {
        return .{
            .allocator = allocator,
            .device = device,
            .shaders = std.StringHashMap(LoadedShader).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.shaders.iterator();
        while (it.next()) |entry| {
            self.device.releaseShader(entry.value_ptr.vertex);
            self.device.releaseShader(entry.value_ptr.fragment);
        }
        self.shaders.deinit();
    }

    /// Load a shader from a definition. Returns cached version if already loaded.
    pub fn load(self: *Self, def: ShaderDef) !LoadedShader {
        // Check cache first
        if (self.shaders.get(def.name)) |cached| {
            return cached;
        }

        // Load vertex shader code
        const vertex_code = try std.fs.cwd().readFileAlloc(
            self.allocator,
            def.vertex_path,
            1024 * 1024,
        );
        defer self.allocator.free(vertex_code);

        // Load fragment shader code (may be same file on macOS)
        const fragment_code = if (is_macos and std.mem.eql(u8, def.vertex_path, def.fragment_path))
            vertex_code
        else
            try std.fs.cwd().readFileAlloc(
                self.allocator,
                def.fragment_path,
                1024 * 1024,
            );
        defer if (!is_macos or !std.mem.eql(u8, def.vertex_path, def.fragment_path))
            self.allocator.free(fragment_code);

        // Create vertex shader
        const vertex_shader = try self.device.createShader(.{
            .code = vertex_code,
            .entry_point = def.vertex_entry,
            .format = ShaderFormat,
            .stage = .vertex,
            .num_samplers = def.vertex_resources.num_samplers,
            .num_storage_buffers = def.vertex_resources.num_storage_buffers,
            .num_storage_textures = def.vertex_resources.num_storage_textures,
            .num_uniform_buffers = def.vertex_resources.num_uniform_buffers,
        });
        errdefer self.device.releaseShader(vertex_shader);

        // Create fragment shader
        const fragment_shader = try self.device.createShader(.{
            .code = fragment_code,
            .entry_point = def.fragment_entry,
            .format = ShaderFormat,
            .stage = .fragment,
            .num_samplers = def.fragment_resources.num_samplers,
            .num_storage_buffers = def.fragment_resources.num_storage_buffers,
            .num_storage_textures = def.fragment_resources.num_storage_textures,
            .num_uniform_buffers = def.fragment_resources.num_uniform_buffers,
        });
        errdefer self.device.releaseShader(fragment_shader);

        const loaded = LoadedShader{
            .vertex = vertex_shader,
            .fragment = fragment_shader,
            .def = def,
        };

        // Cache it
        const name_copy = try self.allocator.dupe(u8, def.name);
        errdefer self.allocator.free(name_copy);
        try self.shaders.put(name_copy, loaded);

        return loaded;
    }

    /// Load the legacy (basic 3D) shader
    pub fn loadLegacy(self: *Self) !LoadedShader {
        return self.load(BuiltinShaders.legacy);
    }

    /// Load the PBR shader
    pub fn loadPBR(self: *Self) !LoadedShader {
        return self.load(BuiltinShaders.pbr);
    }

    /// Load the skybox shader
    pub fn loadSkybox(self: *Self) !LoadedShader {
        return self.load(BuiltinShaders.skybox);
    }

    /// Get a previously loaded shader by name
    pub fn get(self: *Self, name: []const u8) ?LoadedShader {
        return self.shaders.get(name);
    }

    /// Check if a shader is loaded
    pub fn isLoaded(self: *Self, name: []const u8) bool {
        return self.shaders.contains(name);
    }

    /// Get the shader format for the current platform
    pub fn getFormat() sdl.gpu.ShaderFormatFlags {
        return ShaderFormat;
    }
};
