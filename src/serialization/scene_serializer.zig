const std = @import("std");
const flecs = @import("zflecs");
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const Quat = math.Quat;

const ecs = @import("../ecs/ecs.zig");
const Scene = ecs.Scene;
const Entity = ecs.Entity;
const TransformComponent = ecs.TransformComponent;
const CameraComponent = ecs.CameraComponent;
const MeshRendererComponent = ecs.MeshRendererComponent;
const LightComponent = ecs.LightComponent;
const FpvCameraController = ecs.FpvCameraController;

const AssetManager = @import("../assets/asset_manager.zig").AssetManager;

/// Serialized representation of a scene for JSON export/import
pub const SerializedScene = struct {
    version: []const u8 = "1.0.0",
    name: []const u8 = "",
    active_camera_id: ?u64 = null,
    entities: []SerializedEntity = &.{},

    pub fn deinit(self: *SerializedScene, allocator: std.mem.Allocator) void {
        for (self.entities) |*entity| {
            entity.deinit(allocator);
        }
        if (self.entities.len > 0) {
            allocator.free(self.entities);
        }
        if (self.name.len > 0) {
            allocator.free(self.name);
        }
    }
};

/// Serialized representation of an entity
pub const SerializedEntity = struct {
    id: u64,
    name: []const u8 = "",
    parent_id: ?u64 = null,

    // Components (optional)
    transform: ?SerializedTransform = null,
    camera: ?SerializedCamera = null,
    mesh_renderer: ?SerializedMeshRenderer = null,
    light: ?SerializedLight = null,
    fps_controller: ?SerializedFpsController = null,

    pub fn deinit(self: *SerializedEntity, allocator: std.mem.Allocator) void {
        if (self.name.len > 0) {
            allocator.free(self.name);
        }
        if (self.mesh_renderer) |*mr| {
            mr.deinit(allocator);
        }
    }
};

pub const SerializedTransform = struct {
    position: [3]f32 = .{ 0, 0, 0 },
    rotation: [4]f32 = .{ 0, 0, 0, 1 }, // x, y, z, w quaternion
    scale: [3]f32 = .{ 1, 1, 1 },
};

