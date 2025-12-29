# Controller and Gamepad Support

## Overview

Implement comprehensive gamepad and controller support for ZDL, enabling console-style gaming experiences. This includes support for various controller types, input mapping, vibration feedback, and UI navigation.

## Current State

ZDL currently has:
- Keyboard input via SDL scancodes
- Mouse input with position and button tracking
- No gamepad/controller support
- No input action mapping system
- No haptic feedback

## Goals

- Support all major controller types (Xbox, PlayStation, Nintendo)
- Implement analog stick and trigger input
- Add haptic/vibration feedback
- Create action-based input mapping
- Support hot-plugging of controllers
- Enable UI navigation with controller
- Provide dead zone and sensitivity configuration
- Support multiple simultaneous controllers

## Architecture

### Directory Structure

```
src/
├── input/
│   ├── input.zig              # Module exports (existing)
│   ├── keyboard.zig           # Keyboard-specific (refactored)
│   ├── mouse.zig              # Mouse-specific (refactored)
│   ├── gamepad.zig            # Gamepad handling
│   ├── input_manager.zig      # Unified input manager
│   ├── input_mapping.zig      # Action mapping system
│   └── haptics.zig            # Vibration/force feedback
```

### Core Components

#### Gamepad System

```zig
pub const Gamepad = struct {
    id: sdl.GamepadId,
    name: []const u8,
    type: GamepadType,

    // State
    buttons: std.EnumSet(GamepadButton),
    buttons_pressed: std.EnumSet(GamepadButton),   // Just this frame
    buttons_released: std.EnumSet(GamepadButton),  // Just this frame

    // Analog inputs (normalized -1.0 to 1.0 or 0.0 to 1.0)
    left_stick: Vec2,
    right_stick: Vec2,
    left_trigger: f32,
    right_trigger: f32,

    // Configuration
    dead_zone_stick: f32,
    dead_zone_trigger: f32,
    stick_sensitivity: f32,

    // Haptics
    haptic_supported: bool,

    pub fn isButtonDown(self: *Gamepad, button: GamepadButton) bool;
    pub fn isButtonPressed(self: *Gamepad, button: GamepadButton) bool;
    pub fn isButtonReleased(self: *Gamepad, button: GamepadButton) bool;
    pub fn getStickWithDeadZone(self: *Gamepad, stick: Stick) Vec2;
    pub fn vibrate(self: *Gamepad, low_freq: f32, high_freq: f32, duration_ms: u32) void;
};

pub const GamepadType = enum {
    xbox,
    playstation,
    nintendo_switch,
    generic,

    pub fn fromSDL(sdl_type: sdl.GamepadType) GamepadType;
};

pub const GamepadButton = enum {
    // Face buttons
    a,          // Cross (PS), B (Nintendo)
    b,          // Circle (PS), A (Nintendo)
    x,          // Square (PS), Y (Nintendo)
    y,          // Triangle (PS), X (Nintendo)

    // Shoulders
    left_bumper,
    right_bumper,

    // Triggers (also have analog values)
    left_trigger,
    right_trigger,

    // Sticks
    left_stick,
    right_stick,

    // D-Pad
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,

    // Special
    start,      // Options (PS), Plus (Nintendo)
    back,       // Share/Create (PS), Minus (Nintendo)
    guide,      // Xbox/PS/Home button

    // Platform-specific
    touchpad,   // PS touchpad click
    misc1,      // Xbox share, PS5 mic

    pub fn fromSDL(sdl_button: sdl.GamepadButton) GamepadButton;
};

pub const Stick = enum {
    left,
    right,
};
```

#### Gamepad Manager

```zig
pub const GamepadManager = struct {
    allocator: Allocator,
    gamepads: std.AutoHashMap(sdl.GamepadId, *Gamepad),
    connected_order: std.ArrayList(sdl.GamepadId),

    // Callbacks
    on_connected: ?fn(*Gamepad) void,
    on_disconnected: ?fn(*Gamepad) void,

    pub fn init(allocator: Allocator) GamepadManager;
    pub fn deinit(self: *GamepadManager) void;

    pub fn update(self: *GamepadManager) void;
    pub fn handleEvent(self: *GamepadManager, event: sdl.Event) void;

    // Access
    pub fn getGamepad(self: *GamepadManager, index: usize) ?*Gamepad;
    pub fn getGamepadById(self: *GamepadManager, id: sdl.GamepadId) ?*Gamepad;
    pub fn getConnectedCount(self: *GamepadManager) usize;
    pub fn getPrimaryGamepad(self: *GamepadManager) ?*Gamepad;

    // Hot-plug handling
    fn onDeviceAdded(self: *GamepadManager, device_id: i32) void;
    fn onDeviceRemoved(self: *GamepadManager, instance_id: sdl.GamepadId) void;
};
```

