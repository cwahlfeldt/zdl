#version 450

layout (location = 0) in vec3 v_dir;
layout (location = 0) out vec4 out_color;

layout (set = 2, binding = 0) uniform samplerCube u_skybox;

void main() {
    vec3 color = texture(u_skybox, normalize(v_dir)).rgb;

    // ACES filmic tonemapping
    vec3 x = color;
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    color = clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);

    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));

    out_color = vec4(color, 1.0);
}
