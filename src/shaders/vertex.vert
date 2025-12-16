#version 450

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec4 a_color;
layout (location = 2) in vec2 a_uv;

layout (location = 0) out vec4 v_color;
layout (location = 1) out vec2 v_uv;

// Uniform block for MVP matrix
layout (set = 1, binding = 0, std140) uniform Uniforms {
    mat4 mvp;
} uniforms;

void main() {
    gl_Position = uniforms.mvp * vec4(a_position, 1.0);
    v_color = a_color;
    v_uv = a_uv;
}