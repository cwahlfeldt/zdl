const std = @import("std");
const quickjs = @import("quickjs");

const JSContext = @import("../js_context.zig").JSContext;
const input_module = @import("../../input/input.zig");
const Input = input_module.Input;
const Scancode = input_module.Scancode;
const bindings = @import("bindings.zig");

/// Register Input API on the global object.
pub fn register(ctx: *JSContext) !void {
    const input_code =
        \\var Input = {
        \\    // Updated each frame by the script system
        \\    _keys: {},
        \\    _keysPressed: {},
        \\    _keysReleased: {},
        \\    _mouseX: 0,
        \\    _mouseY: 0,
        \\    _mouseDeltaX: 0,
        \\    _mouseDeltaY: 0,
        \\    _mouseButtons: {},
        \\    _mouseButtonsPressed: {},
        \\    _moveX: 0,
        \\    _moveY: 0,
        \\    _lookX: 0,
        \\    _lookY: 0,
        \\    _confirmPressed: false,
        \\    _cancelPressed: false,
        \\    _jumpPressed: false,
        \\    _jumpDown: false,
        \\    _hasGamepad: false,
        \\    _gamepad: null,
        \\
        \\    // Keyboard
        \\    isKeyDown: function(key) {
        \\        return this._keys[key] || false;
        \\    },
        \\    isKeyPressed: function(key) {
        \\        return this._keysPressed[key] || false;
        \\    },
        \\    isKeyReleased: function(key) {
        \\        return this._keysReleased[key] || false;
        \\    },
        \\
        \\    // Mouse
        \\    getMousePosition: function() {
        \\        return new Vec2(this._mouseX, this._mouseY);
        \\    },
        \\    getMouseDelta: function() {
        \\        return new Vec2(this._mouseDeltaX, this._mouseDeltaY);
        \\    },
        \\    isMouseButtonDown: function(button) {
        \\        return this._mouseButtons[button] || false;
        \\    },
        \\    isMouseButtonPressed: function(button) {
        \\        return this._mouseButtonsPressed[button] || false;
        \\    },
        \\
        \\    // Unified input
        \\    getMoveVector: function() {
        \\        return new Vec2(this._moveX, this._moveY);
        \\    },
        \\    getLookVector: function() {
        \\        return new Vec2(this._lookX, this._lookY);
        \\    },
        \\    isConfirmPressed: function() {
        \\        return this._confirmPressed;
        \\    },
        \\    isCancelPressed: function() {
        \\        return this._cancelPressed;
        \\    },
        \\    isJumpPressed: function() {
        \\        return this._jumpPressed;
        \\    },
        \\    isJumpDown: function() {
        \\        return this._jumpDown;
        \\    },
        \\
        \\    // Gamepad
        \\    hasGamepad: function() {
        \\        return this._hasGamepad;
        \\    },
        \\    getGamepad: function() {
        \\        if (!this._hasGamepad) return null;
        \\        return this._gamepad;
        \\    }
        \\};
        \\
        \\// Key constants (SDL scancodes)
        \\var Key = {
        \\    A: 'a', B: 'b', C: 'c', D: 'd', E: 'e', F: 'f', G: 'g', H: 'h',
        \\    I: 'i', J: 'j', K: 'k', L: 'l', M: 'm', N: 'n', O: 'o', P: 'p',
        \\    Q: 'q', R: 'r', S: 's', T: 't', U: 'u', V: 'v', W: 'w', X: 'x',
        \\    Y: 'y', Z: 'z',
        \\    SPACE: 'space', ENTER: 'enter', ESCAPE: 'escape', TAB: 'tab',
        \\    BACKSPACE: 'backspace', DELETE: 'delete', INSERT: 'insert',
        \\    HOME: 'home', END: 'end', PAGEUP: 'pageup', PAGEDOWN: 'pagedown',
        \\    UP: 'up', DOWN: 'down', LEFT: 'left', RIGHT: 'right',
        \\    LSHIFT: 'lshift', RSHIFT: 'rshift', LCTRL: 'lctrl', RCTRL: 'rctrl',
        \\    LALT: 'lalt', RALT: 'ralt',
        \\    NUM_0: '0', NUM_1: '1', NUM_2: '2', NUM_3: '3', NUM_4: '4',
        \\    NUM_5: '5', NUM_6: '6', NUM_7: '7', NUM_8: '8', NUM_9: '9',
        \\    F1: 'f1', F2: 'f2', F3: 'f3', F4: 'f4', F5: 'f5', F6: 'f6',
        \\    F7: 'f7', F8: 'f8', F9: 'f9', F10: 'f10', F11: 'f11', F12: 'f12'
        \\};
        \\
        \\// Mouse button constants
        \\var MouseButton = {
        \\    LEFT: 'left',
        \\    MIDDLE: 'middle',
        \\    RIGHT: 'right'
        \\};
        \\
        \\// Gamepad button constants
        \\var GamepadButton = {
        \\    SOUTH: 'south',      // A (Xbox), Cross (PS)
        \\    EAST: 'east',        // B (Xbox), Circle (PS)
        \\    WEST: 'west',        // X (Xbox), Square (PS)
        \\    NORTH: 'north',      // Y (Xbox), Triangle (PS)
        \\    LEFT_SHOULDER: 'left_shoulder',
        \\    RIGHT_SHOULDER: 'right_shoulder',
        \\    LEFT_STICK: 'left_stick',
        \\    RIGHT_STICK: 'right_stick',
        \\    BACK: 'back',
        \\    START: 'start',
        \\    GUIDE: 'guide',
        \\    DPAD_UP: 'dpad_up',
        \\    DPAD_DOWN: 'dpad_down',
        \\    DPAD_LEFT: 'dpad_left',
        \\    DPAD_RIGHT: 'dpad_right'
        \\};
        \\
        \\true;
    ;
    _ = try ctx.eval(input_code, "<input>");
}

