# SDL3 Game Engine - Incremental Implementation Plan

## Overview

Build a game engine in Zig using SDL3's GPU API. Start with a 2D platformer, then incrementally add 3D capabilities. Each phase produces a testable result.

## Current State

- GPU device initialization, vertex/transfer buffers
- Graphics pipeline with colored triangle
- Cross-platform shaders (SPIR-V + Metal)
- No transforms, uniforms, depth, or textures yet

---

## Phase 0: Foundation (Testable: Animated Triangle)

### 0.1 Build System - Shader Compilation
- Add glslangValidator step to build.zig
- Auto-compile .vert/.frag to .spv on build
- Files: `build.zig`

### 0.2 Math Library
| File | Purpose |
|------|---------|
| `src/math/vec2.zig` | 2D vectors (positions, UVs) |
| `src/math/vec3.zig` | 3D vectors (positions, colors) |
| `src/math/vec4.zig` | Homogeneous coordinates |
| `src/math/mat4.zig` | 4x4 transforms (ortho, perspective, translate, rotate, scale) |
| `src/math/math.zig` | Re-export module |

### 0.3 Uniform Buffer Support
- Create `src/gpu/uniforms.zig` with basic MVP struct
- Update vertex shader with uniform block
- Update pipeline creation (`num_uniform_buffers = 1`)
- Files: `src/gpu/uniforms.zig`, `src/shaders/vertex.vert`, `src/shaders/shaders.metal`, `src/main.zig`

### 0.4 Frame Timing
- Create `src/core/time.zig` with delta time calculation
- Replace hardcoded 16ms delay with proper timing
- Files: `src/core/time.zig`, `src/main.zig`

**Test**: Triangle that rotates smoothly using uniform-based transform and delta time

---

## Phase 1: 2D Core (Testable: Moving Player)

### 1.1 Input System
- Create `src/input/input.zig`
- Track key states (pressed, just_pressed, released)
- Arrow keys / WASD support
- Files: `src/input/input.zig`, `src/main.zig`

### 1.2 2D Camera
- Create `src/camera.zig` with orthographic projection
- Screen-space to world-space conversion
- Camera position for scrolling
- Files: `src/camera.zig`

### 1.3 Sprite Renderer
- Create `src/renderer/sprite.zig`
- Quad generation from position/size
- Batch multiple quads into single vertex buffer
- Color tinting support
- Files: `src/renderer/sprite.zig`

### 1.4 Basic Game Loop
- Separate update() and render() functions
- Player entity with position/velocity
- Simple AABB collision detection
- Files: `src/main.zig` or `src/game.zig`

**Test**: Colored rectangle controlled with arrow keys, collides with static platform rectangles

---

## Phase 2: 2D Platformer (Testable: Jumping on Platforms)

### 2.1 Physics
- Gravity constant
- Jumping with ground check
- Velocity-based movement
- Files: `src/physics/physics.zig` or inline in game

### 2.2 Texture Loading
- Create `src/resources/texture.zig`
- Load PNG/image files (stb_image or SDL_image)
- Upload to GPU texture via transfer buffer
- Files: `src/resources/texture.zig`

### 2.3 Textured Sprites
- Update shaders for texture sampling
- Add UV coordinates to vertex format
- Create sampler with filtering options
- Files: `src/shaders/*.vert`, `src/shaders/*.frag`, `src/shaders/shaders.metal`, `src/renderer/sprite.zig`

### 2.4 Sprite Animation
- Animation data struct (frames, duration)
- Frame advancement based on time
- UV region selection from spritesheet
- Files: `src/renderer/animation.zig`

### 2.5 Tilemap
- Create `src/renderer/tilemap.zig`
- Load tile data from simple format (CSV or custom)
- Render tiles as batched quads
- Collision from tile data
- Files: `src/renderer/tilemap.zig`

**Test**: Textured animated player jumping on tilemap platforms

---

## Phase 3: 2D Polish (Testable: Complete 2D Level)

### 3.1 Audio
- Create `src/audio/audio.zig`
- SDL3 audio stream setup
- Load WAV files
- Play sound effects (jump, land, collect)
- Background music loop
- Files: `src/audio/audio.zig`

### 3.2 Particles (Optional)
- Simple particle emitter
- Position, velocity, lifetime, color fade
- Used for dust, sparkles
- Files: `src/renderer/particles.zig`

### 3.3 UI/HUD
- Score display
- Simple bitmap font or number sprites
- Files: `src/ui/ui.zig`

**Test**: Playable 2D platformer level with sound, score, and polish effects

---

## Phase 4: 3D Foundation (Testable: 3D Cube)

