const std = @import("std");
const math = @import("../math/math.zig");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

/// Model-View-Projection uniforms for 3D rendering
/// Must follow std140 layout rules for GLSL compatibility
pub const Uniforms = extern struct {
    model: [16]f32, // Column-major 4x4 matrix
    view: [16]f32,
    projection: [16]f32,

    pub fn init(model: Mat4, view: Mat4, projection: Mat4) Uniforms {
        return .{
            .model = model.data,
            .view = view.data,
            .projection = projection.data,
        };
    }

    /// Create uniforms with identity model matrix
    pub fn fromViewProjection(view: Mat4, projection: Mat4) Uniforms {
        return init(Mat4.identity(), view, projection);
    }
};

/// Maximum number of point lights supported per frame.
pub const MAX_POINT_LIGHTS = 16;

/// Maximum number of spot lights supported per frame.
pub const MAX_SPOT_LIGHTS = 8;

/// Light data for a single point light (GPU layout).
pub const PointLightData = extern struct {
    /// Position in world space (xyz) + range (w)
    position_range: [4]f32,
    /// Color (rgb) + intensity (a)
    color_intensity: [4]f32,

    pub fn init(position: Vec3, range: f32, color: Vec3, intensity: f32) PointLightData {
        return .{
            .position_range = .{ position.x, position.y, position.z, range },
            .color_intensity = .{ color.x, color.y, color.z, intensity },
        };
    }
};

/// Light data for a single spot light (GPU layout).
pub const SpotLightData = extern struct {
    /// Position in world space (xyz) + range (w)
    position_range: [4]f32,
    /// Direction (xyz) + outer cone cos (w)
    direction_outer: [4]f32,
    /// Color (rgb) + intensity (a)
    color_intensity: [4]f32,
    /// Inner cone cos (x), padding (yzw)
    inner_pad: [4]f32,

    pub fn init(position: Vec3, direction: Vec3, range: f32, color: Vec3, intensity: f32, inner_cos: f32, outer_cos: f32) SpotLightData {
        return .{
            .position_range = .{ position.x, position.y, position.z, range },
            .direction_outer = .{ direction.x, direction.y, direction.z, outer_cos },
            .color_intensity = .{ color.x, color.y, color.z, intensity },
            .inner_pad = .{ inner_cos, 0, 0, 0 },
        };
    }
};

/// Scene-wide lighting uniforms for PBR rendering.
/// This structure is pushed to the GPU each frame.
pub const LightUniforms = extern struct {
    // Directional light (sun) - 32 bytes
    /// Direction the light shines (normalized, world space)
    directional_direction: [4]f32, // xyz + padding
    /// Color (rgb) + intensity (a)
    directional_color_intensity: [4]f32,

    // Ambient/environment - 16 bytes
    /// Ambient color (rgb) + intensity (a)
    ambient_color_intensity: [4]f32,

    // Camera info for specular - 16 bytes
    /// Camera position in world space (xyz) + padding
    camera_position: [4]f32,

    // IBL parameters - 16 bytes
    /// Environment map intensity multiplier (x), max reflection LOD (y), use IBL flag (z), padding (w)
    ibl_params: [4]f32,

    // Light counts - 16 bytes
    /// Number of active point lights
    point_light_count: u32,
    /// Number of active spot lights
    spot_light_count: u32,
    _pad: [2]u32 = .{ 0, 0 },

    // Point lights array - 16 * 2 * MAX_POINT_LIGHTS bytes
    point_lights: [MAX_POINT_LIGHTS]PointLightData,

    // Spot lights array - 16 * 4 * MAX_SPOT_LIGHTS bytes
    spot_lights: [MAX_SPOT_LIGHTS]SpotLightData,

    /// Create default lighting (single white directional + ambient).
    pub fn default() LightUniforms {
        var uniforms = LightUniforms{
            .directional_direction = .{ 0.5, 1.0, 0.3, 0.0 },
            .directional_color_intensity = .{ 1.0, 1.0, 1.0, 1.0 },
            .ambient_color_intensity = .{ 0.1, 0.1, 0.15, 1.0 },
            .camera_position = .{ 0, 0, 5, 0 },
            .ibl_params = .{ 1.0, 4.0, 0.0, 0.0 }, // intensity=1.0, max_lod=4.0, use_ibl=0, pad=0
            .point_light_count = 0,
            .spot_light_count = 0,
            .point_lights = undefined,
            .spot_lights = undefined,
        };
        // Zero initialize the light arrays
        @memset(&uniforms.point_lights, std.mem.zeroes(PointLightData));
        @memset(&uniforms.spot_lights, std.mem.zeroes(SpotLightData));
        return uniforms;
    }

    /// Set the directional light.
    pub fn setDirectionalLight(self: *LightUniforms, direction: Vec3, color: Vec3, intensity: f32) void {
        const normalized = direction.normalize();
        self.directional_direction = .{ normalized.x, normalized.y, normalized.z, 0 };
        self.directional_color_intensity = .{ color.x, color.y, color.z, intensity };
    }

    /// Set the ambient light.
    pub fn setAmbient(self: *LightUniforms, color: Vec3, intensity: f32) void {
        self.ambient_color_intensity = .{ color.x, color.y, color.z, intensity };
    }

    /// Set the camera position (for specular calculations).
    pub fn setCameraPosition(self: *LightUniforms, position: Vec3) void {
        self.camera_position = .{ position.x, position.y, position.z, 0 };
    }

    /// Add a point light. Returns false if MAX_POINT_LIGHTS reached.
    pub fn addPointLight(self: *LightUniforms, position: Vec3, range: f32, color: Vec3, intensity: f32) bool {
        if (self.point_light_count >= MAX_POINT_LIGHTS) return false;
        self.point_lights[self.point_light_count] = PointLightData.init(position, range, color, intensity);
        self.point_light_count += 1;
        return true;
    }

    /// Add a spot light. Returns false if MAX_SPOT_LIGHTS reached.
    pub fn addSpotLight(self: *LightUniforms, position: Vec3, direction: Vec3, range: f32, color: Vec3, intensity: f32, inner_angle: f32, outer_angle: f32) bool {
        if (self.spot_light_count >= MAX_SPOT_LIGHTS) return false;
        const inner_cos = @cos(inner_angle);
        const outer_cos = @cos(outer_angle);
        self.spot_lights[self.spot_light_count] = SpotLightData.init(position, direction.normalize(), range, color, intensity, inner_cos, outer_cos);
        self.spot_light_count += 1;
        return true;
    }

    /// Clear all dynamic lights (keeps directional and ambient).
    pub fn clearDynamicLights(self: *LightUniforms) void {
        self.point_light_count = 0;
        self.spot_light_count = 0;
    }

    /// Enable or disable IBL rendering.
    pub fn setIBLEnabled(self: *LightUniforms, enabled: bool) void {
        self.ibl_params[2] = if (enabled) 1.0 else 0.0;
    }

    /// Set IBL environment intensity and max reflection LOD.
    pub fn setIBLParams(self: *LightUniforms, intensity: f32, max_lod: f32) void {
        self.ibl_params[0] = intensity;
        self.ibl_params[1] = max_lod;
    }
};

// Compile-time size verification for GPU alignment
comptime {
    // LightUniforms header: 96 bytes (6 * 16) - added IBL params
    // Point lights: MAX_POINT_LIGHTS * 32 bytes
    // Spot lights: MAX_SPOT_LIGHTS * 64 bytes
    const expected_size = 96 + (MAX_POINT_LIGHTS * 32) + (MAX_SPOT_LIGHTS * 64);
    std.debug.assert(@sizeOf(LightUniforms) == expected_size);
}
