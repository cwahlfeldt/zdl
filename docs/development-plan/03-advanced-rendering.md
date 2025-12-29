# Advanced Rendering System

## Overview

Evolve ZDL's rendering capabilities from basic immediate-mode rendering to a full-featured graphics pipeline supporting physically-based rendering (PBR), multiple render passes, post-processing, and advanced techniques like ray marching and ray tracing.

## Current State

ZDL currently has:
- Single forward rendering pass
- Basic MVP uniform-based rendering
- One active camera
- No lighting calculations in shaders (LightComponent exists but unused)
- Immediate-mode draw calls (no batching/sorting)
- Fixed shader pipeline (compile-time only)

## Goals

- Implement PBR lighting model
- Support multiple light types (directional, point, spot)
- Add shadow mapping
- Implement post-processing pipeline
- Support deferred rendering option
- Add compute shader support
- Enable ray marching for volumetric effects
- Prepare architecture for hardware ray tracing
- Maintain cross-platform support (Vulkan/Metal)

## Architecture

### Directory Structure

```
src/
├── rendering/
│   ├── rendering.zig           # Module exports
│   ├── render_graph.zig        # Render pass graph
│   ├── render_pass.zig         # Pass abstraction
│   ├── render_queue.zig        # Sorted draw queue
│   ├── material_system.zig     # Runtime materials
│   ├── shader_system.zig       # Shader management
│   │
│   ├── forward/
│   │   ├── forward_renderer.zig
│   │   └── forward_pass.zig
│   │
│   ├── deferred/
│   │   ├── deferred_renderer.zig
│   │   ├── gbuffer.zig
│   │   └── lighting_pass.zig
│   │
│   ├── lighting/
│   │   ├── lighting.zig
│   │   ├── pbr.zig
│   │   ├── shadows.zig
│   │   └── light_culling.zig
│   │
│   ├── post_processing/
│   │   ├── post_process.zig
│   │   ├── bloom.zig
│   │   ├── tonemapping.zig
│   │   ├── ssao.zig
│   │   ├── fxaa.zig
│   │   └── motion_blur.zig
│   │
│   └── advanced/
│       ├── ray_marching.zig
│       ├── volumetrics.zig
│       └── ray_tracing.zig
│
├── shaders/
│   ├── common/
│   │   ├── uniforms.glsl
│   │   ├── pbr_functions.glsl
│   │   └── lighting.glsl
│   ├── forward/
│   │   ├── pbr.vert
│   │   └── pbr.frag
│   ├── deferred/
│   │   ├── gbuffer.vert
│   │   ├── gbuffer.frag
│   │   └── deferred_lighting.frag
│   ├── shadows/
│   │   ├── shadow_map.vert
│   │   └── shadow_map.frag
│   ├── post/
│   │   ├── fullscreen.vert
│   │   ├── bloom.frag
│   │   ├── tonemap.frag
│   │   └── fxaa.frag
│   └── compute/
│       └── light_culling.comp
```

### Core Systems

#### Render Graph

Define rendering pipeline as a directed acyclic graph:

```zig
pub const RenderGraph = struct {
    allocator: Allocator,
    passes: std.ArrayList(RenderPass),
    resources: ResourcePool,
    execution_order: []usize,

    pub fn addPass(self: *RenderGraph, pass: RenderPass) PassHandle;
    pub fn addDependency(self: *RenderGraph, from: PassHandle, to: PassHandle) void;
    pub fn compile(self: *RenderGraph) !void;
    pub fn execute(self: *RenderGraph, frame: *RenderFrame, scene: *Scene) !void;
};

pub const RenderPass = struct {
    name: []const u8,
    execute_fn: fn(*RenderPass, *RenderFrame, *Scene) void,
    inputs: []ResourceHandle,
    outputs: []ResourceHandle,
    pipeline: ?*Pipeline,
};

pub const ResourceHandle = struct {
    id: u32,
    resource_type: ResourceType,
};

pub const ResourceType = enum {
    texture_2d,
    texture_cube,
    buffer,
    depth_stencil,
};
```

#### Render Queue

Sort and batch draw calls for efficiency:

