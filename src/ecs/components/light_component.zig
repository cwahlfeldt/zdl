const math = @import("../../math/math.zig");
const Vec3 = math.Vec3;

/// Type of light source.
pub const LightType = enum {
    directional,
    point,
    spot,
};

/// Light component for scene illumination.
/// Light direction/position is derived from the entity's TransformComponent.
pub const LightComponent = struct {
    /// Type of light
    light_type: LightType,
    /// Light color (RGB, 0-1 range)
    color: Vec3,
    /// Light intensity multiplier
    intensity: f32,
    /// Range for point/spot lights (ignored for directional)
    range: f32,
    /// Inner cone angle for spot lights in radians
    inner_angle: f32,
    /// Outer cone angle for spot lights in radians
    outer_angle: f32,

    /// Create a directional light (like the sun).
    pub fn directional(color: Vec3, intensity: f32) LightComponent {
        return .{
            .light_type = .directional,
            .color = color,
            .intensity = intensity,
            .range = 0,
            .inner_angle = 0,
            .outer_angle = 0,
        };
    }

    /// Create a point light (omni-directional).
    pub fn point(color: Vec3, intensity: f32, range: f32) LightComponent {
        return .{
            .light_type = .point,
            .color = color,
            .intensity = intensity,
            .range = range,
            .inner_angle = 0,
            .outer_angle = 0,
        };
    }

    /// Create a spot light (cone-shaped).
    pub fn spot(color: Vec3, intensity: f32, range: f32, inner_angle: f32, outer_angle: f32) LightComponent {
        return .{
            .light_type = .spot,
            .color = color,
            .intensity = intensity,
            .range = range,
            .inner_angle = inner_angle,
            .outer_angle = outer_angle,
        };
    }

    /// Create a white directional light with default intensity.
    pub fn defaultDirectional() LightComponent {
        return directional(Vec3.init(1, 1, 1), 1.0);
    }

    /// Create a white point light with default settings.
    pub fn defaultPoint() LightComponent {
        return point(Vec3.init(1, 1, 1), 1.0, 10.0);
    }
};
