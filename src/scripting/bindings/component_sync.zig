/// Component synchronization between JavaScript and native ECS
/// This module syncs JS components to native components for rendering
const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;
const Scene = @import("../../ecs/scene.zig").Scene;
const Entity = @import("../../ecs/entity.zig").Entity;
const TransformComponent = @import("../../ecs/components/transform_component.zig").TransformComponent;
const CameraComponent = @import("../../ecs/components/camera_component.zig").CameraComponent;
const MeshRendererComponent = @import("../../ecs/components/mesh_renderer.zig").MeshRendererComponent;
const LightComponent = @import("../../ecs/components/light_component.zig").LightComponent;
const Vec3 = @import("../../math/math.zig").Vec3;
const Vec4 = @import("../../math/math.zig").Vec4;
const Quat = @import("../../math/math.zig").Quat;
const Material = @import("../../resources/material.zig").Material;
const primitives = @import("../../resources/primitives.zig");
const Mesh = @import("../../resources/mesh.zig").Mesh;

// Global mesh cache for primitives created from JS
var primitive_meshes: std.StringHashMap(*Mesh) = undefined;
var mesh_cache_initialized = false;

pub fn init(allocator: std.mem.Allocator) void {
    if (!mesh_cache_initialized) {
        primitive_meshes = std.StringHashMap(*Mesh).init(allocator);
        mesh_cache_initialized = true;
    }
}

pub fn deinit(device: anytype) void {
    if (mesh_cache_initialized) {
        var it = primitive_meshes.valueIterator();
        while (it.next()) |mesh_ptr| {
            mesh_ptr.*.deinit(device);
            primitive_meshes.allocator.destroy(mesh_ptr.*);
        }
        primitive_meshes.deinit();
        mesh_cache_initialized = false;
    }
}

/// Sync all JS components to native components for rendering
pub fn syncComponentsToNative(ctx: *JSContext, scene: *Scene, allocator: std.mem.Allocator, device: anytype) !void {
    const component_store = ctx.getGlobal("__component_store");
    defer ctx.freeValue(component_store);

    if (ctx.isUndefined(component_store)) {
        std.debug.print("[ComponentSync] Component store is undefined\n", .{});
        return;
    }

    // Get all registered entities
    const entities_obj = ctx.getGlobal("__scene_entities");
    defer ctx.freeValue(entities_obj);

    // Iterate through entities
    var entity_id: u32 = 0;
    while (entity_id < 10000) : (entity_id += 1) {  // Reasonable upper limit
        var key_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity_id}) catch continue;

        const entity_exists = ctx.getProperty(entities_obj, key);
        defer ctx.freeValue(entity_exists);

        const exists = ctx.toBool(entity_exists) catch false;
        if (!exists) continue;

        const entity = Entity{ .id = entity_id };

        // Sync Transform
        try syncTransform(ctx, component_store, entity, scene);

        // Sync Camera
        try syncCamera(ctx, component_store, entity, scene);

        // Sync MeshRenderer
        try syncMeshRenderer(ctx, component_store, entity, scene, allocator, device);

        // Sync Light
        try syncLight(ctx, component_store, entity, scene);
    }
}