### 4.1 Depth Buffer
- Create depth texture (D32_FLOAT format)
- Enable depth test/write on pipeline
- Pass depth target to render pass
- Files: `src/main.zig`

### 4.2 3D Camera
- Update `src/camera.zig` for perspective projection
- lookAt() view matrix
- Mouse look / keyboard movement
- Files: `src/camera.zig`

### 4.3 3D Transform
- Create `src/transform.zig`
- Position, rotation (quaternion), scale
- Model matrix generation (TRS)
- Files: `src/transform.zig`, `src/math/quat.zig`

### 4.4 3D Primitives
- Cube mesh generation (24 vertices for proper normals)
- Plane mesh
- Create `src/resources/mesh.zig` with Vertex3D struct
- Files: `src/resources/mesh.zig`, `src/resources/primitives.zig`

**Test**: Textured 3D cube with WASD+mouse camera controls

---

## Phase 5: 3D Resources (Testable: Loaded Model)

### 5.1 OBJ Loader
- Create `src/resources/obj_loader.zig`
- Parse positions, normals, UVs, faces
- Triangulate and build vertex buffer
- Files: `src/resources/obj_loader.zig`

### 5.2 Material System
- Create `src/resources/material.zig`
- Texture references (diffuse, normal)
- Material properties (color, shininess)
- Files: `src/resources/material.zig`

### 5.3 Asset Cache
- Create `src/resources/asset_cache.zig`
- Path-based lookup for textures, meshes
- Automatic loading on first access
- Files: `src/resources/asset_cache.zig`

**Test**: Load and render OBJ model with texture

---

## Phase 6: Lighting (Testable: Lit Scene)

### 6.1 Lighting System
- Create `src/renderer/lighting.zig`
- DirectionalLight, PointLight structs
- Light uniform buffer (max 8-16 lights)
- Files: `src/renderer/lighting.zig`

### 6.2 Lit Shaders
- Blinn-Phong fragment shader
- Normal attribute in vertex format
- Ambient + diffuse + specular
- Files: `src/shaders/lit.vert`, `src/shaders/lit.frag`, `src/shaders/shaders.metal`

### 6.3 Normal Mapping
- Add tangent to Vertex3D
- TBN matrix calculation
- Normal map sampling
- Files: shader updates, mesh generation

**Test**: Scene with directional sun + point lights, normal-mapped surfaces

---

## Phase 7: Scene System (Testable: Multi-Object Scene)

### 7.1 Entity System
- Create `src/scene/entity.zig`
- Entity ID, optional components
- Component: Transform, MeshRenderer, Light, Camera
- Files: `src/scene/entity.zig`

### 7.2 Scene Graph
- Create `src/scene/scene.zig`
- Entity storage and lookup
- Parent/child hierarchy
- World transform calculation
- Files: `src/scene/scene.zig`

### 7.3 Frustum Culling
- Create `src/renderer/culling.zig`
- Extract frustum planes from VP matrix
- AABB intersection test
- Files: `src/renderer/culling.zig`

### 7.4 Instanced Rendering
- Instance buffer with per-instance transforms
- Single draw call for same mesh+material
- Files: `src/renderer/instancing.zig`

**Test**: Scene with 100+ objects, hierarchy transforms, frustum culling

---

## Directory Structure (Final)

```
src/
  main.zig
  game.zig              # Game-specific logic
  math/
    math.zig, vec2.zig, vec3.zig, vec4.zig, mat4.zig, quat.zig
  core/
    time.zig
  input/
    input.zig
  audio/
    audio.zig
  gpu/
    uniforms.zig
  camera.zig
  transform.zig
  resources/
    texture.zig, mesh.zig, obj_loader.zig
    material.zig, asset_cache.zig, primitives.zig
  renderer/
    sprite.zig, tilemap.zig, animation.zig
    particles.zig, lighting.zig, culling.zig, instancing.zig
  scene/
    entity.zig, scene.zig
  ui/
    ui.zig
  shaders/
    vertex.vert, fragment.frag, lit.vert, lit.frag
    shaders.metal, *.spv
```

---

## Implementation Order Summary

| Phase | Deliverable | Key Systems |
|-------|-------------|-------------|
| 0 | Animated triangle | Math, uniforms, timing |
| 1 | Moving player | Input, 2D camera, sprites |
| 2 | Platformer gameplay | Textures, animation, tilemap, physics |
| 3 | Polished 2D game | Audio, particles, UI |
| 4 | 3D cube | Depth, perspective, 3D camera |
| 5 | Loaded 3D model | OBJ loader, materials, asset cache |
| 6 | Lit 3D scene | Lighting, normal mapping |
| 7 | Full 3D engine | Entities, scene graph, culling, instancing |
