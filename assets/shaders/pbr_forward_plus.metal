#include <metal_stdlib>
using namespace metal;

// Forward+ PBR Shader (Metal version)

constant float PI = 3.14159265359;

// ============================================================================
// Data Structures
// ============================================================================

struct Vertex3DInput {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float4 color [[attribute(3)]];
};

struct Vertex3DOutput {
    float4 position [[position]];
    float3 world_pos;
    float3 normal;
    float2 uv;
    float4 color;
};

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

struct MaterialUniforms {
    float4 base_color;
    float4 mrna;           // x=metallic, y=roughness, z=normal_scale, w=ao_strength
    float4 emissive_alpha; // rgb=emissive, a=alpha_cutoff
    float4 uv_transform;   // xy=uv_scale, zw=uv_offset
    uint4 texture_flags;   // x=base, y=normal, z=mr, w=ao
    uint4 extra_flags;     // x=emissive, y=alpha_mode, zw=pad
};

struct PointLight {
    float4 position_range;    // xyz=position, w=range
    float4 color_intensity;   // rgb=color, a=intensity
};

struct SpotLight {
    float4 position_range;    // xyz=position, w=range
    float4 direction_outer;   // xyz=direction, w=outer_cos
    float4 color_intensity;   // rgb=color, a=intensity
    float4 inner_pad;         // x=inner_cos
};

struct LightGrid {
    uint offset;
    uint count;
};

struct ForwardPlusUniforms {
    float4 directional_direction;
    float4 directional_color_intensity;
    float4 ambient_color_intensity;
    float4 camera_position;
    float4 ibl_params;            // x=env_intensity, y=max_lod, z=use_ibl, w=spec_intensity

    float screen_width;
    float screen_height;
    uint cluster_count_x;
    uint cluster_count_y;

    uint cluster_count_z;
    float near_plane;
    float far_plane;
    float log_depth_scale;

    float4x4 view_matrix;
};

// ============================================================================
// Vertex Shader
// ============================================================================

vertex Vertex3DOutput pbr_forward_plus_vertex_main(
    Vertex3DInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    Vertex3DOutput out;

    float4 world_pos = uniforms.model * float4(in.position, 1.0);
    out.world_pos = world_pos.xyz;
    out.position = uniforms.projection * uniforms.view * world_pos;

    float3x3 normal_matrix = transpose(float3x3(
        uniforms.model[0].xyz,
        uniforms.model[1].xyz,
        uniforms.model[2].xyz
    ));
    out.normal = normalize(normal_matrix * in.normal);

    out.uv = in.uv;
    out.color = in.color;

    return out;
}

// ============================================================================
// PBR Functions
// ============================================================================

