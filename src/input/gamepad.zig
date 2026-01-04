const std = @import("std");
const sdl = @import("sdl3");

/// 2D vector for stick/movement values
pub const StickValue = struct { x: f32, y: f32 };

/// Gamepad button state tracking
pub const ButtonState = struct {
    down: bool = false,
    just_pressed: bool = false,
    just_released: bool = false,
};

/// Gamepad button enumeration matching SDL3 gamepad buttons
pub const Button = enum {
    /// Bottom face button (A on Xbox, Cross on PlayStation)
    south,
    /// Right face button (B on Xbox, Circle on PlayStation)
    east,
    /// Left face button (X on Xbox, Square on PlayStation)
    west,
    /// Top face button (Y on Xbox, Triangle on PlayStation)
    north,
    back,
    guide,
    start,
    left_stick,
    right_stick,
    left_shoulder,
    right_shoulder,
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
    /// Additional button (Share, Mic, Capture, etc.)
    misc1,
    right_paddle1,
    left_paddle1,
    right_paddle2,
    left_paddle2,
    touchpad,
    misc2,
    misc3,
    misc4,
    misc5,
    misc6,

    /// Convert from SDL gamepad button
    pub fn fromSdl(sdl_button: sdl.gamepad.Button) Button {
        return switch (sdl_button) {
            .south => .south,
            .east => .east,
            .west => .west,
            .north => .north,
            .back => .back,
            .guide => .guide,
            .start => .start,
            .left_stick => .left_stick,
            .right_stick => .right_stick,
            .left_shoulder => .left_shoulder,
            .right_shoulder => .right_shoulder,
            .dpad_up => .dpad_up,
            .dpad_down => .dpad_down,
            .dpad_left => .dpad_left,
            .dpad_right => .dpad_right,
            .misc1 => .misc1,
            .right_paddle1 => .right_paddle1,
            .left_paddle1 => .left_paddle1,
            .right_paddle2 => .right_paddle2,
            .left_paddle2 => .left_paddle2,
            .touchpad => .touchpad,
            .misc2 => .misc2,
            .misc3 => .misc3,
            .misc4 => .misc4,
            .misc5 => .misc5,
            .misc6 => .misc6,
        };
    }
};

/// Gamepad axis enumeration
pub const Axis = enum {
    left_x,
    left_y,
    right_x,
    right_y,
    left_trigger,
    right_trigger,

    /// Convert from SDL gamepad axis
    pub fn fromSdl(sdl_axis: sdl.gamepad.Axis) Axis {
        return switch (sdl_axis) {
            .left_x => .left_x,
            .left_y => .left_y,
            .right_x => .right_x,
            .right_y => .right_y,
            .left_trigger => .left_trigger,
            .right_trigger => .right_trigger,
        };
    }
};

/// Gamepad type enumeration
pub const GamepadType = enum {
    unknown,
    standard,
    xbox360,
    xbox_one,
    ps3,
    ps4,
    ps5,
    switch_pro,
    switch_joycon_left,
    switch_joycon_right,
    switch_joycon_pair,

    /// Convert from SDL gamepad type
    pub fn fromSdl(sdl_type: ?sdl.gamepad.Type) GamepadType {
        if (sdl_type) |t| {
            return switch (t) {
                .standard => .standard,
                .xbox360 => .xbox360,
                .xbox_one => .xbox_one,
                .ps3 => .ps3,
                .ps4 => .ps4,
                .ps5 => .ps5,
                .switch_pro => .switch_pro,
                .switch_joycon_left => .switch_joycon_left,
                .switch_joycon_right => .switch_joycon_right,
                .switch_joycon_pair => .switch_joycon_pair,
            };
        }
        return .unknown;
    }
};

