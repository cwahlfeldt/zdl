#include <metal_stdlib>
using namespace metal;

// Maximum bones supported
constant int MAX_BONES = 128;

struct SkinnedVertexInput {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float4 color [[attribute(3)]];
    uint4 joints [[attribute(4)]];   // Bone indices
    float4 weights [[attribute(5)]]; // Bone weights
};

struct VertexOutput {
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

struct BoneData {
    float4x4 bones[MAX_BONES];
};

vertex VertexOutput skinned_vertex_main(
    SkinnedVertexInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]],
    constant BoneData& bone_data [[buffer(1)]]
) {
    VertexOutput out;

    // Compute skinning matrix from bone influences
    float4x4 skin_matrix =
        bone_data.bones[in.joints.x] * in.weights.x +
        bone_data.bones[in.joints.y] * in.weights.y +
        bone_data.bones[in.joints.z] * in.weights.z +
        bone_data.bones[in.joints.w] * in.weights.w;

    // Apply skinning to position
    float4 skinned_pos = skin_matrix * float4(in.position, 1.0);

    // Apply model transform
    float4 world_pos = uniforms.model * skinned_pos;
    out.frag_pos = world_pos.xyz;

    out.position = uniforms.projection * uniforms.view * world_pos;

    // Transform normal through skinning and model matrices
    float3x3 skin_normal_matrix = float3x3(skin_matrix[0].xyz, skin_matrix[1].xyz, skin_matrix[2].xyz);
    float3x3 model_normal_matrix = float3x3(uniforms.model[0].xyz, uniforms.model[1].xyz, uniforms.model[2].xyz);
    out.normal = model_normal_matrix * skin_normal_matrix * in.normal;

    out.uv = in.uv;
    out.color = in.color;

    return out;
}

fragment float4 skinned_fragment_main(
    VertexOutput in [[stage_in]],
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
