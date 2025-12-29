# Mobile Platform Support

## Overview

Extend ZDL to support iOS and Android platforms, enabling games to target smartphones and tablets. This involves adapting rendering for mobile GPUs, implementing touch input, handling platform-specific lifecycle events, and optimizing for battery and thermal constraints.

## Current State

ZDL currently supports:

- **Linux**: Vulkan via SDL3
- **macOS**: Metal via SDL3
- No mobile platform support
- No touch input handling
- No mobile GPU optimizations

## Goals

- Support iOS (iPhone, iPad) via Metal
- Support Android via Vulkan
- Implement multi-touch input system
- Handle mobile app lifecycle (pause, resume, background)
- Optimize rendering for mobile GPUs (tile-based)
- Support screen orientation changes
- Handle varying screen sizes and pixel densities
- Integrate with platform app stores
- Support mobile-specific features (haptics, gyroscope)

## Platform Requirements

### iOS

- **Minimum**: iOS 14+ (Metal 2)
- **Devices**: iPhone 8+, iPad 6th gen+
- **Graphics**: Metal
- **Build**: Xcode, Apple Developer account
- **Distribution**: App Store, TestFlight

### Android

- **Minimum**: Android 8.0+ (API 26)
- **Graphics**: Vulkan 1.4
- **Build**: Android NDK, Gradle
- **Distribution**: Google Play, APK sideload

## Architecture

### Directory Structure

```
src/
├── platform/
│   ├── platform.zig           # Platform abstraction
│   ├── desktop.zig            # Windows/Linux/macOS
│   ├── ios/
│   │   ├── ios.zig            # iOS-specific code
│   │   ├── app_delegate.m     # Objective-C bridge
│   │   └── metal_view.m       # Metal rendering view
│   └── android/
│       ├── android.zig        # Android-specific code
│       ├── native_activity.zig
│       └── jni_bridge.zig     # JNI utilities
│
├── input/
│   └── touch.zig              # Touch input handling
│
├── rendering/
│   └── mobile_renderer.zig    # Mobile GPU optimizations
│
└── build/
    ├── ios/
    │   ├── Info.plist
    │   └── project.pbxproj
    └── android/
        ├── AndroidManifest.xml
        ├── build.gradle
        └── CMakeLists.txt
```

### Platform Abstraction Layer

```zig
pub const Platform = struct {
    backend: PlatformBackend,

    pub const PlatformBackend = union(enum) {
        desktop: DesktopPlatform,
        ios: iOSPlatform,
        android: AndroidPlatform,
    };

    // Unified interface
    pub fn getScreenSize(self: *Platform) Size;
    pub fn getPixelDensity(self: *Platform) f32;
    pub fn getOrientation(self: *Platform) Orientation;
    pub fn getSafeAreaInsets(self: *Platform) Insets;
    pub fn getBatteryLevel(self: *Platform) ?f32;
    pub fn getThermalState(self: *Platform) ThermalState;
    pub fn vibrate(self: *Platform, pattern: VibratePattern) void;
    pub fn showKeyboard(self: *Platform) void;
    pub fn hideKeyboard(self: *Platform) void;
};

pub const Orientation = enum {
    portrait,
    portrait_upside_down,
    landscape_left,
    landscape_right,
};

pub const ThermalState = enum {
    nominal,
    fair,
    serious,
    critical,
};

pub const VibratePattern = union(enum) {
    single: u32,             // Duration in ms
    pattern: []const u32,    // On/off pattern
    impact: ImpactStyle,
    selection,
    notification: NotificationType,
};
```

### Touch Input System

```zig
pub const TouchInput = struct {
    touches: std.AutoHashMap(TouchId, Touch),
    gestures: GestureRecognizer,

    pub fn update(self: *TouchInput) void;
    pub fn handleEvent(self: *TouchInput, event: TouchEvent) void;

    // Queries
    pub fn getTouchCount(self: *TouchInput) usize;
    pub fn getTouch(self: *TouchInput, index: usize) ?*Touch;
    pub fn getTouchById(self: *TouchInput, id: TouchId) ?*Touch;
    pub fn getPrimaryTouch(self: *TouchInput) ?*Touch;
};

pub const TouchId = u64;

pub const Touch = struct {
    id: TouchId,
    position: Vec2,
    previous_position: Vec2,
    start_position: Vec2,
    phase: TouchPhase,
    pressure: f32,           // 0.0 to 1.0 (if supported)
    radius: f32,             // Touch radius (if supported)
    timestamp: i64,

    pub fn delta(self: *Touch) Vec2;
    pub fn totalDelta(self: *Touch) Vec2;
    pub fn velocity(self: *Touch) Vec2;
    pub fn duration(self: *Touch) f32;
};

pub const TouchPhase = enum {
    began,
    moved,
    stationary,
    ended,
    cancelled,
};

pub const TouchEvent = struct {
    id: TouchId,
    phase: TouchPhase,
    position: Vec2,
    pressure: f32,
    timestamp: i64,
};
```

### Gesture Recognition

