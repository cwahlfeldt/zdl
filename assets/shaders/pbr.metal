#include <metal_stdlib>
using namespace metal;

// Constants
constant float PI = 3.14159265359;
constant uint MAX_POINT_LIGHTS = 16;
constant uint MAX_SPOT_LIGHTS = 8;

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
    float4 position_range;
    float4 color_intensity;
};

struct SpotLight {
    float4 position_range;
    float4 direction_outer;
    float4 color_intensity;
    float4 inner_pad;
};

struct LightUniforms {
    float4 directional_direction;
    float4 directional_color_intensity;
    float4 ambient_color_intensity;
    float4 camera_position;
    float4 ibl_params;  // x=env_intensity, y=max_lod, z=use_ibl, w=spec_intensity
    uint point_light_count;
    uint spot_light_count;
    uint _pad[2];
    PointLight point_lights[MAX_POINT_LIGHTS];
    SpotLight spot_lights[MAX_SPOT_LIGHTS];
};

// ============================================================================
// Vertex Shader
// ============================================================================

vertex Vertex3DOutput pbr_vertex_main(
    Vertex3DInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    Vertex3DOutput out;

    float4 world_pos = uniforms.model * float4(in.position, 1.0);
    out.world_pos = world_pos.xyz;

    out.position = uniforms.projection * uniforms.view * world_pos;

    // Transform normal to world space using inverse transpose
    float3x3 normal_matrix = transpose(float3x3(
        uniforms.model[0].xyz,
        uniforms.model[1].xyz,
        uniforms.model[2].xyz
    ));
    // Note: For proper inverse transpose, we'd need to compute it on CPU
    // This simplified version assumes uniform scaling
    out.normal = normalize(normal_matrix * in.normal);

    out.uv = in.uv;
    out.color = in.color;

    return out;
}

// ============================================================================
// PBR Functions
// ============================================================================

