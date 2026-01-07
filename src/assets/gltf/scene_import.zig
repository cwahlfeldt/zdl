const std = @import("std");
const types = @import("types.zig");
const mesh_import = @import("mesh_import.zig");
const texture_import = @import("texture_import.zig");
const GLTFError = types.GLTFError;
const GLTFAsset = types.GLTFAsset;
const NodeData = types.NodeData;
const SceneData = types.SceneData;
const MeshPrimitiveKey = types.MeshPrimitiveKey;

const Scene = @import("../../ecs/scene.zig").Scene;
const Entity = @import("../../ecs/entity.zig").Entity;
const TransformComponent = @import("../../ecs/components/transform_component.zig").TransformComponent;
const CameraComponent = @import("../../ecs/components/camera_component.zig").CameraComponent;
const MeshRendererComponent = @import("../../ecs/components/mesh_renderer.zig").MeshRendererComponent;
const Vec3 = @import("../../math/vec3.zig").Vec3;
const Quat = @import("../../math/quat.zig").Quat;
const Vec4 = @import("../../math/vec4.zig").Vec4;
const Material = @import("../../resources/material.zig").Material;

/// Import a glTF scene into an ECS Scene
/// Returns array of root entities (caller owns slice)
pub fn importScene(
    asset: *const GLTFAsset,
    ecs_scene: *Scene,
    scene_index: ?usize,
) ![]Entity {
    // Get the scene to import
    const gltf_scene = blk: {
        if (scene_index) |idx| {
            if (idx >= asset.scenes.len) return GLTFError.InvalidPath;
            break :blk asset.scenes[idx];
        } else if (asset.default_scene) |def| {
            break :blk asset.scenes[def];
        } else if (asset.scenes.len > 0) {
            break :blk asset.scenes[0];
        } else {
            // No scenes - import all nodes as roots
            return importAllNodes(asset, ecs_scene);
        }
    };

    var imported_entities = std.ArrayListUnmanaged(Entity){};
    errdefer imported_entities.deinit(ecs_scene.allocator);

    // Import all root nodes
    for (gltf_scene.nodes) |node_index| {
        const entity = try importNode(asset, ecs_scene, node_index, null);
        try imported_entities.append(ecs_scene.allocator, entity);
    }

    return imported_entities.toOwnedSlice(ecs_scene.allocator);
}

/// Import all nodes as root entities (when no scene is defined)
fn importAllNodes(asset: *const GLTFAsset, ecs_scene: *Scene) ![]Entity {
    var imported_entities = std.ArrayListUnmanaged(Entity){};
    errdefer imported_entities.deinit(ecs_scene.allocator);

    // Find nodes that are not children of any other node
    const is_child = try ecs_scene.allocator.alloc(bool, asset.nodes.len);
    defer ecs_scene.allocator.free(is_child);
    @memset(is_child, false);

    for (asset.nodes) |node| {
        for (node.children) |child_idx| {
            if (child_idx < is_child.len) {
                is_child[child_idx] = true;
            }
        }
    }

    // Import root nodes
    for (0..asset.nodes.len) |node_index| {
        if (!is_child[node_index]) {
            const entity = try importNode(asset, ecs_scene, node_index, null);
            try imported_entities.append(ecs_scene.allocator, entity);
        }
    }

    return imported_entities.toOwnedSlice(ecs_scene.allocator);
}