pub const SerializedCamera = struct {
    fov: f32 = std.math.pi / 4.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

pub const SerializedMeshRenderer = struct {
    mesh_name: []const u8 = "",
    texture_path: ?[]const u8 = null,
    enabled: bool = true,

    pub fn deinit(self: *SerializedMeshRenderer, allocator: std.mem.Allocator) void {
        if (self.mesh_name.len > 0) {
            allocator.free(self.mesh_name);
        }
        if (self.texture_path) |path| {
            if (path.len > 0) {
                allocator.free(path);
            }
        }
    }
};

pub const SerializedLight = struct {
    light_type: []const u8 = "directional",
    color: [3]f32 = .{ 1, 1, 1 },
    intensity: f32 = 1.0,
    range: f32 = 10.0,
    inner_angle: f32 = 0,
    outer_angle: f32 = 0,
};

pub const SerializedFpsController = struct {
    yaw: f32 = 0,
    pitch: f32 = 0,
    sensitivity: f32 = 0.003,
    move_speed: f32 = 5.0,
    capture_on_click: bool = true,
};

/// Scene serializer for saving and loading scenes to JSON
pub const SceneSerializer = struct {
    allocator: std.mem.Allocator,
    asset_manager: ?*AssetManager = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator, .asset_manager = null };
    }

    /// Initialize with an asset manager for mesh/texture name resolution
    pub fn initWithAssets(allocator: std.mem.Allocator, asset_manager: *AssetManager) Self {
        return .{ .allocator = allocator, .asset_manager = asset_manager };
    }

    // ==================== Serialization (Scene -> JSON) ====================

    /// Serialize a scene to a JSON string
    pub fn serializeToJson(self: *Self, scene: *Scene) ![]const u8 {
        const serialized = try self.serializeScene(scene);
        defer {
            var s = serialized;
            s.deinit(self.allocator);
        }

        return try self.toJsonString(serialized);
    }

    /// Save a scene to a JSON file
    pub fn saveToFile(self: *Self, scene: *Scene, path: []const u8) !void {
        const json = try self.serializeToJson(scene);
        defer self.allocator.free(json);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(json);
    }

    /// Convert a scene to serialized representation
    pub fn serializeScene(self: *Self, scene: *Scene) !SerializedScene {
        var entities = std.ArrayList(SerializedEntity).init(self.allocator);
        errdefer {
            for (entities.items) |*e| {
                e.deinit(self.allocator);
            }
            entities.deinit();
        }

        var entity_ids = std.AutoHashMap(u64, void).init(self.allocator);
        defer entity_ids.deinit();

        var to_process = std.ArrayList(u64).init(self.allocator);
        defer to_process.deinit();

        try collectEntitiesWithComponent(scene, TransformComponent, &entity_ids, &to_process);
        try collectEntitiesWithComponent(scene, CameraComponent, &entity_ids, &to_process);
        try collectEntitiesWithComponent(scene, MeshRendererComponent, &entity_ids, &to_process);
        try collectEntitiesWithComponent(scene, LightComponent, &entity_ids, &to_process);
        try collectEntitiesWithComponent(scene, FpvCameraController, &entity_ids, &to_process);

        if (scene.active_camera.isValid()) {
            try addEntityId(@intCast(scene.active_camera.id), &entity_ids, &to_process);
        }

        // Ensure parent chains are included so hierarchy links are preserved.
        var index: usize = 0;
        while (index < to_process.items.len) : (index += 1) {
            const current = Entity{ .id = @intCast(to_process.items[index]) };
            var parent = scene.getParent(current);
            while (parent.isValid()) {
                try addEntityId(@intCast(parent.id), &entity_ids, &to_process);
                parent = scene.getParent(parent);
            }
        }

        var sorted_ids = std.ArrayList(u64).init(self.allocator);
        defer sorted_ids.deinit();

        var it = entity_ids.iterator();
        while (it.next()) |entry| {
            try sorted_ids.append(entry.key_ptr.*);
        }
        std.sort.sort(u64, sorted_ids.items, {}, std.sort.asc(u64));

        for (sorted_ids.items) |entity_id| {
            const entity = Entity{ .id = @intCast(entity_id) };
            var parent_id: ?u64 = null;
            const parent = scene.getParent(entity);
            if (parent.isValid()) {
                const pid: u64 = @intCast(parent.id);
                if (entity_ids.contains(pid)) {
                    parent_id = pid;
                }
            }
            try self.serializeEntity(scene, entity, parent_id, &entities);
        }

        // Find active camera ID
        var active_camera_id: ?u64 = null;
        if (scene.active_camera.isValid()) {
            active_camera_id = @intCast(scene.active_camera.id);
        }

        return SerializedScene{
            .version = "1.0.0",
            .name = "",
            .active_camera_id = active_camera_id,
            .entities = try entities.toOwnedSlice(),
        };
    }

    fn serializeEntity(
        self: *Self,
        scene: *Scene,
        entity: Entity,
        parent_id: ?u64,
        entities: *std.ArrayList(SerializedEntity),
    ) !void {
        var serialized = SerializedEntity{
            .id = @intCast(entity.id),
            .parent_id = parent_id,
        };

        // Serialize TransformComponent
        if (scene.getComponent(TransformComponent, entity)) |transform| {
            serialized.transform = SerializedTransform{
                .position = .{ transform.local.position.x, transform.local.position.y, transform.local.position.z },
                .rotation = .{ transform.local.rotation.x, transform.local.rotation.y, transform.local.rotation.z, transform.local.rotation.w },
                .scale = .{ transform.local.scale.x, transform.local.scale.y, transform.local.scale.z },
            };
        }

        // Serialize CameraComponent
        if (scene.getComponent(CameraComponent, entity)) |camera| {
            serialized.camera = SerializedCamera{
                .fov = camera.fov,
                .near = camera.near,
                .far = camera.far,
            };
        }

        // Serialize MeshRendererComponent
        if (scene.getComponent(MeshRendererComponent, entity)) |mesh_renderer| {
            var mesh_name: []const u8 = "";
            var texture_path: ?[]const u8 = null;

            // Look up asset names via AssetManager if available
            if (self.asset_manager) |am| {
                if (am.findMeshName(mesh_renderer.mesh)) |name| {
                    mesh_name = try self.allocator.dupe(u8, name);
                }
                if (mesh_renderer.texture) |tex| {
                    if (am.findTexturePath(tex)) |path| {
                        texture_path = try self.allocator.dupe(u8, path);
                    }
                }
            }

            serialized.mesh_renderer = SerializedMeshRenderer{
                .mesh_name = mesh_name,
                .texture_path = texture_path,
                .enabled = mesh_renderer.enabled,
            };
        }

        // Serialize LightComponent
        if (scene.getComponent(LightComponent, entity)) |light| {
            const light_types = @import("../ecs/components/light_component.zig");
            serialized.light = SerializedLight{
                .light_type = switch (light.light_type) {
                    .directional => "directional",
                    .point => "point",
                    .spot => "spot",
                },
                .color = .{ light.color.x, light.color.y, light.color.z },
                .intensity = light.intensity,
                .range = light.range,
                .inner_angle = light.inner_angle,
                .outer_angle = light.outer_angle,
            };
            _ = light_types;
        }

        // Serialize FpvCameraController
        if (scene.getComponent(FpvCameraController, entity)) |fps| {
            serialized.fps_controller = SerializedFpsController{
                .yaw = fps.yaw,
                .pitch = fps.pitch,
                .sensitivity = fps.sensitivity,
                .move_speed = fps.move_speed,
                .capture_on_click = fps.capture_on_click,
            };
        }

        try entities.append(serialized);
    }

    fn toJsonString(self: *Self, scene: SerializedScene) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        errdefer buffer.deinit();

        var writer = buffer.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"version\": \"{s}\",\n", .{scene.version});

        if (scene.active_camera_id) |cam_id| {
            try writer.print("  \"active_camera_id\": {d},\n", .{cam_id});
        } else {
            try writer.writeAll("  \"active_camera_id\": null,\n");
        }

        try writer.writeAll("  \"entities\": [\n");

        for (scene.entities, 0..) |entity, i| {
            try self.writeEntityJson(writer, entity, 4);
            if (i < scene.entities.len - 1) {
                try writer.writeAll(",\n");
            } else {
                try writer.writeAll("\n");
            }
        }

        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");

        return try buffer.toOwnedSlice();
    }

    fn writeEntityJson(self: *Self, writer: anytype, entity: SerializedEntity, indent: usize) !void {
        _ = self;
        const spaces = "                                ";

        try writer.print("{s}{{\n", .{spaces[0..indent]});
        try writer.print("{s}  \"id\": {d},\n", .{ spaces[0..indent], entity.id });

        if (entity.parent_id) |pid| {
            try writer.print("{s}  \"parent_id\": {d},\n", .{ spaces[0..indent], pid });
        }

        // Transform
        if (entity.transform) |t| {
            try writer.print("{s}  \"transform\": {{\n", .{spaces[0..indent]});
            try writer.print("{s}    \"position\": [{d:.6}, {d:.6}, {d:.6}],\n", .{ spaces[0..indent], t.position[0], t.position[1], t.position[2] });
            try writer.print("{s}    \"rotation\": [{d:.6}, {d:.6}, {d:.6}, {d:.6}],\n", .{ spaces[0..indent], t.rotation[0], t.rotation[1], t.rotation[2], t.rotation[3] });
            try writer.print("{s}    \"scale\": [{d:.6}, {d:.6}, {d:.6}]\n", .{ spaces[0..indent], t.scale[0], t.scale[1], t.scale[2] });
            try writer.print("{s}  }},\n", .{spaces[0..indent]});
        }

        // Camera
        if (entity.camera) |c| {
            try writer.print("{s}  \"camera\": {{\n", .{spaces[0..indent]});
            try writer.print("{s}    \"fov\": {d:.6},\n", .{ spaces[0..indent], c.fov });
            try writer.print("{s}    \"near\": {d:.6},\n", .{ spaces[0..indent], c.near });
            try writer.print("{s}    \"far\": {d:.6}\n", .{ spaces[0..indent], c.far });
            try writer.print("{s}  }},\n", .{spaces[0..indent]});
        }

        // MeshRenderer
        if (entity.mesh_renderer) |mr| {
            try writer.print("{s}  \"mesh_renderer\": {{\n", .{spaces[0..indent]});
            try writer.print("{s}    \"mesh_name\": \"{s}\",\n", .{ spaces[0..indent], mr.mesh_name });
            if (mr.texture_path) |tex| {
                try writer.print("{s}    \"texture_path\": \"{s}\",\n", .{ spaces[0..indent], tex });
            }
            try writer.print("{s}    \"enabled\": {}\n", .{ spaces[0..indent], mr.enabled });
            try writer.print("{s}  }},\n", .{spaces[0..indent]});
        }

        // Light
        if (entity.light) |l| {
            try writer.print("{s}  \"light\": {{\n", .{spaces[0..indent]});
            try writer.print("{s}    \"light_type\": \"{s}\",\n", .{ spaces[0..indent], l.light_type });
            try writer.print("{s}    \"color\": [{d:.6}, {d:.6}, {d:.6}],\n", .{ spaces[0..indent], l.color[0], l.color[1], l.color[2] });
            try writer.print("{s}    \"intensity\": {d:.6},\n", .{ spaces[0..indent], l.intensity });
            try writer.print("{s}    \"range\": {d:.6},\n", .{ spaces[0..indent], l.range });
            try writer.print("{s}    \"inner_angle\": {d:.6},\n", .{ spaces[0..indent], l.inner_angle });
            try writer.print("{s}    \"outer_angle\": {d:.6}\n", .{ spaces[0..indent], l.outer_angle });
            try writer.print("{s}  }},\n", .{spaces[0..indent]});
        }

        // FpsController
        if (entity.fps_controller) |fps| {
            try writer.print("{s}  \"fps_controller\": {{\n", .{spaces[0..indent]});
            try writer.print("{s}    \"yaw\": {d:.6},\n", .{ spaces[0..indent], fps.yaw });
            try writer.print("{s}    \"pitch\": {d:.6},\n", .{ spaces[0..indent], fps.pitch });
            try writer.print("{s}    \"sensitivity\": {d:.6},\n", .{ spaces[0..indent], fps.sensitivity });
            try writer.print("{s}    \"move_speed\": {d:.6},\n", .{ spaces[0..indent], fps.move_speed });
            try writer.print("{s}    \"capture_on_click\": {}\n", .{ spaces[0..indent], fps.capture_on_click });
            try writer.print("{s}  }}\n", .{spaces[0..indent]});
        } else {
            // Remove trailing comma from last component by backtracking
            // For simplicity, we'll add a dummy field at the end
            try writer.print("{s}  \"_end\": true\n", .{spaces[0..indent]});
        }

        try writer.print("{s}}}", .{spaces[0..indent]});
    }

    // ==================== Deserialization (JSON -> Scene) ====================

    /// Load a scene from a JSON file
    pub fn loadFromFile(self: *Self, path: []const u8, asset_manager: ?*AssetManager) !*Scene {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const json = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(json);

        _ = try file.readAll(json);

        // Use provided asset_manager or fall back to serializer's asset_manager
        const am = asset_manager orelse self.asset_manager;
        return try self.deserializeFromJson(json, am);
    }

    /// Deserialize a scene from a JSON string
    pub fn deserializeFromJson(self: *Self, json: []const u8, asset_manager: ?*AssetManager) !*Scene {
        const parsed = try self.parseJson(json);
        defer {
            var p = parsed;
            p.deinit(self.allocator);
        }

        // Use provided asset_manager or fall back to serializer's asset_manager
        const am = asset_manager orelse self.asset_manager;
        return try self.deserializeScene(parsed, am);
    }

    /// Convert parsed JSON to a new Scene
    pub fn deserializeScene(self: *Self, data: SerializedScene, asset_manager: ?*AssetManager) !*Scene {
        const scene = try self.allocator.create(Scene);
        scene.* = Scene.init(self.allocator);
        errdefer {
            scene.deinit();
            self.allocator.destroy(scene);
        }

        // Map from serialized ID -> new Entity
        var entity_map = std.AutoHashMap(u64, Entity).init(self.allocator);
        defer entity_map.deinit();

        // First pass: create all entities
        for (data.entities) |serialized| {
            const entity = scene.createEntity();
            try entity_map.put(serialized.id, entity);
        }

        // Second pass: add components and set up hierarchy
        for (data.entities) |serialized| {
            const entity = entity_map.get(serialized.id) orelse continue;

            // Add TransformComponent
            if (serialized.transform) |t| {
                const transform = TransformComponent{
                    .local = .{
                        .position = Vec3.init(t.position[0], t.position[1], t.position[2]),
                        .rotation = Quat{ .x = t.rotation[0], .y = t.rotation[1], .z = t.rotation[2], .w = t.rotation[3] },
                        .scale = Vec3.init(t.scale[0], t.scale[1], t.scale[2]),
                    },
                    .world_matrix = math.Mat4.identity(),
                };
                scene.addComponent(entity, transform);
            }

            // Add CameraComponent
            if (serialized.camera) |c| {
                scene.addComponent(entity, CameraComponent{
                    .fov = c.fov,
                    .near = c.near,
                    .far = c.far,
                });
            }

            // Add MeshRendererComponent (requires asset manager)
            if (serialized.mesh_renderer) |mr| {
                if (asset_manager) |am| {
                    if (am.getMesh(mr.mesh_name)) |mesh| {
                        var component = MeshRendererComponent.init(mesh);
                        component.enabled = mr.enabled;

                        if (mr.texture_path) |tex_path| {
                            if (tex_path.len > 0) {
                                if (am.getTexture(tex_path)) |texture| {
                                    component.texture = texture;
                                }
                            }
                        }

                        scene.addComponent(entity, component);
                    }
                }
            }

            // Add LightComponent
            if (serialized.light) |l| {
                const LightType = @import("../ecs/components/light_component.zig").LightType;
                const light_type: LightType = if (std.mem.eql(u8, l.light_type, "point"))
                    .point
                else if (std.mem.eql(u8, l.light_type, "spot"))
                    .spot
                else
                    .directional;

                scene.addComponent(entity, LightComponent{
                    .light_type = light_type,
                    .color = Vec3.init(l.color[0], l.color[1], l.color[2]),
                    .intensity = l.intensity,
                    .range = l.range,
                    .inner_angle = l.inner_angle,
                    .outer_angle = l.outer_angle,
                });
            }

            // Add FpvCameraController
            if (serialized.fps_controller) |fps| {
                scene.addComponent(entity, FpvCameraController{
                    .yaw = fps.yaw,
                    .pitch = fps.pitch,
                    .sensitivity = fps.sensitivity,
                    .move_speed = fps.move_speed,
                    .capture_on_click = fps.capture_on_click,
                });
            }
        }

        // Third pass: set up parent-child hierarchy
        for (data.entities) |serialized| {
            if (serialized.parent_id) |parent_id| {
                const entity = entity_map.get(serialized.id) orelse continue;
                const parent = entity_map.get(parent_id) orelse continue;
                scene.setParent(entity, parent);
            }
        }

        // Set active camera
        if (data.active_camera_id) |cam_id| {
            if (entity_map.get(cam_id)) |camera_entity| {
                scene.setActiveCamera(camera_entity);
            }
        }

        // Update world transforms
        scene.updateWorldTransforms();

        return scene;
    }

    fn parseJson(self: *Self, json: []const u8) !SerializedScene {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json, .{}) catch |err| {
            std.debug.print("JSON parse error: {}\n", .{err});
            return err;
        };
        defer parsed.deinit();

        return try self.parseSerializedScene(parsed.value);
    }

    fn parseSerializedScene(self: *Self, value: std.json.Value) !SerializedScene {
        var result = SerializedScene{};

        if (value != .object) return error.InvalidJson;
        const obj = value.object;

        // Parse active_camera_id
        if (obj.get("active_camera_id")) |cam| {
            if (cam == .integer and cam.integer >= 0) {
                result.active_camera_id = @intCast(cam.integer);
            }
        }

        // Parse entities array
        if (obj.get("entities")) |entities_val| {
            if (entities_val == .array) {
                var entities = std.ArrayList(SerializedEntity).init(self.allocator);
                errdefer {
                    for (entities.items) |*e| {
                        e.deinit(self.allocator);
                    }
                    entities.deinit();
                }

                for (entities_val.array.items) |entity_val| {
                    const entity = try self.parseSerializedEntity(entity_val);
                    try entities.append(entity);
                }

                result.entities = try entities.toOwnedSlice();
            }
        }

        return result;
    }

    fn parseSerializedEntity(self: *Self, value: std.json.Value) !SerializedEntity {
        var result = SerializedEntity{ .id = 0 };

        if (value != .object) return error.InvalidJson;
        const obj = value.object;

        // Parse ID
        if (obj.get("id")) |id_val| {
            if (id_val == .integer and id_val.integer >= 0) {
                result.id = @intCast(id_val.integer);
            }
        }

        // Parse parent_id
        if (obj.get("parent_id")) |parent_val| {
            if (parent_val == .integer and parent_val.integer >= 0) {
                result.parent_id = @intCast(parent_val.integer);
            }
        }

        // Parse transform
        if (obj.get("transform")) |t| {
            result.transform = try self.parseTransform(t);
        }

        // Parse camera
        if (obj.get("camera")) |c| {
            result.camera = try self.parseCamera(c);
        }

        // Parse mesh_renderer
        if (obj.get("mesh_renderer")) |mr| {
            result.mesh_renderer = try self.parseMeshRenderer(mr);
        }

        // Parse light
        if (obj.get("light")) |l| {
            result.light = try self.parseLight(l);
        }

        // Parse fps_controller
        if (obj.get("fps_controller")) |fps| {
            result.fps_controller = try self.parseFpsController(fps);
        }

        return result;
    }

    fn parseTransform(self: *Self, value: std.json.Value) !SerializedTransform {
        _ = self;
        var result = SerializedTransform{};

        if (value != .object) return result;
        const obj = value.object;

        if (obj.get("position")) |pos| {
            if (pos == .array and pos.array.items.len >= 3) {
                result.position[0] = parseFloat(pos.array.items[0]);
                result.position[1] = parseFloat(pos.array.items[1]);
                result.position[2] = parseFloat(pos.array.items[2]);
            }
        }

        if (obj.get("rotation")) |rot| {
            if (rot == .array and rot.array.items.len >= 4) {
                result.rotation[0] = parseFloat(rot.array.items[0]);
                result.rotation[1] = parseFloat(rot.array.items[1]);
                result.rotation[2] = parseFloat(rot.array.items[2]);
                result.rotation[3] = parseFloat(rot.array.items[3]);
            }
        }

        if (obj.get("scale")) |s| {
            if (s == .array and s.array.items.len >= 3) {
                result.scale[0] = parseFloat(s.array.items[0]);
                result.scale[1] = parseFloat(s.array.items[1]);
                result.scale[2] = parseFloat(s.array.items[2]);
            }
        }

        return result;
    }

    fn parseCamera(self: *Self, value: std.json.Value) !SerializedCamera {
        _ = self;
        var result = SerializedCamera{};

        if (value != .object) return result;
        const obj = value.object;

        if (obj.get("fov")) |v| result.fov = parseFloat(v);
        if (obj.get("near")) |v| result.near = parseFloat(v);
        if (obj.get("far")) |v| result.far = parseFloat(v);

        return result;
    }

    fn parseMeshRenderer(self: *Self, value: std.json.Value) !SerializedMeshRenderer {
        var result = SerializedMeshRenderer{};

        if (value != .object) return result;
        const obj = value.object;

        if (obj.get("mesh_name")) |v| {
            if (v == .string) {
                result.mesh_name = try self.allocator.dupe(u8, v.string);
            }
        }

        if (obj.get("texture_path")) |v| {
            if (v == .string and v.string.len > 0) {
                result.texture_path = try self.allocator.dupe(u8, v.string);
            }
        }

        if (obj.get("enabled")) |v| {
            if (v == .bool) result.enabled = v.bool;
        }

        return result;
    }

    fn parseLight(self: *Self, value: std.json.Value) !SerializedLight {
        _ = self;
        var result = SerializedLight{};

        if (value != .object) return result;
        const obj = value.object;

        if (obj.get("light_type")) |v| {
            if (v == .string) result.light_type = v.string;
        }

        if (obj.get("color")) |c| {
            if (c == .array and c.array.items.len >= 3) {
                result.color[0] = parseFloat(c.array.items[0]);
                result.color[1] = parseFloat(c.array.items[1]);
                result.color[2] = parseFloat(c.array.items[2]);
            }
        }

        if (obj.get("intensity")) |v| result.intensity = parseFloat(v);
        if (obj.get("range")) |v| result.range = parseFloat(v);
        if (obj.get("inner_angle")) |v| result.inner_angle = parseFloat(v);
        if (obj.get("outer_angle")) |v| result.outer_angle = parseFloat(v);

        return result;
    }

    fn parseFpsController(self: *Self, value: std.json.Value) !SerializedFpsController {
        _ = self;
        var result = SerializedFpsController{};

        if (value != .object) return result;
        const obj = value.object;

        if (obj.get("yaw")) |v| result.yaw = parseFloat(v);
        if (obj.get("pitch")) |v| result.pitch = parseFloat(v);
        if (obj.get("sensitivity")) |v| result.sensitivity = parseFloat(v);
        if (obj.get("move_speed")) |v| result.move_speed = parseFloat(v);
        if (obj.get("capture_on_click")) |v| {
            if (v == .bool) result.capture_on_click = v.bool;
        }

        return result;
    }

    fn addEntityId(
        id: u64,
        entity_ids: *std.AutoHashMap(u64, void),
        to_process: *std.ArrayList(u64),
    ) !void {
        if (!entity_ids.contains(id)) {
            try entity_ids.put(id, {});
            try to_process.append(id);
        }
    }

    fn collectEntitiesWithComponent(
        scene: *Scene,
        comptime T: type,
        entity_ids: *std.AutoHashMap(u64, void),
        to_process: *std.ArrayList(u64),
    ) !void {
        var query_desc: flecs.query_desc_t = std.mem.zeroes(flecs.query_desc_t);
        query_desc.terms[0] = .{ .id = flecs.id(T) };

        const query = try flecs.query_init(scene.world, &query_desc);
        defer flecs.query_fini(query);

        var it = flecs.query_iter(scene.world, query);
        while (flecs.query_next(&it)) {
            for (it.entities()) |entity_id| {
                try addEntityId(@intCast(entity_id), entity_ids, to_process);
            }
        }
    }
};

