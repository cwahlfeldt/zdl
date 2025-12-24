const math = @import("../math/math.zig");
const Mat4 = math.Mat4;

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
