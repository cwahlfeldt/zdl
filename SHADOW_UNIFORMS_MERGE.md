# Shadow Uniforms Merge Fix

## Issue

After implementing the initial shadow buffer binding fix (SHADOW_FIX.md), the shadow demo was still crashing with exit code 133 (segmentation fault) at the same location in SDL3's Metal backend.

## Root Cause

The fragment shader configuration in [render_manager.zig:510](src/render/render_manager.zig#L510) incorrectly specified:
```zig
.num_uniform_buffers = 7, // ❌ WRONG - told SDL3 we have 7 uniform buffers
```

But we only had **2 uniform buffers**:
- `buffer(0)` - MaterialUniforms (constant)
- `buffer(1)` - ForwardPlusUniforms (constant)

And **4 storage buffers**:
- `buffer(3)` - LightGrid (device const)
- `buffer(4)` - LightIndices (device const)
- `buffer(5)` - PointLights (device const)
- `buffer(6)` - SpotLights (device const)

SDL3's Metal backend was trying to allocate 7 uniform buffer slots (0-6) when it should only allocate 2 (0-1), causing an out-of-bounds access when checking `fragmentUniformBuffers[i]` for i > 1.

## Solution

### 1. Merged Shadow Data into Forward+ Uniforms

**Modified:** [src/render/render_manager.zig](src/render/render_manager.zig)

Added shadow fields to `ForwardPlusUniforms` struct:
```zig
pub const ForwardPlusUniforms = extern struct {
    // ... existing Forward+ fields ...

    // Shadow uniforms (merged to avoid SDL3 buffer limit)
    cascade_view_proj: [3][16]f32,
    cascade_splits: [4]f32,
    shadow_distance: f32,
    depth_bias: f32,
    normal_offset_bias: f32,
    cascade_count: u32,
};
```

Updated `pushForwardPlusUniforms()` to include shadow data:
```zig
const shadow_data = if (mgr.getShadowManager()) |shadow_mgr|
    shadow_mgr.getShadowUniforms()
else
    shadow_manager.ShadowUniforms{
        .cascade_view_proj = [_][16]f32{[_]f32{0} ** 16} ** 3,
        .cascade_splits = [_]f32{0} ** 4,
        .shadow_distance = 0,
        .depth_bias = 0,
        .normal_offset_bias = 0,
        .cascade_count = 0,
    };
```

### 2. Updated Metal Shader

**Modified:** [assets/shaders/pbr_forward_plus.metal](assets/shaders/pbr_forward_plus.metal)

Merged shadow fields into `ForwardPlusUniforms`:
```metal
struct ForwardPlusUniforms {
    // ... existing fields ...

    // Shadow data merged to stay within SDL3's 4-buffer limit
    float4x4 cascade_view_proj[3];
    float4 cascade_splits;
    float shadow_distance;
    float depth_bias;
    float normal_offset_bias;
    uint cascade_count;
};
```

Updated fragment shader parameters - removed separate `ShadowUniforms`:
```metal
fragment float4 fragmentMain(
    constant MaterialUniforms& material [[buffer(0)]],
    constant ForwardPlusUniforms& forward_plus [[buffer(1)]],  // Now includes shadow data
    // ... textures and samplers ...
    device const LightGrid* light_grid [[buffer(3)]],
    device const uint* light_indices [[buffer(4)]],
    device const PointLight* point_lights [[buffer(5)]],
    device const SpotLight* spot_lights [[buffer(6)]]
)
```

Updated `calculateShadow()` to use `forward_plus.cascade_*` fields.

### 3. Updated GLSL Shader

**Modified:** [assets/shaders/pbr_forward_plus.frag](assets/shaders/pbr_forward_plus.frag)

Merged shadow fields into `ForwardPlusUBO`:
```glsl
layout(set = 2, binding = 1) uniform ForwardPlusUBO {
    // ... existing fields ...

    // Shadow data merged to stay within SDL3's 4-buffer limit
    mat4 cascade_view_proj[3];
    vec4 cascade_splits;
    float shadow_distance;
    float depth_bias;
    float normal_offset_bias;
    uint cascade_count;
} forward_plus;
```

Updated `calculateShadow()` to use `forward_plus.cascade_*` fields.

### 4. Fixed Shader Configuration

**Modified:** [src/render/render_manager.zig:510](src/render/render_manager.zig#L510)

Corrected the uniform buffer count:
```zig
const fp_fragment_shader = try self.device.createShader(.{
    // ...
    .num_uniform_buffers = 2, // ✅ material(0), forward_plus(1) - shadow data merged
    .num_storage_buffers = 4, // light_grid(3), light_indices(4), point_lights(5), spot_lights(6)
    // ...
});
```

### 5. Updated Shadow Resource Binding

**Modified:** [src/render/render_manager.zig:939](src/render/render_manager.zig#L939)

Removed uniform buffer push (shadow data now in Forward+ uniforms), kept texture binding:
```zig
pub fn bindShadowResources(self: *RenderFrame) void {
    const mgr = self.manager;
    const shadow_mgr = mgr.getShadowManager() orelse return;

    // Note: Shadow uniform data is now merged into ForwardPlusUniforms to stay within
    // SDL3's 4-buffer limit. This function only binds shadow map textures.

    // Bind shadow maps with sampler
    // ... texture binding code ...
}
```

**Modified:** [src/ecs/systems/render_system.zig:204](src/ecs/systems/render_system.zig#L204)

Re-enabled shadow resource binding:
```zig
if (!ctx.pipeline_bound) {
    if (!ctx.frame.bindForwardPlusPipeline()) return;
    ctx.frame.bindShadowResources(); // Bind shadow map textures if available
    ctx.pipeline_bound = true;
}
```

## Files Modified

### Core Files
- [src/render/render_manager.zig](src/render/render_manager.zig)
  - Added shadow fields to `ForwardPlusUniforms` struct
  - Updated `pushForwardPlusUniforms()` to include shadow data
  - Fixed `.num_uniform_buffers = 2` in shader configuration
  - Updated `bindShadowResources()` to only bind textures

- [src/ecs/systems/render_system.zig](src/ecs/systems/render_system.zig)
  - Re-enabled `bindShadowResources()` call

### Shader Files
- [assets/shaders/pbr_forward_plus.metal](assets/shaders/pbr_forward_plus.metal)
  - Merged shadow fields into `ForwardPlusUniforms`
  - Updated `calculateShadow()` function

- [assets/shaders/pbr_forward_plus.frag](assets/shaders/pbr_forward_plus.frag)
  - Merged shadow fields into `ForwardPlusUBO`
  - Updated `calculateShadow()` function

## Buffer Layout Summary

### Fragment Shader Buffers

**Uniform Buffers (constant in Metal):**
- `buffer(0)` / `set=2, binding=0` - MaterialUniforms
- `buffer(1)` / `set=2, binding=1` - ForwardPlusUniforms (includes shadow data)

**Storage Buffers (device const in Metal):**
- `buffer(3)` / `set=1, binding=0` - LightGrid
- `buffer(4)` / `set=1, binding=1` - LightIndices
- `buffer(5)` / `set=1, binding=2` - PointLights
- `buffer(6)` / `set=1, binding=3` - SpotLights

**Textures:**
- `texture(10)` / `set=2, binding=8` - Shadow map array (3 cascades)

**Samplers:**
- `sampler(2)` - Shadow comparison sampler

## Result

✅ Shadow demo now runs successfully without crashes
✅ Shadows work correctly with 3 cascade levels
✅ Stayed within SDL3's buffer limits (2 uniform buffers < 4 limit)
✅ Both Metal and GLSL shaders consistent

## Testing

```bash
zig build
./zig-out/bin/shadow_demo
```

The demo displays:
- 5x5 grid of cubes and spheres with real-time shadows
- Ground plane with shadow projections
- Two tall towers showcasing cascade transitions
- Rotating directional light (sun)
- PCF-filtered soft shadows

## Key Insight

**SDL3 GPU API requires:**
1. Uniform buffers must be contiguous starting from index 0
2. The `num_uniform_buffers` shader parameter must match the **actual count** of uniform buffers, not the highest buffer index
3. Storage buffers can use any indices but don't count toward the uniform buffer limit
4. Uniform and storage buffers share the same index space in Metal (`buffer(N)`)

When SDL3 sees `num_uniform_buffers = N`, it allocates exactly N uniform buffer slots and expects them at indices 0 to N-1.

---

*Fix completed: January 14, 2026*
*Engine Version: ZDL 0.1*
*Zig Version: 0.15.2*
