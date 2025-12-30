#version 450

// Standard vertex attributes
layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec2 a_uv;
layout (location = 3) in vec4 a_color;

// Skinning attributes
layout (location = 4) in uvec4 a_joints;   // Bone indices (4 influences)
layout (location = 5) in vec4 a_weights;   // Bone weights (4 influences)

// Outputs to fragment shader
layout (location = 0) out vec3 v_normal;
layout (location = 1) out vec2 v_uv;
layout (location = 2) out vec4 v_color;
layout (location = 3) out vec3 v_frag_pos;

// MVP uniforms
layout (set = 1, binding = 0, std140) uniform Uniforms {
    mat4 model;
    mat4 view;
    mat4 projection;
} uniforms;

// Bone matrices (skinning)
// Using storage buffer to support more bones
layout (set = 2, binding = 0, std430) readonly buffer BoneMatrices {
    mat4 bones[];
};

void main() {
    // Compute skinning matrix from bone influences
    mat4 skin_matrix =
        bones[a_joints.x] * a_weights.x +
        bones[a_joints.y] * a_weights.y +
        bones[a_joints.z] * a_weights.z +
        bones[a_joints.w] * a_weights.w;

    // Apply skinning to position
    vec4 skinned_pos = skin_matrix * vec4(a_position, 1.0);

    // Apply model transform
    vec4 world_pos = uniforms.model * skinned_pos;
    v_frag_pos = world_pos.xyz;

    gl_Position = uniforms.projection * uniforms.view * world_pos;

    // Transform normal through skinning and model matrices
    mat3 skin_normal_matrix = mat3(skin_matrix);
    mat3 model_normal_matrix = mat3(uniforms.model);
    v_normal = model_normal_matrix * skin_normal_matrix * a_normal;

    v_uv = a_uv;
    v_color = a_color;
}
