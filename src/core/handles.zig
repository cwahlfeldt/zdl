const std = @import("std");

//! Generic handle types for resource management.
//!
//! Handles use generational indices to detect stale references to freed resources.
//! This module is dependency-free (only uses std) so it can be imported by any layer.

/// Generic handle type with generational index
pub fn Handle(comptime name: []const u8) type {
    return struct {
        index: u32,
        generation: u32,

        const Self = @This();

        /// Name of the handle type (for debugging)
        pub const type_name = name;

        /// Invalid handle constant
        pub const invalid = Self{ .index = std.math.maxInt(u32), .generation = 0 };

        /// Check if the handle is valid (not the invalid sentinel)
        pub fn isValid(self: Self) bool {
            return self.index != std.math.maxInt(u32);
        }

        /// Check equality with another handle
        pub fn eql(self: Self, other: Self) bool {
            return self.index == other.index and self.generation == other.generation;
        }

        /// Format for debugging
        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            if (self.isValid()) {
                try writer.print("{s}({d}:{d})", .{ name, self.index, self.generation });
            } else {
                try writer.print("{s}(invalid)", .{name});
            }
        }
    };
}

/// Handle to a mesh asset
pub const MeshHandle = Handle("Mesh");

/// Handle to a texture asset
pub const TextureHandle = Handle("Texture");

/// Handle to a material asset
pub const MaterialHandle = Handle("Material");

/// Handle to an animation clip asset
pub const AnimationHandle = Handle("Animation");

/// Handle to a skeleton asset
pub const SkeletonHandle = Handle("Skeleton");

/// Generic slot for storing resources with generation tracking
pub fn Slot(comptime T: type) type {
    return struct {
        resource: ?*T,
        generation: u32,
        ref_count: u32,
        name: ?[]const u8,
        /// If true, this slot owns the resource and should free it on release.
        /// If false, the resource is borrowed and should not be freed.
        owned: bool,

        const Self = @This();

        pub fn init() Self {
            return .{
                .resource = null,
                .generation = 0,
                .ref_count = 0,
                .name = null,
                .owned = true,
            };
        }

        pub fn isOccupied(self: Self) bool {
            return self.resource != null;
        }
    };
}

/// Storage for resources with generational handles
pub fn Storage(comptime T: type, comptime HandleType: type) type {
    return struct {
        slots: std.ArrayListUnmanaged(Slot(T)),
        free_indices: std.ArrayListUnmanaged(u32),
        name_to_handle: std.StringHashMap(HandleType),
        allocator: std.mem.Allocator,

        const Self = @This();
        const SlotType = Slot(T);

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .slots = .{},
                .free_indices = .{},
                .name_to_handle = std.StringHashMap(HandleType).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            // Free all name strings
            var it = self.name_to_handle.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.name_to_handle.deinit();
            self.free_indices.deinit(self.allocator);
            self.slots.deinit(self.allocator);
        }

        /// Insert a new resource and return its handle.
        pub fn insert(self: *Self, resource: *T, name: ?[]const u8) !HandleType {
            return self.insertWithOwnership(resource, name, true);
        }

        /// Insert a borrowed resource (won't be freed on release)
        pub fn insertBorrowed(self: *Self, resource: *T, name: ?[]const u8) !HandleType {
            return self.insertWithOwnership(resource, name, false);
        }

        fn insertWithOwnership(self: *Self, resource: *T, name: ?[]const u8, owned: bool) !HandleType {
            var index: u32 = undefined;
            var generation: u32 = undefined;

            if (self.free_indices.items.len > 0) {
                // Reuse a freed slot
                index = self.free_indices.items[self.free_indices.items.len - 1];
                self.free_indices.items.len -= 1;
                generation = self.slots.items[index].generation;
                self.slots.items[index] = .{
                    .resource = resource,
                    .generation = generation,
                    .ref_count = 1,
                    .name = name,
                    .owned = owned,
                };
            } else {
                // Allocate a new slot
                index = @intCast(self.slots.items.len);
                generation = 0;
                try self.slots.append(self.allocator, .{
                    .resource = resource,
                    .generation = generation,
                    .ref_count = 1,
                    .name = name,
                    .owned = owned,
                });
            }

            const handle = HandleType{ .index = index, .generation = generation };

            // Register name mapping if provided
            if (name) |n| {
                const key = try self.allocator.dupe(u8, n);
                try self.name_to_handle.put(key, handle);
            }

            return handle;
        }

        /// Check if a handle's resource is owned
        pub fn isOwned(self: *Self, handle: HandleType) bool {
            if (!handle.isValid()) return false;
            if (handle.index >= self.slots.items.len) return false;
            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return false;
            return slot.owned;
        }

        /// Get resource by handle, returns null if handle is stale or invalid
        pub fn get(self: *Self, handle: HandleType) ?*T {
            if (!handle.isValid()) return null;
            if (handle.index >= self.slots.items.len) return null;

            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return null;

            return slot.resource;
        }

        /// Get handle by name
        pub fn getByName(self: *Self, name: []const u8) ?HandleType {
            return self.name_to_handle.get(name);
        }

        /// Increment reference count
        pub fn addRef(self: *Self, handle: HandleType) void {
            if (!handle.isValid()) return;
            if (handle.index >= self.slots.items.len) return;

            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return;

            slot.ref_count += 1;
        }

        /// Decrement reference count, returns true if resource should be freed
        pub fn release(self: *Self, handle: HandleType) bool {
            if (!handle.isValid()) return false;
            if (handle.index >= self.slots.items.len) return false;

            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return false;

            if (slot.ref_count > 0) {
                slot.ref_count -= 1;
            }

            return slot.ref_count == 0;
        }

        /// Remove a resource (call after release returns true)
        pub fn remove(self: *Self, handle: HandleType) void {
            if (!handle.isValid()) return;
            if (handle.index >= self.slots.items.len) return;

            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return;

            // Remove name mapping
            if (slot.name) |name| {
                if (self.name_to_handle.fetchRemove(name)) |kv| {
                    self.allocator.free(kv.key);
                }
            }

            // Increment generation to invalidate existing handles
            slot.generation +%= 1;
            slot.resource = null;
            slot.ref_count = 0;
            slot.name = null;

            // Add to free list
            self.free_indices.append(self.allocator, handle.index) catch {};
        }

        /// Get reference count for a handle
        pub fn getRefCount(self: *Self, handle: HandleType) u32 {
            if (!handle.isValid()) return 0;
            if (handle.index >= self.slots.items.len) return 0;

            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return 0;

            return slot.ref_count;
        }

        /// Check if a handle is valid (points to a live resource)
        pub fn isValidHandle(self: *Self, handle: HandleType) bool {
            return self.get(handle) != null;
        }

        /// Get the name associated with a handle
        pub fn getName(self: *Self, handle: HandleType) ?[]const u8 {
            if (!handle.isValid()) return null;
            if (handle.index >= self.slots.items.len) return null;

            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return null;

            return slot.name;
        }

        /// Find handle by resource pointer (reverse lookup)
        pub fn findHandle(self: *Self, resource: *const T) ?HandleType {
            for (self.slots.items, 0..) |slot, i| {
                if (slot.resource == resource) {
                    return HandleType{
                        .index = @intCast(i),
                        .generation = slot.generation,
                    };
                }
            }
            return null;
        }

        /// Get count of active resources
        pub fn count(self: *Self) usize {
            var active: usize = 0;
            for (self.slots.items) |slot| {
                if (slot.isOccupied()) active += 1;
            }
            return active;
        }
    };
}

