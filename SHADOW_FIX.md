# Shadow System Buffer Binding Fix

## Issue

The shadow demo was crashing with exit code 133 (segmentation fault) when trying to bind the graphics pipeline. The crash occurred in SDL3's Metal backend at:

```c
// SDL_gpu_metal.m:2413
if (metalCommandBuffer->fragmentUniformBuffers[i] == NULL)
```

## Root Cause

The Metal shader had **non-contiguous uniform buffer indices**:
- buffer(0): Material uniforms
- buffer(1): Forward+ uniforms
- buffer(2-5): Storage buffers (light_grid, light_indices, etc.)
- buffer(6): Shadow uniforms ❌

SDL3's Metal backend allocates fragment uniform buffers based on the **highest buffer index** used by uniform buffers. When it saw `buffer(6)` for shadow uniforms, it expected 7 uniform buffers (0-6), but the `fragmentUniformBuffers` array was only sized for 3 or 6 elements, causing an out-of-bounds access.

## Solution

Reorganized buffer bindings to make uniform buffers **contiguous** (0, 1, 2):

### Before
```metal
constant MaterialUniforms& material [[buffer(0)]],
constant ForwardPlusUniforms& forward_plus [[buffer(1)]],
device const LightGrid* light_grid [[buffer(2)]],      // storage
device const uint* light_indices [[buffer(3)]],        // storage
device const PointLight* point_lights [[buffer(4)]],   // storage
device const SpotLight* spot_lights [[buffer(5)]],     // storage
constant ShadowUniforms& shadow_uniforms [[buffer(6)]], // ❌ gap!
```

### After
```metal
constant MaterialUniforms& material [[buffer(0)]],
constant ForwardPlusUniforms& forward_plus [[buffer(1)]],
constant ShadowUniforms& shadow_uniforms [[buffer(2)]],  // ✅ contiguous!
device const LightGrid* light_grid [[buffer(3)]],        // storage
device const uint* light_indices [[buffer(4)]],          // storage
device const PointLight* point_lights [[buffer(5)]],     // storage
device const SpotLight* spot_lights [[buffer(6)]],       // storage
```

## Files Modified

1. **assets/shaders/pbr_forward_plus.metal**
   - Changed shadow uniforms from `buffer(6)` to `buffer(2)`
   - Shifted storage buffers from indices 2-5 to 3-6

2. **src/render/render_manager.zig**
   - Updated `bindShadowResources()` to use index 2 for `pushFragmentUniformData`
   - Added comment explaining the uniform buffer indexing

## Key Insight

In SDL3 GPU's Metal backend:
- **Uniform buffers** (`constant` in Metal) must use **contiguous indices** starting from 0
- **Storage buffers** (`device const` in Metal) are bound separately but share the same buffer index space
- The binding API separates them:
  - `pushFragmentUniformData(index, data)` - for uniform buffers (0, 1, 2, ...)
  - `bindFragmentStorageBuffers(start, buffers)` - for storage buffers (offset after uniforms)

## Result

✅ Shadow demo now runs successfully with all 3 cascade shadow maps working correctly
✅ No more segmentation faults
✅ Proper buffer binding for both Metal and Vulkan backends

## Testing

```bash
zig build run-shadow
```

The demo now displays a scene with:
- 5x5 grid of cubes and spheres
- Ground plane
- Two tall towers
- Rotating directional light (sun)
- Real-time cascaded shadow maps with PCF filtering
