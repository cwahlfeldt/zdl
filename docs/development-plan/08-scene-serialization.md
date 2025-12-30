# Scene Serialization System

## Overview

Implement a robust scene serialization system for saving and loading game scenes, supporting level editors, save games, and asset pipelines. This enables persistent game worlds, editor workflows, and data-driven scene creation.

## Current State

ZDL currently has:
- Programmatic scene creation only
- No save/load capability
- No scene file format
- Scenes exist only in memory

## Goals

- Define a scene file format (human-readable and binary)
- Serialize all entity and component data
- Support hierarchical relationships
- Enable incremental/streaming loading
- Handle asset references (meshes, textures)
- Support scene inheritance/prefabs
- Enable undo/redo in editors
- Maintain backwards compatibility

## Architecture

### Directory Structure

```
src/
├── serialization/
│   ├── serialization.zig      # Module exports
│   ├── scene_serializer.zig   # Scene save/load
│   ├── json_format.zig        # JSON scene format
│   ├── binary_format.zig      # Binary scene format
│   ├── component_registry.zig # Component type registry
│   ├── asset_refs.zig         # Asset reference handling
│   ├── prefab.zig             # Prefab system
│   └── migration.zig          # Version migration
```

### Scene File Format

#### JSON Format (Human-Readable)

```json
{
  "version": "1.0.0",
  "name": "Level 1",
  "metadata": {
    "author": "Developer",
    "created": "2025-01-15T10:30:00Z",
    "modified": "2025-01-15T14:20:00Z"
  },
  "settings": {
    "environment": {
      "ambient_color": [0.1, 0.1, 0.15],
      "ambient_intensity": 0.3,
      "skybox": "assets/skyboxes/sunset.hdr"
    },
    "physics": {
      "gravity": [0, -9.81, 0]
    }
  },
  "assets": {
    "meshes": {
      "cube_mesh": "assets/meshes/cube.gltf",
      "player_mesh": "assets/characters/player.gltf"
    },
    "textures": {
      "ground_tex": "assets/textures/ground.png",
      "player_tex": "assets/textures/player_diffuse.png"
    },
    "materials": {
      "ground_mat": {
        "base_color": [0.5, 0.5, 0.5, 1.0],
        "metallic": 0.0,
        "roughness": 0.8,
        "albedo_texture": "ground_tex"
      }
    }
  },
  "entities": [
    {
      "id": 1,
      "name": "Main Camera",
      "tags": ["camera", "main"],
      "components": {
        "Transform": {
          "position": [0, 2, 5],
          "rotation": [0, 0, 0, 1],
          "scale": [1, 1, 1]
        },
        "Camera": {
          "fov": 60,
          "near": 0.1,
          "far": 1000
        },
        "FpvCameraController": {
          "sensitivity": 0.002,
          "move_speed": 5.0
        }
      }
    },
    {
      "id": 2,
      "name": "Ground",
      "components": {
        "Transform": {
          "position": [0, 0, 0],
          "rotation": [0, 0, 0, 1],
          "scale": [10, 1, 10]
        },
        "MeshRenderer": {
          "mesh": "cube_mesh",
          "material": "ground_mat"
        }
      }
    },
    {
      "id": 3,
      "name": "Player",
      "parent": null,
      "children": [4],
      "components": {
        "Transform": {
          "position": [0, 1, 0],
          "rotation": [0, 0, 0, 1],
          "scale": [1, 1, 1]
        },
        "MeshRenderer": {
          "mesh": "player_mesh",
          "texture": "player_tex"
        },
        "Script": {
          "path": "scripts/player_controller.js"
        }
      }
    },
    {
      "id": 4,
      "name": "PlayerCamera",
      "parent": 3,
      "components": {
        "Transform": {
          "position": [0, 1.5, 0],
          "rotation": [0, 0, 0, 1],
          "scale": [1, 1, 1]
        }
      }
    }
  ],
  "prefab_instances": [
    {
      "prefab": "prefabs/tree.prefab",
      "overrides": {
        "Transform.position": [5, 0, 3]
      }
    }
  ]
}
```

#### Binary Format (Optimized)

```zig
pub const BinarySceneHeader = extern struct {
    magic: [4]u8,              // "ZDLS"
    version: u32,              // Format version
    flags: u32,                // Compression, endianness
    entity_count: u32,
    component_data_offset: u64,
    asset_table_offset: u64,
    string_table_offset: u64,
    total_size: u64,
};

pub const BinaryEntityHeader = extern struct {
    id: u32,
    name_offset: u32,          // Into string table
    parent_id: u32,            // 0 = no parent
    component_mask: u64,       // Bit flags for component types
    component_data_offset: u64,
};
```

