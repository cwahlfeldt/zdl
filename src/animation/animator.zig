const std = @import("std");
const math = @import("../math/math.zig");
const Mat4 = math.Mat4;
const Transform = @import("../ecs/components/transform_component.zig").Transform;
const Skeleton = @import("skeleton.zig").Skeleton;
const AnimationClip = @import("animation_clip.zig").AnimationClip;

/// Playback state for an animation layer
pub const PlaybackState = enum {
    stopped,
    playing,
    paused,
};

/// Blend mode for combining animations
pub const BlendMode = enum {
    /// Replace the base pose entirely
    override,
    /// Add to the base pose (for additive animations)
    additive,
};

/// A single animation layer that can blend with others
pub const AnimationLayer = struct {
    /// Current animation clip (null if none)
    clip: ?*const AnimationClip,

    /// Current playback time in seconds
    time: f32,

    /// Playback speed multiplier (1.0 = normal)
    speed: f32,

    /// Blend weight (0.0 to 1.0)
    weight: f32,

    /// Current playback state
    state: PlaybackState,

    /// How this layer combines with layers below
    blend_mode: BlendMode,

    /// Target clip for crossfade (null if not transitioning)
    target_clip: ?*const AnimationClip,

    /// Target clip playback time
    target_time: f32,

    /// Transition progress (0.0 to 1.0)
    transition_progress: f32,

    /// Duration of the transition in seconds
    transition_duration: f32,

    pub fn init() AnimationLayer {
        return .{
            .clip = null,
            .time = 0,
            .speed = 1.0,
            .weight = 1.0,
            .state = .stopped,
            .blend_mode = .override,
            .target_clip = null,
            .target_time = 0,
            .transition_progress = 0,
            .transition_duration = 0,
        };
    }

    /// Start playing an animation immediately
    pub fn play(self: *AnimationLayer, clip: *const AnimationClip) void {
        self.clip = clip;
        self.time = 0;
        self.state = .playing;
        self.target_clip = null;
        self.transition_progress = 0;
    }

    /// Crossfade to a new animation over the specified duration
    pub fn crossFade(self: *AnimationLayer, clip: *const AnimationClip, duration: f32) void {
        if (self.clip == null or duration <= 0) {
            // No current animation or instant transition
            self.play(clip);
            return;
        }

        self.target_clip = clip;
        self.target_time = 0;
        self.transition_progress = 0;
        self.transition_duration = duration;
        self.state = .playing;
    }

    /// Stop playback
    pub fn stop(self: *AnimationLayer) void {
        self.state = .stopped;
        self.time = 0;
        self.target_clip = null;
    }

    /// Pause playback
    pub fn pause(self: *AnimationLayer) void {
        if (self.state == .playing) {
            self.state = .paused;
        }
    }

    /// Resume playback
    pub fn unpause(self: *AnimationLayer) void {
        if (self.state == .paused) {
            self.state = .playing;
        }
    }

    /// Update the layer by delta time
    pub fn update(self: *AnimationLayer, dt: f32) void {
        if (self.state != .playing) return;

        const scaled_dt = dt * self.speed;

        // Update main clip time
        if (self.clip) |clip| {
            self.time += scaled_dt;
            if (clip.looping and clip.duration > 0) {
                self.time = @mod(self.time, clip.duration);
            }
        }

        // Update transition
        if (self.target_clip != null and self.transition_duration > 0) {
            self.target_time += scaled_dt;
            if (self.target_clip.?.looping and self.target_clip.?.duration > 0) {
                self.target_time = @mod(self.target_time, self.target_clip.?.duration);
            }

            self.transition_progress += dt / self.transition_duration;

            if (self.transition_progress >= 1.0) {
                // Transition complete - swap to target
                self.clip = self.target_clip;
                self.time = self.target_time;
                self.target_clip = null;
                self.transition_progress = 0;
            }
        }
    }

    /// Sample the current animation(s) into the pose
    pub fn sample(self: *const AnimationLayer, pose: []Transform) void {
        if (self.clip == null) return;

        if (self.target_clip) |target| {
            // We're in a crossfade - blend between clips
            var temp_pose: [128]Transform = undefined;
            const bone_count = @min(pose.len, 128);

            // Sample source clip
            self.clip.?.sample(self.time, pose[0..bone_count]);

            // Sample target clip into temp
            @memcpy(temp_pose[0..bone_count], pose[0..bone_count]);
            target.sample(self.target_time, temp_pose[0..bone_count]);

            // Blend
            const t = self.transition_progress;
            for (0..bone_count) |i| {
                pose[i] = blendTransforms(pose[i], temp_pose[i], t);
            }
        } else {
            // Simple sampling
            self.clip.?.sample(self.time, pose);
        }
    }
};

/// Blend two transforms by factor t (0.0 = a, 1.0 = b)
fn blendTransforms(a: Transform, b: Transform, t: f32) Transform {
    const math_pkg = @import("../math/math.zig");
    const Quat = math_pkg.Quat;
    const Vec3 = math_pkg.Vec3;

    return .{
        .position = Vec3.init(
            a.position.x + (b.position.x - a.position.x) * t,
            a.position.y + (b.position.y - a.position.y) * t,
            a.position.z + (b.position.z - a.position.z) * t,
        ),
        .rotation = Quat.slerp(a.rotation, b.rotation, t),
        .scale = Vec3.init(
            a.scale.x + (b.scale.x - a.scale.x) * t,
            a.scale.y + (b.scale.y - a.scale.y) * t,
            a.scale.z + (b.scale.z - a.scale.z) * t,
        ),
    };
}