```zig
pub const RenderQueue = struct {
    items: std.ArrayList(RenderItem),
    sort_key_fn: fn(*RenderItem) u64,

    pub fn clear(self: *RenderQueue) void;
    pub fn submit(self: *RenderQueue, item: RenderItem) void;
    pub fn sort(self: *RenderQueue) void;
    pub fn execute(self: *RenderQueue, frame: *RenderFrame) void;
};

pub const RenderItem = struct {
    mesh: *Mesh,
    material: *Material,
    transform: Mat4,
    sort_key: u64,  // Encodes: layer, material, depth

    pub fn computeSortKey(self: *RenderItem, camera_pos: Vec3) u64 {
        // Front-to-back for opaque, back-to-front for transparent
        const depth = self.transform.position.sub(camera_pos).length();
        const material_id = @intCast(u32, @ptrToInt(self.material));
        return (@as(u64, self.material.layer) << 48) |
               (@as(u64, material_id) << 16) |
               @floatToInt(u16, depth);
    }
};
```

#### Material System

Runtime material management with shader variants:

```zig
pub const Material = struct {
    shader: *Shader,
    properties: MaterialProperties,
    textures: [8]?*Texture,
    render_state: RenderState,

    pub fn setProperty(self: *Material, name: []const u8, value: PropertyValue) void;
    pub fn bind(self: *Material, frame: *RenderFrame) void;
};

pub const MaterialProperties = struct {
    // PBR properties
    base_color: Vec4 = Vec4.init(1, 1, 1, 1),
    metallic: f32 = 0.0,
    roughness: f32 = 0.5,
    emissive: Vec3 = Vec3.zero(),
    normal_scale: f32 = 1.0,

    // Additional
    alpha_cutoff: f32 = 0.5,
    uv_scale: Vec2 = Vec2.init(1, 1),
};

pub const RenderState = struct {
    cull_mode: CullMode = .back,
    blend_mode: BlendMode = .opaque,
    depth_write: bool = true,
    depth_test: bool = true,
};
```

### PBR Lighting

#### Light Uniforms

```zig
pub const LightUniforms = extern struct {
    // Directional light
    directional_direction: [3]f32,
    directional_intensity: f32,
    directional_color: [3]f32,
    _pad1: f32,

    // Point lights (up to MAX_POINT_LIGHTS)
    point_positions: [MAX_POINT_LIGHTS][4]f32,
    point_colors: [MAX_POINT_LIGHTS][4]f32,  // rgb + intensity
    point_count: u32,

    // Environment
    ambient_color: [3]f32,
    ambient_intensity: f32,

    // Camera
    camera_position: [3]f32,
    _pad2: f32,
};

pub const MAX_POINT_LIGHTS = 128;
```

#### PBR Shader (GLSL Fragment)

```glsl
// pbr.frag
#version 450

layout(location = 0) in vec3 fragPosition;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;
layout(location = 3) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

// Material textures
layout(set = 1, binding = 0) uniform sampler2D albedoMap;
layout(set = 1, binding = 1) uniform sampler2D normalMap;
layout(set = 1, binding = 2) uniform sampler2D metallicRoughnessMap;
layout(set = 1, binding = 3) uniform sampler2D aoMap;
layout(set = 1, binding = 4) uniform sampler2D emissiveMap;

// Material properties
layout(set = 1, binding = 5) uniform MaterialUBO {
    vec4 baseColorFactor;
    float metallicFactor;
    float roughnessFactor;
    vec3 emissiveFactor;
    float normalScale;
    float aoStrength;
};

// Lighting
layout(set = 2, binding = 0) uniform LightUBO { ... };

// PBR Functions
vec3 fresnelSchlick(float cosTheta, vec3 F0);
float distributionGGX(vec3 N, vec3 H, float roughness);
float geometrySmith(vec3 N, vec3 V, vec3 L, float roughness);
vec3 calculatePBR(vec3 albedo, float metallic, float roughness,
                  vec3 N, vec3 V, vec3 L, vec3 radiance);

void main() {
    // Sample textures
    vec4 albedo = texture(albedoMap, fragUV) * baseColorFactor;
    vec3 normal = getNormalFromMap();
    vec2 mr = texture(metallicRoughnessMap, fragUV).bg;
    float metallic = mr.x * metallicFactor;
    float roughness = mr.y * roughnessFactor;
    float ao = texture(aoMap, fragUV).r;
    vec3 emissive = texture(emissiveMap, fragUV).rgb * emissiveFactor;

    vec3 N = normalize(normal);
    vec3 V = normalize(cameraPosition - fragPosition);

    // Calculate lighting
    vec3 Lo = vec3(0.0);

    // Directional light
    Lo += calculateDirectionalLight(N, V, albedo.rgb, metallic, roughness);

    // Point lights
    for (int i = 0; i < pointLightCount; i++) {
        Lo += calculatePointLight(i, N, V, albedo.rgb, metallic, roughness);
    }

    // Ambient
    vec3 ambient = ambientColor * ambientIntensity * albedo.rgb * ao;

    vec3 color = ambient + Lo + emissive;

    outColor = vec4(color, albedo.a);
}
```