/// Update input state for the current frame.
pub fn updateFrame(ctx: *JSContext, input: *Input) void {
    const input_obj = ctx.getGlobal("Input");
    defer ctx.freeValue(input_obj);

    // Update unified input vectors
    const move = input.getMoveVector();
    ctx.setProperty(input_obj, "_moveX", ctx.newFloat(move.x)) catch {};
    ctx.setProperty(input_obj, "_moveY", ctx.newFloat(move.y)) catch {};

    const look = input.getLookVector();
    ctx.setProperty(input_obj, "_lookX", ctx.newFloat(look.x)) catch {};
    ctx.setProperty(input_obj, "_lookY", ctx.newFloat(look.y)) catch {};

    // Update action buttons
    ctx.setProperty(input_obj, "_confirmPressed", ctx.newBool(input.isConfirmPressed())) catch {};
    ctx.setProperty(input_obj, "_cancelPressed", ctx.newBool(input.isCancelPressed())) catch {};
    ctx.setProperty(input_obj, "_jumpPressed", ctx.newBool(input.isJumpPressed())) catch {};
    ctx.setProperty(input_obj, "_jumpDown", ctx.newBool(input.isJumpDown())) catch {};

    // Update mouse position
    const mouse_pos = input.getMousePosition();
    ctx.setProperty(input_obj, "_mouseX", ctx.newFloat(mouse_pos.x)) catch {};
    ctx.setProperty(input_obj, "_mouseY", ctx.newFloat(mouse_pos.y)) catch {};

    const mouse_delta = input.getMouseDelta();
    ctx.setProperty(input_obj, "_mouseDeltaX", ctx.newFloat(mouse_delta.x)) catch {};
    ctx.setProperty(input_obj, "_mouseDeltaY", ctx.newFloat(mouse_delta.y)) catch {};

    // Update common key states
    const keys_obj = ctx.newObject();
    updateKeyState(ctx, keys_obj, input, "w");
    updateKeyState(ctx, keys_obj, input, "a");
    updateKeyState(ctx, keys_obj, input, "s");
    updateKeyState(ctx, keys_obj, input, "d");
    updateKeyState(ctx, keys_obj, input, "space");
    updateKeyState(ctx, keys_obj, input, "escape");
    updateKeyState(ctx, keys_obj, input, "lshift");
    updateKeyState(ctx, keys_obj, input, "lctrl");
    updateKeyState(ctx, keys_obj, input, "e");
    updateKeyState(ctx, keys_obj, input, "q");
    updateKeyState(ctx, keys_obj, input, "f");
    updateKeyState(ctx, keys_obj, input, "r");
    ctx.setProperty(input_obj, "_keys", keys_obj) catch {};

    // Update mouse buttons
    const mouse_buttons = ctx.newObject();
    ctx.setProperty(mouse_buttons, "left", ctx.newBool(input.isMouseButtonDown(.left))) catch {};
    ctx.setProperty(mouse_buttons, "middle", ctx.newBool(input.isMouseButtonDown(.middle))) catch {};
    ctx.setProperty(mouse_buttons, "right", ctx.newBool(input.isMouseButtonDown(.right))) catch {};
    ctx.setProperty(input_obj, "_mouseButtons", mouse_buttons) catch {};

    // Update gamepad state
    const has_gamepad = input.hasGamepad();
    ctx.setProperty(input_obj, "_hasGamepad", ctx.newBool(has_gamepad)) catch {};

    if (has_gamepad) {
        if (input.getGamepad()) |gamepad| {
            const gp_obj = ctx.newObject();

            // Sticks
            const left_stick = gamepad.getLeftStick();
            const right_stick = gamepad.getRightStick();
            ctx.setProperty(gp_obj, "leftStickX", ctx.newFloat(left_stick.x)) catch {};
            ctx.setProperty(gp_obj, "leftStickY", ctx.newFloat(left_stick.y)) catch {};
            ctx.setProperty(gp_obj, "rightStickX", ctx.newFloat(right_stick.x)) catch {};
            ctx.setProperty(gp_obj, "rightStickY", ctx.newFloat(right_stick.y)) catch {};

            // Triggers
            ctx.setProperty(gp_obj, "leftTrigger", ctx.newFloat(gamepad.getLeftTrigger())) catch {};
            ctx.setProperty(gp_obj, "rightTrigger", ctx.newFloat(gamepad.getRightTrigger())) catch {};

            // Buttons - create objects for down and pressed states
            const buttons_down = ctx.newObject();
            const buttons_pressed = ctx.newObject();

            inline for (.{ "south", "east", "west", "north", "left_shoulder", "right_shoulder", "back", "start", "dpad_up", "dpad_down", "dpad_left", "dpad_right" }) |btn_name| {
                const button = @field(@import("../../input/gamepad.zig").Button, btn_name);
                ctx.setProperty(buttons_down, btn_name, ctx.newBool(gamepad.isButtonDown(button))) catch {};
                ctx.setProperty(buttons_pressed, btn_name, ctx.newBool(gamepad.isButtonJustPressed(button))) catch {};
            }

            ctx.setProperty(gp_obj, "buttonsDown", buttons_down) catch {};
            ctx.setProperty(gp_obj, "buttonsPressed", buttons_pressed) catch {};

            // Helper methods as closures (using the cached state)
            const gp_methods =
                \\(function(gp) {
                \\    gp.getLeftStick = function() { return new Vec2(this.leftStickX, this.leftStickY); };
                \\    gp.getRightStick = function() { return new Vec2(this.rightStickX, this.rightStickY); };
                \\    gp.getLeftTrigger = function() { return this.leftTrigger; };
                \\    gp.getRightTrigger = function() { return this.rightTrigger; };
                \\    gp.isButtonDown = function(btn) { return this.buttonsDown[btn] || false; };
                \\    gp.isButtonPressed = function(btn) { return this.buttonsPressed[btn] || false; };
                \\    gp.rumble = function(lowFreq, highFreq, durationMs) {
                \\        __gamepad_rumble = { low: lowFreq, high: highFreq, duration: durationMs };
                \\    };
                \\    gp.stopRumble = function() {
                \\        __gamepad_rumble = { low: 0, high: 0, duration: 0 };
                \\    };
                \\    return gp;
                \\})(Input._gamepad || {})
            ;

            ctx.setProperty(input_obj, "_gamepad", gp_obj) catch {};

            // Add methods
            const with_methods = ctx.eval(gp_methods, "<input>") catch gp_obj;
            ctx.setProperty(input_obj, "_gamepad", with_methods) catch {};
        }
    } else {
        ctx.setProperty(input_obj, "_gamepad", quickjs.NULL) catch {};
    }
}

