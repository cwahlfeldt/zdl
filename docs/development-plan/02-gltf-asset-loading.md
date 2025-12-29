# glTF Asset Loading and Pipeline

## Overview

Implement comprehensive glTF 2.0 support for loading 3D models, materials, textures, animations, and scenes. glTF is the industry-standard format for 3D asset interchange, making it essential for any production game engine.

## Current State

ZDL currently supports:
- Manual mesh creation with `Vertex3D` format
- Primitive generation (cube, plane, sphere)
- Basic texture loading from image files
- No model file format support

## Goals

- Load glTF 2.0 files (.gltf + .bin, .glb)
- Support meshes with multiple primitives
- Load PBR materials (base color, metallic-roughness, normal maps)
- Import skeletal hierarchies and animations
- Support scene graphs from glTF
- Handle glTF extensions for advanced features
- Efficient loading with streaming support

## glTF 2.0 Specification Overview

### File Formats
- **glTF (.gltf)**: JSON file with external binary buffers and images
- **GLB (.glb)**: Single binary file containing JSON and all data

### Core Concepts
- **Scenes**: Collection of root nodes
- **Nodes**: Transform hierarchy (similar to our Entity system)
- **Meshes**: Geometry with primitives
- **Materials**: PBR material definitions
- **Textures/Images**: Texture data and samplers
- **Animations**: Keyframe animations
- **Skins**: Skeletal animation data
- **Cameras**: Perspective and orthographic cameras

## Architecture

### Directory Structure

```
src/
├── assets/
│   ├── assets.zig             # Module exports
│   ├── gltf/
│   │   ├── gltf.zig           # Main loader interface
│   │   ├── parser.zig         # JSON parsing
│   │   ├── binary.zig         # GLB and buffer handling
│   │   ├── accessor.zig       # Data accessor utilities
│   │   ├── mesh_import.zig    # Mesh conversion
│   │   ├── material_import.zig # Material conversion
│   │   ├── texture_import.zig # Texture loading
│   │   ├── animation_import.zig # Animation conversion
│   │   ├── skin_import.zig    # Skeletal data import
│   │   └── scene_import.zig   # Scene graph conversion
│   └── asset_manager.zig      # Caching and lifecycle
```

### Core Types

#### GLTFAsset

Top-level container for loaded glTF data:

```zig
pub const GLTFAsset = struct {
    allocator: std.mem.Allocator,

    // Raw parsed data
    meshes: []MeshData,
    materials: []MaterialData,
    textures: []TextureData,
    images: []ImageData,
    animations: []AnimationData,
    skins: []SkinData,
    nodes: []NodeData,
    scenes: []SceneData,

    // GPU resources (loaded on demand)
    gpu_meshes: std.ArrayList(*Mesh),
    gpu_textures: std.ArrayList(*Texture),

    pub fn loadFromFile(allocator: Allocator, path: []const u8) !GLTFAsset;
    pub fn loadFromMemory(allocator: Allocator, data: []const u8) !GLTFAsset;
    pub fn uploadToGPU(self: *GLTFAsset, device: *sdl.gpu.Device) !void;
    pub fn deinit(self: *GLTFAsset) void;
};
```

#### Mesh Representation

Extended mesh to support glTF features:

```zig
pub const MeshData = struct {
    name: ?[]const u8,
    primitives: []PrimitiveData,
};

pub const PrimitiveData = struct {
    // Vertex attributes
    positions: []Vec3,
    normals: ?[]Vec3,
    tangents: ?[]Vec4,      // xyz = tangent, w = handedness
    texcoords_0: ?[]Vec2,
    texcoords_1: ?[]Vec2,   // For lightmaps
    colors_0: ?[]Vec4,
    joints_0: ?[][4]u16,    // Bone indices for skinning
    weights_0: ?[]Vec4,     // Bone weights

    indices: ?[]u32,
    material_index: ?usize,
    mode: PrimitiveMode,    // triangles, lines, points
};

pub const PrimitiveMode = enum {
    points,
    lines,
    line_loop,
    line_strip,
    triangles,
    triangle_strip,
    triangle_fan,
};
```

#### Material Representation

PBR material matching glTF spec:

