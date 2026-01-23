# Shader Compilation Guide

This guide explains how to compile shaders for ZDL, including support for Cascaded Shadow Maps.

## Overview

ZDL uses different shader formats for different platforms:
- **macOS**: Metal Shading Language (.metal files) - compiled at runtime by Metal framework
- **Linux/Windows**: SPIR-V (.spv files) - compiled from GLSL using glslangValidator

## Prerequisites

### For Vulkan/SPIR-V Compilation

You need **glslangValidator** installed:

**macOS (via Homebrew):**
```bash
brew install glslang
```

**Ubuntu/Debian:**
```bash
sudo apt-get install glslang-tools
```

**Windows:**
Download from: https://github.com/KhronosGroup/glslang/releases

Verify installation:
```bash
glslangValidator --version
```

## Shader Files

All shaders are located in `assets/shaders/`:

### Core Shaders
- **pbr.vert** - PBR vertex shader (position, normal, UV, color)
- **pbr_forward_plus.frag** - PBR fragment shader with Forward+ lighting and shadows
- **pbr_forward_plus.metal** - Metal version of PBR fragment shader
- **light_cull.comp** - Forward+ light culling compute shader
- **light_cull.metal** - Metal version of light culling shader

### Shadow Shaders
- **shadow_depth.vert** - Shadow map vertex shader (depth-only rendering)
- **shadow_depth.frag** - Shadow map fragment shader (empty, depth written automatically)
- **shadow_depth.metal** - Metal version of shadow shaders

### Other Shaders
- **debug_line.vert/frag/metal** - Debug line rendering
- **ui.vert/frag/metal** - UI rendering
- **skybox.vert/frag/metal** - Skybox rendering
- **brdf_lut.vert/frag** - BRDF lookup table generation

## Compiling GLSL to SPIR-V

### Manual Compilation

Compile individual shaders using glslangValidator:

```bash
# Compile vertex shader
glslangValidator -V assets/shaders/shadow_depth.vert -o assets/shaders/shadow_depth.vert.spv

# Compile fragment shader
glslangValidator -V assets/shaders/shadow_depth.frag -o assets/shaders/shadow_depth.frag.spv

# Compile PBR fragment shader (with shadow support)
glslangValidator -V assets/shaders/pbr_forward_plus.frag -o assets/shaders/pbr_forward_plus.frag.spv

# Compile compute shader
glslangValidator -V assets/shaders/light_cull.comp -o assets/shaders/light_cull.comp.spv
```

### Batch Compilation Script

Create a script to compile all shaders at once:

```bash
#!/bin/bash
# compile_shaders.sh

SHADER_DIR="assets/shaders"

echo "Compiling GLSL shaders to SPIR-V..."

# Compile shadow shaders
glslangValidator -V $SHADER_DIR/shadow_depth.vert -o $SHADER_DIR/shadow_depth.vert.spv
glslangValidator -V $SHADER_DIR/shadow_depth.frag -o $SHADER_DIR/shadow_depth.frag.spv

# Compile PBR shaders
glslangValidator -V $SHADER_DIR/pbr.vert -o $SHADER_DIR/pbr.vert.spv
glslangValidator -V $SHADER_DIR/pbr_forward_plus.frag -o $SHADER_DIR/pbr_forward_plus.frag.spv

# Compile light culling compute shader
glslangValidator -V $SHADER_DIR/light_cull.comp -o $SHADER_DIR/light_cull.comp.spv

# Compile debug shaders
glslangValidator -V $SHADER_DIR/debug_line.vert -o $SHADER_DIR/debug_line.vert.spv
glslangValidator -V $SHADER_DIR/debug_line.frag -o $SHADER_DIR/debug_line.frag.spv

# Compile UI shaders
glslangValidator -V $SHADER_DIR/ui.vert -o $SHADER_DIR/ui.vert.spv
glslangValidator -V $SHADER_DIR/ui.frag -o $SHADER_DIR/ui.frag.spv

# Compile skybox shaders
glslangValidator -V $SHADER_DIR/skybox.vert -o $SHADER_DIR/skybox.vert.spv
glslangValidator -V $SHADER_DIR/skybox.frag -o $SHADER_DIR/skybox.frag.spv

# Compile BRDF LUT shaders
glslangValidator -V $SHADER_DIR/brdf_lut.vert -o $SHADER_DIR/brdf_lut.vert.spv
glslangValidator -V $SHADER_DIR/brdf_lut.frag -o $SHADER_DIR/brdf_lut.frag.spv

echo "Shader compilation complete!"
```

Make it executable:
```bash
chmod +x compile_shaders.sh
./compile_shaders.sh
```

### Using the Asset Pipeline

