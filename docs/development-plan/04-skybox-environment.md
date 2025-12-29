# Skybox and Environment Rendering

## Overview

Implement comprehensive environment rendering including skyboxes, procedural skies, image-based lighting (IBL), environment probes, and atmospheric effects. These systems provide visual context and realistic ambient lighting for 3D scenes.

## Current State

ZDL currently has:
- No skybox or background rendering
- Single clear color for background
- No environment lighting
- No atmospheric effects

## Goals

- Render cubemap skyboxes
- Support HDR environment maps
- Implement procedural sky rendering
- Add image-based lighting for PBR
- Create reflection probes for local reflections
- Add atmospheric scattering effects
- Support dynamic time-of-day systems

## Architecture

### Directory Structure

```
src/
├── environment/
│   ├── environment.zig        # Module exports
│   ├── skybox.zig             # Cubemap skybox renderer
│   ├── procedural_sky.zig     # Procedural atmosphere
│   ├── ibl.zig                # Image-based lighting
│   ├── reflection_probe.zig   # Local reflection probes
│   ├── atmosphere.zig         # Atmospheric scattering
│   └── time_of_day.zig        # Day/night cycle
│
├── shaders/
│   └── environment/
│       ├── skybox.vert
│       ├── skybox.frag
│       ├── procedural_sky.frag
│       ├── atmosphere.frag
│       ├── irradiance.frag     # IBL preprocessing
│       ├── prefilter.frag      # Specular prefilter
│       └── brdf_lut.frag       # BRDF lookup table
```

### Core Components

#### Skybox Renderer

```zig
pub const Skybox = struct {
    cubemap: *TextureCube,
    pipeline: *Pipeline,
    cube_mesh: *Mesh,
    intensity: f32,
    rotation: f32,  // Y-axis rotation

    pub fn init(device: *Device) !Skybox;
    pub fn loadFromFiles(
        self: *Skybox,
        device: *Device,
        faces: [6][]const u8,  // +X, -X, +Y, -Y, +Z, -Z
    ) !void;
    pub fn loadFromHDR(self: *Skybox, device: *Device, path: []const u8) !void;
    pub fn loadFromEquirectangular(self: *Skybox, device: *Device, path: []const u8) !void;
    pub fn render(self: *Skybox, frame: *RenderFrame, view_proj: Mat4) void;
    pub fn deinit(self: *Skybox) void;
};

// Cubemap texture
pub const TextureCube = struct {
    gpu_texture: *sdl.gpu.Texture,
    size: u32,
    mip_levels: u32,
    format: TextureFormat,

    pub fn create(device: *Device, size: u32, format: TextureFormat, mips: bool) !TextureCube;
    pub fn uploadFace(self: *TextureCube, face: CubeFace, data: []const u8) !void;
};

pub const CubeFace = enum(u32) {
    positive_x = 0,
    negative_x = 1,
    positive_y = 2,
    negative_y = 3,
    positive_z = 4,
    negative_z = 5,
};
```

#### Skybox Shaders

```glsl
// skybox.vert
#version 450

layout(location = 0) in vec3 aPosition;
layout(location = 0) out vec3 vTexCoord;

layout(set = 0, binding = 0) uniform UBO {
    mat4 viewProjection;  // View without translation
    float rotation;
};

void main() {
    vTexCoord = aPosition;

    // Apply Y rotation
    float c = cos(rotation);
    float s = sin(rotation);
    vTexCoord.xz = mat2(c, -s, s, c) * vTexCoord.xz;

    vec4 pos = viewProjection * vec4(aPosition, 1.0);
    gl_Position = pos.xyww;  // Depth = 1.0 (far plane)
}

// skybox.frag
#version 450

layout(location = 0) in vec3 vTexCoord;
layout(location = 0) out vec4 fragColor;

layout(set = 1, binding = 0) uniform samplerCube skybox;

layout(set = 0, binding = 0) uniform UBO {
    mat4 viewProjection;
    float rotation;
    float intensity;
};

void main() {
    vec3 color = texture(skybox, vTexCoord).rgb * intensity;
    fragColor = vec4(color, 1.0);
}
```

### Procedural Sky

Hosek-Wilkie or Preetham atmospheric model:

