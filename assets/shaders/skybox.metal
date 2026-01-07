#include <metal_stdlib>
using namespace metal;

struct Vertex3DInput {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float4 color [[attribute(3)]];
};

struct VertexSkyboxOutput {
    float4 position [[position]];
    float3 dir;
};

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

vertex VertexSkyboxOutput skybox_vertex_main(
    Vertex3DInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    VertexSkyboxOutput out;

    float4x4 view = uniforms.view;
    view[3].xyz = float3(0.0);

    float4 pos = uniforms.projection * view * float4(in.position, 1.0);
    out.position = float4(pos.xy, pos.w, pos.w);
    out.dir = in.position;

    return out;
}

fragment float4 skybox_fragment_main(
    VertexSkyboxOutput in [[stage_in]],
    texturecube<float> skybox_tex [[texture(0)]],
    sampler samp [[sampler(0)]]
) {
    float3 color = skybox_tex.sample(samp, normalize(in.dir)).rgb;

    // ACES filmic tonemapping
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    color = clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);

    // Gamma correction
    color = pow(color, float3(1.0 / 2.2));

    return float4(color, 1.0);
}
