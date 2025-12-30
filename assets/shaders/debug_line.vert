#version 450

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec4 a_color;

layout (location = 0) out vec4 v_color;

// View-Projection matrix
layout (set = 1, binding = 0, std140) uniform Uniforms {
    mat4 view_projection;
} uniforms;

void main() {
    gl_Position = uniforms.view_projection * vec4(a_position, 1.0);
    v_color = a_color;
}
