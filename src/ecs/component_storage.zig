const std = @import("std");
const Entity = @import("entity.zig").Entity;

/// Sparse set component storage providing O(1) add/remove and cache-friendly iteration.
/// Each component type gets its own storage instance.
pub fn ComponentStorage(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Dense array of components (cache-friendly for iteration)
        dense: std.ArrayList(T) = .{},
        /// Dense array of entity IDs (parallel to dense)
        dense_entities: std.ArrayList(Entity) = .{},
        /// Sparse array: entity.index -> index in dense array (null if not present)
        sparse: std.ArrayList(?u32) = .{},

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.dense.deinit(self.allocator);
            self.dense_entities.deinit(self.allocator);
            self.sparse.deinit(self.allocator);
        }

        /// Add a component to an entity. Overwrites if already present.
        pub fn add(self: *Self, entity: Entity, component: T) !void {
            // Ensure sparse array is large enough
            while (self.sparse.items.len <= entity.index) {
                try self.sparse.append(self.allocator, null);
            }

            if (self.sparse.items[entity.index]) |dense_index| {
                // Entity already has this component, update it
                self.dense.items[dense_index] = component;
            } else {
                // Add new component
                const dense_index: u32 = @intCast(self.dense.items.len);
                try self.dense.append(self.allocator, component);
                try self.dense_entities.append(self.allocator, entity);
                self.sparse.items[entity.index] = dense_index;
            }
        }

        /// Remove a component from an entity. Returns the removed component if present.
        pub fn remove(self: *Self, entity: Entity) ?T {
            if (entity.index >= self.sparse.items.len) return null;

            const dense_index_opt = self.sparse.items[entity.index];
            const dense_index = dense_index_opt orelse return null;

            // Get the component being removed
            const removed = self.dense.items[dense_index];

            // If not the last element, swap with the last
            const last_index = self.dense.items.len - 1;
            if (dense_index != last_index) {
                // Move last element to the removed position
                self.dense.items[dense_index] = self.dense.items[last_index];
                self.dense_entities.items[dense_index] = self.dense_entities.items[last_index];

                // Update sparse array for the moved entity
                const moved_entity = self.dense_entities.items[dense_index];
                self.sparse.items[moved_entity.index] = dense_index;
            }

            // Remove the last element
            _ = self.dense.pop();
            _ = self.dense_entities.pop();
            self.sparse.items[entity.index] = null;

            return removed;
        }

        /// Get a mutable pointer to an entity's component.
        pub fn get(self: *Self, entity: Entity) ?*T {
            if (entity.index >= self.sparse.items.len) return null;
            const dense_index = self.sparse.items[entity.index] orelse return null;
            return &self.dense.items[dense_index];
        }

        /// Get a const pointer to an entity's component.
        pub fn getConst(self: *const Self, entity: Entity) ?*const T {
            if (entity.index >= self.sparse.items.len) return null;
            const dense_index = self.sparse.items[entity.index] orelse return null;
            return &self.dense.items[dense_index];
        }

        /// Check if an entity has this component.
        pub fn has(self: *const Self, entity: Entity) bool {
            if (entity.index >= self.sparse.items.len) return false;
            return self.sparse.items[entity.index] != null;
        }

        /// Get all components as a slice for iteration.
        pub fn items(self: *Self) []T {
            return self.dense.items;
        }

        /// Get all entities with this component.
        pub fn entities(self: *Self) []Entity {
            return self.dense_entities.items;
        }

        /// Get component count.
        pub fn count(self: *const Self) usize {
            return self.dense.items.len;
        }

        /// Clear all components.
        pub fn clear(self: *Self) void {
            self.dense.clearRetainingCapacity();
            self.dense_entities.clearRetainingCapacity();
            for (self.sparse.items) |*slot| {
                slot.* = null;
            }
        }
    };
}

test "component storage basic operations" {
    const TestComponent = struct { value: i32 };

    var storage = ComponentStorage(TestComponent).init(std.testing.allocator);
    defer storage.deinit();

    const e1 = Entity{ .index = 0, .generation = 0 };
    const e2 = Entity{ .index = 1, .generation = 0 };

    try storage.add(e1, .{ .value = 42 });
    try storage.add(e2, .{ .value = 100 });

    try std.testing.expect(storage.has(e1));
    try std.testing.expect(storage.has(e2));
    try std.testing.expectEqual(@as(usize, 2), storage.count());

    const comp1 = storage.get(e1).?;
    try std.testing.expectEqual(@as(i32, 42), comp1.value);

    comp1.value = 99;
    try std.testing.expectEqual(@as(i32, 99), storage.get(e1).?.value);
}

test "component storage remove with swap" {
    const TestComponent = struct { value: i32 };

    var storage = ComponentStorage(TestComponent).init(std.testing.allocator);
    defer storage.deinit();

    const e1 = Entity{ .index = 0, .generation = 0 };
    const e2 = Entity{ .index = 1, .generation = 0 };
    const e3 = Entity{ .index = 2, .generation = 0 };

    try storage.add(e1, .{ .value = 1 });
    try storage.add(e2, .{ .value = 2 });
    try storage.add(e3, .{ .value = 3 });

    // Remove middle element
    const removed = storage.remove(e2);
    try std.testing.expectEqual(@as(i32, 2), removed.?.value);

    // e3 should still be accessible
    try std.testing.expectEqual(@as(i32, 3), storage.get(e3).?.value);
    try std.testing.expect(!storage.has(e2));
    try std.testing.expectEqual(@as(usize, 2), storage.count());
}

test "component storage iteration" {
    const TestComponent = struct { value: i32 };

    var storage = ComponentStorage(TestComponent).init(std.testing.allocator);
    defer storage.deinit();

    const e1 = Entity{ .index = 0, .generation = 0 };
    const e2 = Entity{ .index = 5, .generation = 0 };
    const e3 = Entity{ .index = 10, .generation = 0 };

    try storage.add(e1, .{ .value = 1 });
    try storage.add(e2, .{ .value = 2 });
    try storage.add(e3, .{ .value = 3 });

    var sum: i32 = 0;
    for (storage.items()) |comp| {
        sum += comp.value;
    }
    try std.testing.expectEqual(@as(i32, 6), sum);
}
