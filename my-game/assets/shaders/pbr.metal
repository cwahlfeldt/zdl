#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

struct MaterialUniforms {
    float4 baseColor;
    float metallic;
    float roughness;
    float3 emissive;
};

struct LightUniforms {
    float4 lightPositions[8];
    float4 lightColors[8];
    float4 lightParams[8];
    int lightCount;
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

vertex VertexOut pbr_vertex_main(
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

fragment float4 pbr_fragment_main(
    VertexOut in [[stage_in]],
    constant MaterialUniforms& material [[buffer(1)]],
    constant LightUniforms& lights [[buffer(2)]]
) {
    float3 normal = normalize(in.normal);
    float3 viewPos = float3(0.0, 0.0, 5.0); // Simple camera position
    float3 viewDir = normalize(viewPos - in.worldPos);

    // Simple PBR approximation
    float3 albedo = material.baseColor.rgb * in.color.rgb;
    float roughness = material.roughness;
    float metallic = material.metallic;

    float3 finalColor = float3(0.0);

    // Ambient
    finalColor += albedo * 0.1;

    // Simple directional light
    for (int i = 0; i < lights.lightCount && i < 8; i++) {
        float3 lightDir;
        float attenuation = 1.0;

        // Check light type (w component: 0 = directional, 1 = point/spot)
        if (lights.lightPositions[i].w < 0.5) {
            // Directional light
            lightDir = normalize(lights.lightPositions[i].xyz);
        } else {
            // Point light
            float3 toLight = lights.lightPositions[i].xyz - in.worldPos;
            float distance = length(toLight);
            lightDir = normalize(toLight);
            float range = lights.lightParams[i].x;
            attenuation = 1.0 - smoothstep(0.0, range, distance);
        }

        float NdotL = max(dot(normal, lightDir), 0.0);
        float3 lightColor = lights.lightColors[i].rgb * lights.lightColors[i].a;

        finalColor += albedo * lightColor * NdotL * attenuation;
    }

    // Add emissive
    finalColor += material.emissive;

    return float4(finalColor, material.baseColor.a * in.color.a);
}
