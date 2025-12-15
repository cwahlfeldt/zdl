# 3D Game Engine Implementation Plan

## Overview

Build a 3D game engine in Zig using SDL3's GPU API. The current codebase already has GPU rendering infrastructure with vertex buffers, graphics pipelines, and cross-platform shaders (SPIR-V + Metal).

## Current State

- **Existing**: GPU device init, vertex/transfer buffers, graphics pipeline, command buffer rendering, colored triangle
- **Shader support**: SPIR-V (Linux/Windows), Metal (macOS)
- **Foundation**: Vertex struct with x,y,z position but no 3D transforms yet

---

## Phase 1: Core 3D Foundation

### 1.1 Math Library (`src/math/`)

| File                | Purpose                                     |
| ------------------- | ------------------------------------------- |
| `src/math/vec2.zig` | 2D vectors (UVs, screen coords)             |
| `src/math/vec3.zig` | 3D vectors (position, direction, scale)     |
| `src/math/vec4.zig` | Homogeneous coordinates                     |
| `src/math/mat4.zig` | 4x4 matrices (transforms, projection, view) |
| `src/math/quat.zig` | Quaternion rotations                        |
| `src/math/math.zig` | Root module re-exporting all                |

**Key functions in mat4.zig:**

- `perspective(fov, aspect, near, far)` - Perspective projection
- `lookAt(eye, target, up)` - View matrix
- `translation/scale/rotation` - Transform factories
- `mul(Mat4)` - Matrix multiplication
- `toColumnMajor() -> [16]f32` - For GPU upload

### 1.2 Uniform Buffers (`src/gpu/uniforms.zig`)

```zig
pub const MVPUniforms = extern struct {
    model: [16]f32,
    view: [16]f32,
    projection: [16]f32,
};
```

**Shader updates required:**

- Add uniform block to vertex shader (set = 1, binding = 0)
- Update pipeline `num_uniform_buffers = 1`

### 1.3 Depth Buffer

Modify `main.zig`:

- Create depth texture with `.d32_float` format
- Set `depth_stencil_state` on pipeline (enable test + write, compare = less)
- Pass depth target to `beginRenderPass`

### 1.4 Camera System (`src/camera.zig`)

- Position, rotation (quaternion), FOV, aspect, near/far
- `getViewMatrix()` / `getProjectionMatrix()`
- Cached matrices with dirty flags

### 1.5 Transform (`src/transform.zig`)

- Position, rotation, scale
- `getMatrix()` returning TRS model matrix

---

## Phase 2: Resource Management

### 2.1 Texture Loading (`src/resources/texture.zig`)

- Load images (stb_image or SDL_image)
- Create GPU texture, upload via transfer buffer
- Support for common formats (RGBA8)

### 2.2 Sampler (`src/resources/sampler.zig`)

- Filtering (linear/nearest), address modes
- Common presets (linear-clamp, nearest-repeat)

### 2.3 Mesh System (`src/resources/mesh.zig`)

```zig
pub const Vertex3D = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    color: [4]f32,
};
```

- Vertex + index buffers
- Bounding box for culling

### 2.4 OBJ Loader (`src/resources/obj_loader.zig`)

- Parse positions, normals, UVs, faces
- Triangulate and deduplicate vertices

### 2.5 Material System (`src/resources/material.zig`)

- Texture references (albedo, normal, etc.)
- Fallback colors
- Pipeline/sampler binding

### 2.6 Asset Cache (`src/resources/asset_cache.zig`)

- Generic cache for textures, meshes
- Path-based lookup, automatic loading

---

## Phase 3: Rendering System

### 3.1 Lighting (`src/renderer/lighting.zig`)

**Types:**

- `DirectionalLight` (sun)
- `PointLight` (position, radius, falloff)
- `SpotLight` (position, direction, angles)

**Uniform struct** for shader with max 16 point lights.

### 3.2 Normal Mapping

- Add tangent to Vertex3D
- Calculate TBN matrix in vertex shader
- Sample normal map in fragment shader

### 3.3 Skybox (`src/renderer/skybox.zig`)

- Cubemap texture loading
- Inside-out cube mesh
- Render at far plane, no depth write

### 3.4 Frustum Culling (`src/renderer/culling.zig`)

- Extract 6 planes from view-projection matrix
- AABB and sphere intersection tests

---

## Phase 4: Scene Management

