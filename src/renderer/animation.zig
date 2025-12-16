const std = @import("std");

/// A single frame in an animation
pub const AnimationFrame = struct {
    /// UV coordinates for this frame (left, top, right, bottom)
    uv_left: f32,
    uv_top: f32,
    uv_right: f32,
    uv_bottom: f32,
    /// Duration in seconds
    duration: f32,
};

/// Animation data for sprite sheet animations
pub const Animation = struct {
    frames: []const AnimationFrame,
    loop: bool,

    /// Create an animation from a sprite sheet grid
    /// frame_width and frame_height are in pixels
    /// texture_width and texture_height are the full texture dimensions
    /// frame_count is how many frames to include
    /// frames_per_row is how many frames fit in one row
    pub fn fromGrid(
        allocator: std.mem.Allocator,
        frame_width: u32,
        frame_height: u32,
        texture_width: u32,
        texture_height: u32,
        frame_count: u32,
        frames_per_row: u32,
        frame_duration: f32,
        loop: bool,
    ) !Animation {
        const frames = try allocator.alloc(AnimationFrame, frame_count);

        const frame_w_uv = @as(f32, @floatFromInt(frame_width)) / @as(f32, @floatFromInt(texture_width));
        const frame_h_uv = @as(f32, @floatFromInt(frame_height)) / @as(f32, @floatFromInt(texture_height));

        for (frames, 0..) |*frame, i| {
            const row = i / frames_per_row;
            const col = i % frames_per_row;

            const uv_left = @as(f32, @floatFromInt(col)) * frame_w_uv;
            const uv_top = @as(f32, @floatFromInt(row)) * frame_h_uv;

            frame.* = .{
                .uv_left = uv_left,
                .uv_top = uv_top,
                .uv_right = uv_left + frame_w_uv,
                .uv_bottom = uv_top + frame_h_uv,
                .duration = frame_duration,
            };
        }

        return .{
            .frames = frames,
            .loop = loop,
        };
    }

    /// Create a single-frame animation (for static sprites)
    pub fn single(
        allocator: std.mem.Allocator,
        uv_left: f32,
        uv_top: f32,
        uv_right: f32,
        uv_bottom: f32,
    ) !Animation {
        const frames = try allocator.alloc(AnimationFrame, 1);
        frames[0] = .{
            .uv_left = uv_left,
            .uv_top = uv_top,
            .uv_right = uv_right,
            .uv_bottom = uv_bottom,
            .duration = 1.0,
        };

        return .{
            .frames = frames,
            .loop = true,
        };
    }

    /// Create a full-texture animation (UV 0,0 to 1,1)
    pub fn fullTexture(allocator: std.mem.Allocator) !Animation {
        return try single(allocator, 0, 0, 1, 1);
    }

    pub fn deinit(self: Animation, allocator: std.mem.Allocator) void {
        allocator.free(self.frames);
    }
};

/// Animator state for playing animations
pub const Animator = struct {
    current_frame: u32,
    time_in_frame: f32,
    finished: bool,

    pub fn init() Animator {
        return .{
            .current_frame = 0,
            .time_in_frame = 0,
            .finished = false,
        };
    }

    /// Update the animator with delta time
    /// Returns true if the animation just completed (non-looping only)
    pub fn update(self: *Animator, animation: Animation, delta_time: f32) bool {
        if (self.finished) return false;

        self.time_in_frame += delta_time;

        const current_frame_data = animation.frames[self.current_frame];

        if (self.time_in_frame >= current_frame_data.duration) {
            self.time_in_frame -= current_frame_data.duration;
            self.current_frame += 1;

            if (self.current_frame >= animation.frames.len) {
                if (animation.loop) {
                    self.current_frame = 0;
                } else {
                    self.current_frame = @intCast(animation.frames.len - 1);
                    self.finished = true;
                    return true; // Animation just finished
                }
            }
        }

        return false;
    }

    /// Get the current frame data
    pub fn getCurrentFrame(self: Animator, animation: Animation) AnimationFrame {
        return animation.frames[self.current_frame];
    }

    /// Reset the animator to the beginning
    pub fn reset(self: *Animator) void {
        self.current_frame = 0;
        self.time_in_frame = 0;
        self.finished = false;
    }

    /// Check if the animation has finished (non-looping only)
    pub fn isFinished(self: Animator) bool {
        return self.finished;
    }
};
