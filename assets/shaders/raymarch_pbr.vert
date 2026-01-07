#version 450

layout (location = 0) in vec3 a_pos;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec2 a_uv;
layout (location = 3) in vec4 a_color;

layout (location = 0) out vec3 v_world_pos;

layout (set = 1, binding = 0, std140) uniform Uniforms {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo;

void main() {
    vec4 world_pos = ubo.model * vec4(a_pos, 1.0);
    v_world_pos = world_pos.xyz;
    gl_Position = ubo.projection * ubo.view * world_pos;
}
