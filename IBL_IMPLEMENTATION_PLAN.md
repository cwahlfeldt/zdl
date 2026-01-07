# IBL (Image-Based Lighting) Implementation Plan

This document outlines the plan for adding Image-Based Lighting to the ZDL engine's PBR rendering system. IBL will replace the current procedural sky/ground ambient approximation with proper environment map sampling, providing realistic reflections and ambient lighting.

## Overview

**Goal:** Implement IBL using pre-filtered environment maps and BRDF integration lookup tables (split-sum approximation) for high-quality environment lighting.

**Target Demo:** `examples/pbr_demo/` will be updated to showcase IBL with HDR environment maps.

**Current State:** The PBR shader ([assets/shaders/pbr.frag:292-315](assets/shaders/pbr.frag#L292-L315)) uses a procedural sky/ground gradient for ambient lighting. This works but lacks realism for reflective materials.

---

## Architecture

### Split-Sum Approximation

IBL uses the split-sum approximation to avoid expensive real-time integration:

```
L_specular = ∫ L_i(l) * f(l,v) * (n·l) dl
           ≈ (Pre-filtered Environment) × (BRDF Integration LUT)
```

**Required Textures:**
1. **Irradiance Map** - Diffuse IBL (low-res cubemap, ~32x32 per face)
2. **Pre-filtered Environment Map** - Specular IBL (cubemap with mip levels for roughness)
3. **BRDF LUT** - 2D texture (NdotV × roughness → scale, bias)

### File Structure

```
src/
├── ibl/
│   ├── ibl.zig                    # Module exports
│   ├── environment_map.zig        # Cubemap loading and management
│   ├── ibl_baker.zig              # Pre-filtering (optional, can use offline tools)
│   └── brdf_lut.zig               # BRDF LUT generation
├── resources/
│   └── cubemap.zig                # Cubemap texture type (new)

assets/
├── environments/                  # HDR environment maps
│   ├── studio.hdr                 # Example indoor environment
│   └── outdoor.hdr                # Example outdoor environment
├── shaders/
│   ├── pbr.frag                   # Updated with IBL sampling
│   ├── pbr.metal                  # Updated Metal version
│   ├── equirect_to_cube.frag      # HDR equirectangular → cubemap
│   ├── irradiance.frag            # Irradiance convolution
│   ├── prefilter.frag             # Pre-filter environment
│   └── brdf_lut.frag              # BRDF integration LUT

tools/
└── asset_pipeline/
    └── ibl_baker.zig              # Offline IBL baking tool
```

---

## Implementation Steps

### Phase 1: Core Infrastructure

#### 1.1 Cubemap Texture Support

Create `src/resources/cubemap.zig`:

```zig
pub const Cubemap = struct {
    texture: sdl.gpu.Texture,
    size: u32,
    mip_levels: u32,
    format: sdl.gpu.TextureFormat,

    pub fn init(device: *sdl.gpu.Device, size: u32, mip_levels: u32, format: sdl.gpu.TextureFormat) !Cubemap;
    pub fn deinit(self: *Cubemap, device: *sdl.gpu.Device) void;
    pub fn uploadFace(self: *Cubemap, device: *sdl.gpu.Device, face: CubeFace, mip: u32, data: []const u8) !void;
};

pub const CubeFace = enum(u32) {
    positive_x = 0,  // Right
    negative_x = 1,  // Left
    positive_y = 2,  // Top
    negative_y = 3,  // Bottom
    positive_z = 4,  // Front
    negative_z = 5,  // Back
};
```

**Tasks:**
- [ ] Add `SDL_GPU_TEXTURETYPE_CUBE` support to texture creation
- [ ] Handle 6-face upload with proper layer indexing
- [ ] Support mipmap levels for pre-filtered environment

#### 1.2 BRDF LUT Generation

Create `src/ibl/brdf_lut.zig`:

```zig
pub const BrdfLut = struct {
    texture: *Texture,

    pub fn generate(allocator: Allocator, device: *sdl.gpu.Device, size: u32) !BrdfLut;
    pub fn deinit(self: *BrdfLut, allocator: Allocator, device: *sdl.gpu.Device) void;
};
```

The BRDF LUT is view-angle and roughness independent of the environment, so it can be:
- Generated once at engine init
- Pre-baked and loaded from disk
- Shared across all materials

**BRDF LUT Shader** (`assets/shaders/brdf_lut.frag`):
```glsl
// Importance sampling of GGX distribution
// Integrates (F * G * vis) and (G * vis) for split-sum
vec2 integrateBRDF(float NdotV, float roughness) {
    // Hammersley sequence for quasi-random sampling
    // GGX importance sampling
    // Returns (scale, bias) for F0 * scale + bias
}
```

#### 1.3 Environment Map Loading

Create `src/ibl/environment_map.zig`:

```zig
pub const EnvironmentMap = struct {
    irradiance: Cubemap,          // Diffuse IBL (32x32)
    prefiltered: Cubemap,         // Specular IBL (256x256, 5 mip levels)
    max_mip_level: f32,           // For roughness → mip mapping

    pub fn loadFromHDR(allocator: Allocator, device: *sdl.gpu.Device, path: []const u8) !EnvironmentMap;
    pub fn loadPrecomputed(allocator: Allocator, device: *sdl.gpu.Device, irr_path: []const u8, prefilter_path: []const u8) !EnvironmentMap;
    pub fn deinit(self: *EnvironmentMap, allocator: Allocator, device: *sdl.gpu.Device) void;
};
```

**Tasks:**
- [ ] HDR file loading (Radiance .hdr format)
- [ ] Equirectangular → cubemap conversion shader
- [ ] Irradiance convolution shader
- [ ] Pre-filter convolution shader (per mip level)

---

### Phase 2: Shader Integration

#### 2.1 Update PBR Fragment Shader

Modify [assets/shaders/pbr.frag](assets/shaders/pbr.frag):

**Add new samplers:**
```glsl
// IBL textures (fragment sampler set - new bindings)
layout (set = 2, binding = 5) uniform samplerCube u_irradiance_map;
layout (set = 2, binding = 6) uniform samplerCube u_prefiltered_env;
layout (set = 2, binding = 7) uniform sampler2D u_brdf_lut;
```

**Add IBL uniforms:**
```glsl
// In LightUBO or new IBL UBO
float env_intensity;           // Environment map intensity multiplier
float max_reflection_lod;      // Max mip level for prefiltered map
uint use_ibl;                  // Flag to enable/disable IBL
```

**Replace ambient calculation (lines 292-315):**
```glsl
vec3 calculateIBL(vec3 N, vec3 V, vec3 albedo, float metallic, float roughness, vec3 F0, float ao) {
    float NdotV = max(dot(N, V), 0.0);
    vec3 R = reflect(-V, N);

    // Fresnel with roughness for ambient
    vec3 F = fresnelSchlickRoughness(NdotV, F0, roughness);

    // Diffuse IBL
    vec3 kD = (1.0 - F) * (1.0 - metallic);
    vec3 irradiance = texture(u_irradiance_map, N).rgb;
    vec3 diffuse = kD * irradiance * albedo;

    // Specular IBL
    float lod = roughness * max_reflection_lod;
    vec3 prefiltered = textureLod(u_prefiltered_env, R, lod).rgb;
    vec2 brdf = texture(u_brdf_lut, vec2(NdotV, roughness)).rg;
    vec3 specular = prefiltered * (F * brdf.x + brdf.y);

    return (diffuse + specular) * ao * env_intensity;
}
```

#### 2.2 Update Metal Shader

Mirror changes in [assets/shaders/pbr.metal](assets/shaders/pbr.metal):

```metal
// Add texture arguments
texturecube<float> irradiance_map [[texture(5)]],
texturecube<float> prefiltered_env [[texture(6)]],
texture2d<float> brdf_lut [[texture(7)]],
```

---

### Phase 3: Engine Integration

#### 3.1 Update Engine Struct

Modify [src/engine/engine.zig](src/engine/engine.zig):

```zig
pub const Engine = struct {
    // ... existing fields ...

    // IBL resources
    brdf_lut: ?*Texture = null,
    current_environment: ?*EnvironmentMap = null,
    default_environment: ?*EnvironmentMap = null,
    ibl_enabled: bool = false,

    pub fn initIBL(self: *Engine) !void;
    pub fn setEnvironmentMap(self: *Engine, env: *EnvironmentMap) void;
    pub fn hasIBL(self: *Engine) bool;
};
```

**Tasks:**
- [ ] Generate BRDF LUT during `initIBL()`
- [ ] Create default white environment (no IBL effect)
- [ ] Add IBL sampler bindings to PBR pipeline

#### 3.2 Update Render System

Modify [src/ecs/systems/render_system.zig](src/ecs/systems/render_system.zig):

```zig
// Add IBL texture binding in PBR render path
pub fn bindIBLTextures(self: *RenderFrame, env: *EnvironmentMap, brdf_lut: *Texture) void {
    // Bind irradiance cubemap to slot 5
    // Bind prefiltered cubemap to slot 6
    // Bind BRDF LUT to slot 7
}
```

#### 3.3 Update Light Uniforms

Modify [src/gpu/uniforms.zig](src/gpu/uniforms.zig):

```zig
pub const LightUniforms = extern struct {
    // ... existing fields ...

    // IBL parameters
    env_intensity: f32 = 1.0,
    max_reflection_lod: f32 = 4.0,
    use_ibl: u32 = 0,
    _ibl_pad: u32 = 0,
};
```

---

### Phase 4: Asset Pipeline

#### 4.1 Offline IBL Baker

Create `tools/asset_pipeline/ibl_baker.zig`:

```zig
// Command-line tool for pre-baking IBL maps
// Usage: zdl-ibl-baker input.hdr output_prefix
//
// Generates:
//   output_prefix_irradiance.ktx
//   output_prefix_prefiltered.ktx

pub fn main() !void {
    // 1. Load HDR equirectangular image
    // 2. Convert to cubemap
    // 3. Generate irradiance map (convolution)
    // 4. Generate pre-filtered map (per-mip convolution)
    // 5. Save as KTX or custom format
}
```

**Considerations:**
- GPU-based baking for speed
- CPU fallback for CI/build systems
- KTX2 format for compressed cubemaps

#### 4.2 Runtime vs Offline

| Approach | Pros | Cons |
|----------|------|------|
| Runtime baking | Dynamic environments, less build complexity | Slower load times, GPU memory during bake |
| Offline baking | Fast loading, smaller runtime | Build step required, static only |

**Recommendation:** Support both. Use offline for production, runtime for development/experimentation.

---

### Phase 5: PBR Demo Integration

#### 5.1 Update PBR Demo

Modify [examples/pbr_demo/main.zig](examples/pbr_demo/main.zig):

```zig
pub fn main() !void {
    var eng = try Engine.init(allocator, .{ .window_title = "PBR + IBL Demo" });
    defer eng.deinit();

    try eng.initPBR();
    try eng.initIBL();

    // Load environment map
    var env_map = try EnvironmentMap.loadFromHDR(allocator, &eng.device, "assets/environments/studio.hdr");
    defer env_map.deinit(allocator, &eng.device);

    eng.setEnvironmentMap(&env_map);

    // ... rest of demo setup ...
}
```

#### 5.2 Demo Features

- [ ] Toggle IBL on/off to compare
- [ ] Environment intensity slider (conceptual - no UI yet)
- [ ] Multiple environment maps to switch between
- [ ] Skybox rendering using environment cubemap

---

## Technical Specifications

### Texture Formats

| Texture | Format | Size | Mips |
|---------|--------|------|------|
| Irradiance | RGBA16F | 32x32 per face | 1 |
| Pre-filtered | RGBA16F | 256x256 per face | 5 |
| BRDF LUT | RG16F | 512x512 | 1 |

### Mip Level Mapping

Pre-filtered environment mip levels correspond to roughness:
- Mip 0: roughness = 0.0 (mirror)
- Mip 1: roughness = 0.25
- Mip 2: roughness = 0.5
- Mip 3: roughness = 0.75
- Mip 4: roughness = 1.0 (diffuse-like)

Formula: `mip = roughness * max_mip_level`

### Importance Sampling

For pre-filtering, use GGX importance sampling with Hammersley sequence:

```glsl
vec3 importanceSampleGGX(vec2 Xi, vec3 N, float roughness) {
    float a = roughness * roughness;
    float phi = 2.0 * PI * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // Tangent space half vector
    vec3 H = vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

    // Transform to world space
    vec3 up = abs(N.z) < 0.999 ? vec3(0,0,1) : vec3(1,0,0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
}
```

---

## Dependencies

### External Libraries (Optional)

- **stb_image.h** - HDR loading (already may be in use or easy to add)
- **cmgen** (Filament) - Reference for IBL baking algorithms

### HDR Environment Sources

Free HDR environments for testing:
- [Poly Haven](https://polyhaven.com/hdris) - CC0 license
- [sIBL Archive](http://www.hdrlabs.com/sibl/archive.html)

---

## Fallback Behavior

When IBL is not enabled or environment map is missing:

1. **use_ibl = 0**: Fall back to current procedural sky/ground gradient
2. **Missing textures**: Bind 1x1 default cubemaps (neutral gray)
3. **No initIBL() call**: PBR works without IBL, just uses analytical lights

This ensures backward compatibility with existing code.

---

## Testing Checklist

- [ ] BRDF LUT generates correctly (visual inspection: red-green gradient)
- [ ] Cubemap faces upload in correct order (no seams, correct orientation)
- [ ] Irradiance map is smooth and low-frequency
- [ ] Pre-filtered map shows increasing blur per mip level
- [ ] Smooth metals reflect environment clearly
- [ ] Rough metals show blurred reflections
- [ ] Dielectrics have subtle environment contribution
- [ ] Energy conservation maintained (scene not too bright/dark)
- [ ] IBL toggle shows clear difference
- [ ] Multiple environments can be swapped at runtime

---

## Future Enhancements

1. **Skybox Rendering** - Display environment as background
2. **Local Reflection Probes** - Per-room/area environment capture
3. **Parallax-Corrected Cubemaps** - Box projection for indoor scenes
4. **Real-time Probe Updates** - Dynamic environments
5. **Spherical Harmonics** - Compressed irradiance representation
6. **Screen-Space Reflections** - Complement IBL for nearby geometry

---

## References

- [LearnOpenGL - IBL](https://learnopengl.com/PBR/IBL/Diffuse-irradiance)
- [Real Shading in Unreal Engine 4](https://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf)
- [Filament PBR Documentation](https://google.github.io/filament/Filament.html)
- [Moving Frostbite to PBR](https://seblagarde.files.wordpress.com/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf)