```zig
pub const MaterialData = struct {
    name: ?[]const u8,

    // PBR Metallic-Roughness
    base_color_factor: Vec4,
    base_color_texture: ?TextureRef,
    metallic_factor: f32,
    roughness_factor: f32,
    metallic_roughness_texture: ?TextureRef,

    // Common
    normal_texture: ?TextureRef,
    normal_scale: f32,
    occlusion_texture: ?TextureRef,
    occlusion_strength: f32,
    emissive_factor: Vec3,
    emissive_texture: ?TextureRef,

    // Alpha
    alpha_mode: AlphaMode,
    alpha_cutoff: f32,

    // Rendering
    double_sided: bool,
};

pub const AlphaMode = enum {
    @"opaque",
    mask,
    blend,
};

pub const TextureRef = struct {
    texture_index: usize,
    texcoord: u32,         // Which UV set to use
    transform: ?TextureTransform,
};
```

#### Animation Data

Keyframe animation support:

```zig
pub const AnimationData = struct {
    name: ?[]const u8,
    channels: []AnimationChannel,
    samplers: []AnimationSampler,
    duration: f32,
};

pub const AnimationChannel = struct {
    sampler_index: usize,
    target_node: usize,
    target_path: TargetPath,
};

pub const TargetPath = enum {
    translation,
    rotation,
    scale,
    weights,  // Morph target weights
};

pub const AnimationSampler = struct {
    input: []f32,          // Keyframe times
    output: []const u8,    // Keyframe values (type depends on path)
    interpolation: Interpolation,
};

pub const Interpolation = enum {
    linear,
    step,
    cubic_spline,
};
```

#### Skin (Skeletal) Data

```zig
pub const SkinData = struct {
    name: ?[]const u8,
    joints: []usize,                    // Node indices for bones
    inverse_bind_matrices: []Mat4,      // Bind pose inverse
    skeleton_root: ?usize,              // Root node index
};
```

### Parser Implementation

#### JSON Parsing

```zig
pub const GLTFParser = struct {
    allocator: Allocator,
    json: std.json.Value,
    buffers: [][]const u8,

    pub fn parse(allocator: Allocator, json_data: []const u8) !GLTFParser;
    pub fn loadBuffers(self: *GLTFParser, base_path: []const u8) !void;

    pub fn getMeshes(self: *GLTFParser) ![]MeshData;
    pub fn getMaterials(self: *GLTFParser) ![]MaterialData;
    pub fn getAnimations(self: *GLTFParser) ![]AnimationData;
    // ... other accessors
};
```

#### Accessor Utilities

Helper for reading typed data from buffers:

```zig
pub const Accessor = struct {
    buffer_view: usize,
    byte_offset: usize,
    component_type: ComponentType,
    count: usize,
    element_type: ElementType,
    min: ?[]f32,
    max: ?[]f32,

    pub fn readVec3(self: *Accessor, buffers: [][]const u8) ![]Vec3;
    pub fn readVec4(self: *Accessor, buffers: [][]const u8) ![]Vec4;
    pub fn readMat4(self: *Accessor, buffers: [][]const u8) ![]Mat4;
    pub fn readScalar(self: *Accessor, comptime T: type, buffers: [][]const u8) ![]T;
};

pub const ComponentType = enum {
    byte,
    unsigned_byte,
    short,
    unsigned_short,
    unsigned_int,
    float,
};

pub const ElementType = enum {
    scalar,
    vec2,
    vec3,
    vec4,
    mat2,
    mat3,
    mat4,
};
```

### Integration with ECS

#### Scene Import

Convert glTF scene to ZDL entities:

```zig
pub fn importScene(
    gltf: *GLTFAsset,
    scene: *Scene,
    scene_index: usize,
) ![]Entity {
    var imported_entities = std.ArrayList(Entity).init(scene.allocator);

    const gltf_scene = gltf.scenes[scene_index];

    // Import root nodes
    for (gltf_scene.nodes) |node_index| {
        const entity = try importNode(gltf, scene, node_index, null);
        try imported_entities.append(entity);
    }

    return imported_entities.toOwnedSlice();
}

fn importNode(
    gltf: *GLTFAsset,
    scene: *Scene,
    node_index: usize,
    parent: ?Entity,
) !Entity {
    const node = gltf.nodes[node_index];
    const entity = try scene.createEntity();

    // Add transform
    var transform = TransformComponent.init();
    if (node.translation) |t| transform.position = t;
    if (node.rotation) |r| transform.rotation = r;
    if (node.scale) |s| transform.scale = s;
    try scene.addComponent(entity, transform);

    // Set parent
    if (parent) |p| {
        scene.setParent(entity, p);
    }

    // Add mesh renderer if present
    if (node.mesh_index) |mesh_idx| {
        const mesh_renderer = MeshRendererComponent.init(
            gltf.gpu_meshes.items[mesh_idx],
        );
        try scene.addComponent(entity, mesh_renderer);
    }

    // Import children recursively
    for (node.children) |child_index| {
        _ = try importNode(gltf, scene, child_index, entity);
    }

    return entity;
}
```

