const std = @import("std");
const sdl = @import("sdl3");
const Mesh = @import("../../resources/mesh.zig").Mesh;
const Texture = @import("../../resources/texture.zig").Texture;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Vec4 = @import("../../math/vec4.zig").Vec4;
const Quat = @import("../../math/quat.zig").Quat;
const Mat4 = @import("../../math/mat4.zig").Mat4;

/// Errors that can occur during glTF loading
pub const GLTFError = error{
    // File format errors
    InvalidMagic,
    UnsupportedVersion,
    InvalidJSON,
    MissingRequiredProperty,
    InvalidChunkType,

    // Buffer errors
    BufferOutOfBounds,
    InvalidBufferView,
    AccessorOutOfBounds,
    InvalidAccessor,

    // Mesh errors
    MissingPositionAttribute,
    UnsupportedPrimitiveMode,
    InvalidMeshData,

    // Texture errors
    InvalidImageSource,
    UnsupportedImageFormat,

    // General
    FileNotFound,
    InvalidPath,
};

/// Key for mapping glTF mesh primitives to ZDL meshes
pub const MeshPrimitiveKey = struct {
    mesh_index: usize,
    primitive_index: usize,
};

/// Component type in glTF accessor (maps to GL types)
pub const ComponentType = enum(u32) {
    byte = 5120,
    unsigned_byte = 5121,
    short = 5122,
    unsigned_short = 5123,
    unsigned_int = 5125,
    float = 5126,

    pub fn byteSize(self: ComponentType) usize {
        return switch (self) {
            .byte, .unsigned_byte => 1,
            .short, .unsigned_short => 2,
            .unsigned_int, .float => 4,
        };
    }
};

/// Element type in glTF accessor
pub const ElementType = enum {
    SCALAR,
    VEC2,
    VEC3,
    VEC4,
    MAT2,
    MAT3,
    MAT4,

    pub fn componentCount(self: ElementType) usize {
        return switch (self) {
            .SCALAR => 1,
            .VEC2 => 2,
            .VEC3 => 3,
            .VEC4 => 4,
            .MAT2 => 4,
            .MAT3 => 9,
            .MAT4 => 16,
        };
    }

    pub fn fromString(str: []const u8) ?ElementType {
        const map = std.StaticStringMap(ElementType).initComptime(.{
            .{ "SCALAR", .SCALAR },
            .{ "VEC2", .VEC2 },
            .{ "VEC3", .VEC3 },
            .{ "VEC4", .VEC4 },
            .{ "MAT2", .MAT2 },
            .{ "MAT3", .MAT3 },
            .{ "MAT4", .MAT4 },
        });
        return map.get(str);
    }
};

/// Primitive rendering mode
pub const PrimitiveMode = enum(u32) {
    points = 0,
    lines = 1,
    line_loop = 2,
    line_strip = 3,
    triangles = 4,
    triangle_strip = 5,
    triangle_fan = 6,
};

/// Buffer view target hint
pub const BufferTarget = enum(u32) {
    array_buffer = 34962,
    element_array_buffer = 34963,
};

/// Parsed buffer view data
pub const BufferViewData = struct {
    buffer: usize,
    byte_offset: usize,
    byte_length: usize,
    byte_stride: ?usize,
    target: ?BufferTarget,
};

/// Parsed accessor data
pub const AccessorData = struct {
    buffer_view: ?usize,
    byte_offset: usize,
    component_type: ComponentType,
    normalized: bool,
    count: usize,
    element_type: ElementType,
    min: ?[]f32,
    max: ?[]f32,
};

/// Parsed glTF node
pub const NodeData = struct {
    name: ?[]const u8,
    children: []usize,
    mesh_index: ?usize,
    camera_index: ?usize,
    skin_index: ?usize,

    // Transform - either matrix or TRS
    matrix: ?[16]f32,
    translation: ?[3]f32,
    rotation: ?[4]f32, // xyzw quaternion
    scale: ?[3]f32,

    /// Get local transform as components
    pub fn getTransform(self: NodeData) struct { position: Vec3, rotation: Quat, scale: Vec3 } {
        if (self.matrix) |m| {
            // Decompose matrix (simplified - assumes no shear)
            const sx = Vec3.init(m[0], m[1], m[2]).length();
            const sy = Vec3.init(m[4], m[5], m[6]).length();
            const sz = Vec3.init(m[8], m[9], m[10]).length();

            return .{
                .position = Vec3.init(m[12], m[13], m[14]),
                .rotation = Quat.identity(), // TODO: extract rotation from matrix
                .scale = Vec3.init(sx, sy, sz),
            };
        }

        return .{
            .position = if (self.translation) |t| Vec3.init(t[0], t[1], t[2]) else Vec3.zero(),
            .rotation = if (self.rotation) |r| Quat.init(r[0], r[1], r[2], r[3]) else Quat.identity(),
            .scale = if (self.scale) |s| Vec3.init(s[0], s[1], s[2]) else Vec3.init(1, 1, 1),
        };
    }
};

