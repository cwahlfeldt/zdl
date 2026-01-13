#include <metal_stdlib>
using namespace metal;

// Light Culling Compute Shader for Forward+ Rendering (Metal version)

constant uint MAX_LIGHTS_PER_CLUSTER = 128;

// Point light structure
struct PointLight {
    float4 position_range;    // xyz = position, w = range
    float4 color_intensity;   // rgb = color, a = intensity
};

// Spot light structure
struct SpotLight {
    float4 position_range;    // xyz = position, w = range
    float4 direction_outer;   // xyz = direction, w = outer_cos
    float4 color_intensity;   // rgb = color, a = intensity
    float4 inner_pad;         // x = inner_cos
};

// Cluster AABB
struct ClusterAABB {
    float4 min_point;
    float4 max_point;
};

// Per-cluster light list
struct LightGrid {
    uint offset;
    uint count;
};

// Cluster uniforms
struct ClusterUBO {
    float4x4 view_matrix;
    float4x4 inv_proj_matrix;

    float screen_width;
    float screen_height;
    uint cluster_count_x;
    uint cluster_count_y;

    uint cluster_count_z;
    float near_plane;
    float far_plane;
    float _pad0;

    uint point_light_count;
    uint spot_light_count;
    uint2 _pad1;
};

// Test sphere-AABB intersection
bool sphereAABBIntersect(float3 center, float radius, float3 aabb_min, float3 aabb_max) {
    float3 closest = clamp(center, aabb_min, aabb_max);
    float3 diff = center - closest;
    float dist_sq = dot(diff, diff);
    return dist_sq <= (radius * radius);
}

// Test cone-AABB intersection (simplified)
bool coneAABBIntersect(float3 apex, float3 direction, float range, float outer_cos, float3 aabb_min, float3 aabb_max) {
    float3 center = apex + direction * (range * 0.5);
    float radius = range * 0.5 / max(outer_cos, 0.001f);
    radius = min(radius, range * 2.0f);
    return sphereAABBIntersect(center, radius, aabb_min, aabb_max);
}

kernel void light_cull_main(
    uint3 global_id [[thread_position_in_grid]],

    constant ClusterUBO& cluster_info [[buffer(0)]],

    device const ClusterAABB* cluster_aabbs [[buffer(1)]],
    device const PointLight* point_lights [[buffer(2)]],
    device const SpotLight* spot_lights [[buffer(3)]],

    device LightGrid* light_grid [[buffer(4)]],
    device uint* light_indices [[buffer(5)]]
) {
    uint cluster_x = global_id.x;
    uint cluster_y = global_id.y;
    uint cluster_z = global_id.z;

    if (cluster_x >= cluster_info.cluster_count_x ||
        cluster_y >= cluster_info.cluster_count_y ||
        cluster_z >= cluster_info.cluster_count_z) {
        return;
    }

    uint cluster_idx = cluster_z * cluster_info.cluster_count_x * cluster_info.cluster_count_y +
                       cluster_y * cluster_info.cluster_count_x +
                       cluster_x;

    // Get cluster AABB
    ClusterAABB aabb = cluster_aabbs[cluster_idx];
    float3 aabb_min = aabb.min_point.xyz;
    float3 aabb_max = aabb.max_point.xyz;

    uint base_offset = cluster_idx * MAX_LIGHTS_PER_CLUSTER;
    uint count = 0;

    // Test point lights
    for (uint i = 0; i < cluster_info.point_light_count; i++) {
        PointLight light = point_lights[i];
        float4 view_pos = cluster_info.view_matrix * float4(light.position_range.xyz, 1.0);
        float range = light.position_range.w;

        if (sphereAABBIntersect(view_pos.xyz, range, aabb_min, aabb_max) && count < MAX_LIGHTS_PER_CLUSTER) {
            light_indices[base_offset + count] = i;
            count++;
        }
    }

    // Test spot lights
    for (uint i = 0; i < cluster_info.spot_light_count; i++) {
        SpotLight light = spot_lights[i];
        float4 view_pos = cluster_info.view_matrix * float4(light.position_range.xyz, 1.0);
        float4 view_dir = cluster_info.view_matrix * float4(light.direction_outer.xyz, 0.0);
        float range = light.position_range.w;
        float outer_cos = light.direction_outer.w;

        if (coneAABBIntersect(view_pos.xyz, normalize(view_dir.xyz), range, outer_cos, aabb_min, aabb_max) &&
            count < MAX_LIGHTS_PER_CLUSTER) {
            light_indices[base_offset + count] = i | 0x80000000u;
            count++;
        }
    }

    light_grid[cluster_idx].offset = base_offset;
    light_grid[cluster_idx].count = count;
}
