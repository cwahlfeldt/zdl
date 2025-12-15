const math = @import("../math/math.zig");
const Mat4 = math.Mat4;

/// MVP (Model-View-Projection) uniform data
/// Must follow std140 layout rules for GLSL compatibility
pub const MVPUniforms = extern struct {
    mvp: [16]f32, // Column-major 4x4 matrix

    pub fn init(mvp: Mat4) MVPUniforms {
        return .{ .mvp = mvp.data };
    }
};
