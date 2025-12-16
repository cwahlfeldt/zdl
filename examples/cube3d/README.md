# 3D Cube Demo (Phase 4)

This demo showcases the 3D foundation features added in Phase 4:

## Features

- **3D Camera** with perspective projection
- **Depth buffer** for proper 3D rendering
- **3D Mesh system** with procedural primitives
- **Directional lighting** (Blinn-Phong)
- **Transform system** with quaternion rotations
- **Textured 3D models**

## Controls

- **WASD** or **Arrow Keys** - Move camera forward/back/left/right
- **Q** - Move camera down
- **E** - Move camera up
- **ESC** - Quit

## What You Should See

- A **white rotating cube** at the center
- A **flat ground plane** below the cube
- A **blue-gray background**
- The cube rotates automatically on multiple axes
- Proper depth testing (cube obscures the plane behind it)

## Running

```bash
zig build run              # Run this demo (default)
zig build run-cube3d       # Explicit run
```

## Technical Details

- Uses Vulkan/Metal compatible shaders
- Depth format: `depth32_float`
- Vertex format: position (vec3), normal (vec3), UV (vec2), color (vec4)
- Lighting: 1 directional light with ambient + diffuse components
- Camera: positioned at (0, 2, 5) looking at origin

## Implementation

- **Cube**: 24 vertices (4 per face for proper normals), 36 indices
- **Plane**: 4 vertices, 6 indices
- **Shaders**:
  - SPIR-V for Vulkan/Linux
  - MSL (Metal Shading Language) for macOS
