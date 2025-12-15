#version 450

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec4 a_color;
layout (location = 0) out vec4 v_color;

// Uniform block for MVP matrix
// Try set 1 for vertex uniforms
layout (set = 1, binding = 0, std140) uniform Uniforms {
    mat4 mvp;
} uniforms;

void main() {
    gl_Position = uniforms.mvp * vec4(a_position, 1.0);
    v_color = a_color;
}