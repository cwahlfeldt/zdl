const std = @import("std");
const sdl = @import("sdl3");

/// Key state tracking
pub const KeyState = struct {
    down: bool = false,
    just_pressed: bool = false,
    just_released: bool = false,
};

/// Input manager for tracking keyboard state
pub const Input = struct {
    keys: std.AutoHashMap(sdl.Scancode, KeyState),

    pub fn init(allocator: std.mem.Allocator) Input {
        return .{
            .keys = std.AutoHashMap(sdl.Scancode, KeyState).init(allocator),
        };
    }

    pub fn deinit(self: *Input) void {
        self.keys.deinit();
    }

    /// Call this at the start of each frame to reset just_pressed/just_released flags
    pub fn update(self: *Input) void {
        var it = self.keys.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.just_pressed = false;
            entry.value_ptr.just_released = false;
        }
    }

    /// Process SDL keyboard events
    pub fn processEvent(self: *Input, event: sdl.events.Event) !void {
        switch (event) {
            .key_down => |key_event| {
                const scancode = key_event.scancode orelse return;
                const result = try self.keys.getOrPut(scancode);
                if (!result.found_existing) {
                    result.value_ptr.* = .{};
                }

                if (!result.value_ptr.down) {
                    result.value_ptr.just_pressed = true;
                }
                result.value_ptr.down = true;
            },
            .key_up => |key_event| {
                const scancode = key_event.scancode orelse return;
                const result = try self.keys.getOrPut(scancode);
                if (!result.found_existing) {
                    result.value_ptr.* = .{};
                }

                if (result.value_ptr.down) {
                    result.value_ptr.just_released = true;
                }
                result.value_ptr.down = false;
            },
            else => {},
        }
    }

    /// Check if a key is currently held down
    pub fn isKeyDown(self: *Input, scancode: sdl.Scancode) bool {
        const state = self.keys.get(scancode) orelse return false;
        return state.down;
    }

    /// Check if a key was just pressed this frame
    pub fn isKeyJustPressed(self: *Input, scancode: sdl.Scancode) bool {
        const state = self.keys.get(scancode) orelse return false;
        return state.just_pressed;
    }

    /// Check if a key was just released this frame
    pub fn isKeyJustReleased(self: *Input, scancode: sdl.Scancode) bool {
        const state = self.keys.get(scancode) orelse return false;
        return state.just_released;
    }

    /// Helper: Check if any of the WASD keys are down
    pub fn getWASD(self: *Input) struct { x: f32, y: f32 } {
        var x: f32 = 0.0;
        var y: f32 = 0.0;

        if (self.isKeyDown(.w)) y += 1.0;
        if (self.isKeyDown(.s)) y -= 1.0;
        if (self.isKeyDown(.a)) x -= 1.0;
        if (self.isKeyDown(.d)) x += 1.0;

        return .{ .x = x, .y = y };
    }

    /// Helper: Check if any of the arrow keys are down
    pub fn getArrowKeys(self: *Input) struct { x: f32, y: f32 } {
        var x: f32 = 0.0;
        var y: f32 = 0.0;

        if (self.isKeyDown(.up)) y += 1.0;
        if (self.isKeyDown(.down)) y -= 1.0;
        if (self.isKeyDown(.left)) x -= 1.0;
        if (self.isKeyDown(.right)) x += 1.0;

        return .{ .x = x, .y = y };
    }
};