float3 fresnelSchlick(float cos_theta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

float3 fresnelSchlickRoughness(float cos_theta, float3 F0, float roughness) {
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

float distributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float geometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float geometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = geometrySchlickGGX(NdotV, roughness);
    float ggx1 = geometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

float3 calculatePBRLight(float3 L, float3 radiance, float3 N, float3 V, float3 albedo, float metallic, float roughness, float3 F0) {
    float3 H = normalize(V + L);

    float NDF = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    float3 F = fresnelSchlick(max(dot(H, L), 0.0), F0);

    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    float3 kS = F;
    float3 kD = float3(1.0) - kS;
    kD *= 1.0 - metallic;

    float NdotL = max(dot(N, L), 0.0);
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

float calculateAttenuation(float distance, float range) {
    float attenuation = clamp(1.0 - pow(distance / range, 4.0), 0.0, 1.0);
    return attenuation * attenuation / (distance * distance + 1.0);
}

// ============================================================================
// Cluster Functions
// ============================================================================

uint getClusterIndex(float3 frag_pos, float4 frag_coord, constant ForwardPlusUniforms& fp) {
    float4 view_pos = fp.view_matrix * float4(frag_pos, 1.0);
    float view_z = -view_pos.z;

    float2 screen_pos = frag_coord.xy;

    uint tile_x = uint(screen_pos.x / (fp.screen_width / float(fp.cluster_count_x)));
    uint tile_y = uint(screen_pos.y / (fp.screen_height / float(fp.cluster_count_y)));

    float z_ratio = view_z / fp.near_plane;
    uint z_slice = uint(log(max(z_ratio, 1.0f)) * fp.log_depth_scale * float(fp.cluster_count_z));
    z_slice = min(z_slice, fp.cluster_count_z - 1u);

    tile_x = min(tile_x, fp.cluster_count_x - 1u);
    tile_y = min(tile_y, fp.cluster_count_y - 1u);

    return z_slice * fp.cluster_count_x * fp.cluster_count_y +
           tile_y * fp.cluster_count_x +
           tile_x;
}

// ============================================================================
// Fragment Shader
// ============================================================================

fragment float4 pbr_forward_plus_fragment_main(
    Vertex3DOutput in [[stage_in]],

    constant MaterialUniforms& material [[buffer(0)]],
    constant ForwardPlusUniforms& forward_plus [[buffer(1)]],

    texture2d<float> base_color_tex [[texture(0)]],
    texture2d<float> normal_tex [[texture(1)]],
    texture2d<float> metallic_roughness_tex [[texture(2)]],
    texture2d<float> ao_tex [[texture(3)]],
    texture2d<float> emissive_tex [[texture(4)]],
    texturecube<float> irradiance_map [[texture(5)]],
    texturecube<float> prefiltered_env [[texture(6)]],
    texture2d<float> brdf_lut [[texture(7)]],

    sampler tex_sampler [[sampler(0)]],

    device const LightGrid* light_grid [[buffer(2)]],
    device const uint* light_indices [[buffer(3)]],
    device const PointLight* point_lights [[buffer(4)]],
    device const SpotLight* spot_lights [[buffer(5)]]
) {
    // UV with material transform
    float2 uv = in.uv * material.uv_transform.xy + material.uv_transform.zw;
    uv = fract(uv);

    // Sample base color
    float4 base_color = material.base_color * in.color;
    if (material.texture_flags.x != 0) {
        float4 tex_color = base_color_tex.sample(tex_sampler, uv);
        tex_color.rgb = pow(tex_color.rgb, float3(2.2));
        base_color *= tex_color;
    }

    // Alpha handling
    if (material.extra_flags.y == 1) {
        if (base_color.a < material.emissive_alpha.a) {
            discard_fragment();
        }
    }

    float3 albedo = base_color.rgb;

    // Sample metallic-roughness
    float metallic = material.mrna.x;
    float roughness = material.mrna.y;
    if (material.texture_flags.z != 0) {
        float4 mr = metallic_roughness_tex.sample(tex_sampler, uv);
        metallic *= mr.b;
        roughness *= mr.g;
    }
    roughness = clamp(roughness, 0.04f, 1.0f);

    // Get normal
    float3 N = normalize(in.normal);
    if (material.texture_flags.y != 0) {
        float3 tangent_normal = normal_tex.sample(tex_sampler, uv).xyz * 2.0 - 1.0;
        tangent_normal.xy *= material.mrna.z;

        float3 dPdx = dfdx(in.world_pos);
        float3 dPdy = dfdy(in.world_pos);
        float2 dUVdx = dfdx(uv);
        float2 dUVdy = dfdy(uv);

        float3 T = normalize(dPdx * dUVdy.y - dPdy * dUVdx.y);
        float3 B = normalize(cross(N, T));
        float3x3 TBN = float3x3(T, B, N);

        N = normalize(TBN * tangent_normal);
    }

    // Sample AO
    float ao = 1.0;
    if (material.texture_flags.w != 0) {
        ao = mix(1.0f, ao_tex.sample(tex_sampler, uv).r, material.mrna.w);
    }

    // Sample emissive
    float3 emissive = material.emissive_alpha.rgb;
    if (material.extra_flags.x != 0) {
        float3 emissive_sample = emissive_tex.sample(tex_sampler, uv).rgb;
        emissive_sample = pow(emissive_sample, float3(2.2));
        emissive *= emissive_sample;
    }

    // View direction
    float3 V = normalize(forward_plus.camera_position.xyz - in.world_pos);

    // F0
    float3 F0 = float3(0.04);
    F0 = mix(F0, albedo, metallic);

    // Accumulate lighting
    float3 Lo = float3(0.0);

    // Directional light
    {
        float3 L = normalize(-forward_plus.directional_direction.xyz);
        float3 radiance = forward_plus.directional_color_intensity.rgb * forward_plus.directional_color_intensity.a;
        Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
    }

    // Get cluster for this fragment
    uint cluster_idx = getClusterIndex(in.world_pos, in.position, forward_plus);
    LightGrid grid = light_grid[cluster_idx];

    // Process only lights in this cluster
    for (uint i = 0; i < grid.count; i++) {
        uint packed_index = light_indices[grid.offset + i];
        bool is_spot = (packed_index & 0x80000000u) != 0;
        uint light_idx = packed_index & 0x7FFFFFFFu;

        if (is_spot) {
            SpotLight light = spot_lights[light_idx];
            float3 light_pos = light.position_range.xyz;
            float range = light.position_range.w;
            float3 light_dir = light.direction_outer.xyz;
            float outer_cos = light.direction_outer.w;
            float3 light_color = light.color_intensity.rgb;
            float intensity = light.color_intensity.a;
            float inner_cos = light.inner_pad.x;

            float3 L = light_pos - in.world_pos;
            float distance = length(L);

            if (distance < range) {
                L = normalize(L);

                float theta = dot(L, normalize(-light_dir));
                float epsilon = max(inner_cos - outer_cos, 0.0001f);
                float spot_intensity = clamp((theta - outer_cos) / epsilon, 0.0f, 1.0f);

                if (spot_intensity > 0.0) {
                    float attenuation = calculateAttenuation(distance, range);
                    float3 radiance = light_color * intensity * attenuation * spot_intensity;
                    Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
                }
            }
        } else {
            PointLight light = point_lights[light_idx];
            float3 light_pos = light.position_range.xyz;
            float range = light.position_range.w;
            float3 light_color = light.color_intensity.rgb;
            float intensity = light.color_intensity.a;

            float3 L = light_pos - in.world_pos;
            float distance = length(L);

            if (distance < range) {
                L = normalize(L);
                float attenuation = calculateAttenuation(distance, range);
                float3 radiance = light_color * intensity * attenuation;
                Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
            }
        }
    }

    // Ambient lighting
    float3 ambient;
    if (forward_plus.ibl_params.z > 0.5) {
        float NdotV = max(dot(N, V), 0.0);
        float3 R = reflect(-V, N);

        float3 F = fresnelSchlickRoughness(NdotV, F0, roughness);
        float3 kD = (1.0 - F) * (1.0 - metallic);

        float3 irradiance = irradiance_map.sample(tex_sampler, N).rgb;
        float3 diffuse = kD * irradiance * albedo;

        float lod = roughness * roughness * forward_plus.ibl_params.y;
        float3 prefiltered = prefiltered_env.sample(tex_sampler, R, level(lod)).rgb;
        float2 brdf = brdf_lut.sample(tex_sampler, float2(NdotV, roughness)).rg;
        float3 specular = prefiltered * (F * brdf.x + brdf.y) * forward_plus.ibl_params.w;

        ambient = (diffuse + specular) * ao * forward_plus.ibl_params.x;
    } else {
        float NdotV = max(dot(N, V), 0.0);
        float3 F_ambient = F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);

        float3 kD_ambient = (1.0 - F_ambient) * (1.0 - metallic);
        float3 diffuse_ambient = kD_ambient * albedo * forward_plus.ambient_color_intensity.rgb * forward_plus.ambient_color_intensity.a;

        float3 R = reflect(-V, N);
        float sky_factor = R.y * 0.5 + 0.5;
        float3 sky_color = float3(0.6, 0.7, 0.9);
        float3 ground_color = float3(0.2, 0.15, 0.1);
        float3 env_color = mix(ground_color, sky_color, sky_factor);
        float env_mip = roughness * roughness;
        env_color = mix(env_color, float3(0.3, 0.35, 0.4), env_mip);
        float3 specular_ambient = F_ambient * env_color * (1.0 - roughness * 0.5);

        ambient = (diffuse_ambient + specular_ambient) * ao;
    }

    // Final color
    float3 color = ambient + Lo + emissive;

    // ACES tonemapping
    float3 x = color;
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    color = clamp((x * (a * x + b)) / (x * (c * x + d) + e), float3(0.0), float3(1.0));

    // Gamma correction
    color = pow(color, float3(1.0 / 2.2));

    return float4(color, base_color.a);
}