### Core Components

#### Component Registry

```zig
pub const ComponentRegistry = struct {
    allocator: Allocator,
    types: std.StringHashMap(ComponentTypeInfo),

    pub fn init(allocator: Allocator) ComponentRegistry;

    pub fn register(
        self: *ComponentRegistry,
        comptime T: type,
        name: []const u8,
    ) void {
        self.types.put(name, ComponentTypeInfo{
            .name = name,
            .size = @sizeOf(T),
            .serialize = @ptrCast(&serializeComponent(T)),
            .deserialize = @ptrCast(&deserializeComponent(T)),
            .default = @ptrCast(&T.init),
        });
    }

    pub fn getTypeInfo(self: *ComponentRegistry, name: []const u8) ?ComponentTypeInfo;
};

pub const ComponentTypeInfo = struct {
    name: []const u8,
    size: usize,
    serialize: SerializeFn,
    deserialize: DeserializeFn,
    default: DefaultFn,
    migrate: ?MigrateFn,
};

// Register built-in components
pub fn registerBuiltinComponents(registry: *ComponentRegistry) void {
    registry.register(TransformComponent, "Transform");
    registry.register(CameraComponent, "Camera");
    registry.register(MeshRendererComponent, "MeshRenderer");
    registry.register(LightComponent, "Light");
    registry.register(FpvCameraController, "FpvCameraController");
}
```

#### Scene Serializer

```zig
pub const SceneSerializer = struct {
    allocator: Allocator,
    registry: *ComponentRegistry,
    asset_resolver: *AssetResolver,

    pub fn init(
        allocator: Allocator,
        registry: *ComponentRegistry,
        asset_resolver: *AssetResolver,
    ) SceneSerializer;

    // Save
    pub fn saveToJson(self: *SceneSerializer, scene: *Scene, path: []const u8) !void;
    pub fn saveToBinary(self: *SceneSerializer, scene: *Scene, path: []const u8) !void;
    pub fn serializeToJson(self: *SceneSerializer, scene: *Scene) ![]const u8;
    pub fn serializeToBinary(self: *SceneSerializer, scene: *Scene) ![]const u8;

    // Load
    pub fn loadFromJson(self: *SceneSerializer, path: []const u8) !*Scene;
    pub fn loadFromBinary(self: *SceneSerializer, path: []const u8) !*Scene;
    pub fn deserializeFromJson(self: *SceneSerializer, data: []const u8) !*Scene;
    pub fn deserializeFromBinary(self: *SceneSerializer, data: []const u8) !*Scene;

    // Streaming load
    pub fn beginStreamLoad(self: *SceneSerializer, path: []const u8) !StreamLoader;
};

pub const StreamLoader = struct {
    serializer: *SceneSerializer,
    scene: *Scene,
    remaining_entities: u32,
    state: LoadState,

    pub fn loadChunk(self: *StreamLoader, max_entities: u32) !bool;
    pub fn getProgress(self: *StreamLoader) f32;
    pub fn cancel(self: *StreamLoader) void;
};
```

#### Component Serialization

```zig
pub fn serializeComponent(comptime T: type) fn(*T, *JsonWriter) void {
    return struct {
        fn serialize(component: *T, writer: *JsonWriter) void {
            inline for (@typeInfo(T).Struct.fields) |field| {
                const value = @field(component, field.name);
                serializeField(writer, field.name, value);
            }
        }
    }.serialize;
}

pub fn deserializeComponent(comptime T: type) fn(*JsonReader, Allocator) !T {
    return struct {
        fn deserialize(reader: *JsonReader, allocator: Allocator) !T {
            var component = T.init();
            while (reader.next()) |key| {
                inline for (@typeInfo(T).Struct.fields) |field| {
                    if (std.mem.eql(u8, key, field.name)) {
                        @field(component, field.name) = try deserializeField(
                            reader,
                            field.type,
                            allocator,
                        );
                    }
                }
            }
            return component;
        }
    }.deserialize;
}

// Handle special types
fn serializeField(writer: *JsonWriter, name: []const u8, value: anytype) void {
    const T = @TypeOf(value);
    switch (T) {
        Vec3 => writer.writeArray(name, &.{ value.x, value.y, value.z }),
        Quat => writer.writeArray(name, &.{ value.x, value.y, value.z, value.w }),
        *Mesh => writer.writeString(name, value.name),
        *Texture => writer.writeString(name, value.path),
        else => writer.write(name, value),
    }
}
```