// Tests
test "Handle basic operations" {
    const TestHandle = Handle("Test");
    const testing = std.testing;

    var handle = TestHandle{ .index = 5, .generation = 2 };
    try testing.expect(handle.isValid());
    try testing.expect(handle.eql(TestHandle{ .index = 5, .generation = 2 }));
    try testing.expect(!handle.eql(TestHandle{ .index = 5, .generation = 3 }));

    const invalid = TestHandle.invalid;
    try testing.expect(!invalid.isValid());
}

test "Storage insert and get" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const TestHandle = Handle("Test");

    var storage = Storage(u32, TestHandle).init(allocator);
    defer storage.deinit();

    var value1: u32 = 42;
    var value2: u32 = 100;

    const handle1 = try storage.insert(&value1, "test1");
    const handle2 = try storage.insert(&value2, "test2");

    try testing.expectEqual(@as(u32, 42), storage.get(handle1).?.*);
    try testing.expectEqual(@as(u32, 100), storage.get(handle2).?.*);
    try testing.expect(handle1.eql(storage.getByName("test1").?));
}

test "Storage reference counting" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const TestHandle = Handle("Test");

    var storage = Storage(u32, TestHandle).init(allocator);
    defer storage.deinit();

    var value: u32 = 42;
    const handle = try storage.insert(&value, null);

    try testing.expectEqual(@as(u32, 1), storage.getRefCount(handle));

    storage.addRef(handle);
    try testing.expectEqual(@as(u32, 2), storage.getRefCount(handle));

    try testing.expect(!storage.release(handle)); // Still has refs
    try testing.expectEqual(@as(u32, 1), storage.getRefCount(handle));

    try testing.expect(storage.release(handle)); // Now at 0
}

test "Storage generational safety" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const TestHandle = Handle("Test");

    var storage = Storage(u32, TestHandle).init(allocator);
    defer storage.deinit();

    var value1: u32 = 42;
    var value2: u32 = 100;

    const handle1 = try storage.insert(&value1, null);
    _ = storage.release(handle1);
    storage.remove(handle1);

    // Old handle should be invalid now
    try testing.expect(storage.get(handle1) == null);

    // New resource in same slot should have different generation
    const handle2 = try storage.insert(&value2, null);
    try testing.expectEqual(handle1.index, handle2.index);
    try testing.expect(handle1.generation != handle2.generation);
    try testing.expectEqual(@as(u32, 100), storage.get(handle2).?.*);
}
