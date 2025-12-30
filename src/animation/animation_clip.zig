const std = @import("std");
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const Quat = math.Quat;
const Transform = @import("../ecs/components/transform_component.zig").Transform;
const BoneIndex = @import("skeleton.zig").BoneIndex;

/// Interpolation type for keyframes (matches glTF)
pub const InterpolationType = enum {
    /// No interpolation - jump to next value
    step,
    /// Linear interpolation
    linear,
    /// Cubic spline interpolation (requires tangent data)
    cubic_spline,
};

/// A single keyframe for a Vec3 property (position, scale)
pub const Vec3Keyframe = struct {
    time: f32,
    value: Vec3,
    // Tangents for cubic spline (optional)
    in_tangent: ?Vec3 = null,
    out_tangent: ?Vec3 = null,
};

/// A single keyframe for a quaternion property (rotation)
pub const QuatKeyframe = struct {
    time: f32,
    value: Quat,
    // Tangents for cubic spline (optional)
    in_tangent: ?Quat = null,
    out_tangent: ?Quat = null,
};

/// Generic keyframe union for any transform property
pub const Keyframe = union(enum) {
    translation: Vec3Keyframe,
    rotation: QuatKeyframe,
    scale: Vec3Keyframe,
};

/// Target property being animated
pub const ChannelTarget = enum {
    translation,
    rotation,
    scale,
    // Could add: weights (morph targets) in the future
};

