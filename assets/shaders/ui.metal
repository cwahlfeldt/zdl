#include <metal_stdlib>
using namespace metal;

struct UIVertexInput {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct UIVertexOutput {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

struct UIUniforms {
    float4x4 projection;
};

vertex UIVertexOutput ui_vertex_main(
    UIVertexInput in [[stage_in]],
    constant UIUniforms& uniforms [[buffer(0)]]
) {
    UIVertexOutput out;
    out.position = uniforms.projection * float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    out.color = in.color;
    return out;
}

fragment float4 ui_fragment_main(
    UIVertexOutput in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float4 tex_color = tex.sample(smp, in.uv);
    return tex_color * in.color;
}