/// Animator manages animation playback for a skeleton
pub const Animator = struct {
    allocator: std.mem.Allocator,

    /// Reference to the skeleton being animated
    skeleton: *const Skeleton,

    /// Current pose (local transforms for each bone)
    current_pose: []Transform,

    /// Computed world transforms
    world_transforms: []Mat4,

    /// Computed skinning matrices (for GPU)
    skinning_matrices: []Mat4,

    /// Animation layers (supports up to 4 layers)
    layers: [4]AnimationLayer,

    /// Number of active layers
    layer_count: u8,

    /// Animation clip library
    clips: std.StringHashMap(*const AnimationClip),

    /// Global playback speed
    speed: f32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, skeleton: *const Skeleton) !Self {
        const bone_count = skeleton.boneCount();

        const current_pose = try allocator.alloc(Transform, bone_count);
        const world_transforms = try allocator.alloc(Mat4, bone_count);
        const skinning_matrices = try allocator.alloc(Mat4, bone_count);

        // Initialize pose to bind pose
        skeleton.getBindPose(current_pose);

        // Initialize matrices to identity
        for (world_transforms) |*m| m.* = Mat4.identity();
        for (skinning_matrices) |*m| m.* = Mat4.identity();

        var layers: [4]AnimationLayer = undefined;
        for (&layers) |*layer| {
            layer.* = AnimationLayer.init();
        }

        return .{
            .allocator = allocator,
            .skeleton = skeleton,
            .current_pose = current_pose,
            .world_transforms = world_transforms,
            .skinning_matrices = skinning_matrices,
            .layers = layers,
            .layer_count = 1,
            .clips = std.StringHashMap(*const AnimationClip).init(allocator),
            .speed = 1.0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.current_pose);
        self.allocator.free(self.world_transforms);
        self.allocator.free(self.skinning_matrices);
        self.clips.deinit();
    }

    /// Register an animation clip with a name
    pub fn addClip(self: *Self, name: []const u8, clip: *const AnimationClip) !void {
        try self.clips.put(name, clip);
    }

    /// Play an animation by name on layer 0
    pub fn play(self: *Self, name: []const u8) bool {
        return self.playOnLayer(name, 0);
    }

    /// Play an animation by name on a specific layer
    pub fn playOnLayer(self: *Self, name: []const u8, layer: u8) bool {
        if (layer >= self.layer_count) return false;
        const clip = self.clips.get(name) orelse return false;
        self.layers[layer].play(clip);
        return true;
    }

    /// Crossfade to an animation by name on layer 0
    pub fn crossFade(self: *Self, name: []const u8, duration: f32) bool {
        return self.crossFadeOnLayer(name, duration, 0);
    }

    /// Crossfade to an animation by name on a specific layer
    pub fn crossFadeOnLayer(self: *Self, name: []const u8, duration: f32, layer: u8) bool {
        if (layer >= self.layer_count) return false;
        const clip = self.clips.get(name) orelse return false;
        self.layers[layer].crossFade(clip, duration);
        return true;
    }

    /// Stop playback on layer 0
    pub fn stop(self: *Self) void {
        self.layers[0].stop();
    }

    /// Pause playback on layer 0
    pub fn pause(self: *Self) void {
        self.layers[0].pause();
    }

    /// Resume playback on layer 0
    pub fn unpause(self: *Self) void {
        self.layers[0].unpause();
    }

    /// Get playback state of layer 0
    pub fn getState(self: *const Self) PlaybackState {
        return self.layers[0].state;
    }

    /// Get current playback time of layer 0
    pub fn getTime(self: *const Self) f32 {
        return self.layers[0].time;
    }

    /// Set playback time of layer 0
    pub fn setTime(self: *Self, time: f32) void {
        self.layers[0].time = time;
    }

    /// Set layer weight
    pub fn setLayerWeight(self: *Self, layer: u8, weight: f32) void {
        if (layer < self.layer_count) {
            self.layers[layer].weight = std.math.clamp(weight, 0.0, 1.0);
        }
    }

    /// Update all layers and compute final pose
    pub fn update(self: *Self, dt: f32) void {
        const scaled_dt = dt * self.speed;

        // Reset pose to bind pose
        self.skeleton.getBindPose(self.current_pose);

        // Update and sample each layer
        for (0..self.layer_count) |i| {
            self.layers[i].update(scaled_dt);

            if (self.layers[i].weight > 0 and self.layers[i].clip != null) {
                if (self.layers[i].blend_mode == .override and self.layers[i].weight >= 1.0) {
                    // Full override - sample directly
                    self.layers[i].sample(self.current_pose);
                } else {
                    // Partial blend - sample to temp and blend
                    var temp_pose: [128]Transform = undefined;
                    const bone_count = @min(self.current_pose.len, 128);
                    @memcpy(temp_pose[0..bone_count], self.current_pose[0..bone_count]);
                    self.layers[i].sample(temp_pose[0..bone_count]);

                    // Blend
                    const w = self.layers[i].weight;
                    for (0..bone_count) |j| {
                        self.current_pose[j] = blendTransforms(self.current_pose[j], temp_pose[j], w);
                    }
                }
            }
        }

        // Compute world transforms from local pose
        self.skeleton.computeWorldTransforms(self.current_pose, self.world_transforms);

        // Compute skinning matrices
        self.skeleton.computeSkinningMatrices(self.world_transforms, self.skinning_matrices);
    }

    /// Get the skinning matrices for GPU upload
    pub fn getSkinningMatrices(self: *const Self) []const Mat4 {
        return self.skinning_matrices;
    }

    /// Get world transform for a specific bone
    pub fn getBoneWorldTransform(self: *const Self, bone_index: usize) ?Mat4 {
        if (bone_index >= self.world_transforms.len) return null;
        return self.world_transforms[bone_index];
    }
};