fn updateKeyState(ctx: *JSContext, keys_obj: quickjs.Value, input: *Input, key_name: [:0]const u8) void {
    // Map key name to SDL scancode
    const scancode = keyNameToScancode(key_name) orelse return;
    ctx.setProperty(keys_obj, key_name, ctx.newBool(input.isKeyDown(scancode))) catch {};
}

fn keyNameToScancode(name: []const u8) ?Scancode {
    if (std.mem.eql(u8, name, "w")) return .w;
    if (std.mem.eql(u8, name, "a")) return .a;
    if (std.mem.eql(u8, name, "s")) return .s;
    if (std.mem.eql(u8, name, "d")) return .d;
    if (std.mem.eql(u8, name, "e")) return .e;
    if (std.mem.eql(u8, name, "q")) return .q;
    if (std.mem.eql(u8, name, "f")) return .f;
    if (std.mem.eql(u8, name, "r")) return .r;
    if (std.mem.eql(u8, name, "space")) return .space;
    if (std.mem.eql(u8, name, "escape")) return .escape;
    if (std.mem.eql(u8, name, "lshift")) return .left_shift;
    if (std.mem.eql(u8, name, "lctrl")) return .left_ctrl;
    return null;
}

/// Check if rumble was requested from JavaScript.
pub fn checkRumbleRequest(ctx: *JSContext) ?struct { low: f32, high: f32, duration: u32 } {
    const rumble_val = ctx.getGlobal("__gamepad_rumble");
    defer ctx.freeValue(rumble_val);

    if (ctx.isUndefined(rumble_val) or ctx.isNull(rumble_val)) return null;

    const low_val = ctx.getProperty(rumble_val, "low");
    const high_val = ctx.getProperty(rumble_val, "high");
    const duration_val = ctx.getProperty(rumble_val, "duration");
    defer ctx.freeValue(low_val);
    defer ctx.freeValue(high_val);
    defer ctx.freeValue(duration_val);

    const low = ctx.toFloat32(low_val) catch return null;
    const high = ctx.toFloat32(high_val) catch return null;
    const duration = ctx.toInt32(duration_val) catch return null;

    // Clear the request
    ctx.setGlobal("__gamepad_rumble", quickjs.UNDEFINED) catch {};

    return .{
        .low = low,
        .high = high,
        .duration = @intCast(@max(0, duration)),
    };
}