### Shadow Mapping

#### Shadow System

```zig
pub const ShadowSystem = struct {
    shadow_map: *Texture,
    shadow_pipeline: *Pipeline,
    light_space_matrix: Mat4,
    resolution: u32,
    bias: f32,
    cascade_count: u32,  // For CSM

    pub fn init(device: *Device, resolution: u32) !ShadowSystem;
    pub fn updateLightMatrix(self: *ShadowSystem, light: *LightComponent, camera: *Camera) void;
    pub fn renderShadowMap(self: *ShadowSystem, frame: *RenderFrame, scene: *Scene) void;
};

// Cascaded Shadow Maps for large outdoor scenes
pub const CascadedShadowMap = struct {
    cascades: [4]Cascade,

    pub const Cascade = struct {
        shadow_map: *Texture,
        view_proj: Mat4,
        split_depth: f32,
    };
};
```

### Post-Processing Pipeline

#### Post-Process Manager

```zig
pub const PostProcessPipeline = struct {
    effects: std.ArrayList(*PostProcessEffect),
    ping_pong_buffers: [2]*Texture,
    fullscreen_quad: *Mesh,

    pub fn addEffect(self: *PostProcessPipeline, effect: *PostProcessEffect) void;
    pub fn removeEffect(self: *PostProcessPipeline, effect: *PostProcessEffect) void;
    pub fn process(self: *PostProcessPipeline, frame: *RenderFrame, input: *Texture) *Texture;
};

pub const PostProcessEffect = struct {
    name: []const u8,
    enabled: bool,
    shader: *Shader,
    uniforms: []const u8,

    pub fn apply(self: *PostProcessEffect, frame: *RenderFrame, input: *Texture, output: *Texture) void;
};
```

#### Common Effects

```zig
// Bloom effect
pub const BloomEffect = struct {
    threshold: f32 = 1.0,
    intensity: f32 = 1.0,
    blur_passes: u32 = 5,
    downsample_textures: [6]*Texture,
};

// Tone mapping
pub const TonemapEffect = struct {
    mode: TonemapMode = .aces,
    exposure: f32 = 1.0,
    gamma: f32 = 2.2,

    pub const TonemapMode = enum {
        reinhard,
        aces,
        uncharted2,
        exposure,
    };
};

// SSAO
pub const SSAOEffect = struct {
    radius: f32 = 0.5,
    bias: f32 = 0.025,
    kernel_size: u32 = 64,
    noise_texture: *Texture,
    kernel: [64]Vec3,
};

// FXAA
pub const FXAAEffect = struct {
    edge_threshold: f32 = 0.166,
    edge_threshold_min: f32 = 0.0833,
    subpixel_quality: f32 = 0.75,
};
```

### Deferred Rendering

#### G-Buffer

```zig
pub const GBuffer = struct {
    // Render targets
    albedo: *Texture,          // RGB: albedo, A: ?
    normal: *Texture,          // RGB: world normal (encoded)
    material: *Texture,        // R: metallic, G: roughness, B: AO
    depth: *Texture,           // Depth buffer
    emissive: *Texture,        // RGB: emissive

    framebuffer: *Framebuffer,

    pub fn init(device: *Device, width: u32, height: u32) !GBuffer;
    pub fn resize(self: *GBuffer, width: u32, height: u32) !void;
    pub fn bind(self: *GBuffer, frame: *RenderFrame) void;
};
```

#### Deferred Renderer

```zig
pub const DeferredRenderer = struct {
    gbuffer: GBuffer,
    gbuffer_pass: *Pipeline,
    lighting_pass: *Pipeline,
    light_volumes: LightVolumes,

    pub fn geometryPass(self: *DeferredRenderer, frame: *RenderFrame, scene: *Scene) void;
    pub fn lightingPass(self: *DeferredRenderer, frame: *RenderFrame) void;
    pub fn forwardPass(self: *DeferredRenderer, frame: *RenderFrame, scene: *Scene) void;  // Transparent objects
};
```

### Ray Marching

For volumetric effects (clouds, fog, god rays):

```zig
pub const RayMarchingEffect = struct {
    volume_texture: ?*Texture3D,
    step_count: u32 = 64,
    step_size: f32 = 0.01,

    // Volumetric fog
    fog_density: f32 = 0.1,
    fog_color: Vec3,
    fog_height_falloff: f32 = 0.5,

    // God rays
    god_ray_intensity: f32 = 1.0,
    god_ray_decay: f32 = 0.95,

    pub fn render(self: *RayMarchingEffect, frame: *RenderFrame, depth: *Texture) void;
};
```

