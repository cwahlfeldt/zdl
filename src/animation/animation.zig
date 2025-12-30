// Animation module exports
//
// This module provides skeletal animation support including:
// - Skeleton with bone hierarchy
// - Animation clips with keyframe sampling
// - AnimatorComponent for playback and blending
// - AnimationSystem for ECS integration
// - GPU skinning support

// Core types
pub const Skeleton = @import("skeleton.zig").Skeleton;
pub const Bone = @import("skeleton.zig").Bone;
pub const BoneIndex = @import("skeleton.zig").BoneIndex;
pub const NO_BONE = @import("skeleton.zig").NO_BONE;
pub const MAX_BONES = @import("skeleton.zig").MAX_BONES;

// Animation data
pub const AnimationClip = @import("animation_clip.zig").AnimationClip;
pub const AnimationChannel = @import("animation_clip.zig").AnimationChannel;
pub const Keyframe = @import("animation_clip.zig").Keyframe;
pub const InterpolationType = @import("animation_clip.zig").InterpolationType;

// Playback
pub const Animator = @import("animator.zig").Animator;
pub const AnimatorComponent = @import("animator_component.zig").AnimatorComponent;
pub const PlaybackState = @import("animator.zig").PlaybackState;

// ECS System
pub const AnimationSystem = @import("animation_system.zig").AnimationSystem;

// Skinned mesh
pub const SkinnedMesh = @import("skinned_mesh.zig").SkinnedMesh;
pub const SkinnedVertex = @import("skinned_mesh.zig").SkinnedVertex;
pub const BoneMatrixBuffer = @import("skinned_mesh.zig").BoneMatrixBuffer;

// Re-export Transform from transform_component for animation use
pub const Transform = @import("../ecs/components/transform_component.zig").Transform;
