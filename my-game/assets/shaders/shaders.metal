#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float4 color [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float4 color;
    float3 worldPos;
};

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    VertexOut out;

    float4 worldPos = uniforms.model * float4(in.position, 1.0);
    out.worldPos = worldPos.xyz;
    out.position = uniforms.projection * uniforms.view * worldPos;
    out.normal = (uniforms.model * float4(in.normal, 0.0)).xyz;
    out.uv = in.uv;
    out.color = in.color;

    return out;
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]]
) {
    // Simple diffuse lighting
    float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
    float3 normal = normalize(in.normal);
    float diffuse = max(dot(normal, lightDir), 0.2); // Ambient + diffuse

    float3 color = in.color.rgb * diffuse;
    return float4(color, in.color.a);
}