ZDL includes an asset pipeline tool that can compile shaders:

```bash
# Build the asset pipeline tool
zig build

# Compile shaders
./zig-out/bin/zdl-assets build --source=assets/shaders --output=assets/shaders
```

## Shadow Shader Details

### Shadow Map Rendering

The shadow depth shaders are minimal for performance:

**shadow_depth.vert:**
- Takes only position as input (no normals or UVs needed)
- Transforms position to light space using cascade view-projection matrices
- Outputs depth value

**shadow_depth.frag:**
- Empty fragment shader (depth written automatically by hardware)
- No color output needed for depth-only rendering

### Shadow Sampling in PBR Shader

The PBR fragment shader (pbr_forward_plus.frag/metal) includes:

**Shadow Uniforms:**
```glsl
layout (set = 3, binding = 2) uniform ShadowUBO {
    mat4 cascade_view_proj[3];  // View-projection for each cascade
    vec4 cascade_splits;         // Split distances for cascade selection
    vec4 shadow_params;          // Bias, normal offset, PCF radius, enabled
} shadows;
```

**Shadow Texture:**
```glsl
layout (set = 2, binding = 8) uniform sampler2DArrayShadow u_shadow_maps;
```

**Shadow Calculation:**
- Selects appropriate cascade based on view depth
- Applies normal offset bias to reduce shadow acne
- Uses 3x3 PCF (Percentage Closer Filtering) for soft shadows
- Returns shadow factor (0.0 = fully shadowed, 1.0 = fully lit)

## Shader Binding Layouts

### Fragment Shader Bindings

**Set 2 (Fragment Samplers):**
- Binding 0: Base color texture
- Binding 1: Normal texture
- Binding 2: Metallic-roughness texture
- Binding 3: AO texture
- Binding 4: Emissive texture
- Binding 5: Irradiance map (IBL)
- Binding 6: Prefiltered environment (IBL)
- Binding 7: BRDF LUT (IBL)
- Binding 8: Shadow maps (2D array)

**Set 2 (Storage Buffers - separate binding space):**
- Binding 0: Light grid
- Binding 1: Light indices
- Binding 2: Point lights
- Binding 3: Spot lights

**Set 3 (Uniform Buffers):**
- Binding 0: Material uniforms
- Binding 1: Forward+ uniforms (lights, camera, clusters)
- Binding 2: Shadow uniforms (cascade matrices, splits, params)

## Testing Shadow Shaders

After compiling shaders, test with the shadow demo:

```bash
# Build and run shadow demo
zig build run-shadow

# The demo showcases:
# - 3 cascade shadow maps
# - PCF filtering for soft shadows
# - Dynamic sun rotation
# - Multiple objects at varying distances
```

## Troubleshooting

### Shader Compilation Errors

If you see compilation errors:

1. **Check glslangValidator version:**
   ```bash
   glslangValidator --version
   # Should be version 11.0 or newer
   ```

2. **Validate shader syntax:**
   ```bash
   glslangValidator --help
   # Shows all available flags
   ```

3. **Check for syntax errors:**
   - Ensure all uniforms have correct bindings
   - Verify struct layouts match between vertex and fragment shaders
   - Check that array indices are in bounds

### Runtime Shader Errors

If shaders fail to load at runtime:

1. **Metal (macOS):** Check console for Metal compilation errors
2. **Vulkan:** Ensure .spv files exist in `assets/shaders/`
3. **Verify shader files are copied:** ZDL looks for shaders relative to the executable

### Shadow Artifacts

If you see shadow artifacts:

1. **Shadow Acne:** Increase `depth_bias` or `normal_offset` in ShadowManager
2. **Peter Panning:** Decrease bias values
3. **Blocky Shadows:** Increase `pcf_radius` for softer filtering
4. **Missing Shadows:** Check that shadow distance covers the scene

## Platform-Specific Notes

### macOS (Metal)
- Metal shaders (.metal) are compiled at runtime by the Metal framework
- No pre-compilation needed
- Shader errors appear in console with detailed diagnostics

### Linux/Windows (Vulkan)
- SPIR-V shaders (.spv) must be pre-compiled
- Use glslangValidator to compile GLSL to SPIR-V
- Shader validation happens at pipeline creation time

## Additional Resources

- [GLSL Specification](https://www.khronos.org/registry/OpenGL/specs/gl/)
- [SPIR-V Guide](https://www.khronos.org/spir/)
- [Metal Shading Language](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
- [Shadow Mapping Tutorial](https://learnopengl.com/Advanced-Lighting/Shadows/Shadow-Mapping)
- [Cascaded Shadow Maps](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-10-parallel-split-shadow-maps-programmable-gpus)