/// Represents a connected gamepad with state tracking
pub const Gamepad = struct {
    /// SDL gamepad handle
    handle: sdl.gamepad.Gamepad,
    /// Joystick instance ID for event matching
    id: sdl.joystick.Id,
    /// Gamepad name
    name: []const u8,
    /// Gamepad type
    gamepad_type: GamepadType,
    /// Player index (0-3 typically)
    player_index: ?usize,

    /// Button states
    buttons: std.EnumArray(Button, ButtonState),

    /// Analog stick values (normalized -1.0 to 1.0)
    left_stick_x: f32 = 0,
    left_stick_y: f32 = 0,
    right_stick_x: f32 = 0,
    right_stick_y: f32 = 0,

    /// Trigger values (normalized 0.0 to 1.0)
    left_trigger: f32 = 0,
    right_trigger: f32 = 0,

    /// Dead zone configuration
    stick_dead_zone: f32 = 0.15,
    trigger_dead_zone: f32 = 0.05,

    /// Whether rumble is supported
    rumble_supported: bool = false,

    /// Initialize a gamepad from an SDL joystick ID
    pub fn init(joystick_id: sdl.joystick.Id) !Gamepad {
        const handle = try sdl.gamepad.Gamepad.init(joystick_id);

        const name = handle.getName() catch "Unknown Gamepad";
        const gamepad_type = GamepadType.fromSdl(handle.getType());
        const player_index = handle.getPlayerIndex();

        // Check rumble support
        const props = handle.getProperties() catch null;
        const rumble_supported = if (props) |p| p.rumble orelse false else false;

        return .{
            .handle = handle,
            .id = joystick_id,
            .name = name,
            .gamepad_type = gamepad_type,
            .player_index = player_index,
            .buttons = std.EnumArray(Button, ButtonState).initFill(.{}),
            .rumble_supported = rumble_supported,
        };
    }

    /// Close the gamepad
    pub fn deinit(self: *Gamepad) void {
        self.handle.deinit();
    }

    /// Reset just_pressed/just_released flags for all buttons
    pub fn resetFrameState(self: *Gamepad) void {
        var it = self.buttons.iterator();
        while (it.next()) |entry| {
            entry.value.just_pressed = false;
            entry.value.just_released = false;
        }
    }

    /// Handle a button down event
    pub fn handleButtonDown(self: *Gamepad, button: Button) void {
        var state = self.buttons.getPtr(button);
        if (!state.down) {
            state.just_pressed = true;
        }
        state.down = true;
    }

    /// Handle a button up event
    pub fn handleButtonUp(self: *Gamepad, button: Button) void {
        var state = self.buttons.getPtr(button);
        if (state.down) {
            state.just_released = true;
        }
        state.down = false;
    }

    /// Handle an axis motion event
    pub fn handleAxisMotion(self: *Gamepad, axis: Axis, value: i16) void {
        // Normalize axis value
        // Sticks: -32768 to 32767 -> -1.0 to 1.0
        // Triggers: 0 to 32767 -> 0.0 to 1.0
        const normalized = switch (axis) {
            .left_trigger, .right_trigger => @as(f32, @floatFromInt(value)) / 32767.0,
            else => @as(f32, @floatFromInt(value)) / 32767.0,
        };

        switch (axis) {
            .left_x => self.left_stick_x = normalized,
            .left_y => self.left_stick_y = normalized,
            .right_x => self.right_stick_x = normalized,
            .right_y => self.right_stick_y = normalized,
            .left_trigger => self.left_trigger = normalized,
            .right_trigger => self.right_trigger = normalized,
        }
    }

    /// Check if a button is currently held down
    pub fn isButtonDown(self: *const Gamepad, button: Button) bool {
        return self.buttons.get(button).down;
    }

    /// Check if a button was just pressed this frame
    pub fn isButtonJustPressed(self: *const Gamepad, button: Button) bool {
        return self.buttons.get(button).just_pressed;
    }

    /// Check if a button was just released this frame
    pub fn isButtonJustReleased(self: *const Gamepad, button: Button) bool {
        return self.buttons.get(button).just_released;
    }

    /// Get left stick with dead zone applied
    pub fn getLeftStick(self: *const Gamepad) StickValue {
        return applyDeadZone(self.left_stick_x, self.left_stick_y, self.stick_dead_zone);
    }

    /// Get right stick with dead zone applied
    pub fn getRightStick(self: *const Gamepad) StickValue {
        return applyDeadZone(self.right_stick_x, self.right_stick_y, self.stick_dead_zone);
    }

    /// Get left trigger with dead zone applied (0.0 to 1.0)
    pub fn getLeftTrigger(self: *const Gamepad) f32 {
        if (self.left_trigger < self.trigger_dead_zone) return 0.0;
        return (self.left_trigger - self.trigger_dead_zone) / (1.0 - self.trigger_dead_zone);
    }

    /// Get right trigger with dead zone applied (0.0 to 1.0)
    pub fn getRightTrigger(self: *const Gamepad) f32 {
        if (self.right_trigger < self.trigger_dead_zone) return 0.0;
        return (self.right_trigger - self.trigger_dead_zone) / (1.0 - self.trigger_dead_zone);
    }

    /// Start rumble/vibration effect
    /// low_frequency: 0.0 to 1.0 (heavy rumble motor)
    /// high_frequency: 0.0 to 1.0 (light rumble motor)
    /// duration_ms: Duration in milliseconds (0 = stop)
    pub fn rumble(self: *Gamepad, low_frequency: f32, high_frequency: f32, duration_ms: u32) void {
        if (!self.rumble_supported) return;

        const low = @as(u16, @intFromFloat(@min(1.0, @max(0.0, low_frequency)) * 65535.0));
        const high = @as(u16, @intFromFloat(@min(1.0, @max(0.0, high_frequency)) * 65535.0));

        self.handle.rumble(low, high, duration_ms) catch {};
    }

    /// Stop all rumble effects
    pub fn stopRumble(self: *Gamepad) void {
        self.rumble(0, 0, 0);
    }

    /// Check if the gamepad is still connected
    pub fn isConnected(self: *const Gamepad) bool {
        return self.handle.connected();
    }
};

