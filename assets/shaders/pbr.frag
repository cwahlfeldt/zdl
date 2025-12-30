#version 450

// Inputs from vertex shader
layout (location = 0) in vec3 v_world_pos;
layout (location = 1) in vec3 v_normal;
layout (location = 2) in vec2 v_uv;
layout (location = 3) in vec4 v_color;

// Output
layout (location = 0) out vec4 out_color;

// Constants
const float PI = 3.14159265359;
const uint MAX_POINT_LIGHTS = 16;
const uint MAX_SPOT_LIGHTS = 8;

// Material textures (fragment sampler set)
layout (set = 2, binding = 0) uniform sampler2D u_base_color_tex;
layout (set = 2, binding = 1) uniform sampler2D u_normal_tex;
layout (set = 2, binding = 2) uniform sampler2D u_metallic_roughness_tex;
layout (set = 2, binding = 3) uniform sampler2D u_ao_tex;
layout (set = 2, binding = 4) uniform sampler2D u_emissive_tex;

// Material uniforms (fragment uniform buffer 0)
layout (set = 3, binding = 0, std140) uniform MaterialUBO {
    vec4 base_color;            // RGBA
    float metallic;
    float roughness;
    float normal_scale;
    float ao_strength;
    vec3 emissive;
    float alpha_cutoff;
    vec2 uv_scale;
    vec2 uv_offset;
    uint has_base_color_texture;
    uint has_normal_texture;
    uint has_metallic_roughness_texture;
    uint has_ao_texture;
    uint has_emissive_texture;
    uint alpha_mode;            // 0=opaque, 1=mask, 2=blend
    uint _pad[2];
} material;

// Point light structure
struct PointLight {
    vec4 position_range;        // xyz=position, w=range
    vec4 color_intensity;       // rgb=color, a=intensity
};

// Spot light structure
struct SpotLight {
    vec4 position_range;        // xyz=position, w=range
    vec4 direction_outer;       // xyz=direction, w=outer_cos
    vec4 color_intensity;       // rgb=color, a=intensity
    vec4 inner_pad;             // x=inner_cos
};

// Lighting uniforms (fragment uniform buffer 1)
layout (set = 3, binding = 1, std140) uniform LightUBO {
    vec4 directional_direction;         // xyz=direction
    vec4 directional_color_intensity;   // rgb=color, a=intensity
    vec4 ambient_color_intensity;       // rgb=color, a=intensity
    vec4 camera_position;               // xyz=position
    uint point_light_count;
    uint spot_light_count;
    uint _pad[2];
    PointLight point_lights[MAX_POINT_LIGHTS];
    SpotLight spot_lights[MAX_SPOT_LIGHTS];
} lights;

// ============================================================================
// PBR Functions
// ============================================================================

