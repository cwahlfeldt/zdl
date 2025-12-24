const std = @import("std");

/// Entity handle with generational index for safe reference tracking.
/// The generation prevents dangling references when entities are reused.
pub const Entity = struct {
    index: u32,
    generation: u32,

    pub const invalid = Entity{ .index = std.math.maxInt(u32), .generation = 0 };

    pub fn isValid(self: Entity) bool {
        return self.index != std.math.maxInt(u32);
    }

    pub fn eql(self: Entity, other: Entity) bool {
        return self.index == other.index and self.generation == other.generation;
    }

    pub fn format(
        self: Entity,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (self.isValid()) {
            try writer.print("Entity({}, gen={})", .{ self.index, self.generation });
        } else {
            try writer.writeAll("Entity(invalid)");
        }
    }
};

/// Manages entity creation, destruction, and lifecycle.
/// Uses a free list for efficient entity recycling.
pub const EntityManager = struct {
    /// Current generation for each entity slot
    generations: std.ArrayList(u32),
    /// Indices available for reuse
    free_indices: std.ArrayList(u32),
    /// Number of currently alive entities
    alive_count: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EntityManager {
        return .{
            .generations = .{},
            .free_indices = .{},
            .alive_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EntityManager) void {
        self.generations.deinit(self.allocator);
        self.free_indices.deinit(self.allocator);
    }

    /// Create a new entity, reusing slots when available.
    pub fn create(self: *EntityManager) !Entity {
        if (self.free_indices.items.len > 0) {
            // Reuse a freed slot
            const index = self.free_indices.pop().?;
            self.alive_count += 1;
            return Entity{
                .index = index,
                .generation = self.generations.items[index],
            };
        } else {
            // Allocate a new slot
            const index: u32 = @intCast(self.generations.items.len);
            try self.generations.append(self.allocator, 0);
            self.alive_count += 1;
            return Entity{
                .index = index,
                .generation = 0,
            };
        }
    }

    /// Destroy an entity, making its slot available for reuse.
    pub fn destroy(self: *EntityManager, entity: Entity) !void {
        if (!self.isAlive(entity)) return;

        // Increment generation to invalidate old handles
        self.generations.items[entity.index] += 1;
        try self.free_indices.append(self.allocator, entity.index);
        self.alive_count -= 1;
    }

    /// Check if an entity is still alive (not destroyed or stale handle).
    pub fn isAlive(self: *const EntityManager, entity: Entity) bool {
        if (!entity.isValid()) return false;
        if (entity.index >= self.generations.items.len) return false;
        return self.generations.items[entity.index] == entity.generation;
    }

    /// Get the number of currently alive entities.
    pub fn count(self: *const EntityManager) u32 {
        return self.alive_count;
    }
};

test "entity creation and destruction" {
    var manager = EntityManager.init(std.testing.allocator);
    defer manager.deinit();

    const e1 = try manager.create();
    const e2 = try manager.create();

    try std.testing.expect(manager.isAlive(e1));
    try std.testing.expect(manager.isAlive(e2));
    try std.testing.expectEqual(@as(u32, 2), manager.count());

    try manager.destroy(e1);
    try std.testing.expect(!manager.isAlive(e1));
    try std.testing.expect(manager.isAlive(e2));
    try std.testing.expectEqual(@as(u32, 1), manager.count());

    // New entity should reuse e1's slot but have different generation
    const e3 = try manager.create();
    try std.testing.expectEqual(e1.index, e3.index);
    try std.testing.expect(e3.generation > e1.generation);
    try std.testing.expect(!e1.eql(e3));
}

test "invalid entity" {
    var manager = EntityManager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expect(!Entity.invalid.isValid());
    try std.testing.expect(!manager.isAlive(Entity.invalid));
}
