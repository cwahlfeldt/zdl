const std = @import("std");

const Entity = @import("../ecs/entity.zig").Entity;

pub const ComponentSchema = struct {
    schema_json: []const u8,
    is_tag: bool,
};

const ComponentTypeStorage = struct {
    schema_json: []u8,
    is_tag: bool,
    entities: std.AutoHashMap(u64, []u8),

    fn init(allocator: std.mem.Allocator, schema_json: []const u8, is_tag: bool) !ComponentTypeStorage {
        return .{
            .schema_json = try allocator.dupe(u8, schema_json),
            .is_tag = is_tag,
            .entities = std.AutoHashMap(u64, []u8).init(allocator),
        };
    }

    fn deinit(self: *ComponentTypeStorage, allocator: std.mem.Allocator) void {
        var iter = self.entities.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        self.entities.deinit();
        allocator.free(self.schema_json);
    }

    fn setComponent(self: *ComponentTypeStorage, allocator: std.mem.Allocator, entity: Entity, data_json: []const u8) !void {
        const data_copy = try allocator.dupe(u8, data_json);
        if (self.entities.getPtr(entity.id)) |existing| {
            allocator.free(existing.*);
            existing.* = data_copy;
            return;
        }
        try self.entities.put(entity.id, data_copy);
    }

    fn removeComponent(self: *ComponentTypeStorage, allocator: std.mem.Allocator, entity: Entity) void {
        if (self.entities.fetchRemove(entity.id)) |entry| {
            allocator.free(entry.value);
        }
    }
};

/// Storage for JavaScript-defined components serialized as JSON.
pub const JsComponentStorage = struct {
    allocator: std.mem.Allocator,
    types: std.StringHashMap(ComponentTypeStorage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .types = std.StringHashMap(ComponentTypeStorage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.types.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.types.deinit();
    }

    pub fn registerType(self: *Self, type_name: []const u8, schema_json: []const u8, is_tag: bool) !void {
        if (self.types.getPtr(type_name)) |existing| {
            self.allocator.free(existing.schema_json);
            existing.schema_json = try self.allocator.dupe(u8, schema_json);
            existing.is_tag = is_tag;
            return;
        }

        const key = try self.allocator.dupe(u8, type_name);
        var storage = try ComponentTypeStorage.init(self.allocator, schema_json, is_tag);
        errdefer storage.deinit(self.allocator);
        try self.types.put(key, storage);
    }

    pub fn hasType(self: *const Self, type_name: []const u8) bool {
        return self.types.contains(type_name);
    }

    pub fn getSchema(self: *const Self, type_name: []const u8) ?ComponentSchema {
        const storage = self.types.getPtr(type_name) orelse return null;
        return .{
            .schema_json = storage.schema_json,
            .is_tag = storage.is_tag,
        };
    }

    pub fn addComponent(self: *Self, entity: Entity, type_name: []const u8, data_json: []const u8) !void {
        const storage = self.types.getPtr(type_name) orelse return error.UnknownComponentType;
        try storage.setComponent(self.allocator, entity, data_json);
    }

    pub fn updateComponent(self: *Self, entity: Entity, type_name: []const u8, data_json: []const u8) !void {
        const storage = self.types.getPtr(type_name) orelse return error.UnknownComponentType;
        try storage.setComponent(self.allocator, entity, data_json);
    }

    pub fn removeComponent(self: *Self, entity: Entity, type_name: []const u8) void {
        if (self.types.getPtr(type_name)) |storage| {
            storage.removeComponent(self.allocator, entity);
        }
    }

    pub fn hasComponent(self: *const Self, entity: Entity, type_name: []const u8) bool {
        const storage = self.types.getPtr(type_name) orelse return false;
        return storage.entities.contains(entity.id);
    }

    pub fn getComponent(self: *const Self, entity: Entity, type_name: []const u8) ?[]const u8 {
        const storage = self.types.getPtr(type_name) orelse return null;
        return storage.entities.get(entity.id);
    }

    pub fn removeEntity(self: *Self, entity: Entity) void {
        var iter = self.types.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.removeComponent(self.allocator, entity);
        }
    }

    pub fn query(self: *const Self, allocator: std.mem.Allocator, type_names: []const []const u8) ![]Entity {
        if (type_names.len == 0) {
            return try allocator.alloc(Entity, 0);
        }

        var storages = try allocator.alloc(*const ComponentTypeStorage, type_names.len);
        defer allocator.free(storages);

        for (type_names, 0..) |type_name, i| {
            const storage = self.types.getPtr(type_name) orelse {
                return try allocator.alloc(Entity, 0);
            };
            storages[i] = storage;
        }

        var base_index: usize = 0;
        var base_count = storages[0].entities.count();
        for (storages, 0..) |storage, i| {
            const count = storage.entities.count();
            if (count < base_count) {
                base_index = i;
                base_count = count;
            }
        }

        var results = std.ArrayList(Entity).empty;
        errdefer results.deinit(allocator);

        var iter = storages[base_index].entities.iterator();
        while (iter.next()) |entry| {
            const entity_id = entry.key_ptr.*;
            var matches = true;
            for (storages, 0..) |storage, i| {
                if (i == base_index) continue;
                if (!storage.entities.contains(entity_id)) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                try results.append(allocator, .{ .id = entity_id });
            }
        }

        return results.toOwnedSlice(allocator);
    }
};