fn syncTransform(ctx: *JSContext, component_store: quickjs.Value, entity: Entity, scene: *Scene) !void {
    const transform_map = ctx.getProperty(component_store, "Transform");
    defer ctx.freeValue(transform_map);

    if (ctx.isUndefined(transform_map)) {
        std.debug.print("[ComponentSync] Transform map undefined for entity {d}\n", .{entity.id});
        return;
    }

    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch return;

    const transform_data = ctx.getProperty(transform_map, key);
    defer ctx.freeValue(transform_data);

    if (ctx.isUndefined(transform_data)) return;

    // Parse position
    const pos_val = ctx.getProperty(transform_data, "position");
    defer ctx.freeValue(pos_val);

    const position = if (!ctx.isUndefined(pos_val)) blk: {
        const x = ctx.toFloat32(ctx.getProperty(pos_val, "x")) catch 0;
        defer ctx.freeValue(ctx.getProperty(pos_val, "x"));
        const y = ctx.toFloat32(ctx.getProperty(pos_val, "y")) catch 0;
        defer ctx.freeValue(ctx.getProperty(pos_val, "y"));
        const z = ctx.toFloat32(ctx.getProperty(pos_val, "z")) catch 0;
        defer ctx.freeValue(ctx.getProperty(pos_val, "z"));
        break :blk Vec3.init(x, y, z);
    } else Vec3.zero();

    // Parse rotation (quaternion)
    const rot_val = ctx.getProperty(transform_data, "rotation");
    defer ctx.freeValue(rot_val);

    const rotation = if (!ctx.isUndefined(rot_val)) blk: {
        const x = ctx.toFloat32(ctx.getProperty(rot_val, "x")) catch 0;
        defer ctx.freeValue(ctx.getProperty(rot_val, "x"));
        const y = ctx.toFloat32(ctx.getProperty(rot_val, "y")) catch 0;
        defer ctx.freeValue(ctx.getProperty(rot_val, "y"));
        const z = ctx.toFloat32(ctx.getProperty(rot_val, "z")) catch 0;
        defer ctx.freeValue(ctx.getProperty(rot_val, "z"));
        const w = ctx.toFloat32(ctx.getProperty(rot_val, "w")) catch 1;
        defer ctx.freeValue(ctx.getProperty(rot_val, "w"));
        break :blk Quat.init(x, y, z, w);
    } else Quat.identity();

    // Parse scale
    const scale_val = ctx.getProperty(transform_data, "scale");
    defer ctx.freeValue(scale_val);

    const scale = if (!ctx.isUndefined(scale_val)) blk: {
        const x = ctx.toFloat32(ctx.getProperty(scale_val, "x")) catch 1;
        defer ctx.freeValue(ctx.getProperty(scale_val, "x"));
        const y = ctx.toFloat32(ctx.getProperty(scale_val, "y")) catch 1;
        defer ctx.freeValue(ctx.getProperty(scale_val, "y"));
        const z = ctx.toFloat32(ctx.getProperty(scale_val, "z")) catch 1;
        defer ctx.freeValue(ctx.getProperty(scale_val, "z"));
        break :blk Vec3.init(x, y, z);
    } else Vec3.init(1, 1, 1);

    // Create or update transform component
    if (scene.getComponent(TransformComponent, entity)) |transform| {
        transform.setPosition(position);
        transform.setRotation(rotation);
        transform.setScale(scale);
    } else {
        var transform = TransformComponent.init();
        transform.setPosition(position);
        transform.setRotation(rotation);
        transform.setScale(scale);
        scene.addComponent(entity, transform);
    }
}

fn syncCamera(ctx: *JSContext, component_store: quickjs.Value, entity: Entity, scene: *Scene) !void {
    const camera_map = ctx.getProperty(component_store, "Camera");
    defer ctx.freeValue(camera_map);

    if (ctx.isUndefined(camera_map)) return;

    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch return;

    const camera_data = ctx.getProperty(camera_map, key);
    defer ctx.freeValue(camera_data);

    if (ctx.isUndefined(camera_data)) return;

    const fov_val = ctx.getProperty(camera_data, "fov");
    defer ctx.freeValue(fov_val);
    const fov = ctx.toFloat32(fov_val) catch 1.0472; // Default 60 degrees

    const near_val = ctx.getProperty(camera_data, "near");
    defer ctx.freeValue(near_val);
    const near = ctx.toFloat32(near_val) catch 0.1;

    const far_val = ctx.getProperty(camera_data, "far");
    defer ctx.freeValue(far_val);
    const far = ctx.toFloat32(far_val) catch 1000.0;

    if (scene.getComponent(CameraComponent, entity)) |camera| {
        camera.fov = fov;
        camera.near = near;
        camera.far = far;
    } else {
        var camera = CameraComponent.init();
        camera.fov = fov;
        camera.near = near;
        camera.far = far;
        scene.addComponent(entity, camera);
    }
}

fn syncMeshRenderer(ctx: *JSContext, component_store: quickjs.Value, entity: Entity, scene: *Scene, allocator: std.mem.Allocator, device: anytype) !void {
    const mesh_map = ctx.getProperty(component_store, "MeshRenderer");
    defer ctx.freeValue(mesh_map);

    if (ctx.isUndefined(mesh_map)) return;

    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch return;

    const mesh_data = ctx.getProperty(mesh_map, key);
    defer ctx.freeValue(mesh_data);

    if (ctx.isUndefined(mesh_data)) return;

    const mesh_type_val = ctx.getProperty(mesh_data, "meshType");
    defer ctx.freeValue(mesh_type_val);

    const mesh_type_cstr = ctx.toCString(mesh_type_val) catch return;
    defer ctx.freeCString(mesh_type_cstr);
    const mesh_type = std.mem.span(mesh_type_cstr);

    // Get or create primitive mesh
    const mesh_ptr = try getOrCreatePrimitiveMesh(mesh_type, allocator, device);

    // Parse material
    const material_val = ctx.getProperty(mesh_data, "material");
    defer ctx.freeValue(material_val);

    const material = if (!ctx.isUndefined(material_val)) blk: {
        const base_color_val = ctx.getProperty(material_val, "baseColor");
        defer ctx.freeValue(base_color_val);

        const base_color = if (!ctx.isUndefined(base_color_val)) Vec4.init(
            ctx.toFloat32(ctx.getProperty(base_color_val, "x")) catch 1,
            ctx.toFloat32(ctx.getProperty(base_color_val, "y")) catch 1,
            ctx.toFloat32(ctx.getProperty(base_color_val, "z")) catch 1,
            ctx.toFloat32(ctx.getProperty(base_color_val, "w")) catch 1,
        ) else Vec4.init(1, 1, 1, 1);

        // Free the individual property values
        ctx.freeValue(ctx.getProperty(base_color_val, "x"));
        ctx.freeValue(ctx.getProperty(base_color_val, "y"));
        ctx.freeValue(ctx.getProperty(base_color_val, "z"));
        ctx.freeValue(ctx.getProperty(base_color_val, "w"));

        const metallic_val = ctx.getProperty(material_val, "metallic");
        defer ctx.freeValue(metallic_val);
        const metallic = ctx.toFloat32(metallic_val) catch 0;

        const roughness_val = ctx.getProperty(material_val, "roughness");
        defer ctx.freeValue(roughness_val);
        const roughness = ctx.toFloat32(roughness_val) catch 0.5;

        var mat = Material.init();
        mat.base_color = base_color;
        mat.metallic = metallic;
        mat.roughness = roughness;
        break :blk mat;
    } else Material.init();

    // Add or update mesh renderer
    if (!scene.hasComponent(MeshRendererComponent, entity)) {
        const renderer = MeshRendererComponent.fromMeshPtrWithMaterial(mesh_ptr, material);
        scene.addComponent(entity, renderer);
    }
}

