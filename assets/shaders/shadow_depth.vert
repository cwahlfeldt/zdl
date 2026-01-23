#version 450

// Vertex input (position only)
layout(location = 0) in vec3 position;

// Uniforms
layout(binding = 0) uniform ShadowUniforms {
    mat4 light_view_proj;
    mat4 model;
} uniforms;

void main() {
    vec4 world_pos = uniforms.model * vec4(position, 1.0);
    gl_Position = uniforms.light_view_proj * world_pos;
}