```zig
pub const ProceduralSky = struct {
    pipeline: *Pipeline,
    params: SkyParams,

    pub const SkyParams = struct {
        sun_direction: Vec3,
        sun_intensity: f32,
        sun_size: f32,
        turbidity: f32,          // Atmospheric haze (2-10)
        ground_albedo: Vec3,
        rayleigh_coefficient: f32,
        mie_coefficient: f32,
        mie_directional_g: f32,
    };

    pub fn init(device: *Device) !ProceduralSky;
    pub fn update(self: *ProceduralSky, params: SkyParams) void;
    pub fn render(self: *ProceduralSky, frame: *RenderFrame, view_proj: Mat4) void;

    // Generate cubemap from procedural sky for IBL
    pub fn bakeToEnvironment(self: *ProceduralSky, size: u32) !*TextureCube;
};

// Shader uniforms
pub const SkyUniforms = extern struct {
    sun_direction: [3]f32,
    sun_intensity: f32,
    turbidity: f32,
    rayleigh: f32,
    mie_coefficient: f32,
    mie_directional_g: f32,
    sun_size: f32,
    _pad: [3]f32,
};
```

#### Procedural Sky Shader

```glsl
// procedural_sky.frag
#version 450

layout(location = 0) in vec3 vDirection;
layout(location = 0) out vec4 fragColor;

layout(set = 0, binding = 0) uniform SkyUBO {
    vec3 sunDirection;
    float sunIntensity;
    float turbidity;
    float rayleigh;
    float mieCoefficient;
    float mieDirectionalG;
    float sunAngularDiameter;
};

// Rayleigh and Mie scattering coefficients
vec3 totalRayleigh(float lambda) {
    return (8.0 * pow(PI, 3.0) * pow(pow(n, 2.0) - 1.0, 2.0) * (6.0 + 3.0 * pn)) /
           (3.0 * N * pow(lambda, 4.0) * (6.0 - 7.0 * pn));
}

float rayleighPhase(float cosTheta) {
    return (3.0 / (16.0 * PI)) * (1.0 + pow(cosTheta, 2.0));
}

float hgPhase(float cosTheta, float g) {
    return (1.0 / (4.0 * PI)) * ((1.0 - g * g) / pow(1.0 - 2.0 * g * cosTheta + g * g, 1.5));
}

void main() {
    vec3 direction = normalize(vDirection);
    float sunCos = dot(direction, sunDirection);

    // Atmospheric scattering
    vec3 betaR = totalRayleigh(vec3(680e-9, 550e-9, 450e-9)) * rayleigh;
    vec3 betaM = totalMie(turbidity) * mieCoefficient;

    float zenithAngle = acos(max(0.0, direction.y));
    float rayleighCoeff = rayleighPhase(sunCos);
    float mieCoeff = hgPhase(sunCos, mieDirectionalG);

    vec3 extinction = exp(-(betaR + betaM) * opticalDepth(zenithAngle));
    vec3 inscatter = (betaR * rayleighCoeff + betaM * mieCoeff) *
                     sunIntensity * (1.0 - extinction);

    vec3 color = inscatter;

    // Sun disc
    float sunDisc = smoothstep(cos(sunAngularDiameter), 1.0, sunCos);
    color += vec3(1.0, 0.9, 0.7) * sunDisc * sunIntensity;

    fragColor = vec4(color, 1.0);
}
```

### Image-Based Lighting (IBL)

Pre-compute environment maps for PBR:

```zig
pub const IBLGenerator = struct {
    device: *Device,
    irradiance_pipeline: *Pipeline,
    prefilter_pipeline: *Pipeline,
    brdf_pipeline: *Pipeline,

    pub fn init(device: *Device) !IBLGenerator;

    // Generate diffuse irradiance cubemap
    pub fn generateIrradianceMap(
        self: *IBLGenerator,
        environment: *TextureCube,
        size: u32,
    ) !*TextureCube;

    // Generate specular prefiltered cubemap
    pub fn generatePrefilterMap(
        self: *IBLGenerator,
        environment: *TextureCube,
        size: u32,
        mip_levels: u32,
    ) !*TextureCube;

    // Generate BRDF lookup texture
    pub fn generateBRDFLUT(self: *IBLGenerator, size: u32) !*Texture;
};

pub const EnvironmentMap = struct {
    skybox: *TextureCube,        // Original HDR environment
    irradiance: *TextureCube,    // Diffuse convolution (32x32)
    prefiltered: *TextureCube,   // Specular mip chain (128x128)
    brdf_lut: *Texture,          // BRDF lookup (512x512)

    pub fn loadFromHDR(device: *Device, path: []const u8) !EnvironmentMap;
    pub fn bindForPBR(self: *EnvironmentMap, frame: *RenderFrame) void;
};
```

#### IBL Shaders

