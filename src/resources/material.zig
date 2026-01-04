const std = @import("std");
const math = @import("../math/math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Texture = @import("texture.zig").Texture;

/// PBR Material properties following the metallic-roughness workflow.
/// Based on glTF 2.0 PBR material model.
pub const Material = struct {
    /// Base color factor (RGBA). Multiplied with base_color_texture if present.
    base_color: Vec4 = Vec4.init(1.0, 1.0, 1.0, 1.0),

    /// Metallic factor (0.0 = dielectric, 1.0 = metal).
    metallic: f32 = 0.0,

    /// Roughness factor (0.0 = smooth/glossy, 1.0 = rough/diffuse).
    roughness: f32 = 0.5,

    /// Emissive color (RGB). Added to final color after lighting.
    emissive: Vec3 = Vec3.zero(),

    /// Normal map scale. Controls the strength of normal mapping.
    normal_scale: f32 = 1.0,

    /// Ambient occlusion strength (0.0 = no AO, 1.0 = full AO).
    ao_strength: f32 = 1.0,

    /// Alpha cutoff for alpha testing. Fragments with alpha below this are discarded.
    alpha_cutoff: f32 = 0.5,

    /// UV coordinate scale for texture tiling.
    uv_scale: Vec2 = Vec2.init(1.0, 1.0),

    /// UV coordinate offset.
    uv_offset: Vec2 = Vec2.zero(),

    // Texture references (optional)

    /// Base color / albedo texture (sRGB).
    base_color_texture: ?*const Texture = null,

    /// Normal map texture (linear, tangent space).
    normal_texture: ?*const Texture = null,

    /// Metallic-roughness texture (linear).
    /// Blue channel = metallic, Green channel = roughness (glTF convention).
    metallic_roughness_texture: ?*const Texture = null,

    /// Ambient occlusion texture (linear, R channel).
    ao_texture: ?*const Texture = null,

    /// Emissive texture (sRGB).
    emissive_texture: ?*const Texture = null,

    // Render state

    /// Alpha blending mode.
    alpha_mode: AlphaMode = .@"opaque",

    /// Enable double-sided rendering (disables backface culling).
    double_sided: bool = false,

    /// Create a default PBR material (white, non-metallic, medium roughness).
    pub fn init() Material {
        return .{};
    }

    /// Create a material with a base color.
    pub fn withColor(r: f32, g: f32, b: f32) Material {
        return .{
            .base_color = Vec4.init(r, g, b, 1.0),
        };
    }

    /// Create a material with a base color and alpha.
    pub fn withColorAlpha(r: f32, g: f32, b: f32, a: f32) Material {
        return .{
            .base_color = Vec4.init(r, g, b, a),
            .alpha_mode = if (a < 1.0) .blend else .@"opaque",
        };
    }

    /// Create a metallic material (shiny metal appearance).
    pub fn metal(r: f32, g: f32, b: f32, roughness_value: f32) Material {
        return .{
            .base_color = Vec4.init(r, g, b, 1.0),
            .metallic = 1.0,
            .roughness = roughness_value,
        };
    }

    /// Create a dielectric material (plastic, wood, etc.).
    pub fn dielectric(r: f32, g: f32, b: f32, roughness_value: f32) Material {
        return .{
            .base_color = Vec4.init(r, g, b, 1.0),
            .metallic = 0.0,
            .roughness = roughness_value,
        };
    }

    /// Create an emissive material (glowing effect).
    pub fn withEmissive(r: f32, g: f32, b: f32, emission_r: f32, emission_g: f32, emission_b: f32) Material {
        return .{
            .base_color = Vec4.init(r, g, b, 1.0),
            .emissive = Vec3.init(emission_r, emission_g, emission_b),
        };
    }

    /// Set the base color texture.
    pub fn setBaseColorTexture(self: *Material, texture: *const Texture) void {
        self.base_color_texture = texture;
    }

    /// Set the normal map texture.
    pub fn setNormalTexture(self: *Material, texture: *const Texture) void {
        self.normal_texture = texture;
    }

    /// Set the metallic-roughness texture.
    pub fn setMetallicRoughnessTexture(self: *Material, texture: *const Texture) void {
        self.metallic_roughness_texture = texture;
    }

    /// Set the ambient occlusion texture.
    pub fn setAoTexture(self: *Material, texture: *const Texture) void {
        self.ao_texture = texture;
    }

    /// Set the emissive texture.
    pub fn setEmissiveTexture(self: *Material, texture: *const Texture) void {
        self.emissive_texture = texture;
    }

    /// Check if this material has any textures.
    pub fn hasTextures(self: Material) bool {
        return self.base_color_texture != null or
            self.normal_texture != null or
            self.metallic_roughness_texture != null or
            self.ao_texture != null or
            self.emissive_texture != null;
    }

    /// Check if this material uses alpha blending.
    pub fn isTransparent(self: Material) bool {
        return self.alpha_mode == .blend;
    }

    /// Check if this material uses alpha testing.
    pub fn usesMasking(self: Material) bool {
        return self.alpha_mode == .mask;
    }
};

/// Alpha blending mode for materials.
pub const AlphaMode = enum {
    /// Fully opaque, alpha is ignored.
    @"opaque",
    /// Alpha testing with cutoff threshold.
    mask,
    /// Alpha blending (semi-transparent).
    blend,
};

/// GPU-compatible material uniforms (std140 layout).
/// This structure is uploaded to the GPU for shader access.
///
/// std140 layout rules:
/// - vec4/mat4 are 16-byte aligned
/// - vec3 is 16-byte aligned (takes 16 bytes with padding)
/// - vec2 is 8-byte aligned
/// - float/int is 4-byte aligned
/// - Arrays have elements aligned to 16 bytes
pub const MaterialUniforms = extern struct {
    // Block 0: Base color (16 bytes, offset 0)
    base_color: [4]f32,

    // Block 1: Metallic, roughness, normal scale, ao strength (16 bytes, offset 16)
    metallic: f32,
    roughness: f32,
    normal_scale: f32,
    ao_strength: f32,

    // Block 2: Emissive RGB + alpha cutoff (16 bytes, offset 32)
    // In std140, vec3 followed by float packs into 16 bytes
    emissive: [3]f32,
    alpha_cutoff: f32,

    // Block 3: UV scale and offset (16 bytes, offset 48)
    uv_scale: [2]f32,
    uv_offset: [2]f32,

    // Block 4: Texture flags (16 bytes, offset 64)
    has_base_color_texture: u32,
    has_normal_texture: u32,
    has_metallic_roughness_texture: u32,
    has_ao_texture: u32,

    // Block 5: Additional flags (16 bytes, offset 80)
    has_emissive_texture: u32,
    alpha_mode: u32, // 0 = opaque, 1 = mask, 2 = blend
    _pad: [2]u32 = .{ 0, 0 },

    /// Create GPU uniforms from a Material.
    pub fn fromMaterial(mat: Material) MaterialUniforms {
        return .{
            .base_color = .{ mat.base_color.x, mat.base_color.y, mat.base_color.z, mat.base_color.w },
            .metallic = mat.metallic,
            .roughness = mat.roughness,
            .normal_scale = mat.normal_scale,
            .ao_strength = mat.ao_strength,
            .emissive = .{ mat.emissive.x, mat.emissive.y, mat.emissive.z },
            .alpha_cutoff = mat.alpha_cutoff,
            .uv_scale = .{ mat.uv_scale.x, mat.uv_scale.y },
            .uv_offset = .{ mat.uv_offset.x, mat.uv_offset.y },
            .has_base_color_texture = if (mat.base_color_texture != null) 1 else 0,
            .has_normal_texture = if (mat.normal_texture != null) 1 else 0,
            .has_metallic_roughness_texture = if (mat.metallic_roughness_texture != null) 1 else 0,
            .has_ao_texture = if (mat.ao_texture != null) 1 else 0,
            .has_emissive_texture = if (mat.emissive_texture != null) 1 else 0,
            .alpha_mode = @intFromEnum(mat.alpha_mode),
        };
    }
};

// Compile-time size verification
comptime {
    // MaterialUniforms should be 96 bytes (6 * 16 for std140 alignment)
    std.debug.assert(@sizeOf(MaterialUniforms) == 96);
}

test "Material defaults" {
    const mat = Material.init();
    try std.testing.expectEqual(@as(f32, 1.0), mat.base_color.x);
    try std.testing.expectEqual(@as(f32, 0.0), mat.metallic);
    try std.testing.expectEqual(@as(f32, 0.5), mat.roughness);
    try std.testing.expect(!mat.hasTextures());
}

test "MaterialUniforms size" {
    try std.testing.expectEqual(@as(usize, 96), @sizeOf(MaterialUniforms));
}