/// Parsed glTF scene
pub const SceneData = struct {
    name: ?[]const u8,
    nodes: []usize, // Root node indices
};

/// Parsed primitive data (subset of mesh)
pub const PrimitiveData = struct {
    attributes: struct {
        position: ?usize, // Accessor index
        normal: ?usize,
        tangent: ?usize,
        texcoord_0: ?usize,
        texcoord_1: ?usize,
        color_0: ?usize,
        joints_0: ?usize,
        weights_0: ?usize,
    },
    indices: ?usize, // Accessor index
    material: ?usize,
    mode: PrimitiveMode,
};

/// Parsed mesh data
pub const MeshData = struct {
    name: ?[]const u8,
    primitives: []PrimitiveData,
};

/// Parsed material data (PBR metallic-roughness)
pub const MaterialData = struct {
    name: ?[]const u8,

    // PBR base
    base_color_factor: [4]f32,
    base_color_texture: ?TextureInfo,
    metallic_factor: f32,
    roughness_factor: f32,
    metallic_roughness_texture: ?TextureInfo,

    // Common maps
    normal_texture: ?TextureInfo,
    normal_scale: f32,
    occlusion_texture: ?TextureInfo,
    occlusion_strength: f32,
    emissive_factor: [3]f32,
    emissive_texture: ?TextureInfo,

    // Alpha
    alpha_mode: AlphaMode,
    alpha_cutoff: f32,

    // Rendering
    double_sided: bool,

    pub fn default() MaterialData {
        return .{
            .name = null,
            .base_color_factor = .{ 1, 1, 1, 1 },
            .base_color_texture = null,
            .metallic_factor = 1,
            .roughness_factor = 1,
            .metallic_roughness_texture = null,
            .normal_texture = null,
            .normal_scale = 1,
            .occlusion_texture = null,
            .occlusion_strength = 1,
            .emissive_factor = .{ 0, 0, 0 },
            .emissive_texture = null,
            .alpha_mode = .@"opaque",
            .alpha_cutoff = 0.5,
            .double_sided = false,
        };
    }
};

pub const AlphaMode = enum {
    @"opaque",
    mask,
    blend,
};

pub const TextureInfo = struct {
    index: usize, // Texture index
    tex_coord: u32, // Which UV set (0 or 1)
};

/// Parsed texture reference
pub const TextureData = struct {
    sampler: ?usize,
    source: ?usize, // Image index
};

/// Parsed image data
pub const ImageData = struct {
    name: ?[]const u8,
    uri: ?[]const u8,
    buffer_view: ?usize, // For embedded images
    mime_type: ?[]const u8,
};

/// Parsed sampler data
pub const SamplerData = struct {
    mag_filter: ?u32,
    min_filter: ?u32,
    wrap_s: u32,
    wrap_t: u32,

    pub fn default() SamplerData {
        return .{
            .mag_filter = null,
            .min_filter = null,
            .wrap_s = 10497, // REPEAT
            .wrap_t = 10497,
        };
    }
};

/// Parsed camera data
pub const CameraData = struct {
    name: ?[]const u8,
    camera_type: CameraType,

    // Perspective params
    aspect_ratio: ?f32,
    yfov: f32,
    znear: f32,
    zfar: ?f32,

    // Orthographic params
    xmag: f32,
    ymag: f32,
};

pub const CameraType = enum {
    perspective,
    orthographic,
};