```glsl
// irradiance.frag - Convolve environment for diffuse lighting
#version 450

layout(location = 0) in vec3 localPos;
layout(location = 0) out vec4 fragColor;

layout(set = 0, binding = 0) uniform samplerCube environmentMap;

const float PI = 3.14159265359;

void main() {
    vec3 normal = normalize(localPos);
    vec3 irradiance = vec3(0.0);

    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, normal));
    up = normalize(cross(normal, right));

    float sampleDelta = 0.025;
    int nrSamples = 0;

    for (float phi = 0.0; phi < 2.0 * PI; phi += sampleDelta) {
        for (float theta = 0.0; theta < 0.5 * PI; theta += sampleDelta) {
            vec3 tangentSample = vec3(
                sin(theta) * cos(phi),
                sin(theta) * sin(phi),
                cos(theta)
            );
            vec3 sampleVec = tangentSample.x * right +
                            tangentSample.y * up +
                            tangentSample.z * normal;

            irradiance += texture(environmentMap, sampleVec).rgb *
                         cos(theta) * sin(theta);
            nrSamples++;
        }
    }
    irradiance = PI * irradiance * (1.0 / float(nrSamples));

    fragColor = vec4(irradiance, 1.0);
}

// prefilter.frag - Specular prefilter with roughness
#version 450

layout(location = 0) in vec3 localPos;
layout(location = 0) out vec4 fragColor;

layout(set = 0, binding = 0) uniform samplerCube environmentMap;
layout(push_constant) uniform PC { float roughness; };

void main() {
    vec3 N = normalize(localPos);
    vec3 R = N;
    vec3 V = R;

    const uint SAMPLE_COUNT = 1024u;
    vec3 prefilteredColor = vec3(0.0);
    float totalWeight = 0.0;

    for (uint i = 0u; i < SAMPLE_COUNT; ++i) {
        vec2 Xi = hammersley(i, SAMPLE_COUNT);
        vec3 H = importanceSampleGGX(Xi, N, roughness);
        vec3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0) {
            prefilteredColor += texture(environmentMap, L).rgb * NdotL;
            totalWeight += NdotL;
        }
    }
    prefilteredColor = prefilteredColor / totalWeight;

    fragColor = vec4(prefilteredColor, 1.0);
}
```

### Reflection Probes

Local environment mapping:

```zig
pub const ReflectionProbe = struct {
    position: Vec3,
    bounds: AABB,                // Influence area
    cubemap: *TextureCube,
    irradiance: *TextureCube,
    prefiltered: *TextureCube,
    priority: i32,              // Higher = preferred
    blend_distance: f32,        // Fade at edges

    pub fn capture(self: *ReflectionProbe, scene: *Scene, renderer: *Renderer) !void;
    pub fn processIBL(self: *ReflectionProbe, generator: *IBLGenerator) !void;
};

pub const ReflectionProbeSystem = struct {
    probes: std.ArrayList(*ReflectionProbe),
    global_probe: ?*ReflectionProbe,  // Fallback/sky

    pub fn findProbesForPosition(self: *ReflectionProbeSystem, pos: Vec3) []ProbeWeight;
    pub fn blendProbes(probes: []ProbeWeight, roughness: f32) Vec3;
};

pub const ProbeWeight = struct {
    probe: *ReflectionProbe,
    weight: f32,
};
```

### Atmospheric Effects

Advanced scattering simulation:

```zig
pub const Atmosphere = struct {
    // Physical parameters
    planet_radius: f32,          // 6371km for Earth
    atmosphere_height: f32,      // ~100km
    rayleigh_scale_height: f32,  // 8.5km
    mie_scale_height: f32,       // 1.2km

    // Scattering coefficients
    rayleigh_scattering: Vec3,   // Wavelength-dependent
    mie_scattering: f32,
    mie_absorption: f32,
    ozone_absorption: Vec3,

    // Rendering
    transmittance_lut: *Texture,
    multiscatter_lut: *Texture,
    sky_view_lut: *Texture,
    aerial_perspective_lut: *Texture3D,

    pub fn precompute(self: *Atmosphere, device: *Device) !void;
    pub fn render(self: *Atmosphere, frame: *RenderFrame, camera: *Camera) void;
};
```

### Time of Day

Dynamic sky system:

```zig
pub const TimeOfDay = struct {
    time: f32,                   // 0-24 hours
    speed_multiplier: f32,       // Real-time = 1.0
    latitude: f32,               // For accurate sun position
    day_of_year: u32,

    // Computed
    sun_direction: Vec3,
    moon_direction: Vec3,
    sun_color: Vec3,
    ambient_color: Vec3,

    // References
    sky: *ProceduralSky,
    main_light: *LightComponent,

    pub fn update(self: *TimeOfDay, delta_time: f32) void;
    pub fn setTime(self: *TimeOfDay, hours: f32) void;

    // Sun position calculation
    fn calculateSunPosition(self: *TimeOfDay) Vec3;
};

pub const TimeOfDayPreset = struct {
    time: f32,
    sun_color: Vec3,
    sun_intensity: f32,
    ambient_color: Vec3,
    fog_color: Vec3,
    fog_density: f32,
};

pub const TimeOfDayPresets = struct {
    pub const dawn = TimeOfDayPreset{ .time = 6.0, ... };
    pub const noon = TimeOfDayPreset{ .time = 12.0, ... };
    pub const sunset = TimeOfDayPreset{ .time = 18.0, ... };
    pub const midnight = TimeOfDayPreset{ .time = 0.0, ... };
};
```