test "js component storage CRUD" {
    var storage = JsComponentStorage.init(std.testing.allocator);
    defer storage.deinit();

    try storage.registerType("Position", "{\"x\":\"number\"}", false);

    const entity = Entity{ .id = 1 };
    try storage.addComponent(entity, "Position", "{\"x\":1}");
    try std.testing.expect(storage.hasComponent(entity, "Position"));
    try std.testing.expectEqualStrings("{\"x\":1}", storage.getComponent(entity, "Position").?);

    try storage.updateComponent(entity, "Position", "{\"x\":2}");
    try std.testing.expectEqualStrings("{\"x\":2}", storage.getComponent(entity, "Position").?);

    storage.removeComponent(entity, "Position");
    try std.testing.expect(!storage.hasComponent(entity, "Position"));
}

test "js component storage schema updates" {
    var storage = JsComponentStorage.init(std.testing.allocator);
    defer storage.deinit();

    try storage.registerType("Tag", "{}", true);
    try storage.registerType("Tag", "{\"enabled\":\"boolean\"}", false);

    const schema = storage.getSchema("Tag") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("{\"enabled\":\"boolean\"}", schema.schema_json);
    try std.testing.expect(!schema.is_tag);
}

test "js component storage removes entity across types" {
    var storage = JsComponentStorage.init(std.testing.allocator);
    defer storage.deinit();

    try storage.registerType("A", "{}", true);
    try storage.registerType("B", "{}", true);

    const entity = Entity{ .id = 42 };
    try storage.addComponent(entity, "A", "{}");
    try storage.addComponent(entity, "B", "{}");

    storage.removeEntity(entity);

    try std.testing.expect(!storage.hasComponent(entity, "A"));
    try std.testing.expect(!storage.hasComponent(entity, "B"));
}

test "js component storage query intersection" {
    var storage = JsComponentStorage.init(std.testing.allocator);
    defer storage.deinit();

    try storage.registerType("Player", "{}", true);
    try storage.registerType("Position", "{}", false);

    const entity_a = Entity{ .id = 100 };
    const entity_b = Entity{ .id = 200 };

    try storage.addComponent(entity_a, "Player", "{}");
    try storage.addComponent(entity_a, "Position", "{}");
    try storage.addComponent(entity_b, "Player", "{}");

    const results = try storage.query(std.testing.allocator, &[_][]const u8{ "Player", "Position" });
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expect(results[0].eql(entity_a));
}
