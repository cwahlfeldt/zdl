# Asset Pipeline and Build Tools

## Overview

Create a comprehensive asset pipeline for processing, optimizing, and packaging game assets. This includes offline asset processing, build-time optimization, hot-reloading during development, and asset bundling for distribution.

## Current State

ZDL currently has:
- Runtime asset loading only
- No asset preprocessing
- No compression or optimization
- Manual shader compilation via glslangValidator
- No asset bundling

## Goals

- Offline asset processing and optimization
- Texture compression (BCn, ASTC, ETC2)
- Mesh optimization and LOD generation
- Shader compilation and validation
- Asset bundling and packaging
- Hot-reloading for development iteration
- Asset dependency tracking
- Cross-platform asset variants
- Build caching for fast iteration

## Architecture

### Directory Structure

```
tools/
├── asset_pipeline/
│   ├── main.zig               # CLI entry point
│   ├── pipeline.zig           # Core pipeline
│   ├── asset_database.zig     # Asset tracking
│   ├── processors/
│   │   ├── texture_processor.zig
│   │   ├── mesh_processor.zig
│   │   ├── shader_processor.zig
│   │   ├── audio_processor.zig
│   │   └── scene_processor.zig
│   ├── importers/
│   │   ├── gltf_importer.zig
│   │   ├── image_importer.zig
│   │   ├── audio_importer.zig
│   │   └── font_importer.zig
│   └── exporters/
│       ├── bundle_exporter.zig
│       └── platform_exporter.zig

src/
├── assets/
│   ├── asset_manager.zig      # Runtime asset loading
│   ├── asset_bundle.zig       # Bundle loading
│   └── hot_reload.zig         # Development hot-reload

assets/                        # Source assets (version controlled)
├── textures/
├── models/
├── audio/
└── shaders/

build/                         # Processed assets (generated)
├── cache/                     # Intermediate files
└── output/
    ├── desktop/
    ├── mobile/
    └── bundles/
```

### Core Components

#### Asset Pipeline CLI

```zig
// tools/asset_pipeline/main.zig
pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);

    const command = args[1];
    switch (command) {
        "build" => try buildAssets(args[2..]),
        "watch" => try watchAssets(args[2..]),
        "clean" => try cleanCache(args[2..]),
        "info" => try showAssetInfo(args[2..]),
        "bundle" => try createBundle(args[2..]),
        else => printUsage(),
    }
}

// Usage:
// zdl-assets build                    # Build all assets
// zdl-assets build --platform=mobile  # Build for mobile
// zdl-assets watch                    # Watch and rebuild on changes
// zdl-assets bundle game.pak          # Create distribution bundle
```

#### Asset Database

```zig
pub const AssetDatabase = struct {
    allocator: Allocator,
    assets: std.StringHashMap(AssetEntry),
    dependencies: DependencyGraph,
    cache_path: []const u8,

    pub fn init(allocator: Allocator, project_path: []const u8) !AssetDatabase;
    pub fn scan(self: *AssetDatabase, source_path: []const u8) !void;

    // Asset tracking
    pub fn getAsset(self: *AssetDatabase, path: []const u8) ?*AssetEntry;
    pub fn addAsset(self: *AssetDatabase, path: []const u8, asset_type: AssetType) !*AssetEntry;
    pub fn removeAsset(self: *AssetDatabase, path: []const u8) void;

    // Dependency management
    pub fn addDependency(self: *AssetDatabase, from: []const u8, to: []const u8) void;
    pub fn getDependents(self: *AssetDatabase, path: []const u8) [][]const u8;

    // Change detection
    pub fn getModifiedAssets(self: *AssetDatabase) ![][]const u8;
    pub fn getDirtyAssets(self: *AssetDatabase) ![][]const u8;

    // Persistence
    pub fn save(self: *AssetDatabase) !void;
    pub fn load(self: *AssetDatabase) !void;
};

pub const AssetEntry = struct {
    path: []const u8,
    asset_type: AssetType,
    source_hash: u64,
    processed_hash: ?u64,
    last_modified: i64,
    last_processed: i64,
    output_paths: [][]const u8,
    metadata: AssetMetadata,
    state: AssetState,
};

pub const AssetState = enum {
    unprocessed,
    processing,
    processed,
    error,
};

pub const AssetType = enum {
    texture,
    mesh,
    shader,
    audio,
    scene,
    font,
    script,
    unknown,

    pub fn fromExtension(ext: []const u8) AssetType;
};
```

#### Pipeline Processor

