const std = @import("std");
pub const sdl = @import("sdl3");
const gamepad_module = @import("gamepad.zig");

pub const Scancode = sdl.Scancode;
pub const Gamepad = gamepad_module.Gamepad;
pub const GamepadManager = gamepad_module.GamepadManager;
pub const GamepadButton = gamepad_module.Button;
pub const GamepadAxis = gamepad_module.Axis;
pub const GamepadType = gamepad_module.GamepadType;
pub const HapticPresets = gamepad_module.HapticPresets;
pub const StickValue = gamepad_module.StickValue;

/// Key state tracking
pub const KeyState = struct {
    down: bool = false,
    just_pressed: bool = false,
    just_released: bool = false,
};

/// Mouse button state tracking
pub const MouseButton = enum {
    left,
    middle,
    right,

    /// Convert from SDL mouse button
    pub fn fromSdl(button: sdl.mouse.Button) ?MouseButton {
        return switch (button) {
            .left => .left,
            .middle => .middle,
            .right => .right,
            else => null,
        };
    }
};

/// Input device type for tracking last active device
pub const InputDevice = enum {
    keyboard_mouse,
    gamepad,
};

/// Input manager for tracking keyboard, mouse, and gamepad state.
///
/// This struct provides both SDL event processing (via processEvent) and
/// direct state-setting methods (setKeyDown, setMousePosition, etc.) for
/// testability. In production, use processEvent. For unit tests, use the
/// direct setters to mock input without SDL.
pub const Input = struct {
    allocator: std.mem.Allocator,
    keys: std.AutoHashMap(sdl.Scancode, KeyState),

    // Mouse state
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_delta_x: f32 = 0,
    mouse_delta_y: f32 = 0,
    mouse_left: bool = false,
    mouse_right: bool = false,
    mouse_middle: bool = false,
    mouse_left_just_pressed: bool = false,
    mouse_right_just_pressed: bool = false,
    mouse_middle_just_pressed: bool = false,
    mouse_left_just_released: bool = false,
    mouse_right_just_released: bool = false,
    mouse_middle_just_released: bool = false,
    mouse_captured: bool = false,

    // Gamepad state
    gamepads: GamepadManager,

    /// Track last input device for UI prompt switching
    last_input_device: InputDevice = .keyboard_mouse,

    pub fn init(allocator: std.mem.Allocator) Input {
        var input = Input{
            .allocator = allocator,
            .keys = std.AutoHashMap(sdl.Scancode, KeyState).init(allocator),
            .gamepads = GamepadManager.init(allocator),
        };

        // Scan for already-connected gamepads
        input.gamepads.scanForGamepads() catch {};

        return input;
    }

    // ============ Direct State-Setting Methods (for testing) ============
    // These methods allow setting input state without SDL events.

    /// Set a key as pressed. If already down, this is a repeat.
    pub fn setKeyDown(self: *Input, scancode: sdl.Scancode, repeat: bool) void {
        const result = self.keys.getOrPut(scancode) catch return;
        if (!result.found_existing) {
            result.value_ptr.* = .{};
        }

        if (!result.value_ptr.down and !repeat) {
            result.value_ptr.just_pressed = true;
        }
        result.value_ptr.down = true;
        self.last_input_device = .keyboard_mouse;
    }

    /// Set a key as released.
    pub fn setKeyUp(self: *Input, scancode: sdl.Scancode) void {
        const result = self.keys.getOrPut(scancode) catch return;
        if (!result.found_existing) {
            result.value_ptr.* = .{};
        }

        if (result.value_ptr.down) {
            result.value_ptr.just_released = true;
        }
        result.value_ptr.down = false;
    }

    /// Set mouse position directly.
    pub fn setMousePosition(self: *Input, x: f32, y: f32) void {
        self.mouse_x = x;
        self.mouse_y = y;
        self.last_input_device = .keyboard_mouse;
    }

    /// Add to mouse delta (accumulates within frame).
    pub fn setMouseDelta(self: *Input, dx: f32, dy: f32) void {
        self.mouse_delta_x += dx;
        self.mouse_delta_y += dy;
        self.last_input_device = .keyboard_mouse;
    }

    /// Set mouse button state.
    pub fn setMouseButton(self: *Input, button: MouseButton, down: bool) void {
        self.last_input_device = .keyboard_mouse;
        switch (button) {
            .left => {
                if (down and !self.mouse_left) {
                    self.mouse_left_just_pressed = true;
                } else if (!down and self.mouse_left) {
                    self.mouse_left_just_released = true;
                }
                self.mouse_left = down;
            },
            .middle => {
                if (down and !self.mouse_middle) {
                    self.mouse_middle_just_pressed = true;
                } else if (!down and self.mouse_middle) {
                    self.mouse_middle_just_released = true;
                }
                self.mouse_middle = down;
            },
            .right => {
                if (down and !self.mouse_right) {
                    self.mouse_right_just_pressed = true;
                } else if (!down and self.mouse_right) {
                    self.mouse_right_just_released = true;
                }
                self.mouse_right = down;
            },
        }
    }

    /// Reset all input state. Useful for tests.
    pub fn reset(self: *Input) void {
        self.keys.clearRetainingCapacity();
        self.mouse_x = 0;
        self.mouse_y = 0;
        self.mouse_delta_x = 0;
        self.mouse_delta_y = 0;
        self.mouse_left = false;
        self.mouse_right = false;
        self.mouse_middle = false;
        self.mouse_left_just_pressed = false;
        self.mouse_right_just_pressed = false;
        self.mouse_middle_just_pressed = false;
        self.mouse_left_just_released = false;
        self.mouse_right_just_released = false;
        self.mouse_middle_just_released = false;
        self.last_input_device = .keyboard_mouse;
    }

    pub fn deinit(self: *Input) void {
        self.gamepads.deinit();
        self.keys.deinit();
    }

    /// Call this at the start of each frame to reset just_pressed/just_released flags.
    /// This is called by the Engine at the beginning of each frame.
    pub fn update(self: *Input) void {
        var it = self.keys.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.just_pressed = false;
            entry.value_ptr.just_released = false;
        }

        // Reset mouse delta each frame
        self.mouse_delta_x = 0;
        self.mouse_delta_y = 0;

        // Reset mouse button just_pressed/just_released flags
        self.mouse_left_just_pressed = false;
        self.mouse_right_just_pressed = false;
        self.mouse_middle_just_pressed = false;
        self.mouse_left_just_released = false;
        self.mouse_right_just_released = false;
        self.mouse_middle_just_released = false;

        // Reset gamepad frame state
        self.gamepads.update();
    }

    /// Call this at the end of each frame (alternative to update at start).
    /// Use either update() at frame start OR endFrame() at frame end, not both.
    pub fn endFrame(self: *Input) void {
        self.update();
    }

    /// Process SDL keyboard, mouse, and gamepad events
    pub fn processEvent(self: *Input, event: sdl.events.Event) !void {
        switch (event) {
            .key_down => |key_event| {
                self.last_input_device = .keyboard_mouse;
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
            .mouse_motion => |motion| {
                self.last_input_device = .keyboard_mouse;
                self.mouse_x = motion.x;
                self.mouse_y = motion.y;
                self.mouse_delta_x += motion.x_rel;
                self.mouse_delta_y += motion.y_rel;
            },
            .mouse_button_down => |button| {
                self.last_input_device = .keyboard_mouse;
                switch (button.button) {
                    .left => self.mouse_left = true,
                    .middle => self.mouse_middle = true,
                    .right => self.mouse_right = true,
                    else => {},
                }
            },
            .mouse_button_up => |button| {
                switch (button.button) {
                    .left => self.mouse_left = false,
                    .middle => self.mouse_middle = false,
                    .right => self.mouse_right = false,
                    else => {},
                }
            },
            // Gamepad events
            .gamepad_added => |gp_event| {
                try self.gamepads.handleGamepadAdded(gp_event.id);
            },
            .gamepad_removed => |gp_event| {
                self.gamepads.handleGamepadRemoved(gp_event.id);
            },
            .gamepad_button_down => |gp_event| {
                self.last_input_device = .gamepad;
                if (self.gamepads.getById(gp_event.id)) |gamepad| {
                    gamepad.handleButtonDown(GamepadButton.fromSdl(gp_event.button));
                }
            },
            .gamepad_button_up => |gp_event| {
                if (self.gamepads.getById(gp_event.id)) |gamepad| {
                    gamepad.handleButtonUp(GamepadButton.fromSdl(gp_event.button));
                }
            },
            .gamepad_axis_motion => |gp_event| {
                self.last_input_device = .gamepad;
                if (self.gamepads.getById(gp_event.id)) |gamepad| {
                    gamepad.handleAxisMotion(GamepadAxis.fromSdl(gp_event.axis), gp_event.value);
                }
            },
            else => {},
        }
    }

    /// Get mouse delta since last frame
    pub fn getMouseDelta(self: *const Input) StickValue {
        return .{ .x = self.mouse_delta_x, .y = self.mouse_delta_y };
    }

    /// Get mouse position
    pub fn getMousePosition(self: *const Input) StickValue {
        return .{ .x = self.mouse_x, .y = self.mouse_y };
    }

    /// Check if a mouse button is down
    pub fn isMouseButtonDown(self: *const Input, button: MouseButton) bool {
        return switch (button) {
            .left => self.mouse_left,
            .middle => self.mouse_middle,
            .right => self.mouse_right,
        };
    }

    /// Check if a mouse button was just pressed this frame
    pub fn isMouseButtonJustPressed(self: *const Input, button: MouseButton) bool {
        return switch (button) {
            .left => self.mouse_left_just_pressed,
            .middle => self.mouse_middle_just_pressed,
            .right => self.mouse_right_just_pressed,
        };
    }

    /// Check if a mouse button was just released this frame
    pub fn isMouseButtonJustReleased(self: *const Input, button: MouseButton) bool {
        return switch (button) {
            .left => self.mouse_left_just_released,
            .middle => self.mouse_middle_just_released,
            .right => self.mouse_right_just_released,
        };
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
    pub fn getWASD(self: *Input) StickValue {
        var x: f32 = 0.0;
        var y: f32 = 0.0;

        if (self.isKeyDown(.w)) y -= 1.0;
        if (self.isKeyDown(.s)) y += 1.0;
        if (self.isKeyDown(.a)) x -= 1.0;
        if (self.isKeyDown(.d)) x += 1.0;

        return .{ .x = x, .y = y };
    }

    /// Helper: Check if any of the arrow keys are down
    pub fn getArrowKeys(self: *Input) StickValue {
        var x: f32 = 0.0;
        var y: f32 = 0.0;

        if (self.isKeyDown(.up)) y -= 1.0;
        if (self.isKeyDown(.down)) y += 1.0;
        if (self.isKeyDown(.left)) x -= 1.0;
        if (self.isKeyDown(.right)) x += 1.0;

        return .{ .x = x, .y = y };
    }

    // ============ Gamepad Helper Methods ============

    /// Get the primary (first connected) gamepad
    pub fn getGamepad(self: *Input) ?*Gamepad {
        return self.gamepads.getPrimary();
    }

    /// Get gamepad by player index (0 = first connected)
    pub fn getGamepadByIndex(self: *Input, index: usize) ?*Gamepad {
        return self.gamepads.getByIndex(index);
    }

    /// Get number of connected gamepads
    pub fn getGamepadCount(self: *const Input) usize {
        return self.gamepads.getCount();
    }

    /// Check if any gamepad is connected
    pub fn hasGamepad(self: *const Input) bool {
        return self.gamepads.getCount() > 0;
    }

    /// Check if using gamepad as last input device
    pub fn isUsingGamepad(self: *const Input) bool {
        return self.last_input_device == .gamepad;
    }

    // ============ Unified Input Methods ============

    /// Get movement vector from WASD keys OR primary gamepad left stick
    /// Returns combined input from keyboard and gamepad (keyboard takes priority if both active)
    pub fn getMoveVector(self: *Input) StickValue {
        const wasd = self.getWASD();

        // If keyboard input, use it
        if (wasd.x != 0 or wasd.y != 0) {
            return wasd;
        }

        // Otherwise check gamepad
        if (self.gamepads.getPrimary()) |gamepad| {
            return gamepad.getLeftStick();
        }

        return .{ .x = 0, .y = 0 };
    }

    /// Get look vector from mouse delta OR primary gamepad right stick
    /// Note: Mouse delta is in pixels, stick is normalized -1 to 1
    /// Consider applying sensitivity/scaling in your game code
    pub fn getLookVector(self: *Input) StickValue {
        const mouse = self.getMouseDelta();

        // If mouse moved, use it
        if (mouse.x != 0 or mouse.y != 0) {
            return mouse;
        }

        // Otherwise check gamepad
        if (self.gamepads.getPrimary()) |gamepad| {
            const stick = gamepad.getRightStick();
            // Scale stick input to be more comparable to mouse (adjust as needed)
            return .{ .x = stick.x * 10.0, .y = stick.y * 10.0 };
        }

        return .{ .x = 0, .y = 0 };
    }

    /// Check if "confirm" action is pressed (Space/Enter OR gamepad south button)
    pub fn isConfirmPressed(self: *Input) bool {
        if (self.isKeyJustPressed(.space) or self.isKeyJustPressed(.return_key)) {
            return true;
        }
        if (self.gamepads.getPrimary()) |gamepad| {
            return gamepad.isButtonJustPressed(.south);
        }
        return false;
    }

    /// Check if "cancel" action is pressed (Escape OR gamepad east button)
    pub fn isCancelPressed(self: *Input) bool {
        if (self.isKeyJustPressed(.escape)) {
            return true;
        }
        if (self.gamepads.getPrimary()) |gamepad| {
            return gamepad.isButtonJustPressed(.east);
        }
        return false;
    }

    /// Check if "jump" action (Space OR gamepad south button) is down
    pub fn isJumpDown(self: *Input) bool {
        if (self.isKeyDown(.space)) {
            return true;
        }
        if (self.gamepads.getPrimary()) |gamepad| {
            return gamepad.isButtonDown(.south);
        }
        return false;
    }

    /// Check if "jump" was just pressed this frame
    pub fn isJumpPressed(self: *Input) bool {
        if (self.isKeyJustPressed(.space)) {
            return true;
        }
        if (self.gamepads.getPrimary()) |gamepad| {
            return gamepad.isButtonJustPressed(.south);
        }
        return false;
    }
};