fn syncLight(ctx: *JSContext, component_store: quickjs.Value, entity: Entity, scene: *Scene) !void {
    const light_map = ctx.getProperty(component_store, "Light");
    defer ctx.freeValue(light_map);

    if (ctx.isUndefined(light_map)) return;

    var key_buf: [64]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "{d}", .{entity.id}) catch return;

    const light_data = ctx.getProperty(light_map, key);
    defer ctx.freeValue(light_data);

    if (ctx.isUndefined(light_data)) return;

    const light_type_val = ctx.getProperty(light_data, "lightType");
    defer ctx.freeValue(light_type_val);

    const light_type_cstr = ctx.toCString(light_type_val) catch return;
    defer ctx.freeCString(light_type_cstr);
    const light_type_str = std.mem.span(light_type_cstr);

    // Parse color
    const color_val = ctx.getProperty(light_data, "color");
    defer ctx.freeValue(color_val);

    const color = if (!ctx.isUndefined(color_val)) Vec3.init(
        ctx.toFloat32(ctx.getProperty(color_val, "x")) catch 1,
        ctx.toFloat32(ctx.getProperty(color_val, "y")) catch 1,
        ctx.toFloat32(ctx.getProperty(color_val, "z")) catch 1,
    ) else Vec3.init(1, 1, 1);

    // Free individual color properties
    ctx.freeValue(ctx.getProperty(color_val, "x"));
    ctx.freeValue(ctx.getProperty(color_val, "y"));
    ctx.freeValue(ctx.getProperty(color_val, "z"));

    const intensity_val = ctx.getProperty(light_data, "intensity");
    defer ctx.freeValue(intensity_val);
    const intensity = ctx.toFloat32(intensity_val) catch 1;

    const range_val = ctx.getProperty(light_data, "range");
    defer ctx.freeValue(range_val);
    const range = ctx.toFloat32(range_val) catch 10;

    // Create appropriate light type
    const light = if (std.mem.eql(u8, light_type_str, "directional"))
        LightComponent.directional(color, intensity)
    else if (std.mem.eql(u8, light_type_str, "point"))
        LightComponent.point(color, intensity, range)
    else
        LightComponent.directional(color, intensity);

    if (!scene.hasComponent(LightComponent, entity)) {
        scene.addComponent(entity, light);
    }
}

fn getOrCreatePrimitiveMesh(mesh_type: []const u8, allocator: std.mem.Allocator, device: anytype) !*Mesh {
    if (primitive_meshes.get(mesh_type)) |mesh_ptr| {
        return mesh_ptr;
    }

    // Create new primitive
    const mesh_ptr = try allocator.create(Mesh);
    errdefer allocator.destroy(mesh_ptr);

    if (std.mem.eql(u8, mesh_type, "cube")) {
        mesh_ptr.* = try primitives.createCube(allocator);
    } else if (std.mem.eql(u8, mesh_type, "plane")) {
        mesh_ptr.* = try primitives.createPlane(allocator);
    } else if (std.mem.eql(u8, mesh_type, "sphere")) {
        mesh_ptr.* = try primitives.createSphere(allocator, 32);
    } else {
        // Default to cube
        mesh_ptr.* = try primitives.createCube(allocator);
    }

    try mesh_ptr.upload(device);
    try primitive_meshes.put(mesh_type, mesh_ptr);

    return mesh_ptr;
}