### Input Action Mapping

Abstraction layer for binding inputs to game actions:

```zig
pub const InputMapping = struct {
    allocator: Allocator,
    actions: std.StringHashMap(InputAction),
    contexts: std.StringHashMap(*InputContext),
    active_context: ?*InputContext,

    pub fn init(allocator: Allocator) InputMapping;

    // Action registration
    pub fn registerAction(self: *InputMapping, name: []const u8, action: InputAction) !void;
    pub fn createContext(self: *InputMapping, name: []const u8) !*InputContext;
    pub fn setActiveContext(self: *InputMapping, name: []const u8) void;

    // Query
    pub fn isActionActive(self: *InputMapping, name: []const u8) bool;
    pub fn getActionValue(self: *InputMapping, name: []const u8) f32;
    pub fn getActionVector(self: *InputMapping, name: []const u8) Vec2;
};

pub const InputAction = struct {
    name: []const u8,
    bindings: std.ArrayList(InputBinding),
    value: f32,
    active: bool,
    just_activated: bool,
    just_deactivated: bool,
};

pub const InputBinding = union(enum) {
    keyboard: KeyboardBinding,
    mouse: MouseBinding,
    gamepad: GamepadBinding,
};

pub const KeyboardBinding = struct {
    key: sdl.Scancode,
    modifiers: KeyModifiers,
};

pub const MouseBinding = struct {
    button: MouseButton,
};

pub const GamepadBinding = struct {
    input: GamepadInput,
    player_index: ?u8,  // null = any player

    pub const GamepadInput = union(enum) {
        button: GamepadButton,
        axis: struct {
            axis: GamepadAxis,
            direction: AxisDirection,
        },
        trigger: struct {
            trigger: Trigger,
            threshold: f32,
        },
    };
};

pub const GamepadAxis = enum {
    left_stick_x,
    left_stick_y,
    right_stick_x,
    right_stick_y,
};

pub const Trigger = enum {
    left,
    right,
};

pub const AxisDirection = enum {
    positive,
    negative,
    both,
};
```

#### Input Context

Group actions for different game states:

```zig
pub const InputContext = struct {
    name: []const u8,
    actions: std.ArrayList([]const u8),
    enabled: bool,
    consume_input: bool,  // Prevent lower contexts from receiving

    pub fn addAction(self: *InputContext, action_name: []const u8) !void;
    pub fn removeAction(self: *InputContext, action_name: []const u8) void;
};

// Example contexts
pub const DefaultContexts = struct {
    pub const gameplay = "gameplay";
    pub const ui_navigation = "ui_navigation";
    pub const vehicle = "vehicle";
    pub const menu = "menu";
};
```

### Haptic Feedback

```zig
pub const HapticEffect = struct {
    low_frequency: f32,   // 0.0 to 1.0 (rumble motor)
    high_frequency: f32,  // 0.0 to 1.0 (vibration motor)
    duration_ms: u32,
};

pub const HapticPresets = struct {
    pub const light_tap = HapticEffect{ .low_frequency = 0.2, .high_frequency = 0.1, .duration_ms = 50 };
    pub const medium_impact = HapticEffect{ .low_frequency = 0.5, .high_frequency = 0.3, .duration_ms = 100 };
    pub const heavy_impact = HapticEffect{ .low_frequency = 1.0, .high_frequency = 0.5, .duration_ms = 200 };
    pub const explosion = HapticEffect{ .low_frequency = 1.0, .high_frequency = 1.0, .duration_ms = 300 };
    pub const heartbeat = HapticEffect{ .low_frequency = 0.8, .high_frequency = 0.0, .duration_ms = 150 };
    pub const engine_idle = HapticEffect{ .low_frequency = 0.3, .high_frequency = 0.1, .duration_ms = 0 };  // Continuous
};

pub const HapticManager = struct {
    // Continuous effects (loop until stopped)
    active_effects: std.AutoHashMap(sdl.GamepadId, ActiveEffect),

    pub fn playEffect(self: *HapticManager, gamepad: *Gamepad, effect: HapticEffect) void;
    pub fn startContinuous(self: *HapticManager, gamepad: *Gamepad, effect: HapticEffect) void;
    pub fn stopContinuous(self: *HapticManager, gamepad: *Gamepad) void;
    pub fn stopAll(self: *HapticManager) void;
};
```

### Unified Input Manager

