#include <metal_stdlib>
using namespace metal;

struct Vertex3DInput {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float4 color [[attribute(3)]];
};

struct Vertex3DOutput {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float4 color;
    float3 frag_pos;
};

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

vertex Vertex3DOutput vertex_3d_main(
    Vertex3DInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    Vertex3DOutput out;

    float4 world_pos = uniforms.model * float4(in.position, 1.0);
    out.frag_pos = world_pos.xyz;

    out.position = uniforms.projection * uniforms.view * world_pos;

    // Transform normal to world space
    out.normal = (uniforms.model * float4(in.normal, 0.0)).xyz;
    out.uv = in.uv;
    out.color = in.color;

    return out;
}

fragment float4 fragment_3d_main(
    Vertex3DOutput in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler samp [[sampler(0)]]
) {
    // Simple directional light
    float3 light_dir = normalize(float3(0.5, 1.0, 0.3));
    float3 normal = normalize(in.normal);

    // Ambient
    float ambient_strength = 0.3;
    float3 ambient = ambient_strength * float3(1.0, 1.0, 1.0);

    // Diffuse
    float diff = max(dot(normal, light_dir), 0.0);
    float3 diffuse = diff * float3(1.0, 1.0, 1.0);

    // Combine lighting with texture and vertex color
    float4 tex_color = tex.sample(samp, in.uv);
    float3 lighting = ambient + diffuse;

    return float4(lighting, 1.0) * tex_color * in.color;
}
