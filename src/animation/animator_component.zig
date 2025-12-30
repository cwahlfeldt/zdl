const std = @import("std");
const math = @import("../math/math.zig");
const Mat4 = math.Mat4;
const Skeleton = @import("skeleton.zig").Skeleton;
const Animator = @import("animator.zig").Animator;
const AnimationClip = @import("animation_clip.zig").AnimationClip;
const PlaybackState = @import("animator.zig").PlaybackState;

/// ECS Component for animated entities
/// Wraps an Animator for use in the component system
pub const AnimatorComponent = struct {
    /// The underlying animator (owns memory)
    animator: Animator,

    /// Whether this component is enabled
    enabled: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, skeleton: *const Skeleton) !Self {
        return .{
            .animator = try Animator.init(allocator, skeleton),
            .enabled = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.animator.deinit();
    }

    /// Register an animation clip
    pub fn addClip(self: *Self, name: []const u8, clip: *const AnimationClip) !void {
        try self.animator.addClip(name, clip);
    }

    /// Play an animation by name
    pub fn play(self: *Self, name: []const u8) bool {
        return self.animator.play(name);
    }

    /// Crossfade to an animation
    pub fn crossFade(self: *Self, name: []const u8, duration: f32) bool {
        return self.animator.crossFade(name, duration);
    }

    /// Stop playback
    pub fn stop(self: *Self) void {
        self.animator.stop();
    }

    /// Pause playback
    pub fn pause(self: *Self) void {
        self.animator.pause();
    }

    /// Resume playback
    pub fn unpause(self: *Self) void {
        self.animator.unpause();
    }

    /// Check if playing
    pub fn isPlaying(self: *const Self) bool {
        return self.animator.getState() == .playing;
    }

    /// Get current playback time
    pub fn getTime(self: *const Self) f32 {
        return self.animator.getTime();
    }

    /// Set playback time
    pub fn setTime(self: *Self, time: f32) void {
        self.animator.setTime(time);
    }

    /// Set playback speed
    pub fn setSpeed(self: *Self, speed: f32) void {
        self.animator.speed = speed;
    }

    /// Get playback speed
    pub fn getSpeed(self: *const Self) f32 {
        return self.animator.speed;
    }

    /// Update the animator
    pub fn update(self: *Self, dt: f32) void {
        if (self.enabled) {
            self.animator.update(dt);
        }
    }

    /// Get skinning matrices for GPU
    pub fn getSkinningMatrices(self: *const Self) []const Mat4 {
        return self.animator.getSkinningMatrices();
    }

    /// Get the skeleton
    pub fn getSkeleton(self: *const Self) *const Skeleton {
        return self.animator.skeleton;
    }
};