```zig
pub const InputManager = struct {
    allocator: Allocator,

    // Subsystems
    keyboard: *Keyboard,
    mouse: *Mouse,
    gamepads: *GamepadManager,
    mapping: *InputMapping,
    haptics: *HapticManager,

    // State
    any_key_pressed: bool,
    any_button_pressed: bool,
    last_input_device: InputDevice,

    pub fn init(allocator: Allocator) !InputManager;
    pub fn deinit(self: *InputManager) void;

    pub fn update(self: *InputManager) void;
    pub fn handleEvent(self: *InputManager, event: sdl.Event) void;

    // Unified queries
    pub fn isActionActive(self: *InputManager, action: []const u8) bool;
    pub fn getActionValue(self: *InputManager, action: []const u8) f32;
    pub fn getMoveVector(self: *InputManager) Vec2;  // WASD/Left stick
    pub fn getLookVector(self: *InputManager) Vec2;  // Mouse/Right stick

    // Device detection
    pub fn getLastInputDevice(self: *InputManager) InputDevice;
    pub fn isUsingGamepad(self: *InputManager) bool;
};

pub const InputDevice = enum {
    keyboard_mouse,
    gamepad,
};
```

## Usage Examples

### Basic Gamepad Usage

```zig
pub fn update(engine: *Engine, scene: *Scene, input: *InputManager, dt: f32) !void {
    if (input.gamepads.getPrimaryGamepad()) |gamepad| {
        // Movement with left stick
        const move = gamepad.getStickWithDeadZone(.left);
        player.velocity.x = move.x * player.speed;
        player.velocity.z = move.y * player.speed;

        // Camera with right stick
        const look = gamepad.getStickWithDeadZone(.right);
        camera.yaw += look.x * camera.sensitivity * dt;
        camera.pitch += look.y * camera.sensitivity * dt;

        // Jump with A button
        if (gamepad.isButtonPressed(.a) and player.on_ground) {
            player.velocity.y = player.jump_force;
            gamepad.vibrate(0.3, 0.1, 100);
        }

        // Sprint with left trigger
        const sprint = gamepad.left_trigger;
        player.speed_multiplier = 1.0 + sprint * 0.5;
    }
}
```

### Action Mapping Setup

```zig
pub fn setupInputMappings(mapping: *InputMapping) !void {
    // Movement action with multiple bindings
    var move_forward = InputAction{ .name = "move_forward", .bindings = .{} };
    try move_forward.bindings.append(.{ .keyboard = .{ .key = .w, .modifiers = .{} } });
    try move_forward.bindings.append(.{ .gamepad = .{
        .input = .{ .axis = .{ .axis = .left_stick_y, .direction = .negative } },
        .player_index = null,
    } });
    try mapping.registerAction("move_forward", move_forward);

    // Jump action
    var jump = InputAction{ .name = "jump", .bindings = .{} };
    try jump.bindings.append(.{ .keyboard = .{ .key = .space, .modifiers = .{} } });
    try jump.bindings.append(.{ .gamepad = .{ .input = .{ .button = .a }, .player_index = null } });
    try mapping.registerAction("jump", jump);

    // Create gameplay context
    var gameplay = try mapping.createContext("gameplay");
    try gameplay.addAction("move_forward");
    try gameplay.addAction("jump");
    // ... more actions

    mapping.setActiveContext("gameplay");
}

// In game update
pub fn update(input: *InputManager, dt: f32) void {
    // Works with keyboard OR gamepad automatically
    if (input.isActionActive("move_forward")) {
        const value = input.getActionValue("move_forward");
        player.move_forward(value * dt);
    }

    if (input.mapping.getAction("jump").?.just_activated) {
        player.jump();
    }
}
```

### UI Navigation with Gamepad

```zig
pub const UINavigator = struct {
    selected_index: usize,
    widgets: []*Widget,
    repeat_delay: f32,
    repeat_timer: f32,

    pub fn update(self: *UINavigator, input: *InputManager, dt: f32) void {
        const gamepad = input.gamepads.getPrimaryGamepad() orelse return;

        // D-pad navigation
        var move_y: i32 = 0;
        if (gamepad.isButtonPressed(.dpad_up)) move_y = -1;
        if (gamepad.isButtonPressed(.dpad_down)) move_y = 1;

        // Left stick navigation with repeat
        const stick = gamepad.getStickWithDeadZone(.left);
        if (@abs(stick.y) > 0.5) {
            self.repeat_timer += dt;
            if (self.repeat_timer >= self.repeat_delay) {
                move_y = if (stick.y > 0) 1 else -1;
                self.repeat_timer = 0;
            }
        } else {
            self.repeat_timer = self.repeat_delay;  // Ready for immediate input
        }

        // Apply navigation
        if (move_y != 0) {
            self.selected_index = @intCast(@mod(
                @as(i64, @intCast(self.selected_index)) + move_y,
                @as(i64, @intCast(self.widgets.len))
            ));
            gamepad.vibrate(0.1, 0.05, 30);  // Navigation feedback
        }

        // Confirm with A
        if (gamepad.isButtonPressed(.a)) {
            self.widgets[self.selected_index].activate();
            gamepad.vibrate(0.3, 0.1, 50);
        }

        // Back with B
        if (gamepad.isButtonPressed(.b)) {
            self.goBack();
        }
    }
};
```