/// Import a single node and its children recursively
fn importNode(
    asset: *const GLTFAsset,
    ecs_scene: *Scene,
    node_index: usize,
    parent: ?Entity,
) !Entity {
    if (node_index >= asset.nodes.len) {
        return GLTFError.InvalidPath;
    }

    const node = asset.nodes[node_index];
    const entity = ecs_scene.createEntity();

    // Add TransformComponent
    var transform = TransformComponent.init();
    const node_transform = node.getTransform();
    transform.local.position = node_transform.position;
    transform.local.rotation = node_transform.rotation;
    transform.local.scale = node_transform.scale;
    ecs_scene.addComponent(entity, transform);

    // Set parent if provided
    if (parent) |p| {
        ecs_scene.setParent(entity, p);
    }

    // Add MeshRendererComponent if node has mesh
    if (node.mesh_index) |mesh_idx| {
        if (mesh_idx < asset.meshes.len) {
            const mesh_data = asset.meshes[mesh_idx];

            if (mesh_data.primitives.len == 1) {
                // Single primitive - add directly to this entity
                try addMeshRenderer(asset, ecs_scene, entity, mesh_idx, 0);
            } else {
                // Multiple primitives - create child entities for each
                for (mesh_data.primitives, 0..) |_, prim_idx| {
                    const child = ecs_scene.createEntity();
                    ecs_scene.addComponent(child, TransformComponent.init());
                    ecs_scene.setParent(child, entity);
                    try addMeshRenderer(asset, ecs_scene, child, mesh_idx, prim_idx);
                }
            }
        }
    }

    // Add CameraComponent if node has camera
    if (node.camera_index) |cam_idx| {
        if (cam_idx < asset.cameras.len) {
            const cam_data = asset.cameras[cam_idx];
            if (cam_data.camera_type == .perspective) {
                const cam = CameraComponent.initWithSettings(
                    cam_data.yfov,
                    cam_data.znear,
                    cam_data.zfar orelse 1000.0,
                );
                ecs_scene.addComponent(entity, cam);
            }
        }
    }

    // Recursively import children
    for (node.children) |child_index| {
        _ = try importNode(asset, ecs_scene, child_index, entity);
    }

    return entity;
}

/// Add a MeshRendererComponent for a specific primitive
fn addMeshRenderer(
    asset: *const GLTFAsset,
    ecs_scene: *Scene,
    entity: Entity,
    mesh_idx: usize,
    prim_idx: usize,
) !void {
    const mesh = mesh_import.getGPUMesh(asset, mesh_idx, prim_idx) orelse return;

    var renderer = MeshRendererComponent.init(mesh);

    // Apply glTF material (PBR) and textures if available.
    const mesh_data = asset.meshes[mesh_idx];
    if (prim_idx < mesh_data.primitives.len) {
        const primitive = mesh_data.primitives[prim_idx];
        if (primitive.material) |mat_idx| {
            if (mat_idx < asset.materials.len) {
                const mat_data = asset.materials[mat_idx];
                var mat = Material.init();
                mat.base_color = Vec4.init(
                    mat_data.base_color_factor[0],
                    mat_data.base_color_factor[1],
                    mat_data.base_color_factor[2],
                    mat_data.base_color_factor[3],
                );
                mat.metallic = mat_data.metallic_factor;
                mat.roughness = mat_data.roughness_factor;
                mat.normal_scale = mat_data.normal_scale;
                mat.ao_strength = mat_data.occlusion_strength;
                mat.emissive = Vec3.init(
                    mat_data.emissive_factor[0],
                    mat_data.emissive_factor[1],
                    mat_data.emissive_factor[2],
                );
                mat.alpha_cutoff = mat_data.alpha_cutoff;
                mat.alpha_mode = switch (mat_data.alpha_mode) {
                    .@"opaque" => .@"opaque",
                    .mask => .mask,
                    .blend => .blend,
                };
                mat.double_sided = mat_data.double_sided;

                if (texture_import.getMaterialBaseColorTexture(asset, mat_idx)) |texture| {
                    mat.base_color_texture = texture;
                    renderer.texture = texture;
                }
                if (texture_import.getMaterialMetallicRoughnessTexture(asset, mat_idx)) |texture| {
                    mat.metallic_roughness_texture = texture;
                }
                if (texture_import.getMaterialNormalTexture(asset, mat_idx)) |texture| {
                    mat.normal_texture = texture;
                }
                if (texture_import.getMaterialOcclusionTexture(asset, mat_idx)) |texture| {
                    mat.ao_texture = texture;
                }
                if (texture_import.getMaterialEmissiveTexture(asset, mat_idx)) |texture| {
                    mat.emissive_texture = texture;
                }

                renderer.material = mat;
            } else if (texture_import.getMaterialBaseColorTexture(asset, mat_idx)) |texture| {
                renderer.texture = texture;
            }
        }
    }

    ecs_scene.addComponent(entity, renderer);
}

/// Get the default scene index (or 0 if none specified)
pub fn getDefaultSceneIndex(asset: *const GLTFAsset) usize {
    return asset.default_scene orelse 0;
}

/// Get the number of scenes in the asset
pub fn getSceneCount(asset: *const GLTFAsset) usize {
    return asset.scenes.len;
}

/// Get scene name (if available)
pub fn getSceneName(asset: *const GLTFAsset, scene_index: usize) ?[]const u8 {
    if (scene_index >= asset.scenes.len) return null;
    return asset.scenes[scene_index].name;
}