/// Apply circular dead zone to stick values
fn applyDeadZone(x: f32, y: f32, dead_zone: f32) StickValue {
    const magnitude = @sqrt(x * x + y * y);

    if (magnitude < dead_zone) {
        return .{ .x = 0, .y = 0 };
    }

    // Normalize and rescale outside dead zone
    const normalized_magnitude = @min(1.0, (magnitude - dead_zone) / (1.0 - dead_zone));
    const scale = normalized_magnitude / magnitude;

    return .{
        .x = x * scale,
        .y = y * scale,
    };
}

/// Gamepad manager for handling multiple gamepads
pub const GamepadManager = struct {
    allocator: std.mem.Allocator,
    gamepads: std.AutoHashMap(sdl.joystick.Id, *Gamepad),
    /// Gamepads in connection order for player indexing
    connected_order: std.ArrayList(*Gamepad),

    pub fn init(allocator: std.mem.Allocator) GamepadManager {
        return .{
            .allocator = allocator,
            .gamepads = std.AutoHashMap(sdl.joystick.Id, *Gamepad).init(allocator),
            .connected_order = .{ .items = &.{}, .capacity = 0 },
        };
    }

    pub fn deinit(self: *GamepadManager) void {
        // Close all gamepads
        var it = self.gamepads.valueIterator();
        while (it.next()) |gamepad_ptr| {
            gamepad_ptr.*.deinit();
            self.allocator.destroy(gamepad_ptr.*);
        }
        self.gamepads.deinit();
        self.connected_order.deinit(self.allocator);
    }

    /// Reset frame state for all gamepads
    pub fn update(self: *GamepadManager) void {
        var it = self.gamepads.valueIterator();
        while (it.next()) |gamepad_ptr| {
            gamepad_ptr.*.resetFrameState();
        }
    }

    /// Handle gamepad added event
    pub fn handleGamepadAdded(self: *GamepadManager, joystick_id: sdl.joystick.Id) !void {
        // Check if already added
        if (self.gamepads.contains(joystick_id)) return;

        const gamepad = try self.allocator.create(Gamepad);
        gamepad.* = try Gamepad.init(joystick_id);

        try self.gamepads.put(joystick_id, gamepad);
        try self.connected_order.append(self.allocator, gamepad);

        std.debug.print("Gamepad connected: {s} (type: {s}, player: {?})\n", .{
            gamepad.name,
            @tagName(gamepad.gamepad_type),
            gamepad.player_index,
        });
    }

    /// Handle gamepad removed event
    pub fn handleGamepadRemoved(self: *GamepadManager, joystick_id: sdl.joystick.Id) void {
        if (self.gamepads.fetchRemove(joystick_id)) |entry| {
            const gamepad = entry.value;

            // Remove from connected order
            for (self.connected_order.items, 0..) |g, i| {
                if (g == gamepad) {
                    _ = self.connected_order.orderedRemove(i);
                    break;
                }
            }

            std.debug.print("Gamepad disconnected: {s}\n", .{gamepad.name});

            gamepad.deinit();
            self.allocator.destroy(gamepad);
        }
    }

    /// Get gamepad by joystick ID
    pub fn getById(self: *GamepadManager, joystick_id: sdl.joystick.Id) ?*Gamepad {
        return self.gamepads.get(joystick_id);
    }

    /// Get gamepad by player index (0 = first connected)
    pub fn getByIndex(self: *GamepadManager, index: usize) ?*Gamepad {
        if (index >= self.connected_order.items.len) return null;
        return self.connected_order.items[index];
    }

    /// Get the primary gamepad (first connected)
    pub fn getPrimary(self: *GamepadManager) ?*Gamepad {
        return self.getByIndex(0);
    }

    /// Get count of connected gamepads
    pub fn getCount(self: *const GamepadManager) usize {
        return self.connected_order.items.len;
    }

    /// Scan for already-connected gamepads (call at startup)
    pub fn scanForGamepads(self: *GamepadManager) !void {
        if (!sdl.gamepad.hasGamepad()) return;

        const gamepad_ids = sdl.gamepad.getGamepads() catch return;
        defer sdl.free(gamepad_ids);

        for (gamepad_ids) |id| {
            self.handleGamepadAdded(id) catch |err| {
                std.debug.print("Failed to add gamepad: {}\n", .{err});
            };
        }
    }
};

/// Haptic presets for common effects
pub const HapticPresets = struct {
    pub fn lightTap(gamepad: *Gamepad) void {
        gamepad.rumble(0.2, 0.1, 50);
    }

    pub fn mediumImpact(gamepad: *Gamepad) void {
        gamepad.rumble(0.5, 0.3, 100);
    }

    pub fn heavyImpact(gamepad: *Gamepad) void {
        gamepad.rumble(1.0, 0.5, 200);
    }

    pub fn explosion(gamepad: *Gamepad) void {
        gamepad.rumble(1.0, 1.0, 300);
    }

    pub fn heartbeat(gamepad: *Gamepad) void {
        gamepad.rumble(0.8, 0.0, 150);
    }
};