/// An animation channel animates a single property of a single bone
pub const AnimationChannel = struct {
    allocator: std.mem.Allocator,

    /// Which bone this channel affects
    bone_index: BoneIndex,

    /// Which property is being animated
    target: ChannelTarget,

    /// Interpolation mode
    interpolation: InterpolationType,

    /// Keyframe times (shared across all keyframe types)
    times: []f32,

    /// Keyframe values (union based on target)
    translation_values: ?[]Vec3,
    rotation_values: ?[]Quat,
    scale_values: ?[]Vec3,

    // Tangent data for cubic spline
    translation_in_tangents: ?[]Vec3,
    translation_out_tangents: ?[]Vec3,
    rotation_in_tangents: ?[]Quat,
    rotation_out_tangents: ?[]Quat,
    scale_in_tangents: ?[]Vec3,
    scale_out_tangents: ?[]Vec3,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, bone_index: BoneIndex, target: ChannelTarget, keyframe_count: usize) !Self {
        const times = try allocator.alloc(f32, keyframe_count);
        @memset(times, 0);

        var channel = Self{
            .allocator = allocator,
            .bone_index = bone_index,
            .target = target,
            .interpolation = .linear,
            .times = times,
            .translation_values = null,
            .rotation_values = null,
            .scale_values = null,
            .translation_in_tangents = null,
            .translation_out_tangents = null,
            .rotation_in_tangents = null,
            .rotation_out_tangents = null,
            .scale_in_tangents = null,
            .scale_out_tangents = null,
        };

        // Allocate appropriate value array based on target
        switch (target) {
            .translation => {
                channel.translation_values = try allocator.alloc(Vec3, keyframe_count);
            },
            .rotation => {
                channel.rotation_values = try allocator.alloc(Quat, keyframe_count);
            },
            .scale => {
                channel.scale_values = try allocator.alloc(Vec3, keyframe_count);
            },
        }

        return channel;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.times);

        if (self.translation_values) |v| self.allocator.free(v);
        if (self.rotation_values) |v| self.allocator.free(v);
        if (self.scale_values) |v| self.allocator.free(v);

        if (self.translation_in_tangents) |v| self.allocator.free(v);
        if (self.translation_out_tangents) |v| self.allocator.free(v);
        if (self.rotation_in_tangents) |v| self.allocator.free(v);
        if (self.rotation_out_tangents) |v| self.allocator.free(v);
        if (self.scale_in_tangents) |v| self.allocator.free(v);
        if (self.scale_out_tangents) |v| self.allocator.free(v);
    }

    /// Get number of keyframes
    pub fn keyframeCount(self: *const Self) usize {
        return self.times.len;
    }

    /// Find the keyframe indices that surround the given time
    /// Returns (prev_index, next_index, blend_factor)
    fn findKeyframes(self: *const Self, time: f32) struct { prev: usize, next: usize, t: f32 } {
        if (self.times.len == 0) {
            return .{ .prev = 0, .next = 0, .t = 0 };
        }

        if (self.times.len == 1 or time <= self.times[0]) {
            return .{ .prev = 0, .next = 0, .t = 0 };
        }

        const last = self.times.len - 1;
        if (time >= self.times[last]) {
            return .{ .prev = last, .next = last, .t = 0 };
        }

        // Binary search for the surrounding keyframes
        var low: usize = 0;
        var high: usize = last;

        while (low < high - 1) {
            const mid = (low + high) / 2;
            if (time < self.times[mid]) {
                high = mid;
            } else {
                low = mid;
            }
        }

        const dt = self.times[high] - self.times[low];
        const t = if (dt > 0) (time - self.times[low]) / dt else 0;

        return .{ .prev = low, .next = high, .t = t };
    }

    /// Sample the channel at the given time
    pub fn sample(self: *const Self, time: f32, out_transform: *Transform) void {
        const kf = self.findKeyframes(time);

        switch (self.target) {
            .translation => {
                const values = self.translation_values orelse return;
                out_transform.position = self.interpolateVec3(values, kf.prev, kf.next, kf.t);
            },
            .rotation => {
                const values = self.rotation_values orelse return;
                out_transform.rotation = self.interpolateQuat(values, kf.prev, kf.next, kf.t);
            },
            .scale => {
                const values = self.scale_values orelse return;
                out_transform.scale = self.interpolateVec3(values, kf.prev, kf.next, kf.t);
            },
        }
    }

    fn interpolateVec3(self: *const Self, values: []const Vec3, prev: usize, next: usize, t: f32) Vec3 {
        if (prev == next) return values[prev];

        switch (self.interpolation) {
            .step => return values[prev],
            .linear => return lerpVec3(values[prev], values[next], t),
            .cubic_spline => {
                // Hermite spline interpolation
                const in_tangents = if (self.target == .translation)
                    self.translation_in_tangents
                else
                    self.scale_in_tangents;
                const out_tangents = if (self.target == .translation)
                    self.translation_out_tangents
                else
                    self.scale_out_tangents;

                if (in_tangents != null and out_tangents != null) {
                    const dt = self.times[next] - self.times[prev];
                    return hermiteVec3(
                        values[prev],
                        out_tangents.?[prev].mul(dt),
                        values[next],
                        in_tangents.?[next].mul(dt),
                        t,
                    );
                }
                return lerpVec3(values[prev], values[next], t);
            },
        }
    }

    fn interpolateQuat(self: *const Self, values: []const Quat, prev: usize, next: usize, t: f32) Quat {
        if (prev == next) return values[prev];

        switch (self.interpolation) {
            .step => return values[prev],
            .linear => return Quat.slerp(values[prev], values[next], t),
            .cubic_spline => {
                // For quaternions, cubic spline is complex - fall back to slerp
                // A full implementation would use squad interpolation
                return Quat.slerp(values[prev], values[next], t);
            },
        }
    }
};

/// Linear interpolation for Vec3
fn lerpVec3(a: Vec3, b: Vec3, t: f32) Vec3 {
    return Vec3.init(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
    );
}