// Fresnel-Schlick approximation
float3 fresnelSchlick(float cos_theta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

// Fresnel-Schlick with roughness for IBL
float3 fresnelSchlickRoughness(float cos_theta, float3 F0, float roughness) {
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

// Trowbridge-Reitz GGX Normal Distribution Function
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

// Schlick-GGX Geometry function
float geometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

// Smith's method for geometry
float geometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = geometrySchlickGGX(NdotV, roughness);
    float ggx1 = geometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Calculate PBR lighting contribution for a single light
float3 calculatePBRLight(float3 L, float3 radiance, float3 N, float3 V,
                         float3 albedo, float metallic, float roughness, float3 F0) {
    float3 H = normalize(V + L);

    // Cook-Torrance BRDF
    float NDF = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    // Use H·L for Fresnel - physically correct for specular reflection
    float3 F = fresnelSchlick(max(dot(H, L), 0.0), F0);

    // Specular
    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    // Energy conservation
    float3 kS = F;
    float3 kD = float3(1.0) - kS;
    kD *= 1.0 - metallic;

    // Final contribution
    float NdotL = max(dot(N, L), 0.0);
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

// Attenuation for point/spot lights
float calculateAttenuation(float distance, float range) {
    float attenuation = clamp(1.0 - pow(distance / range, 4.0), 0.0, 1.0);
    return attenuation * attenuation / (distance * distance + 1.0);
}

// ============================================================================
// Fragment Shader
// ============================================================================

fragment float4 pbr_fragment_main(
    Vertex3DOutput in [[stage_in]],
    constant MaterialUniforms& material [[buffer(0)]],
    constant LightUniforms& lights [[buffer(1)]],
    texture2d<float> base_color_tex [[texture(0)]],
    texture2d<float> normal_tex [[texture(1)]],
    texture2d<float> metallic_roughness_tex [[texture(2)]],
    texture2d<float> ao_tex [[texture(3)]],
    texture2d<float> emissive_tex [[texture(4)]],
    texturecube<float> irradiance_map [[texture(5)]],
    texturecube<float> prefiltered_env [[texture(6)]],
    texture2d<float> brdf_lut [[texture(7)]],
    sampler samp [[sampler(0)]]
) {
    // UV with material transform; force repeat to avoid clamp-only sampling.
    float2 uv = in.uv * material.uv_transform.xy + material.uv_transform.zw;
    uv = fract(uv);

    // Sample base color (textures are in sRGB, convert to linear)
    float4 base_color = material.base_color * in.color;
    if (material.texture_flags.x != 0) {
        float4 tex_color = base_color_tex.sample(samp, uv);
        // Convert from sRGB to linear space
        tex_color.rgb = pow(tex_color.rgb, float3(2.2));
        base_color *= tex_color;
    }

    // Alpha handling
    if (material.extra_flags.y == 1) { // Mask mode
        if (base_color.a < material.emissive_alpha.w) {
            discard_fragment();
        }
    }

    float3 albedo = base_color.rgb;

    // Sample metallic-roughness
    float metallic = material.mrna.x;
    float roughness = material.mrna.y;
    if (material.texture_flags.z != 0) {
        float4 mr = metallic_roughness_tex.sample(samp, uv);
        metallic *= mr.b;
        roughness *= mr.g;
    }
    roughness = clamp(roughness, 0.04, 1.0);

    // Get normal
    float3 N = normalize(in.normal);
    if (material.texture_flags.y != 0) {
        float3 tangent_normal = normal_tex.sample(samp, uv).xyz * 2.0 - 1.0;
        tangent_normal.xy *= material.mrna.z;

        // Simple tangent space calculation
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
        ao = mix(1.0, ao_tex.sample(samp, uv).r, material.mrna.w);
    }

    // Sample emissive (texture is in sRGB, convert to linear)
    float3 emissive = material.emissive_alpha.rgb;
    if (material.extra_flags.x != 0) {
        float3 emissive_sample = emissive_tex.sample(samp, uv).rgb;
        // Convert from sRGB to linear space
        emissive_sample = pow(emissive_sample, float3(2.2));
        emissive *= emissive_sample;
    }

    // View direction
    float3 V = normalize(lights.camera_position.xyz - in.world_pos);

    // Calculate F0
    float3 F0 = float3(0.04);
    F0 = mix(F0, albedo, metallic);

    // Accumulate lighting
    float3 Lo = float3(0.0);

    // Directional light
    {
        float3 L = normalize(-lights.directional_direction.xyz);
        float3 radiance = lights.directional_color_intensity.rgb * lights.directional_color_intensity.a;
        Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
    }

    // Point lights
    for (uint i = 0; i < lights.point_light_count && i < MAX_POINT_LIGHTS; i++) {
        float3 light_pos = lights.point_lights[i].position_range.xyz;
        float range = lights.point_lights[i].position_range.w;
        float3 light_color = lights.point_lights[i].color_intensity.rgb;
        float intensity = lights.point_lights[i].color_intensity.a;

        float3 L = light_pos - in.world_pos;
        float distance = length(L);

        if (distance < range) {
            L = normalize(L);
            float attenuation = calculateAttenuation(distance, range);
            float3 radiance = light_color * intensity * attenuation;
            Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
        }
    }

    // Spot lights
    for (uint i = 0; i < lights.spot_light_count && i < MAX_SPOT_LIGHTS; i++) {
        float3 light_pos = lights.spot_lights[i].position_range.xyz;
        float range = lights.spot_lights[i].position_range.w;
        float3 light_dir = lights.spot_lights[i].direction_outer.xyz;
        float outer_cos = lights.spot_lights[i].direction_outer.w;
        float3 light_color = lights.spot_lights[i].color_intensity.rgb;
        float intensity = lights.spot_lights[i].color_intensity.a;
        float inner_cos = lights.spot_lights[i].inner_pad.x;

        float3 L = light_pos - in.world_pos;
        float distance = length(L);

        if (distance < range) {
            L = normalize(L);

            float theta = dot(L, normalize(-light_dir));
            float epsilon = max(inner_cos - outer_cos, 0.0001);
            float spot_intensity = clamp((theta - outer_cos) / epsilon, 0.0, 1.0);

            if (spot_intensity > 0.0) {
                float attenuation = calculateAttenuation(distance, range);
                float3 radiance = light_color * intensity * attenuation * spot_intensity;
                Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
            }
        }
    }

    // Ambient lighting
    float3 ambient;

    // Check if IBL is enabled
    if (lights.ibl_params.z > 0.5) {
        // Image-Based Lighting (IBL)
        float NdotV = max(dot(N, V), 0.0);
        float3 R = reflect(-V, N);

        // Fresnel with roughness for ambient
        float3 F = fresnelSchlickRoughness(NdotV, F0, roughness);

        // Diffuse IBL
        float3 kD = (1.0 - F) * (1.0 - metallic);
        float3 irradiance = irradiance_map.sample(samp, N).rgb;
        float3 diffuse = kD * irradiance * albedo;

        // Specular IBL
        float lod = roughness * roughness * lights.ibl_params.y; // max_reflection_lod
        float3 prefiltered = prefiltered_env.sample(samp, R, level(lod)).rgb;
        float2 brdf = brdf_lut.sample(samp, float2(NdotV, roughness)).rg;
        float3 specular = prefiltered * (F * brdf.x + brdf.y) * lights.ibl_params.w;

        ambient = (diffuse + specular) * ao * lights.ibl_params.x; // env_intensity
    } else {
        // Fallback: procedural ambient with Fresnel-based environment approximation
        float NdotV = max(dot(N, V), 0.0);
        float3 F_ambient = F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);

        // Diffuse ambient (reduced for metals)
        float3 kD_ambient = (1.0 - F_ambient) * (1.0 - metallic);
        float3 diffuse_ambient = kD_ambient * albedo * lights.ambient_color_intensity.rgb * lights.ambient_color_intensity.a;

        // Fake environment reflection for metals
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

    // DEBUG: Uncomment one of these to debug:
    // color = N * 0.5 + 0.5;  // View normals (should show color variation on sphere)
    // color = float3(roughness);  // View roughness
    // color = float3(metallic);  // View metallic
    // color = V * 0.5 + 0.5;  // View direction
    // color = Lo;  // Direct lighting only (before tonemapping)

    // ACES filmic tonemapping (better contrast than Reinhard)
    float3 x = color;
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    color = clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);

    // Gamma correction
    color = pow(color, float3(1.0 / 2.2));

    return float4(color, base_color.a);
}
