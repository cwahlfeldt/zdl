const std = @import("std");
const quickjs = @import("quickjs");
const zflecs = @import("zflecs");

const JSContext = @import("js_context.zig").JSContext;
const Scene = @import("../ecs/scene.zig").Scene;

/// Phases for system execution (aligned with Flecs phases)
pub const SystemPhase = enum {
    init,
    update,
    destroy,

    pub fn toFlecsPhase(self: SystemPhase) zflecs.entity_t {
        return switch (self) {
            .init => zflecs.OnStart,
            .update => zflecs.OnUpdate,
            .destroy => zflecs.OnRemove,
        };
    }
};

/// A JavaScript system with its function reference and metadata
pub const JsSystem = struct {
    name: []const u8,
    function: quickjs.Value, // Duplicated reference to prevent GC
    phase: SystemPhase,
    flecs_entity: zflecs.entity_t = 0, // Flecs system entity ID
};

/// Registry for managing JavaScript systems with Flecs integration
pub const SystemRegistry = struct {
    allocator: std.mem.Allocator,
    init_systems: std.ArrayListUnmanaged(JsSystem),
    update_systems: std.ArrayListUnmanaged(JsSystem),
    destroy_systems: std.ArrayListUnmanaged(JsSystem),
    flecs_world: ?*zflecs.world_t = null,
    context: ?*JSContext = null,
    system_counter: usize = 0,

    pub fn init(allocator: std.mem.Allocator) SystemRegistry {
        return .{
            .allocator = allocator,
            .init_systems = .{},
            .update_systems = .{},
            .destroy_systems = .{},
        };
    }

    pub fn deinit(self: *SystemRegistry) void {
        // Free all JS function references
        if (self.context) |ctx| {
            for (self.init_systems.items) |sys| {
                ctx.freeValue(sys.function);
                self.allocator.free(sys.name);
            }
            for (self.update_systems.items) |sys| {
                ctx.freeValue(sys.function);
                self.allocator.free(sys.name);
            }
            for (self.destroy_systems.items) |sys| {
                ctx.freeValue(sys.function);
                self.allocator.free(sys.name);
            }
        }

        self.init_systems.deinit(self.allocator);
        self.update_systems.deinit(self.allocator);
        self.destroy_systems.deinit(self.allocator);
    }

    /// Set the Flecs world for system registration
    pub fn setFlecsWorld(self: *SystemRegistry, world: ?*zflecs.world_t, ctx: *JSContext) void {
        self.flecs_world = world;
        self.context = ctx;
    }

    /// Add a JavaScript system to the registry
    pub fn add(self: *SystemRegistry, system: JsSystem) !void {
        const list = switch (system.phase) {
            .init => &self.init_systems,
            .update => &self.update_systems,
            .destroy => &self.destroy_systems,
        };

        try list.append(self.allocator, system);

        // If we have a Flecs world, register the system with Flecs
        if (self.flecs_world) |world| {
            try self.registerWithFlecs(world, &list.items[list.items.len - 1]);
        }
    }

    /// Register a JS system with Flecs (creates a Flecs system entity)
    fn registerWithFlecs(self: *SystemRegistry, world: *zflecs.world_t, system: *JsSystem) !void {
        _ = self;
        _ = world;
        _ = system;

        // TODO: Implement Flecs system registration
        // This would create a proper Flecs system entity that integrates with
        // the Flecs scheduler. For now, we use the manual runPhase() approach.
        //
        // Future implementation would use:
        // - ecs_system_init with proper descriptor
        // - Callback that invokes the JS function
        // - Phase integration with Flecs pipeline
    }

    /// Run all systems in a specific phase (JS-side execution)
    pub fn runPhase(self: *SystemRegistry, phase: SystemPhase) void {
        const list = switch (phase) {
            .init => &self.init_systems,
            .update => &self.update_systems,
            .destroy => &self.destroy_systems,
        };

        const ctx = self.context orelse return;

        // Get the active world object to pass to systems
        const world = ctx.getGlobal("__world_active");
        defer ctx.freeValue(world);

        for (list.items) |sys| {
            // Call the JavaScript function with world as parameter
            const result = ctx.call(sys.function, sys.function, &.{world}) catch |err| {
                std.debug.print("[SystemRegistry] Error running system '{s}': {}\n", .{ sys.name, err });
                continue;
            };
            ctx.freeValue(result);
        }
    }

    /// Get system count for a specific phase
    pub fn getSystemCount(self: *SystemRegistry, phase: SystemPhase) usize {
        return switch (phase) {
            .init => self.init_systems.items.len,
            .update => self.update_systems.items.len,
            .destroy => self.destroy_systems.items.len,
        };
    }

    /// Generate a unique system name
    pub fn generateSystemName(self: *SystemRegistry, allocator: std.mem.Allocator) ![]const u8 {
        self.system_counter += 1;
        return try std.fmt.allocPrint(allocator, "system_{d}", .{self.system_counter});
    }
};

/// Flecs callback for JS systems
fn jsSystemCallback(it: *zflecs.ecs_iter_t) callconv(.C) void {
    const system: *JsSystem = @ptrCast(@alignCast(it.ctx));
    _ = system;

    // Note: This is a placeholder. In a full implementation, we would:
    // 1. Get the JSContext from the system or iterator
    // 2. Call the JS function with appropriate arguments
    // 3. Handle any errors
    //
    // For now, we rely on the runPhase method for execution.
}

test "system registry init and deinit" {
    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.init_systems.items.len == 0);
    try std.testing.expect(registry.update_systems.items.len == 0);
    try std.testing.expect(registry.destroy_systems.items.len == 0);
}

test "generate unique system names" {
    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const name1 = try registry.generateSystemName(std.testing.allocator);
    defer std.testing.allocator.free(name1);
    const name2 = try registry.generateSystemName(std.testing.allocator);
    defer std.testing.allocator.free(name2);

    try std.testing.expect(!std.mem.eql(u8, name1, name2));
}
