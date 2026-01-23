# SDL3 Uniform Buffer Limit Issue

## Problem

SDL3 GPU has a hardcoded limit of `MAX_UNIFORM_BUFFERS_PER_STAGE = 4` defined in `src/gpu/SDL_sysgpu.h:32`.

This causes a crash when attempting to use more than 4 uniform buffers in the fragment shader, even though Metal supports up to 31 buffer bindings.

## Root Cause

In `src/gpu/metal/SDL_gpu_metal.m:586`:
```c
MetalUniformBuffer *fragmentUniformBuffers[MAX_UNIFORM_BUFFERS_PER_STAGE];
```

When binding a graphics pipeline with more than 4 fragment uniform buffers, SDL3 attempts to access indices beyond the array bounds, causing a segmentation fault.

## Impact on ZDL Shadow System

The Forward+ PBR shader requires:
- Buffer 0: Material uniforms
- Buffer 1: Forward+ uniforms (lights, camera, clusters)
- Buffer 2: Shadow uniforms (cascade matrices, splits, params)
- Buffers 3-6: Storage buffers (light grid, indices, point/spot lights)

While storage buffers are bound separately via `bindFragmentStorageBuffers`, Metal's shader reflection may report the total buffer count (including storage buffers) to SDL3, exceeding the 4-buffer limit.

## Temporary Workaround

**Shadows are currently disabled** in the Metal shader to stay within the 4-buffer limit:

1. **Metal Shader** (`assets/shaders/pbr_forward_plus.metal`):
   - Shadow uniforms parameter commented out (line 291-292)
   - Shadow calculation disabled (lines 382-397)

2. **Render System** (`src/ecs/systems/render_system.zig`):
   - `bindShadowResources()` call commented out (line 204-205)

3. **Demo Behavior**:
   - Scene renders correctly without shadows
   - All geometry, materials, and Forward+ lighting work
   - Shadow maps are still generated but not sampled

## Proper Solutions

### Option 1: Increase SDL3 Buffer Limit (Upstream Fix)

**File:** `SDL/src/gpu/SDL_sysgpu.h`
```c
// Change from:
#define MAX_UNIFORM_BUFFERS_PER_STAGE  4

// To:
#define MAX_UNIFORM_BUFFERS_PER_STAGE  16  // or higher
```

**Pros:**
- Simple fix
- Aligns with Metal's actual capability (31 buffers)
- Future-proof for complex shaders

**Cons:**
- Requires SDL3 upstream change
- Increases memory usage for command buffers
- May affect other backends (Vulkan, D3D12)

### Option 2: Separate Uniform/Storage Buffer Reflection (SDL3 Fix)

Modify SDL3's Metal backend to properly distinguish between `constant` and `device const` buffers during shader reflection, counting them separately.

**Pros:**
- Correct interpretation of Metal shader semantics
- No arbitrary limits

**Cons:**
- More complex SDL3 patch
- Requires understanding of Metal shader reflection API

### Option 3: Workaround in ZDL (Temporary)

**A. Push Constants for Shadow Data:**
Use `pushFragmentUniformData()` for shadow uniforms instead of binding as a buffer. This counts against push constant limits instead of buffer limits.

**B. Merge Shadow Data into Forward+ Uniforms:**
Combine shadow uniforms into the existing Forward+ uniform buffer (buffer 1):
```metal
struct ForwardPlusUniforms {
    // ... existing fields ...
    float4x4 cascade_view_proj[3];
    float4 cascade_splits;
    float4 shadow_params;
};
```

**Pros:**
- Works within current SDL3 limits
- No SDL3 changes needed

**Cons:**
- Larger uniform buffer
- Less modular shader design
- Still limited to 4 total uniform buffers

## Recommended Path Forward

1. **Short Term:** Use Option 3B (merge shadow uniforms into Forward+ buffer)
2. **Long Term:** Report issue to SDL3 and request Option 1 (increase buffer limit to 16)

## Testing

With shadows disabled, the demo runs successfully:
```bash
zig build run-shadow
```

**Works:**
- Window opens
- Scene renders with PBR materials
- Forward+ lighting (directional + point lights)
- Camera controls
- No crashes

**Disabled:**
- Shadow maps (not sampled)
- Shadow factor in lighting calculations

## Related Files

- `SDL/src/gpu/SDL_sysgpu.h:32` - MAX_UNIFORM_BUFFERS_PER_STAGE definition
- `SDL/src/gpu/metal/SDL_gpu_metal.m:586` - fragmentUniformBuffers array
- `SDL/src/gpu/metal/SDL_gpu_metal.m:2413` - Crash location
- `assets/shaders/pbr_forward_plus.metal` - Metal shader with shadows disabled
- `src/ecs/systems/render_system.zig:204` - Shadow binding disabled
- `src/render/render_manager.zig:912` - bindShadowResources() still defined but not called

## SDL3 Bug Report

This should be reported to SDL with:
- Crash location and stack trace
- Shader code demonstrating the issue
- Request to increase MAX_UNIFORM_BUFFERS_PER_STAGE
- Note that Metal supports 31 buffer bindings natively

## Status

🔴 **Shadows Disabled** - Demo runs successfully without shadow rendering
🟡 **Waiting on SDL3** - Proper fix requires SDL3 changes
🟢 **Workaround Available** - Can merge uniforms to enable shadows within limits