```zig
pub const Pipeline = struct {
    allocator: Allocator,
    database: *AssetDatabase,
    processors: std.EnumMap(AssetType, *Processor),
    config: PipelineConfig,

    // Thread pool for parallel processing
    thread_pool: *ThreadPool,

    pub fn init(allocator: Allocator, config: PipelineConfig) !Pipeline;

    pub fn process(self: *Pipeline, asset_path: []const u8) !void;
    pub fn processAll(self: *Pipeline) !BuildResult;
    pub fn processDirty(self: *Pipeline) !BuildResult;

    pub fn watch(self: *Pipeline, callback: fn([]const u8) void) !void;
    pub fn stopWatch(self: *Pipeline) void;
};

pub const PipelineConfig = struct {
    source_path: []const u8,
    output_path: []const u8,
    cache_path: []const u8,
    target_platform: Platform,
    quality: QualityPreset,
    parallel_jobs: u32,
    verbose: bool,
};

pub const Platform = enum {
    desktop_windows,
    desktop_linux,
    desktop_macos,
    mobile_ios,
    mobile_android,
    web,
};

pub const QualityPreset = enum {
    low,
    medium,
    high,
    ultra,
};

pub const BuildResult = struct {
    processed: u32,
    skipped: u32,
    errors: u32,
    warnings: u32,
    duration_ms: u64,
    error_messages: []ErrorMessage,
};
```

### Asset Processors

#### Texture Processor

```zig
pub const TextureProcessor = struct {
    pub fn process(
        input_path: []const u8,
        output_path: []const u8,
        config: TextureConfig,
    ) !ProcessResult;

    pub const TextureConfig = struct {
        // Format
        format: TextureFormat,
        compression: CompressionFormat,

        // Sizing
        max_size: u32,
        power_of_two: bool,

        // Mipmaps
        generate_mipmaps: bool,
        mip_filter: MipFilter,

        // Processing
        srgb: bool,
        premultiply_alpha: bool,
        flip_y: bool,

        // Normal maps
        is_normal_map: bool,
        normalize: bool,
    };

    pub const CompressionFormat = enum {
        none,
        bc1,        // RGB, 4bpp (DXT1)
        bc3,        // RGBA, 8bpp (DXT5)
        bc5,        // RG, 8bpp (normal maps)
        bc7,        // RGBA, 8bpp (high quality)
        astc_4x4,   // Mobile, 8bpp
        astc_6x6,   // Mobile, 3.56bpp
        astc_8x8,   // Mobile, 2bpp
        etc2_rgb,   // Mobile fallback
        etc2_rgba,
    };
};

// Processing steps:
// 1. Load source image
// 2. Resize if needed
// 3. Generate mipmaps
// 4. Compress to target format
// 5. Save processed texture
```

#### Mesh Processor

```zig
pub const MeshProcessor = struct {
    pub fn process(
        input_path: []const u8,
        output_path: []const u8,
        config: MeshConfig,
    ) !ProcessResult;

    pub const MeshConfig = struct {
        // Optimization
        optimize_vertex_cache: bool,
        optimize_overdraw: bool,
        optimize_vertex_fetch: bool,

        // Simplification
        generate_lods: bool,
        lod_levels: []LODLevel,

        // Vertex format
        compress_vertices: bool,
        quantize_positions: bool,
        quantize_normals: bool,

        // Tangent space
        generate_tangents: bool,

        // Bounds
        calculate_bounds: bool,
    };

    pub const LODLevel = struct {
        target_ratio: f32,      // 0.5 = 50% triangles
        max_error: f32,         // Allowed simplification error
        distance: f32,          // Switch distance from camera
    };
};

// Processing steps:
// 1. Import mesh from glTF/OBJ/FBX
// 2. Optimize vertex order (cache optimization)
// 3. Generate LODs
// 4. Calculate tangent space
// 5. Compress vertex attributes
// 6. Calculate bounds
// 7. Export processed mesh
```

#### Shader Processor

```zig
pub const ShaderProcessor = struct {
    pub fn process(
        input_path: []const u8,
        output_path: []const u8,
        config: ShaderConfig,
    ) !ProcessResult;

    pub const ShaderConfig = struct {
        target_api: GraphicsAPI,
        optimization_level: OptLevel,
        debug_info: bool,
        defines: []Define,
        include_paths: [][]const u8,
    };

    pub const GraphicsAPI = enum {
        vulkan_spirv,
        metal_msl,
        opengl_glsl,
        directx_dxil,
    };

    pub const Define = struct {
        name: []const u8,
        value: ?[]const u8,
    };

    // Validate shader
    pub fn validate(shader_path: []const u8) !ValidationResult;

    // Compile for multiple targets
    pub fn compileVariants(
        shader_path: []const u8,
        variants: []ShaderVariant,
    ) ![]CompiledShader;
};

pub const ShaderVariant = struct {
    defines: []Define,
    name: []const u8,
};

pub const CompiledShader = struct {
    variant_name: []const u8,
    api: GraphicsAPI,
    bytecode: []const u8,
    reflection: ShaderReflection,
};

pub const ShaderReflection = struct {
    inputs: []ShaderInput,
    outputs: []ShaderOutput,
    uniforms: []UniformInfo,
    textures: []TextureInfo,
    push_constants: ?PushConstantInfo,
};
```

