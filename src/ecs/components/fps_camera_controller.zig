const std = @import("std");
const math = @import("../../math/math.zig");
const Vec3 = math.Vec3;
const Quat = math.Quat;
const Input = @import("../../input/input.zig").Input;
const TransformComponent = @import("transform_component.zig").TransformComponent;

/// FPS-style camera controller component.
/// Handles mouse look and WASD movement for first-person camera control.
/// Requires the entity to also have a TransformComponent and CameraComponent.
pub const FpsCameraController = struct {
    /// Yaw angle (rotation around Y axis) in radians
    yaw: f32,
    /// Pitch angle (rotation around X axis) in radians
    pitch: f32,
    /// Mouse look sensitivity
    sensitivity: f32,
    /// Movement speed in units per second
    move_speed: f32,
    /// Whether to capture mouse on left click
    capture_on_click: bool,

    pub const Config = struct {
        initial_yaw: f32 = 0,
        initial_pitch: f32 = 0,
        sensitivity: f32 = 0.003,
        move_speed: f32 = 5.0,
        capture_on_click: bool = true,
    };

    /// Create an FPS camera controller with default settings.
    pub fn init() FpsCameraController {
        return initWithConfig(.{});
    }

    /// Create an FPS camera controller with custom settings.
    pub fn initWithConfig(config: Config) FpsCameraController {
        return .{
            .yaw = config.initial_yaw,
            .pitch = config.initial_pitch,
            .sensitivity = config.sensitivity,
            .move_speed = config.move_speed,
            .capture_on_click = config.capture_on_click,
        };
    }

    /// Update the camera controller. Call this every frame.
    /// Returns true if mouse capture state should be toggled on.
    pub fn update(
        self: *FpsCameraController,
        transform: *TransformComponent,
        input: *Input,
        delta_time: f32,
    ) bool {
        var should_capture = false;

        // Click to capture mouse
        if (self.capture_on_click and input.isMouseButtonDown(.left) and !input.mouse_captured) {
            should_capture = true;
        }

        // Mouse look (only when captured)
        if (input.mouse_captured) {
            const mouse_delta = input.getMouseDelta();

            self.yaw -= mouse_delta.x * self.sensitivity;
            self.pitch -= mouse_delta.y * self.sensitivity;

            // Clamp pitch to avoid gimbal lock
            const max_pitch = std.math.pi / 2.0 - 0.1;
            self.pitch = @max(-max_pitch, @min(max_pitch, self.pitch));
        }

        // Update camera rotation from yaw/pitch
        const yaw_quat = Quat.fromAxisAngle(Vec3.init(0, 1, 0), self.yaw);
        const pitch_quat = Quat.fromAxisAngle(Vec3.init(1, 0, 0), self.pitch);
        transform.local.rotation = yaw_quat.mul(pitch_quat);

        // Calculate forward and right vectors from camera rotation
        const cam_rotation = transform.local.rotation;
        const forward = cam_rotation.rotateVec3(Vec3.init(0, 0, -1));
        const right_dir = cam_rotation.rotateVec3(Vec3.init(1, 0, 0));

        // WASD movement relative to camera direction
        const wasd = input.getWASD();

        if (wasd.x != 0 or wasd.y != 0) {
            const move_forward = forward.mul(-wasd.y * self.move_speed * delta_time);
            const move_right = right_dir.mul(wasd.x * self.move_speed * delta_time);
            transform.translate(move_forward.add(move_right));
        }

        // Up/down movement with Space/Shift
        if (input.isKeyDown(.space)) {
            transform.translate(Vec3.init(0, self.move_speed * delta_time, 0));
        }
        if (input.isKeyDown(.left_shift) or input.isKeyDown(.right_shift)) {
            transform.translate(Vec3.init(0, -self.move_speed * delta_time, 0));
        }

        transform.markDirty();

        return should_capture;
    }

    /// Set yaw and pitch from a direction vector (useful for initialization).
    pub fn lookAt(self: *FpsCameraController, direction: Vec3) void {
        // Calculate yaw from XZ plane
        self.yaw = std.math.atan2(direction.x, -direction.z);
        // Calculate pitch from Y component
        const horizontal_len = @sqrt(direction.x * direction.x + direction.z * direction.z);
        self.pitch = std.math.atan2(-direction.y, horizontal_len);
    }

    /// Get the forward direction vector based on current yaw/pitch.
    pub fn getForward(self: FpsCameraController) Vec3 {
        const yaw_quat = Quat.fromAxisAngle(Vec3.init(0, 1, 0), self.yaw);
        const pitch_quat = Quat.fromAxisAngle(Vec3.init(1, 0, 0), self.pitch);
        const rotation = yaw_quat.mul(pitch_quat);
        return rotation.rotateVec3(Vec3.init(0, 0, -1));
    }
};
