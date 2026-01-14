#version 450

// Forward+ PBR Fragment Shader
//
// This shader uses clustered light culling for efficient many-light rendering.
// Instead of iterating over all lights, it only processes lights assigned
// to the cluster containing this fragment.

// Inputs from vertex shader
layout (location = 0) in vec3 v_world_pos;
layout (location = 1) in vec3 v_normal;
layout (location = 2) in vec2 v_uv;
layout (location = 3) in vec4 v_color;

// Output
layout (location = 0) out vec4 out_color;

// Constants
const float PI = 3.14159265359;

// Material textures (fragment sampler set)
layout (set = 2, binding = 0) uniform sampler2D u_base_color_tex;
layout (set = 2, binding = 1) uniform sampler2D u_normal_tex;
layout (set = 2, binding = 2) uniform sampler2D u_metallic_roughness_tex;
layout (set = 2, binding = 3) uniform sampler2D u_ao_tex;
layout (set = 2, binding = 4) uniform sampler2D u_emissive_tex;

// IBL textures
layout (set = 2, binding = 5) uniform samplerCube u_irradiance_map;
layout (set = 2, binding = 6) uniform samplerCube u_prefiltered_env;
layout (set = 2, binding = 7) uniform sampler2D u_brdf_lut;

// Material uniforms (fragment uniform buffer 0)
layout (set = 3, binding = 0, std140) uniform MaterialUBO {
    vec4 base_color;
    vec4 mrna;              // x=metallic, y=roughness, z=normal_scale, w=ao_strength
    vec4 emissive_alpha;    // rgb=emissive, a=alpha_cutoff
    vec4 uv_transform;      // xy=uv_scale, zw=uv_offset
    uvec4 texture_flags;    // x=base, y=normal, z=mr, w=ao
    uvec4 extra_flags;      // x=emissive, y=alpha_mode, zw=pad
} material;

// Point light structure
struct PointLight {
    vec4 position_range;    // xyz=position, w=range
    vec4 color_intensity;   // rgb=color, a=intensity
};

// Spot light structure
struct SpotLight {
    vec4 position_range;    // xyz=position, w=range
    vec4 direction_outer;   // xyz=direction, w=outer_cos
    vec4 color_intensity;   // rgb=color, a=intensity
    vec4 inner_pad;         // x=inner_cos
};

// Per-cluster light list
struct LightGrid {
    uint offset;
    uint count;
};

// Forward+ uniforms
layout (set = 3, binding = 1, std140) uniform ForwardPlusUBO {
    vec4 directional_direction;
    vec4 directional_color_intensity;
    vec4 ambient_color_intensity;
    vec4 camera_position;
    vec4 ibl_params;            // x=env_intensity, y=max_lod, z=use_ibl, w=spec_intensity

    // Cluster parameters
    float screen_width;
    float screen_height;
    uint cluster_count_x;
    uint cluster_count_y;

    uint cluster_count_z;
    float near_plane;
    float far_plane;
    float log_depth_scale;      // Precomputed: 1.0 / log(far/near)

    mat4 view_matrix;
} forward_plus;

// Storage buffers for clustered lights
// SDL3 GPU Fragment Shader Binding Layout (SPIR-V):
//   Set 2: Fragment samplers (bindings 0-7) + storage buffers (separate binding space, slots 0-3)
//   Set 3: Uniform buffers
// Note: SDL3 GPU uses separate binding spaces for samplers vs storage buffers within a set.
// Storage buffers start at binding 0 in their own space, not binding 8.
layout (std430, set = 2, binding = 0) readonly buffer LightGridBuffer {
    LightGrid light_grid[];
};

layout (std430, set = 2, binding = 1) readonly buffer LightIndexBuffer {
    uint light_indices[];
};

layout (std430, set = 2, binding = 2) readonly buffer PointLightBuffer {
    PointLight point_lights[];
};

layout (std430, set = 2, binding = 3) readonly buffer SpotLightBuffer {
    SpotLight spot_lights[];
};

// ============================================================================
// PBR Functions
// ============================================================================