#### Audio Processor

```zig
pub const AudioProcessor = struct {
    pub fn process(
        input_path: []const u8,
        output_path: []const u8,
        config: AudioConfig,
    ) !ProcessResult;

    pub const AudioConfig = struct {
        format: AudioFormat,
        sample_rate: u32,
        channels: u32,
        bit_depth: u32,

        // Compression
        compression: AudioCompression,
        quality: f32,         // 0.0 to 1.0

        // Processing
        normalize: bool,
        trim_silence: bool,

        // Streaming
        stream_threshold: u64,  // File size threshold for streaming
    };

    pub const AudioCompression = enum {
        none,      // Raw PCM
        ogg,       // Vorbis
        mp3,       // MP3
        opus,      // Opus (best quality/size)
        adpcm,     // IMA ADPCM (fast decode)
    };
};
```

### Asset Bundling

```zig
pub const BundleBuilder = struct {
    allocator: Allocator,
    entries: std.ArrayList(BundleEntry),
    compression: BundleCompression,

    pub fn init(allocator: Allocator) BundleBuilder;

    pub fn addAsset(self: *BundleBuilder, path: []const u8, data: []const u8) !void;
    pub fn addDirectory(self: *BundleBuilder, dir_path: []const u8) !void;

    pub fn build(self: *BundleBuilder, output_path: []const u8) !void;

    // Create multiple bundles by category
    pub fn buildCategorized(
        self: *BundleBuilder,
        categories: []Category,
    ) ![]BundleOutput;
};

pub const BundleEntry = struct {
    virtual_path: []const u8,
    data: []const u8,
    compressed_size: u64,
    original_size: u64,
    hash: u64,
};

pub const BundleCompression = enum {
    none,
    lz4,
    zstd,
};

// Bundle file format
pub const BundleHeader = extern struct {
    magic: [4]u8,          // "ZDLB"
    version: u32,
    compression: u32,
    entry_count: u32,
    index_offset: u64,
    index_size: u64,
    data_offset: u64,
    data_size: u64,
};

pub const BundleIndex = extern struct {
    path_offset: u32,
    path_length: u32,
    data_offset: u64,
    compressed_size: u64,
    original_size: u64,
    hash: u64,
};
```

### Runtime Asset Manager

```zig
pub const AssetManager = struct {
    allocator: Allocator,
    device: *Device,

    // Caches
    textures: std.StringHashMap(*Texture),
    meshes: std.StringHashMap(*Mesh),
    materials: std.StringHashMap(*Material),
    sounds: std.StringHashMap(*Sound),

    // Bundles
    bundles: std.ArrayList(*AssetBundle),

    // Loading
    load_queue: std.ArrayList(LoadRequest),
    loading_thread: ?std.Thread,

    pub fn init(allocator: Allocator, device: *Device) !AssetManager;

    // Synchronous loading
    pub fn loadTexture(self: *AssetManager, path: []const u8) !*Texture;
    pub fn loadMesh(self: *AssetManager, path: []const u8) !*Mesh;
    pub fn loadSound(self: *AssetManager, path: []const u8) !*Sound;

    // Async loading
    pub fn loadAsync(self: *AssetManager, path: []const u8, callback: LoadCallback) void;
    pub fn loadBatch(self: *AssetManager, paths: [][]const u8, callback: BatchCallback) void;

    // Bundle management
    pub fn mountBundle(self: *AssetManager, bundle_path: []const u8) !void;
    pub fn unmountBundle(self: *AssetManager, bundle_path: []const u8) void;

    // Memory management
    pub fn unload(self: *AssetManager, path: []const u8) void;
    pub fn unloadUnused(self: *AssetManager) void;
    pub fn getMemoryUsage(self: *AssetManager) MemoryStats;
};

pub const AssetBundle = struct {
    file: std.fs.File,
    header: BundleHeader,
    index: []BundleIndex,
    path_table: []const u8,

    pub fn open(path: []const u8) !AssetBundle;
    pub fn contains(self: *AssetBundle, asset_path: []const u8) bool;
    pub fn load(self: *AssetBundle, asset_path: []const u8) ![]const u8;
    pub fn close(self: *AssetBundle) void;
};
```

