#version 450

layout (location = 0) in vec3 v_normal;
layout (location = 1) in vec2 v_uv;
layout (location = 2) in vec4 v_color;
layout (location = 3) in vec3 v_frag_pos;

layout (location = 0) out vec4 out_color;

layout (set = 2, binding = 0) uniform sampler2D u_texture;

void main() {
    // Simple directional light
    vec3 light_dir = normalize(vec3(0.5, 1.0, 0.3));
    vec3 normal = normalize(v_normal);

    // Ambient
    float ambient_strength = 0.3;
    vec3 ambient = ambient_strength * vec3(1.0, 1.0, 1.0);

    // Diffuse
    float diff = max(dot(normal, light_dir), 0.0);
    vec3 diffuse = diff * vec3(1.0, 1.0, 1.0);

    // Combine lighting with texture and vertex color
    vec4 tex_color = texture(u_texture, v_uv);
    vec3 lighting = ambient + diffuse;
    out_color = vec4(lighting, 1.0) * tex_color * v_color;
}