// Fresnel-Schlick approximation
vec3 fresnelSchlick(float cos_theta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

// Fresnel-Schlick with roughness for IBL
vec3 fresnelSchlickRoughness(float cos_theta, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

// Trowbridge-Reitz GGX Normal Distribution Function
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

// Schlick-GGX Geometry function
float geometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

// Smith's method for geometry
float geometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = geometrySchlickGGX(NdotV, roughness);
    float ggx1 = geometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Calculate PBR lighting contribution for a single light
vec3 calculatePBRLight(vec3 L, vec3 radiance, vec3 N, vec3 V, vec3 albedo, float metallic, float roughness, vec3 F0) {
    vec3 H = normalize(V + L);

    // Cook-Torrance BRDF
    float NDF = distributionGGX(N, H, roughness);
    float G = geometrySmith(N, V, L, roughness);
    vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    // Specular
    vec3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = numerator / denominator;

    // Energy conservation
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metallic;  // Metals have no diffuse

    // Final contribution
    float NdotL = max(dot(N, L), 0.0);
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

// Attenuation for point/spot lights
float calculateAttenuation(float distance, float range) {
    // Smooth attenuation that reaches zero at range
    float attenuation = clamp(1.0 - pow(distance / range, 4.0), 0.0, 1.0);
    return attenuation * attenuation / (distance * distance + 1.0);
}

// ============================================================================
// Main
// ============================================================================

void main() {
    // UV with material transform
    vec2 uv = v_uv * material.uv_scale + material.uv_offset;

    // Sample base color
    vec4 base_color = material.base_color * v_color;
    if (material.has_base_color_texture != 0) {
        base_color *= texture(u_base_color_tex, uv);
    }

    // Alpha handling
    if (material.alpha_mode == 1) { // Mask mode
        if (base_color.a < material.alpha_cutoff) {
            discard;
        }
    }

    vec3 albedo = base_color.rgb;

    // Sample metallic-roughness
    float metallic = material.metallic;
    float roughness = material.roughness;
    if (material.has_metallic_roughness_texture != 0) {
        vec4 mr = texture(u_metallic_roughness_tex, uv);
        metallic *= mr.b;   // Blue channel = metallic
        roughness *= mr.g;  // Green channel = roughness
    }
    // Clamp roughness to avoid division by zero
    roughness = clamp(roughness, 0.04, 1.0);

    // Get normal
    vec3 N = normalize(v_normal);
    if (material.has_normal_texture != 0) {
        // Sample normal map and unpack from [0,1] to [-1,1]
        vec3 tangent_normal = texture(u_normal_tex, uv).xyz * 2.0 - 1.0;
        tangent_normal.xy *= material.normal_scale;

        // Simple tangent space calculation (works for most cases)
        // For better quality, use pre-computed tangents
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
    if (material.has_ao_texture != 0) {
        ao = mix(1.0, texture(u_ao_tex, uv).r, material.ao_strength);
    }

    // Sample emissive
    vec3 emissive = material.emissive;
    if (material.has_emissive_texture != 0) {
        emissive *= texture(u_emissive_tex, uv).rgb;
    }

    // View direction
    vec3 V = normalize(lights.camera_position.xyz - v_world_pos);

    // Calculate F0 (reflectance at normal incidence)
    // Dielectrics use 0.04, metals use albedo
    vec3 F0 = vec3(0.04);
    F0 = mix(F0, albedo, metallic);

    // Accumulate lighting
    vec3 Lo = vec3(0.0);

    // Directional light
    {
        vec3 L = normalize(-lights.directional_direction.xyz);
        vec3 radiance = lights.directional_color_intensity.rgb * lights.directional_color_intensity.a;
        Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
    }

    // Point lights
    for (uint i = 0; i < lights.point_light_count && i < MAX_POINT_LIGHTS; i++) {
        vec3 light_pos = lights.point_lights[i].position_range.xyz;
        float range = lights.point_lights[i].position_range.w;
        vec3 light_color = lights.point_lights[i].color_intensity.rgb;
        float intensity = lights.point_lights[i].color_intensity.a;

        vec3 L = light_pos - v_world_pos;
        float distance = length(L);

        if (distance < range) {
            L = normalize(L);
            float attenuation = calculateAttenuation(distance, range);
            vec3 radiance = light_color * intensity * attenuation;
            Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
        }
    }

    // Spot lights
    for (uint i = 0; i < lights.spot_light_count && i < MAX_SPOT_LIGHTS; i++) {
        vec3 light_pos = lights.spot_lights[i].position_range.xyz;
        float range = lights.spot_lights[i].position_range.w;
        vec3 light_dir = lights.spot_lights[i].direction_outer.xyz;
        float outer_cos = lights.spot_lights[i].direction_outer.w;
        vec3 light_color = lights.spot_lights[i].color_intensity.rgb;
        float intensity = lights.spot_lights[i].color_intensity.a;
        float inner_cos = lights.spot_lights[i].inner_pad.x;

        vec3 L = light_pos - v_world_pos;
        float distance = length(L);

        if (distance < range) {
            L = normalize(L);

            // Spot cone attenuation
            float theta = dot(L, normalize(-light_dir));
            float epsilon = inner_cos - outer_cos;
            float spot_intensity = clamp((theta - outer_cos) / epsilon, 0.0, 1.0);

            if (spot_intensity > 0.0) {
                float attenuation = calculateAttenuation(distance, range);
                vec3 radiance = light_color * intensity * attenuation * spot_intensity;
                Lo += calculatePBRLight(L, radiance, N, V, albedo, metallic, roughness, F0);
            }
        }
    }

    // Ambient lighting (simplified IBL approximation)
    vec3 ambient = lights.ambient_color_intensity.rgb * lights.ambient_color_intensity.a * albedo * ao;

    // Final color
    vec3 color = ambient + Lo + emissive;

    // HDR tonemapping (Reinhard)
    color = color / (color + vec3(1.0));

    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));

    out_color = vec4(color, base_color.a);
}