vec3 fresnelSchlick(float cos_theta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

vec3 fresnelSchlickRoughness(float cos_theta, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

float distributionGGX(vec3 N, vec3 H, float roughness) {
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

float geometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = geometrySchlickGGX(NdotV, roughness);
    float ggx1 = geometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec3 calculatePBRLight(vec3 L, vec3 radiance, vec3 N, vec3 V, vec3 albedo, float metallic, float roughness, vec3 F0) {
    vec3 H = normalize(V + L);

    float NDF = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    vec3 F = fresnelSchlick(max(dot(H, L), 0.0), F0);

    vec3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = numerator / denominator;

    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
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

// Get the cluster index for a fragment
uint getClusterIndex(vec3 frag_pos) {
    // Transform to view space
    vec4 view_pos = forward_plus.view_matrix * vec4(frag_pos, 1.0);
    float view_z = -view_pos.z; // View space Z is negative looking forward

    // Screen space position
    vec2 screen_pos = gl_FragCoord.xy;

    // Calculate tile indices
    uint tile_x = uint(screen_pos.x / (forward_plus.screen_width / float(forward_plus.cluster_count_x)));
    uint tile_y = uint(screen_pos.y / (forward_plus.screen_height / float(forward_plus.cluster_count_y)));

    // Calculate depth slice using exponential distribution (DOOM 2016 style)
    // z_slice = log(view_z / near) / log(far / near) * num_slices
    float z_ratio = view_z / forward_plus.near_plane;
    uint z_slice = uint(log(max(z_ratio, 1.0)) * forward_plus.log_depth_scale * float(forward_plus.cluster_count_z));
    z_slice = min(z_slice, forward_plus.cluster_count_z - 1u);

    // Clamp to valid range
    tile_x = min(tile_x, forward_plus.cluster_count_x - 1u);
    tile_y = min(tile_y, forward_plus.cluster_count_y - 1u);

    return z_slice * forward_plus.cluster_count_x * forward_plus.cluster_count_y +
           tile_y * forward_plus.cluster_count_x +
           tile_x;
}

// ============================================================================
// Main
// ============================================================================

void main() {
    // UV with material transform
    vec2 uv = v_uv * material.uv_transform.xy + material.uv_transform.zw;
    uv = fract(uv);

    // Sample base color
    vec4 base_color = material.base_color * v_color;
    if (material.texture_flags.x != 0) {
        vec4 tex_color = texture(u_base_color_tex, uv);
        tex_color.rgb = pow(tex_color.rgb, vec3(2.2));
        base_color *= tex_color;
    }

    // Alpha handling
    if (material.extra_flags.y == 1) {
        if (base_color.a < material.emissive_alpha.a) {
            discard;
        }
    }

    vec3 albedo = base_color.rgb;

    // Sample metallic-roughness
    float metallic = material.mrna.x;
    float roughness = material.mrna.y;
    if (material.texture_flags.z != 0) {
        vec4 mr = texture(u_metallic_roughness_tex, uv);
        metallic *= mr.b;
        roughness *= mr.g;
    }
    roughness = clamp(roughness, 0.04, 1.0);

    // Get normal
    vec3 N = normalize(v_normal);
    if (material.texture_flags.y != 0) {
        vec3 tangent_normal = texture(u_normal_tex, uv).xyz * 2.0 - 1.0;
        tangent_normal.xy *= material.mrna.z;

        vec3 dPdx = dFdx(v_world_pos);
        vec3 dPdy = dFdy(v_world_pos);
        vec2 dUVdx = dFdx(uv);
        vec2 dUVdy = dFdy(uv);

        vec3 T = normalize(dPdx * dUVdy.y - dPdy * dUVdx.y);
        vec3 B = normalize(cross(N, T));
        mat3 TBN = mat3(T, B, N);

        N = normalize(TBN * tangent_normal);
    }

    // Sample AO
    float ao = 1.0;
    if (material.texture_flags.w != 0) {
        ao = mix(1.0, texture(u_ao_tex, uv).r, material.mrna.w);
    }

    // Sample emissive
    vec3 emissive = material.emissive_alpha.rgb;
    if (material.extra_flags.x != 0) {
        vec3 emissive_tex = texture(u_emissive_tex, uv).rgb;
        emissive_tex = pow(emissive_tex, vec3(2.2));
        emissive *= emissive_tex;
    }

    // View direction
    vec3 V = normalize(forward_plus.camera_position.xyz - v_world_pos);

    // F0
    vec3 F0 = vec3(0.04);
    F0 = mix(F0, albedo, metallic);

    // Accumulate lighting
    vec3 Lo = vec3(0.0);

    // Directional light (always processed)
    {
        vec3 L = normalize(-forward_plus.directional_direction.xyz);
        vec3 radiance = forward_plus.directional_color_intensity.rgb * forward_plus.directional_color_intensity.a;
        Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
    }

    // Get cluster for this fragment
    uint cluster_idx = getClusterIndex(v_world_pos);
    LightGrid grid = light_grid[cluster_idx];

    // Process only lights in this cluster
    for (uint i = 0; i < grid.count; i++) {
        uint packed_index = light_indices[grid.offset + i];
        bool is_spot = (packed_index & 0x80000000u) != 0;
        uint light_idx = packed_index & 0x7FFFFFFFu;

        if (is_spot) {
            // Spot light
            SpotLight light = spot_lights[light_idx];
            vec3 light_pos = light.position_range.xyz;
            float range = light.position_range.w;
            vec3 light_dir = light.direction_outer.xyz;
            float outer_cos = light.direction_outer.w;
            vec3 light_color = light.color_intensity.rgb;
            float intensity = light.color_intensity.a;
            float inner_cos = light.inner_pad.x;

            vec3 L = light_pos - v_world_pos;
            float distance = length(L);

            if (distance < range) {
                L = normalize(L);

                float theta = dot(L, normalize(-light_dir));
                float epsilon = max(inner_cos - outer_cos, 0.0001);
                float spot_intensity = clamp((theta - outer_cos) / epsilon, 0.0, 1.0);

                if (spot_intensity > 0.0) {
                    float attenuation = calculateAttenuation(distance, range);
                    vec3 radiance = light_color * intensity * attenuation * spot_intensity;
                    Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
                }
            }
        } else {
            // Point light
            PointLight light = point_lights[light_idx];
            vec3 light_pos = light.position_range.xyz;
            float range = light.position_range.w;
            vec3 light_color = light.color_intensity.rgb;
            float intensity = light.color_intensity.a;

            vec3 L = light_pos - v_world_pos;
            float distance = length(L);

            if (distance < range) {
                L = normalize(L);
                float attenuation = calculateAttenuation(distance, range);
                vec3 radiance = light_color * intensity * attenuation;
                Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
            }
        }
    }

    // Ambient lighting
    vec3 ambient;
    if (forward_plus.ibl_params.z > 0.5) {
        // IBL
        float NdotV = max(dot(N, V), 0.0);
        vec3 R = reflect(-V, N);

        vec3 F = fresnelSchlickRoughness(NdotV, F0, roughness);
        vec3 kD = (1.0 - F) * (1.0 - metallic);

        vec3 irradiance = texture(u_irradiance_map, N).rgb;
        vec3 diffuse = kD * irradiance * albedo;

        float lod = roughness * roughness * forward_plus.ibl_params.y;
        vec3 prefiltered = textureLod(u_prefiltered_env, R, lod).rgb;
        vec2 brdf = texture(u_brdf_lut, vec2(NdotV, roughness)).rg;
        vec3 specular = prefiltered * (F * brdf.x + brdf.y) * forward_plus.ibl_params.w;

        ambient = (diffuse + specular) * ao * forward_plus.ibl_params.x;
    } else {
        // Fallback ambient
        float NdotV = max(dot(N, V), 0.0);
        vec3 F_ambient = F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);

        vec3 kD_ambient = (1.0 - F_ambient) * (1.0 - metallic);
        vec3 diffuse_ambient = kD_ambient * albedo * forward_plus.ambient_color_intensity.rgb * forward_plus.ambient_color_intensity.a;

        vec3 R = reflect(-V, N);
        float sky_factor = R.y * 0.5 + 0.5;
        vec3 sky_color = vec3(0.6, 0.7, 0.9);
        vec3 ground_color = vec3(0.2, 0.15, 0.1);
        vec3 env_color = mix(ground_color, sky_color, sky_factor);
        float env_mip = roughness * roughness;
        env_color = mix(env_color, vec3(0.3, 0.35, 0.4), env_mip);
        vec3 specular_ambient = F_ambient * env_color * (1.0 - roughness * 0.5);

        ambient = (diffuse_ambient + specular_ambient) * ao;
    }

    // Final color
    vec3 color = ambient + Lo + emissive;

    // ACES tonemapping
    vec3 x = color;
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    color = clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);

    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));

    out_color = vec4(color, base_color.a);
}