### Hot Reloading

```zig
pub const HotReloader = struct {
    allocator: Allocator,
    asset_manager: *AssetManager,
    watch_paths: std.ArrayList([]const u8),
    file_watcher: FileWatcher,

    // Reload callbacks
    on_texture_reload: ?fn(*Texture, []const u8) void,
    on_shader_reload: ?fn(*Shader, []const u8) void,
    on_script_reload: ?fn([]const u8) void,

    pub fn init(allocator: Allocator, asset_manager: *AssetManager) !HotReloader;

    pub fn watch(self: *HotReloader, path: []const u8) !void;
    pub fn unwatch(self: *HotReloader, path: []const u8) void;

    pub fn update(self: *HotReloader) void {
        while (self.file_watcher.getChanges()) |change| {
            self.reloadAsset(change.path);
        }
    }

    fn reloadAsset(self: *HotReloader, path: []const u8) void {
        const asset_type = AssetType.fromExtension(std.fs.path.extension(path));

        switch (asset_type) {
            .texture => self.reloadTexture(path),
            .shader => self.reloadShader(path),
            .script => if (self.on_script_reload) |cb| cb(path),
            else => {},
        }
    }
};
```

### Import Presets

```zig
// Asset import settings via .meta files or embedded config
pub const ImportPreset = struct {
    name: []const u8,
    asset_type: AssetType,
    settings: Settings,

    pub const Settings = union(enum) {
        texture: TextureProcessor.TextureConfig,
        mesh: MeshProcessor.MeshConfig,
        audio: AudioProcessor.AudioConfig,
    };
};

// Example: textures/player.png.meta
// {
//   "preset": "character_texture",
//   "settings": {
//     "format": "bc7",
//     "srgb": true,
//     "generate_mipmaps": true,
//     "max_size": 2048
//   }
// }

pub const PresetManager = struct {
    presets: std.StringHashMap(ImportPreset),

    pub fn loadPresets(self: *PresetManager, path: []const u8) !void;
    pub fn getPreset(self: *PresetManager, name: []const u8) ?ImportPreset;
    pub fn getPresetForAsset(self: *PresetManager, asset_path: []const u8) ?ImportPreset;
};
```

## Implementation Steps

### Phase 1: Core Pipeline
1. Create asset database structure
2. Implement file scanning and hashing
3. Create basic processor interface
4. Add dependency tracking

### Phase 2: Texture Processing
1. Integrate image loading libraries
2. Implement mipmap generation
3. Add BC compression (desktop)
4. Add ASTC compression (mobile)

### Phase 3: Mesh Processing
1. Implement mesh optimization
2. Add LOD generation
3. Create binary mesh format
4. Implement vertex compression

### Phase 4: Shader Processing
1. Integrate glslang/SPIRV-Tools
2. Implement shader validation
3. Add variant compilation
4. Generate reflection data

### Phase 5: Build System
1. Create CLI tool
2. Implement parallel processing
3. Add incremental builds
4. Create build caching

### Phase 6: Bundling
1. Design bundle format
2. Implement bundle creation
3. Add compression support
4. Create bundle mounting

### Phase 7: Hot Reloading
1. Implement file watching
2. Create reload system
3. Integrate with asset manager
4. Add shader hot-reload

## CLI Usage Examples

```bash
# Build all assets for desktop
zdl-assets build --platform=desktop --output=build/desktop

# Build with specific quality
zdl-assets build --quality=high --verbose

# Watch mode for development
zdl-assets watch --source=assets --hot-reload

# Clean build cache
zdl-assets clean --all

# Create distribution bundle
zdl-assets bundle --output=game.pak --compress=zstd

# Process single asset
zdl-assets process assets/textures/hero.png --force

# Show asset info
zdl-assets info assets/models/character.gltf

# Validate shaders
zdl-assets validate shaders/*.vert shaders/*.frag
```

## Performance Considerations

- **Parallel Processing**: Use all CPU cores for independent assets
- **Incremental Builds**: Only process changed assets
- **Caching**: Cache intermediate results
- **Compression**: LZ4 for speed, Zstd for size
- **Streaming**: Support large asset streaming

## References

- [meshoptimizer](https://github.com/zeux/meshoptimizer) - Mesh optimization
- [basis_universal](https://github.com/BinomialLLC/basis_universal) - Texture compression
- [SPIRV-Tools](https://github.com/KhronosGroup/SPIRV-Tools) - Shader tools
- [Unity Asset Pipeline](https://docs.unity3d.com/Manual/AssetWorkflow.html)
- [Unreal Cooking](https://docs.unrealengine.com/5.0/en-US/cooking-content-in-unreal-engine/)