fn parseFloat(value: std.json.Value) f32 {
    return switch (value) {
        .float => @floatCast(value.float),
        .integer => @floatFromInt(value.integer),
        else => 0,
    };
}

// ==================== Tests ====================

test "serialize empty scene" {
    var serializer = SceneSerializer.init(std.testing.allocator);
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const json = try serializer.serializeToJson(&scene);
    defer std.testing.allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\"") != null);
}

test "serialize scene with entity" {
    var serializer = SceneSerializer.init(std.testing.allocator);
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const entity = scene.createEntity();
    scene.addComponent(entity, TransformComponent.withPosition(Vec3.init(1, 2, 3)));
    scene.addComponent(entity, CameraComponent.init());

    const json = try serializer.serializeToJson(&scene);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"transform\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"camera\"") != null);
}

test "roundtrip serialization" {
    var serializer = SceneSerializer.init(std.testing.allocator);

    // Create scene with entities
    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();

    const camera = scene.createEntity();
    scene.addComponent(camera, TransformComponent.withPosition(Vec3.init(0, 5, 10)));
    scene.addComponent(camera, CameraComponent.initWithSettings(std.math.pi / 3.0, 0.5, 500.0));
    scene.setActiveCamera(camera);

    const cube = scene.createEntity();
    scene.addComponent(cube, TransformComponent.withPosition(Vec3.init(1, 2, 3)));

    // Serialize to JSON
    const json = try serializer.serializeToJson(&scene);
    defer std.testing.allocator.free(json);

    // Deserialize back
    const loaded_scene = try serializer.deserializeFromJson(json, null);
    defer {
        loaded_scene.deinit();
        std.testing.allocator.destroy(loaded_scene);
    }

    // Verify entity count
    try std.testing.expectEqual(@as(u32, 2), loaded_scene.entityCount());

    // Verify active camera is set
    try std.testing.expect(loaded_scene.active_camera.isValid());
}
