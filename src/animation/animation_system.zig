const std = @import("std");
const math = @import("../math/math.zig");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const Entity = @import("../ecs/entity.zig").Entity;
const Scene = @import("../ecs/scene.zig").Scene;
const TransformComponent = @import("../ecs/components/transform_component.zig").TransformComponent;

const AnimatorComponent = @import("animator_component.zig").AnimatorComponent;

/// Animation system updates all AnimatorComponents in the scene
pub const AnimationSystem = struct {
    /// Update all animators in the scene
    /// This should be called once per frame before rendering
    pub fn update(animators: []AnimatorComponent, dt: f32) void {
        for (animators) |*animator| {
            if (animator.enabled) {
                animator.update(dt);
            }
        }
    }

    /// Update animators and apply root motion to transforms
    /// For entities that use root motion, this extracts movement from the animation
    /// and applies it to the entity's transform
    pub fn updateWithRootMotion(
        animators: []AnimatorComponent,
        animator_entities: []const Entity,
        scene: *Scene,
        dt: f32,
    ) void {
        for (animators, animator_entities) |*animator, entity| {
            if (!animator.enabled) continue;

            animator.update(dt);

            // TODO: Implement root motion extraction and application
            // This would involve:
            // 1. Extract root bone delta position/rotation from animation
            // 2. Apply delta to entity's TransformComponent
            // 3. Zero out root bone's translation in the pose

            _ = entity;
            _ = scene;
        }
    }

    /// Get debug info for an animator
    pub fn getDebugInfo(animator: *const AnimatorComponent) AnimatorDebugInfo {
        const anim = &animator.animator;
        const layer = &anim.layers[0];

        return .{
            .bone_count = anim.skeleton.boneCount(),
            .is_playing = layer.state == .playing,
            .current_time = layer.time,
            .current_clip_name = if (layer.clip) |clip| clip.name else "none",
            .playback_speed = anim.speed,
        };
    }
};

/// Debug info for animation visualization
pub const AnimatorDebugInfo = struct {
    bone_count: usize,
    is_playing: bool,
    current_time: f32,
    current_clip_name: []const u8,
    playback_speed: f32,
};