### Vertex Format Extension

Extended vertex format for glTF features:

```zig
pub const Vertex3DExtended = struct {
    // Position
    x: f32, y: f32, z: f32,

    // Normal
    nx: f32, ny: f32, nz: f32,

    // Tangent (for normal mapping)
    tx: f32, ty: f32, tz: f32, tw: f32,

    // UV coordinates
    u: f32, v: f32,

    // Vertex color
    r: f32, g: f32, b: f32, a: f32,

    // Skinning (for skeletal animation)
    joints: [4]u16,
    weights: [4]f32,
};
```

## Implementation Steps

### Phase 1: Core Parser
1. Implement JSON parsing for glTF structure
2. Create buffer loading for external .bin files
3. Implement GLB binary format parsing
4. Create accessor utilities for typed data reading

### Phase 2: Mesh Import
1. Convert glTF primitives to ZDL meshes
2. Handle all vertex attributes (position, normal, UV, color)
3. Support indexed geometry
4. Handle multiple primitives per mesh

### Phase 3: Material Import
1. Parse PBR metallic-roughness materials
2. Load and convert textures
3. Handle texture transforms
4. Support alpha modes

### Phase 4: Scene Import
1. Convert glTF node hierarchy to entities
2. Apply transforms correctly
3. Set up parent-child relationships
4. Handle cameras and lights if present

### Phase 5: Animation Import
1. Parse animation data structures
2. Create animation clip format
3. Support translation, rotation, scale channels
4. Implement linear and step interpolation

### Phase 6: Skeletal Animation
1. Parse skin data
2. Create joint hierarchy
3. Import inverse bind matrices
4. Extend vertex format for skinning

### Phase 7: Extensions
1. KHR_materials_unlit (unlit materials)
2. KHR_texture_transform (UV transforms)
3. KHR_draco_mesh_compression (optional)
4. KHR_lights_punctual (point/spot/directional lights)

## Asset Manager

Caching and lifecycle management:

```zig
pub const AssetManager = struct {
    allocator: Allocator,
    device: *sdl.gpu.Device,

    // Caches
    gltf_cache: std.StringHashMap(*GLTFAsset),
    mesh_cache: std.StringHashMap(*Mesh),
    texture_cache: std.StringHashMap(*Texture),

    pub fn loadGLTF(self: *AssetManager, path: []const u8) !*GLTFAsset;
    pub fn getMesh(self: *AssetManager, gltf: *GLTFAsset, index: usize) !*Mesh;
    pub fn getTexture(self: *AssetManager, gltf: *GLTFAsset, index: usize) !*Texture;

    pub fn unload(self: *AssetManager, path: []const u8) void;
    pub fn unloadAll(self: *AssetManager) void;
};
```

## Performance Considerations

- **Streaming**: Load large models in chunks to avoid frame hitches
- **GPU Upload**: Batch buffer uploads in single command submission
- **Memory**: Use arena allocator for temporary parsing data
- **Compression**: Support Draco compression for mesh data
- **LOD**: Consider generating LOD levels for distant objects
- **Instancing**: Identify and batch identical meshes

## Validation

Handle malformed files gracefully:

```zig
pub const GLTFError = error{
    InvalidJSON,
    MissingRequiredProperty,
    InvalidBufferView,
    AccessorOutOfBounds,
    UnsupportedVersion,
    InvalidMeshTopology,
    // ...
};

pub fn validate(gltf: *GLTFAsset) !void {
    // Check version compatibility
    // Validate buffer references
    // Check accessor bounds
    // Verify material references
}
```

## Testing Strategy

1. Load official glTF sample models
2. Test all primitive types (triangles, lines, points)
3. Verify material property import
4. Test animation playback
5. Validate skeletal mesh deformation
6. Performance test with large models

## Dependencies

- **JSON Parsing**: Zig standard library `std.json`
- **Image Loading**: Existing SDL image loader
- **Compression**: Optional Draco decompression library

## References

- [glTF 2.0 Specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
- [glTF Sample Models](https://github.com/KhronosGroup/glTF-Sample-Models)
- [glTF Tutorials](https://github.khronos.org/glTF-Tutorials/)
- [glTF Extensions](https://github.com/KhronosGroup/glTF/tree/main/extensions)