### Asset Reference System

```zig
pub const AssetRef = struct {
    path: []const u8,
    asset_type: AssetType,
    loaded: ?*anyopaque,

    pub fn resolve(self: *AssetRef, resolver: *AssetResolver) !*anyopaque;
};

pub const AssetType = enum {
    mesh,
    texture,
    material,
    audio,
    script,
    prefab,
};

pub const AssetResolver = struct {
    base_path: []const u8,
    asset_manager: *AssetManager,

    // Maps serialized paths to runtime assets
    mesh_map: std.StringHashMap(*Mesh),
    texture_map: std.StringHashMap(*Texture),
    material_map: std.StringHashMap(*Material),

    pub fn resolveMesh(self: *AssetResolver, path: []const u8) !*Mesh;
    pub fn resolveTexture(self: *AssetResolver, path: []const u8) !*Texture;
    pub fn resolveMaterial(self: *AssetResolver, path: []const u8) !*Material;

    // Collect referenced assets for scene
    pub fn collectReferences(self: *AssetResolver, scene: *Scene) ![]AssetRef;
};
```

### Prefab System

```zig
pub const Prefab = struct {
    name: []const u8,
    root_entity: SerializedEntity,
    children: []SerializedEntity,

    pub fn load(allocator: Allocator, path: []const u8) !Prefab;
    pub fn save(self: *Prefab, path: []const u8) !void;

    pub fn instantiate(
        self: *Prefab,
        scene: *Scene,
        position: Vec3,
        rotation: Quat,
    ) !Entity;
};

pub const PrefabInstance = struct {
    prefab: *Prefab,
    root_entity: Entity,
    overrides: std.StringHashMap(SerializedValue),

    pub fn applyOverride(self: *PrefabInstance, property_path: []const u8, value: SerializedValue) void;
    pub fn resetOverride(self: *PrefabInstance, property_path: []const u8) void;
    pub fn syncWithPrefab(self: *PrefabInstance) void;
};

pub const SerializedValue = union(enum) {
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: []const u8,
    vec3_val: Vec3,
    quat_val: Quat,
};
```

### Version Migration

```zig
pub const VersionMigrator = struct {
    migrations: std.ArrayList(Migration),

    pub fn addMigration(self: *VersionMigrator, from: Version, to: Version, migrate_fn: MigrateFn) void;

    pub fn migrate(
        self: *VersionMigrator,
        data: *JsonValue,
        from_version: Version,
        to_version: Version,
    ) !void;
};

pub const Migration = struct {
    from_version: Version,
    to_version: Version,
    migrate: fn(*JsonValue) !void,
};

// Example migrations
pub fn registerMigrations(migrator: *VersionMigrator) void {
    // v1.0.0 -> v1.1.0: Renamed "position" to "local_position" in Transform
    migrator.addMigration(.{ 1, 0, 0 }, .{ 1, 1, 0 }, struct {
        fn migrate(data: *JsonValue) !void {
            for (data.get("entities").?.array()) |entity| {
                if (entity.get("components")?.get("Transform")) |transform| {
                    if (transform.get("position")) |pos| {
                        transform.put("local_position", pos);
                        transform.remove("position");
                    }
                }
            }
        }
    }.migrate);
}
```

### Undo/Redo System (For Editors)

```zig
pub const SceneHistory = struct {
    undo_stack: std.ArrayList(SceneSnapshot),
    redo_stack: std.ArrayList(SceneSnapshot),
    max_history: usize,

    pub fn init(allocator: Allocator, max_history: usize) SceneHistory;

    pub fn pushState(self: *SceneHistory, scene: *Scene) void;
    pub fn undo(self: *SceneHistory, scene: *Scene) ?void;
    pub fn redo(self: *SceneHistory, scene: *Scene) ?void;

    pub fn canUndo(self: *SceneHistory) bool;
    pub fn canRedo(self: *SceneHistory) bool;
    pub fn clear(self: *SceneHistory) void;
};

pub const SceneSnapshot = struct {
    data: []const u8,
    description: []const u8,
    timestamp: i64,
};

// For more granular undo, use command pattern
pub const EditCommand = union(enum) {
    create_entity: struct { entity_data: SerializedEntity },
    delete_entity: struct { entity: Entity, data: SerializedEntity },
    modify_component: struct {
        entity: Entity,
        component_type: []const u8,
        old_value: []const u8,
        new_value: []const u8,
    },
    reparent: struct {
        entity: Entity,
        old_parent: ?Entity,
        new_parent: ?Entity,
    },

    pub fn execute(self: *EditCommand, scene: *Scene) void;
    pub fn undo(self: *EditCommand, scene: *Scene) void;
};
```