/// Container for a loaded glTF asset
pub const GLTFAsset = struct {
    allocator: std.mem.Allocator,

    /// Source path for naming/caching
    source_path: []const u8,

    /// Base directory for resolving relative URIs
    base_path: []const u8,

    /// Loaded binary buffers
    buffers: [][]const u8,
    owns_buffers: []bool, // Track which buffers we allocated

    /// Parsed data
    buffer_views: []BufferViewData,
    accessors: []AccessorData,
    meshes: []MeshData,
    materials: []MaterialData,
    textures: []TextureData,
    images: []ImageData,
    samplers: []SamplerData,
    nodes: []NodeData,
    scenes: []SceneData,
    cameras: []CameraData,
    default_scene: ?usize,

    /// Converted GPU resources
    gpu_meshes: std.ArrayListUnmanaged(*Mesh),
    gpu_textures: std.ArrayListUnmanaged(*Texture),

    /// Maps glTF indices to GPU resource indices
    mesh_map: std.AutoHashMap(MeshPrimitiveKey, usize),
    texture_map: std.AutoHashMap(usize, usize),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .source_path = "",
            .base_path = "",
            .buffers = &.{},
            .owns_buffers = &.{},
            .buffer_views = &.{},
            .accessors = &.{},
            .meshes = &.{},
            .materials = &.{},
            .textures = &.{},
            .images = &.{},
            .samplers = &.{},
            .nodes = &.{},
            .scenes = &.{},
            .cameras = &.{},
            .default_scene = null,
            .gpu_meshes = .{},
            .gpu_textures = .{},
            .mesh_map = std.AutoHashMap(MeshPrimitiveKey, usize).init(allocator),
            .texture_map = std.AutoHashMap(usize, usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self, device: ?*sdl.gpu.Device) void {
        // Free GPU resources
        for (self.gpu_meshes.items) |mesh| {
            mesh.deinit(device);
            self.allocator.destroy(mesh);
        }
        self.gpu_meshes.deinit(self.allocator);

        for (self.gpu_textures.items) |texture| {
            if (device) |dev| {
                texture.deinit(dev);
            }
            self.allocator.destroy(texture);
        }
        self.gpu_textures.deinit(self.allocator);

        self.mesh_map.deinit();
        self.texture_map.deinit();

        // Free owned buffers
        for (self.buffers, 0..) |buffer, i| {
            if (self.owns_buffers[i]) {
                self.allocator.free(buffer);
            }
        }
        if (self.buffers.len > 0) {
            self.allocator.free(self.buffers);
            self.allocator.free(self.owns_buffers);
        }

        // Free parsed data arrays
        for (self.nodes) |node| {
            if (node.children.len > 0) self.allocator.free(node.children);
        }
        if (self.nodes.len > 0) self.allocator.free(self.nodes);

        for (self.scenes) |scene| {
            if (scene.nodes.len > 0) self.allocator.free(scene.nodes);
        }
        if (self.scenes.len > 0) self.allocator.free(self.scenes);

        for (self.meshes) |mesh| {
            if (mesh.primitives.len > 0) self.allocator.free(mesh.primitives);
        }
        if (self.meshes.len > 0) self.allocator.free(self.meshes);

        if (self.buffer_views.len > 0) self.allocator.free(self.buffer_views);
        if (self.accessors.len > 0) self.allocator.free(self.accessors);
        if (self.materials.len > 0) self.allocator.free(self.materials);
        if (self.textures.len > 0) self.allocator.free(self.textures);
        if (self.images.len > 0) self.allocator.free(self.images);
        if (self.samplers.len > 0) self.allocator.free(self.samplers);
        if (self.cameras.len > 0) self.allocator.free(self.cameras);

        if (self.source_path.len > 0) self.allocator.free(self.source_path);
        if (self.base_path.len > 0) self.allocator.free(self.base_path);
    }

    /// Get mesh name for caching/serialization
    pub fn getMeshName(self: *const Self, mesh_index: usize, primitive_index: usize) ![]const u8 {
        // Format: "{source_path}:mesh:{mesh_index}:{primitive_index}"
        return std.fmt.allocPrint(self.allocator, "{s}:mesh:{d}:{d}", .{
            self.source_path,
            mesh_index,
            primitive_index,
        });
    }

    /// Get texture name for caching/serialization
    pub fn getTextureName(self: *const Self, texture_index: usize) ![]const u8 {
        // Format: "{source_path}:texture:{texture_index}"
        return std.fmt.allocPrint(self.allocator, "{s}:texture:{d}", .{
            self.source_path,
            texture_index,
        });
    }
};