### 4.1 Entity System (`src/scene/entity.zig`)

- Entity ID, name, active flag
- Parent/children for hierarchy
- Optional component pointers (transform, mesh_renderer, light, camera)

### 4.2 Scene Graph (`src/scene/scene.zig`)

- Entity storage (hash map)
- Component arrays (transforms, renderers, lights)
- `getWorldTransform()` - recursive parent traversal
- `collectRenderables()` - gather visible meshes with frustum culling

### 4.3 Instanced Rendering (`src/renderer/instancing.zig`)

- Instance buffer with per-instance model matrices
- Batching same mesh+material
- Single draw call for many objects

---

## Phase 5: Engine Features

### 5.1 Input System (`src/input/input.zig`)

- Key states (pressed, just_pressed, just_released)
- Mouse position, delta, buttons, scroll
- `getAxis()` helper for movement

### 5.2 Audio System (`src/audio/audio.zig`)

- SDL3 audio streams
- AudioClip (loaded WAV data)
- AudioSource (play, stop, volume, looping)
- 3D positional audio with distance attenuation

### 5.3 Frame Timing (`src/core/time.zig`)

- Delta time (scaled and unscaled)
- FPS counter
- Rolling average frame time
- Profiler with scoped timers

### 5.4 Engine Core (`src/engine.zig`)

Orchestrates all systems:

- Window, GPU device
- Input, audio, time
- Asset caches
- Renderer
- Scene
- Main loop with update/render callbacks

---

## Implementation Order

### Milestone 1: Basic 3D Rendering

1. `src/math/vec3.zig`
2. `src/math/vec4.zig`
3. `src/math/mat4.zig`
4. `src/math/quat.zig`
5. `src/math/vec2.zig`
6. `src/math/math.zig`
7. `src/gpu/uniforms.zig`
8. Update `src/shaders/vertex.vert` for uniforms
9. Modify `main.zig` for depth buffer
10. `src/camera.zig`
11. `src/transform.zig`
12. **Test**: Rotating 3D cube with perspective

### Milestone 2: Textured Models

13. `src/resources/texture.zig`
14. `src/resources/sampler.zig`
15. Update shaders for texture sampling
16. `src/resources/mesh.zig`
17. `src/resources/obj_loader.zig`
18. `src/resources/material.zig`
19. `src/resources/asset_cache.zig`
20. **Test**: Load and render OBJ model with texture

### Milestone 3: Lighting

21. `src/renderer/lighting.zig`
22. Update fragment shader for Blinn-Phong
23. Add normal mapping to shaders
24. `src/renderer/skybox.zig`
25. `src/renderer/culling.zig`
26. **Test**: Lit scene with skybox

### Milestone 4: Scene System

27. `src/scene/entity.zig`
28. `src/scene/scene.zig`
29. `src/renderer/instancing.zig`
30. **Test**: Multiple entities with hierarchy

### Milestone 5: Full Engine

31. `src/input/input.zig`
32. `src/core/time.zig`
33. `src/audio/audio.zig`
34. `src/engine.zig`
35. Refactor `main.zig` to use Engine
36. **Test**: Complete demo with camera controls

---

## Final Directory Structure

```
src/
  main.zig
  engine.zig
  math/
    math.zig, vec2.zig, vec3.zig, vec4.zig, mat4.zig, quat.zig
  gpu/
    gpu.zig, uniforms.zig
  resources/
    resources.zig, texture.zig, sampler.zig, mesh.zig,
    obj_loader.zig, material.zig, asset_cache.zig
  renderer/
    renderer.zig, lighting.zig, skybox.zig, culling.zig, instancing.zig
  scene/
    scene.zig, entity.zig
  input/
    input.zig
  audio/
    audio.zig
  core/
    time.zig
  shaders/
    vertex.vert, fragment.frag, skybox.vert, skybox.frag,
    shaders.metal, *.spv
```

---

## Critical Files to Modify

| File                        | Changes                                          |
| --------------------------- | ------------------------------------------------ |
| `src/main.zig`              | Depth buffer, uniforms integration, engine usage |
| `src/shaders/vertex.vert`   | MVP uniform block                                |
| `src/shaders/fragment.frag` | Texture sampling, lighting                       |
| `src/shaders/shaders.metal` | Metal equivalents                                |
| `build.zig`                 | New modules, optional shader compilation         |
