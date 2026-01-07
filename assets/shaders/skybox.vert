#version 450

layout (location = 0) in vec3 a_position;

layout (location = 0) out vec3 v_dir;

// MVP uniforms (vertex uniform buffer 0)
layout (set = 1, binding = 0, std140) uniform Uniforms {
    mat4 model;
    mat4 view;
    mat4 projection;
} uniforms;

void main() {
    mat4 view = uniforms.view;
    view[3].xyz = vec3(0.0);

    vec4 pos = uniforms.projection * view * vec4(a_position, 1.0);
    gl_Position = pos.xyww;
    v_dir = a_position;
}