## Implementation Steps

### Phase 1: Component Registry
1. Create component type registry
2. Implement compile-time serialization traits
3. Register built-in component types
4. Support custom component registration

### Phase 2: JSON Serialization
1. Implement JSON writer/reader utilities
2. Serialize basic component types
3. Handle entity hierarchy (parent/child)
4. Serialize scene settings

### Phase 3: Asset References
1. Create asset reference type
2. Implement path resolution
3. Handle mesh/texture references
4. Support relative/absolute paths

### Phase 4: Scene Loading
1. Parse JSON scene files
2. Create entities from data
3. Resolve asset references
4. Restore hierarchy relationships

### Phase 5: Binary Format
1. Design binary header structure
2. Implement binary writer
3. Implement binary reader
4. Add compression support (optional)

### Phase 6: Prefab System
1. Define prefab file format
2. Implement prefab instantiation
3. Support property overrides
4. Handle nested prefabs

### Phase 7: Version Migration
1. Add version to scene format
2. Create migration framework
3. Implement common migrations
4. Test upgrade paths

### Phase 8: Editor Support
1. Implement undo/redo stack
2. Create command pattern for edits
3. Support partial scene updates
4. Add scene diffing for changes

## Usage Examples

### Saving a Scene

```zig
pub fn saveLevel(scene: *Scene, path: []const u8) !void {
    var serializer = SceneSerializer.init(allocator, registry, asset_resolver);
    try serializer.saveToJson(scene, path);
}
```

### Loading a Scene

```zig
pub fn loadLevel(path: []const u8) !*Scene {
    var serializer = SceneSerializer.init(allocator, registry, asset_resolver);
    return try serializer.loadFromJson(path);
}
```

### Using Prefabs

```zig
// Load prefab
const tree_prefab = try Prefab.load(allocator, "prefabs/tree.prefab");

// Instantiate multiple trees
for (tree_positions) |pos| {
    const tree = try tree_prefab.instantiate(scene, pos, Quat.identity());

    // Override specific properties
    const instance = scene.getPrefabInstance(tree);
    instance.applyOverride("Transform.scale", .{ .vec3_val = Vec3.init(1.5, 1.5, 1.5) });
}
```

### Streaming Load for Large Levels

```zig
pub fn loadLargeLevel(path: []const u8, progress_callback: fn(f32) void) !*Scene {
    var serializer = SceneSerializer.init(allocator, registry, asset_resolver);
    var loader = try serializer.beginStreamLoad(path);

    while (try loader.loadChunk(100)) {
        progress_callback(loader.getProgress());

        // Yield to allow rendering loading screen
        yield();
    }

    return loader.scene;
}
```

## Integration Points

### Editor Integration

```zig
pub const SceneEditor = struct {
    scene: *Scene,
    serializer: *SceneSerializer,
    history: SceneHistory,

    pub fn save(self: *SceneEditor) !void {
        try self.serializer.saveToJson(self.scene, self.current_path);
        self.dirty = false;
    }

    pub fn load(self: *SceneEditor, path: []const u8) !void {
        self.scene = try self.serializer.loadFromJson(path);
        self.history.clear();
        self.dirty = false;
    }

    pub fn undo(self: *SceneEditor) void {
        if (self.history.undo(self.scene)) {
            self.dirty = true;
        }
    }
};
```

### Game Save System

```zig
pub const SaveGame = struct {
    scene_data: []const u8,
    player_state: PlayerState,
    game_time: f64,
    checkpoint: []const u8,

    pub fn save(scene: *Scene, player: *Player) !SaveGame;
    pub fn load(self: *SaveGame, scene: *Scene, player: *Player) !void;
};
```

## Performance Considerations

- **Lazy Loading**: Load assets on demand, not all at once
- **Compression**: Use LZ4 for binary format
- **Streaming**: Load large scenes in chunks
- **Caching**: Cache parsed scene data
- **Differencing**: Only save changed entities for saves

## References

- [Unity Scene Format](https://docs.unity3d.com/Manual/FormatDescription.html)
- [Godot Scene Format](https://docs.godotengine.org/en/stable/development/file_formats/tscn.html)
- [glTF for Scenes](https://www.khronos.org/gltf/)
- [Prefab Systems](https://docs.unity3d.com/Manual/Prefabs.html)