Ray marching shader:
```glsl
// ray_march.frag
vec4 raymarchVolume(vec3 rayOrigin, vec3 rayDir, float maxDist) {
    vec4 accumulated = vec4(0.0);
    float t = 0.0;

    for (int i = 0; i < MAX_STEPS && t < maxDist; i++) {
        vec3 pos = rayOrigin + rayDir * t;
        float density = sampleDensity(pos);

        if (density > 0.001) {
            vec3 lighting = calculateVolumetricLighting(pos);
            vec4 sample = vec4(lighting * density, density);
            sample.rgb *= sample.a;
            accumulated += sample * (1.0 - accumulated.a);
        }

        t += stepSize;
    }

    return accumulated;
}
```

### Ray Tracing (Future)

Architecture preparation for hardware RT:

```zig
pub const RayTracingSupport = struct {
    // Feature detection
    pub fn isSupported(device: *Device) bool;

    // Acceleration structures
    blas: std.ArrayList(BLAS),  // Bottom-level (per mesh)
    tlas: TLAS,                  // Top-level (scene)

    pub fn buildBLAS(self: *RayTracingSupport, mesh: *Mesh) !*BLAS;
    pub fn buildTLAS(self: *RayTracingSupport, instances: []Instance) !void;
    pub fn traceRays(self: *RayTracingSupport, frame: *RenderFrame) void;
};

// Ray tracing pipelines
pub const RTMode = enum {
    reflections,    // RT reflections only
    shadows,        // RT shadows
    gi,             // Global illumination
    path_traced,    // Full path tracing
};
```

## Implementation Steps

### Phase 1: Render Infrastructure
1. Implement render queue with sorting
2. Create material system with properties
3. Add shader management and variants
4. Implement basic render graph

### Phase 2: PBR Lighting
1. Create PBR shaders with proper BRDF
2. Implement point light support
3. Add spot lights with cone attenuation
4. Create light culling for many lights

### Phase 3: Shadows
1. Implement basic shadow mapping
2. Add PCF soft shadows
3. Implement cascaded shadow maps
4. Add shadow bias and slope scale

### Phase 4: Post-Processing
1. Create post-process pipeline
2. Implement bloom effect
3. Add tone mapping operators
4. Implement FXAA anti-aliasing

### Phase 5: Deferred Rendering (Optional Path)
1. Create G-buffer render targets
2. Implement geometry pass
3. Create deferred lighting pass
4. Handle transparent objects with forward pass

### Phase 6: Advanced Effects
1. Implement SSAO
2. Add screen-space reflections
3. Create volumetric fog with ray marching
4. Add motion blur

### Phase 7: Ray Tracing Preparation
1. Abstract acceleration structure building
2. Create ray tracing pipeline interface
3. Implement hybrid rendering path

## Integration Points

### Engine Integration

```zig
pub const Engine = struct {
    renderer: Renderer,

    pub const Renderer = union(enum) {
        forward: *ForwardRenderer,
        deferred: *DeferredRenderer,
    };

    pub fn setRenderMode(self: *Engine, mode: RenderMode) !void;
};
```

### ECS Integration

```zig
// Extended light component
pub const LightComponent = struct {
    light_type: LightType,
    color: Vec3,
    intensity: f32,
    range: f32,
    inner_cone: f32,
    outer_cone: f32,
    cast_shadows: bool,
    shadow_resolution: u32,
};

// Material component
pub const MaterialComponent = struct {
    material: *Material,
};
```

## Performance Considerations

- **Light Culling**: Tile-based or clustered for many lights
- **Instancing**: Batch identical meshes
- **LOD**: Reduce geometry for distant objects
- **Occlusion Culling**: Skip hidden objects
- **Async Compute**: Shadow maps and post-processing in parallel
- **Resolution Scaling**: Dynamic resolution for consistent frame times

## Platform Considerations

- **Vulkan**: Full feature set, compute shaders, ray tracing
- **Metal**: Compute shaders, ray tracing on Apple Silicon
- **Mobile**: Reduced feature set, lower resolution, simpler effects

## References

- [LearnOpenGL PBR](https://learnopengl.com/PBR/Theory)
- [Filament Rendering](https://google.github.io/filament/Filament.html)
- [Real-Time Rendering 4th Edition](https://www.realtimerendering.com/)
- [GPU Gems - Volumetric Rendering](https://developer.nvidia.com/gpugems)
- [DX12 Ray Tracing Tutorial](https://microsoft.github.io/DirectX-Specs/d3d/Raytracing.html)