## Implementation Steps

### Phase 1: Basic Gamepad Support
1. Enumerate connected gamepads via SDL3
2. Read button states from gamepad
3. Read analog stick values
4. Handle hot-plug events (connect/disconnect)

### Phase 2: Input Processing
1. Implement dead zones for sticks
2. Add trigger threshold detection
3. Track just-pressed/released states
4. Normalize all values consistently

### Phase 3: Haptic Feedback
1. Query haptic capabilities per device
2. Implement basic rumble (low/high frequency)
3. Create preset effects
4. Support continuous vibration

### Phase 4: Action Mapping
1. Create input action registration system
2. Implement binding evaluation
3. Add input contexts for game states
4. Support rebinding at runtime

### Phase 5: Unified Input Manager
1. Combine keyboard/mouse/gamepad systems
2. Implement device-agnostic queries
3. Track last active input device
4. Auto-switch prompts based on device

### Phase 6: UI Integration
1. Create UI navigation system
2. Implement focus management
3. Add navigation sounds/haptics
4. Support both D-pad and stick navigation

## Platform Considerations

### Controller Types
- **Xbox**: Most straightforward, SDL default mapping
- **PlayStation**: Different button names, touchpad, adaptive triggers (PS5)
- **Nintendo Switch**: Inverted A/B and X/Y positions
- **Generic**: May need manual mapping

### Platform-Specific Features
- **PS5 Adaptive Triggers**: Resistance/vibration in triggers
- **PS5 Touchpad**: Track position and gestures
- **Xbox Elite**: Paddles and extra buttons
- **Switch**: Gyro aiming, HD Rumble

```zig
pub const AdvancedFeatures = struct {
    // PS5 adaptive triggers
    pub fn setTriggerEffect(gamepad: *Gamepad, trigger: Trigger, effect: TriggerEffect) void;

    pub const TriggerEffect = union(enum) {
        off,
        feedback: struct { position: u8, strength: u8 },
        weapon: struct { start: u8, end: u8, strength: u8 },
        vibration: struct { position: u8, amplitude: u8, frequency: u8 },
    };

    // Gyro input (Switch, PS4/5)
    pub fn getGyro(gamepad: *Gamepad) ?GyroState;

    pub const GyroState = struct {
        pitch: f32,
        yaw: f32,
        roll: f32,
    };
};
```

## Configuration & Persistence

```zig
pub const InputConfig = struct {
    // Per-player settings
    stick_dead_zone: f32 = 0.15,
    trigger_dead_zone: f32 = 0.1,
    stick_sensitivity: f32 = 1.0,
    invert_y: bool = false,
    vibration_enabled: bool = true,
    vibration_intensity: f32 = 1.0,

    // Action bindings (serializable)
    bindings: std.StringHashMap([]InputBinding),

    pub fn save(self: *InputConfig, path: []const u8) !void;
    pub fn load(allocator: Allocator, path: []const u8) !InputConfig;
    pub fn resetToDefaults(self: *InputConfig) void;
};
```

## Integration with Existing Systems

### Engine Integration

```zig
// In Engine
pub const Engine = struct {
    input: *InputManager,  // Replaces separate keyboard/mouse

    pub fn init(allocator: Allocator, config: EngineConfig) !Engine {
        // ...
        self.input = try InputManager.init(allocator);
        // ...
    }
};

// Update callback signature change
pub const UpdateFn = fn(*Engine, *Scene, *InputManager, f32) anyerror!void;
```

### Component Integration

```zig
// PlayerController uses InputManager
pub const PlayerController = struct {
    player_index: u8,

    pub fn update(self: *PlayerController, input: *InputManager, transform: *TransformComponent, dt: f32) void {
        // Automatically uses keyboard or assigned gamepad
        const move = input.getMoveVector();
        transform.translate(Vec3.init(move.x, 0, move.y).scale(speed * dt));
    }
};
```

## References

- [SDL3 Gamepad API](https://wiki.libsdl.org/SDL3/CategoryGamepad)
- [Steam Input](https://partner.steamgames.com/doc/features/steam_controller) - Action-based input system inspiration
- [XInput Programming Guide](https://docs.microsoft.com/en-us/windows/win32/xinput/programming-guide)
- [DualSense Features](https://www.playstation.com/en-us/accessories/dualsense-wireless-controller/) - Advanced haptics reference