```zig
pub const GestureRecognizer = struct {
    tap_recognizer: TapRecognizer,
    pan_recognizer: PanRecognizer,
    pinch_recognizer: PinchRecognizer,
    rotation_recognizer: RotationRecognizer,
    swipe_recognizer: SwipeRecognizer,
    long_press_recognizer: LongPressRecognizer,

    // Callbacks
    on_tap: ?fn(TapGesture) void,
    on_pan: ?fn(PanGesture) void,
    on_pinch: ?fn(PinchGesture) void,
    on_rotation: ?fn(RotationGesture) void,
    on_swipe: ?fn(SwipeGesture) void,
    on_long_press: ?fn(LongPressGesture) void,

    pub fn update(self: *GestureRecognizer, touches: *TouchInput) void;
};

pub const TapGesture = struct {
    position: Vec2,
    tap_count: u32,      // Single, double, triple tap
};

pub const PanGesture = struct {
    position: Vec2,
    translation: Vec2,
    velocity: Vec2,
    state: GestureState,
};

pub const PinchGesture = struct {
    center: Vec2,
    scale: f32,          // Relative to start (1.0 = no change)
    velocity: f32,       // Scale change per second
    state: GestureState,
};

pub const RotationGesture = struct {
    center: Vec2,
    rotation: f32,       // Radians
    velocity: f32,       // Radians per second
    state: GestureState,
};

pub const SwipeGesture = struct {
    direction: SwipeDirection,
    velocity: Vec2,
};

pub const SwipeDirection = enum {
    up,
    down,
    left,
    right,
};

pub const GestureState = enum {
    possible,
    began,
    changed,
    ended,
    cancelled,
    failed,
};
```

### Mobile Renderer Optimizations

```zig
pub const MobileRenderer = struct {
    // Tile-based rendering optimizations
    use_transient_attachments: bool,
    use_memoryless_attachments: bool,
    use_programmable_blending: bool,

    // Resolution scaling
    render_scale: f32,          // 0.5 to 1.0
    dynamic_resolution: bool,
    target_frame_time: f32,

    // Quality presets
    quality_level: QualityLevel,

    pub fn init(device: *Device, config: MobileConfig) !MobileRenderer;
    pub fn beginFrame(self: *MobileRenderer, frame: *RenderFrame) void;
    pub fn endFrame(self: *MobileRenderer, frame: *RenderFrame) void;
    pub fn adjustQuality(self: *MobileRenderer, frame_time: f32) void;
};

pub const MobileConfig = struct {
    prefer_low_power: bool,
    max_fps: u32,
    enable_dynamic_resolution: bool,
    min_render_scale: f32,
};

pub const QualityLevel = enum {
    low,
    medium,
    high,
    ultra,

    pub fn getSettings(self: QualityLevel) QualitySettings;
};

pub const QualitySettings = struct {
    shadow_resolution: u32,
    shadow_cascades: u32,
    texture_quality: f32,      // Mip bias
    post_processing: bool,
    ssao_enabled: bool,
    bloom_enabled: bool,
    max_point_lights: u32,
    draw_distance: f32,
};
```

### App Lifecycle

```zig
pub const AppLifecycle = struct {
    state: AppState,
    on_state_change: ?fn(AppState, AppState) void,

    // Platform callbacks (called from native side)
    pub fn onActivate(self: *AppLifecycle) void;
    pub fn onDeactivate(self: *AppLifecycle) void;
    pub fn onEnterBackground(self: *AppLifecycle) void;
    pub fn onEnterForeground(self: *AppLifecycle) void;
    pub fn onTerminate(self: *AppLifecycle) void;
    pub fn onLowMemory(self: *AppLifecycle) void;

    // For game to check
    pub fn shouldPause(self: *AppLifecycle) bool;
    pub fn shouldRender(self: *AppLifecycle) bool;
};

pub const AppState = enum {
    active,           // Foreground, running normally
    inactive,         // Foreground but interrupted (notification, phone call)
    background,       // In background, should pause
    suspended,        // About to be terminated
};
```

### iOS-Specific

```zig
pub const iOSPlatform = struct {
    window: *anyopaque,        // UIWindow
    view: *anyopaque,          // MTKView
    device: *anyopaque,        // MTLDevice
    view_controller: *anyopaque,

    // iOS-specific features
    pub fn getSafeAreaInsets(self: *iOSPlatform) Insets;
    pub fn getStatusBarHeight(self: *iOSPlatform) f32;
    pub fn setStatusBarHidden(self: *iOSPlatform, hidden: bool) void;
    pub fn setHomeIndicatorHidden(self: *iOSPlatform, hidden: bool) void;
    pub fn requestReview(self: *iOSPlatform) void;  // App Store review prompt
    pub fn openURL(self: *iOSPlatform, url: []const u8) void;

    // Haptic feedback
    pub fn hapticImpact(self: *iOSPlatform, style: ImpactStyle) void;
    pub fn hapticSelection(self: *iOSPlatform) void;
    pub fn hapticNotification(self: *iOSPlatform, type: NotificationType) void;
};

pub const ImpactStyle = enum {
    light,
    medium,
    heavy,
    soft,
    rigid,
};

pub const NotificationType = enum {
    success,
    warning,
    error,
};
```