/// Hermite spline interpolation for Vec3
fn hermiteVec3(p0: Vec3, m0: Vec3, p1: Vec3, m1: Vec3, t: f32) Vec3 {
    const t2 = t * t;
    const t3 = t2 * t;

    const h00 = 2 * t3 - 3 * t2 + 1;
    const h10 = t3 - 2 * t2 + t;
    const h01 = -2 * t3 + 3 * t2;
    const h11 = t3 - t2;

    return Vec3.init(
        h00 * p0.x + h10 * m0.x + h01 * p1.x + h11 * m1.x,
        h00 * p0.y + h10 * m0.y + h01 * p1.y + h11 * m1.y,
        h00 * p0.z + h10 * m0.z + h01 * p1.z + h11 * m1.z,
    );
}

/// An animation clip containing multiple channels
pub const AnimationClip = struct {
    allocator: std.mem.Allocator,

    /// Name of the animation
    name: []const u8,

    /// Duration of the animation in seconds
    duration: f32,

    /// All channels in this animation
    channels: []AnimationChannel,

    /// Whether the animation should loop
    looping: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, name: []const u8, channel_count: usize) !Self {
        const name_copy = try allocator.dupe(u8, name);
        const channels = try allocator.alloc(AnimationChannel, channel_count);

        return .{
            .allocator = allocator,
            .name = name_copy,
            .duration = 0,
            .channels = channels,
            .looping = true,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.channels) |*channel| {
            channel.deinit();
        }
        self.allocator.free(self.channels);
        self.allocator.free(self.name);
    }

    /// Number of channels in this clip
    pub fn channelCount(self: *const Self) usize {
        return self.channels.len;
    }

    /// Sample all channels at the given time, modifying the pose transforms
    /// pose: array of transforms, indexed by bone index
    pub fn sample(self: *const Self, time: f32, pose: []Transform) void {
        // Clamp or loop time
        var sample_time = time;
        if (self.duration > 0) {
            if (self.looping) {
                sample_time = @mod(time, self.duration);
            } else {
                sample_time = @min(time, self.duration);
            }
        }

        // Sample each channel
        for (self.channels) |*channel| {
            if (channel.bone_index < pose.len) {
                channel.sample(sample_time, &pose[channel.bone_index]);
            }
        }
    }

    /// Compute duration from channel keyframes
    pub fn computeDuration(self: *Self) void {
        var max_time: f32 = 0;
        for (self.channels) |channel| {
            if (channel.times.len > 0) {
                const last_time = channel.times[channel.times.len - 1];
                if (last_time > max_time) {
                    max_time = last_time;
                }
            }
        }
        self.duration = max_time;
    }
};

test "animation channel interpolation" {
    const allocator = std.testing.allocator;

    var channel = try AnimationChannel.init(allocator, 0, .translation, 3);
    defer channel.deinit();

    // Set up keyframes: position moves from 0 to 1 to 2 over 2 seconds
    channel.times[0] = 0.0;
    channel.times[1] = 1.0;
    channel.times[2] = 2.0;
    channel.translation_values.?[0] = Vec3.init(0, 0, 0);
    channel.translation_values.?[1] = Vec3.init(1, 0, 0);
    channel.translation_values.?[2] = Vec3.init(2, 0, 0);

    var transform = Transform.init();

    // Sample at t=0.5 (halfway between 0 and 1)
    channel.sample(0.5, &transform);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), transform.position.x, 0.001);

    // Sample at t=1.5 (halfway between 1 and 2)
    channel.sample(1.5, &transform);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), transform.position.x, 0.001);
}

test "animation clip sampling" {
    const allocator = std.testing.allocator;

    var clip = try AnimationClip.init(allocator, "test", 1);
    defer clip.deinit();

    clip.channels[0] = try AnimationChannel.init(allocator, 0, .translation, 2);
    clip.channels[0].times[0] = 0.0;
    clip.channels[0].times[1] = 1.0;
    clip.channels[0].translation_values.?[0] = Vec3.zero();
    clip.channels[0].translation_values.?[1] = Vec3.init(10, 0, 0);

    clip.computeDuration();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), clip.duration, 0.001);

    var pose: [1]Transform = .{Transform.init()};
    clip.sample(0.5, &pose);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), pose[0].position.x, 0.001);
}