## Implementation Steps

### Phase 1: Basic Skybox
1. Create cubemap texture type
2. Implement skybox mesh (inside-out cube)
3. Create skybox shader with depth at far plane
4. Load 6-face cubemap images
5. Integrate with render pipeline (render last)

### Phase 2: HDR Environment
1. Implement equirectangular to cubemap conversion
2. Add HDR (.hdr/.exr) image loading
3. Support exposure/intensity control
4. Add skybox rotation

### Phase 3: Procedural Sky
1. Implement Preetham/Hosek-Wilkie atmosphere model
2. Create procedural sky shader
3. Add sun disc rendering
4. Support day/night parameters

### Phase 4: Image-Based Lighting
1. Implement irradiance map generation
2. Create specular prefilter with roughness mips
3. Generate BRDF lookup texture
4. Integrate with PBR shader

### Phase 5: Reflection Probes
1. Create probe capture system
2. Implement probe blending
3. Add box projection correction
4. Support dynamic probe updates

### Phase 6: Advanced Atmosphere
1. Implement LUT-based atmosphere rendering
2. Add aerial perspective
3. Support clouds (separate system)
4. Implement god rays from sun

### Phase 7: Time of Day
1. Calculate accurate sun/moon positions
2. Interpolate sky parameters over time
3. Update lighting automatically
4. Support preset-based transitions

## Integration Points

### Scene Component

```zig
// Environment component for scene-wide settings
pub const EnvironmentComponent = struct {
    mode: EnvironmentMode,
    skybox: ?*Skybox,
    procedural_sky: ?*ProceduralSky,
    environment_map: ?*EnvironmentMap,
    ambient_intensity: f32,
    fog: ?FogSettings,
};

pub const EnvironmentMode = enum {
    solid_color,
    cubemap_skybox,
    procedural,
    hdri,
};
```

### Render System Integration

```zig
// In render loop
pub fn renderScene(frame: *RenderFrame, scene: *Scene) void {
    // 1. Render opaque objects
    renderOpaqueObjects(frame, scene);

    // 2. Render skybox/environment (depth test, no depth write)
    if (scene.environment) |env| {
        env.render(frame, camera);
    }

    // 3. Render transparent objects
    renderTransparentObjects(frame, scene);
}
```

### PBR Integration

```glsl
// In PBR shader
vec3 calculateAmbientIBL(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness) {
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 F = fresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);

    vec3 kS = F;
    vec3 kD = (1.0 - kS) * (1.0 - metallic);

    // Diffuse IBL
    vec3 irradiance = texture(irradianceMap, N).rgb;
    vec3 diffuse = irradiance * albedo;

    // Specular IBL
    vec3 R = reflect(-V, N);
    float MAX_REFLECTION_LOD = 4.0;
    vec3 prefilteredColor = textureLod(prefilterMap, R, roughness * MAX_REFLECTION_LOD).rgb;
    vec2 brdf = texture(brdfLUT, vec2(max(dot(N, V), 0.0), roughness)).rg;
    vec3 specular = prefilteredColor * (F * brdf.x + brdf.y);

    return kD * diffuse + specular;
}
```

## Performance Considerations

- **Skybox LOD**: Use lower resolution for distant views
- **IBL Precomputation**: Generate at load time or in background
- **Probe Updates**: Spread capture across frames
- **LUT Caching**: Store precomputed atmospheric LUTs
- **Mip Levels**: Use appropriate mip for roughness
- **Half Resolution**: Render atmosphere at reduced resolution

## References

- [LearnOpenGL IBL](https://learnopengl.com/PBR/IBL/Diffuse-irradiance)
- [Hosek-Wilkie Sky Model](https://cgg.mff.cuni.cz/projects/SkylightModelling/)
- [Precomputed Atmospheric Scattering](https://ebruneton.github.io/precomputed_atmospheric_scattering/)
- [A Scalable and Production Ready Sky and Atmosphere Rendering Technique](https://sebh.github.io/publications/egsr2020.pdf)
- [Real-Time Polygonal-Light Shading with Linearly Transformed Cosines](https://eheitzresearch.wordpress.com/415-2/)
