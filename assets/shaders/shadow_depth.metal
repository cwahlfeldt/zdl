//
// Shadow Depth Shader - Metal
// Renders depth-only pass for cascaded shadow mapping
//

#include <metal_stdlib>
using namespace metal;

// Vertex input (matches Vertex3D)
struct VertexIn {
    float3 position [[attribute(0)]];
};

// Vertex output
struct VertexOut {
    float4 position [[position]];
};

// Uniforms
struct ShadowUniforms {
    float4x4 light_view_proj;
    float4x4 model;
};

// Vertex shader - transform to light space
vertex VertexOut shadow_depth_vertex_main(
    VertexIn in [[stage_in]],
    constant ShadowUniforms& uniforms [[buffer(0)]]
) {
    VertexOut out;
    float4 world_pos = uniforms.model * float4(in.position, 1.0);
    out.position = uniforms.light_view_proj * world_pos;
    return out;
}

// Fragment shader - depth write only (no color output)
fragment void shadow_depth_fragment_main() {
    // Depth is written automatically, no output needed
}
