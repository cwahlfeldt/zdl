#include <metal_stdlib>
using namespace metal;

struct LineVertexInput {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct LineVertexOutput {
    float4 position [[position]];
    float4 color;
};

struct DebugUniforms {
    float4x4 view_projection;
};

vertex LineVertexOutput debug_vertex_main(
    LineVertexInput in [[stage_in]],
    constant DebugUniforms& uniforms [[buffer(0)]]
) {
    LineVertexOutput out;
    out.position = uniforms.view_projection * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 debug_fragment_main(LineVertexOutput in [[stage_in]]) {
    return in.color;
}
