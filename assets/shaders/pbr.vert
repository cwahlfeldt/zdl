#version 450

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec2 a_uv;
layout (location = 3) in vec4 a_color;

layout (location = 0) out vec3 v_world_pos;
layout (location = 1) out vec3 v_normal;
layout (location = 2) out vec2 v_uv;
layout (location = 3) out vec4 v_color;

// MVP uniforms (vertex uniform buffer 0)
layout (set = 1, binding = 0, std140) uniform Uniforms {
    mat4 model;
    mat4 view;
    mat4 projection;
} uniforms;

void main() {
    vec4 world_pos = uniforms.model * vec4(a_position, 1.0);
    v_world_pos = world_pos.xyz;

    gl_Position = uniforms.projection * uniforms.view * world_pos;

    // Transform normal to world space
    // Use inverse transpose for non-uniform scaling support
    mat3 normal_matrix = transpose(inverse(mat3(uniforms.model)));
    v_normal = normalize(normal_matrix * a_normal);

    v_uv = a_uv;
    v_color = a_color;
}
