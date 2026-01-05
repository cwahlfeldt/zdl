const std = @import("std");
const ecs = @import("zflecs");

/// Entity handle compatible with Flecs.
/// Wraps Flecs' 64-bit entity ID.
pub const Entity = struct {
    id: ecs.entity_t,

    pub const invalid = Entity{ .id = 0 };

    pub fn isValid(self: Entity) bool {
        return self.id != 0;
    }

    pub fn eql(self: Entity, other: Entity) bool {
        return self.id == other.id;
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
            try writer.print("Entity({})", .{self.id});
        } else {
            try writer.writeAll("Entity(invalid)");
        }
    }
};