### Android-Specific

```zig
pub const AndroidPlatform = struct {
    activity: *anyopaque,      // ANativeActivity
    window: *anyopaque,        // ANativeWindow
    jvm: *anyopaque,           // JavaVM
    env: *anyopaque,           // JNIEnv

    // Android-specific features
    pub fn getDisplayCutout(self: *AndroidPlatform) ?Rect;
    pub fn setImmersiveMode(self: *AndroidPlatform, enabled: bool) void;
    pub fn showToast(self: *AndroidPlatform, message: []const u8) void;
    pub fn getExternalStoragePath(self: *AndroidPlatform) []const u8;
    pub fn checkPermission(self: *AndroidPlatform, permission: Permission) bool;
    pub fn requestPermission(self: *AndroidPlatform, permission: Permission) void;

    // Vibration
    pub fn vibrate(self: *AndroidPlatform, duration_ms: u32) void;
    pub fn vibratePattern(self: *AndroidPlatform, pattern: []const u32) void;
};

pub const Permission = enum {
    write_external_storage,
    camera,
    microphone,
    vibrate,
};
```

## Build System Integration

### iOS Build (build.zig additions)

```zig
pub fn build(b: *std.Build) void {
    // ... existing build ...

    // iOS target
    const ios_target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .ios,
    });

    const ios_exe = b.addStaticLibrary(.{
        .name = "zdl_game",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = ios_target,
        .optimize = optimize,
    });

    // iOS needs static library linked into Xcode project
    const ios_install = b.addInstallArtifact(ios_exe);
    b.step("ios", "Build for iOS").dependOn(&ios_install.step);
}
```

### Android Build (build.zig additions)

```zig
pub fn build(b: *std.Build) void {
    // Android targets (multiple ABIs)
    const android_targets = [_]std.Target.Query{
        .{ .cpu_arch = .aarch64, .os_tag = .android },
        .{ .cpu_arch = .x86_64, .os_tag = .android },  // Emulator
    };

    for (android_targets) |target_query| {
        const target = b.resolveTargetQuery(target_query);
        const lib = b.addSharedLibrary(.{
            .name = "zdl_game",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        lib.linkSystemLibrary("android");
        lib.linkSystemLibrary("log");

        const install = b.addInstallArtifact(lib);
        b.step("android", "Build for Android").dependOn(&install.step);
    }
}
```

## Implementation Steps

### Phase 1: Platform Abstraction

1. Create platform abstraction layer
2. Refactor engine to use platform interface
3. Move desktop-specific code to platform module
4. Abstract window/surface creation

### Phase 2: iOS Support

1. Create Xcode project template
2. Implement Metal view integration
3. Handle iOS lifecycle callbacks
4. Test basic rendering on iOS simulator

### Phase 3: Android Support

1. Create Android project template
2. Implement NativeActivity integration
3. Handle Android lifecycle callbacks
4. Test basic rendering on Android emulator

### Phase 4: Touch Input

1. Implement touch event handling
2. Create gesture recognizers
3. Integrate with existing input system
4. Support multi-touch scenarios

### Phase 5: Mobile Optimizations

1. Implement tile-based rendering hints
2. Add dynamic resolution scaling
3. Create quality presets
4. Optimize shaders for mobile GPUs

### Phase 6: Platform Features

1. Add haptic feedback support
2. Implement orientation handling
3. Handle safe areas and notches
4. Support screen keyboard

### Phase 7: Distribution

1. Create App Store submission workflow
2. Create Play Store submission workflow
3. Implement in-app purchase hooks
4. Add analytics integration points

## Performance Guidelines

### Memory

- Budget: ~200MB total on older devices
- Use streaming for large assets
- Implement texture compression (ASTC/ETC2)
- Pool allocations, avoid runtime allocations

### GPU

- Target 30-60 FPS depending on game type
- Use lower resolution rendering with upscaling
- Minimize overdraw (tile-based GPUs)
- Reduce shader complexity
- Batch draw calls aggressively

### Battery

- Implement frame rate limiting
- Pause rendering when inactive
- Use efficient compute (avoid polling)
- Reduce CPU wake-ups

### Thermal

- Monitor thermal state
- Reduce quality dynamically when hot
- Avoid sustained high GPU usage

## Testing Strategy

### Devices to Test

- **iOS**: iPhone SE (low-end), iPhone 12 (mid), iPhone 14 Pro (high)
- **Android**: Pixel 4a (mid), Samsung Galaxy S21 (high), budget device

### Test Cases

1. Basic rendering and interaction
2. Orientation changes
3. App backgrounding and resuming
4. Multi-touch gestures
5. Performance under thermal throttling
6. Memory pressure handling
7. Different screen sizes/densities

## References

- [SDL3 iOS/Android Support](https://wiki.libsdl.org/SDL3/README/ios)
- [Metal Best Practices](https://developer.apple.com/documentation/metal/metal_best_practices_guide)
- [Vulkan Mobile Best Practices](https://arm-software.github.io/vulkan_best_practice_for_mobile_developers/)
- [Android Game Development](https://developer.android.com/games)
- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
