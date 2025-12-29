# Animation System

## Overview

Implement a comprehensive animation system supporting skeletal animation, blend trees, animation state machines, procedural animation, and runtime animation retargeting. The system should integrate with glTF import and provide tools for game-ready character animation.

## Current State

ZDL currently has:
- Quaternion-based rotation (good foundation)
- No skeletal animation
- No keyframe interpolation
- No animation blending
- glTF skin import planned but not implemented

## Goals

- Skeletal animation with bone hierarchies
- Animation clips with multiple channels
- Smooth blending between animations
- Animation state machines for complex behavior
- Inverse kinematics for procedural animation
- Root motion support
- Animation events and callbacks
- Animation compression
- GPU skinning for performance

## Architecture

### Directory Structure

```
src/
├── animation/
│   ├── animation.zig          # Module exports
│   ├── skeleton.zig           # Bone hierarchy
│   ├── animation_clip.zig     # Keyframe data
│   ├── animator.zig           # Animation playback
│   ├── blend_tree.zig         # Animation blending
│   ├── state_machine.zig      # Animator state machine
│   ├── ik/
│   │   ├── ik.zig             # IK module
│   │   ├── two_bone_ik.zig    # Simple IK solver
│   │   ├── ccd_ik.zig         # CCD solver
│   │   └── fabrik.zig         # FABRIK solver
│   ├── skinning.zig           # Mesh skinning
│   └── root_motion.zig        # Root motion extraction
```

### Core Components

#### Skeleton

```zig
pub const Skeleton = struct {
    allocator: Allocator,
    bones: []Bone,
    bone_names: std.StringHashMap(u32),
    root_bone: u32,

    // Bind pose
    bind_pose: []Transform,
    inverse_bind_pose: []Mat4,

    pub fn init(allocator: Allocator, bone_count: u32) !Skeleton;
    pub fn deinit(self: *Skeleton) void;

    pub fn getBoneIndex(self: *Skeleton, name: []const u8) ?u32;
    pub fn getBone(self: *Skeleton, index: u32) *Bone;
    pub fn getBindPose(self: *Skeleton) []Transform;

    // Pose evaluation
    pub fn computeWorldTransforms(
        self: *Skeleton,
        local_transforms: []const Transform,
        out_world_transforms: []Mat4,
    ) void;

    pub fn computeSkinningMatrices(
        self: *Skeleton,
        world_transforms: []const Mat4,
        out_skinning_matrices: []Mat4,
    ) void;
};

pub const Bone = struct {
    name: []const u8,
    parent: ?u32,
    children: []u32,
    local_bind_transform: Transform,
};

pub const Transform = struct {
    translation: Vec3,
    rotation: Quat,
    scale: Vec3,

    pub fn identity() Transform;
    pub fn toMat4(self: Transform) Mat4;
    pub fn lerp(a: Transform, b: Transform, t: f32) Transform;
};
```

#### Animation Clip

```zig
pub const AnimationClip = struct {
    name: []const u8,
    duration: f32,
    ticks_per_second: f32,
    channels: []AnimationChannel,

    // Metadata
    loop: bool,
    root_motion: bool,

    // Events
    events: []AnimationEvent,

    pub fn init(allocator: Allocator, name: []const u8) !AnimationClip;
    pub fn deinit(self: *AnimationClip) void;

    pub fn sample(self: *AnimationClip, time: f32, out_pose: []Transform) void;
    pub fn sampleChannel(self: *AnimationClip, channel: u32, time: f32) Transform;
    pub fn getEventsInRange(self: *AnimationClip, start: f32, end: f32) []AnimationEvent;
};

pub const AnimationChannel = struct {
    bone_index: u32,
    position_keys: []PositionKey,
    rotation_keys: []RotationKey,
    scale_keys: []ScaleKey,

    pub fn sample(self: *AnimationChannel, time: f32) Transform;
};

pub const PositionKey = struct {
    time: f32,
    value: Vec3,
};

pub const RotationKey = struct {
    time: f32,
    value: Quat,
};

pub const ScaleKey = struct {
    time: f32,
    value: Vec3,
};

pub const AnimationEvent = struct {
    time: f32,
    name: []const u8,
    data: ?[]const u8,
};
```

#### Animator Component

```zig
pub const AnimatorComponent = struct {
    skeleton: *Skeleton,
    current_pose: []Transform,
    skinning_matrices: []Mat4,

    // Playback state
    clips: std.StringHashMap(*AnimationClip),
    layers: []AnimationLayer,

    // State machine (optional)
    state_machine: ?*AnimatorStateMachine,

    // Blend tree (optional)
    blend_tree: ?*BlendTree,

    // Settings
    speed: f32,
    root_motion_enabled: bool,

    // Events
    on_event: ?fn([]const u8, ?[]const u8) void,

    pub fn init(allocator: Allocator, skeleton: *Skeleton) !AnimatorComponent;
    pub fn deinit(self: *AnimatorComponent) void;

    // Playback control
    pub fn play(self: *AnimatorComponent, clip_name: []const u8) void;
    pub fn playWithTransition(self: *AnimatorComponent, clip_name: []const u8, duration: f32) void;
    pub fn crossFade(self: *AnimatorComponent, clip_name: []const u8, duration: f32) void;
    pub fn stop(self: *AnimatorComponent) void;
    pub fn pause(self: *AnimatorComponent) void;

    // State
    pub fn isPlaying(self: *AnimatorComponent) bool;
    pub fn getCurrentTime(self: *AnimatorComponent) f32;
    pub fn setTime(self: *AnimatorComponent, time: f32) void;

    // Layer control
    pub fn setLayerWeight(self: *AnimatorComponent, layer: u32, weight: f32) void;
    pub fn setLayerMask(self: *AnimatorComponent, layer: u32, mask: BoneMask) void;

    // Update
    pub fn update(self: *AnimatorComponent, dt: f32) void;
    pub fn getRootMotionDelta(self: *AnimatorComponent) ?RootMotion;
};

pub const AnimationLayer = struct {
    clip: ?*AnimationClip,
    time: f32,
    weight: f32,
    blend_mode: BlendMode,
    mask: ?BoneMask,

    // Transition
    target_clip: ?*AnimationClip,
    transition_time: f32,
    transition_duration: f32,
};

pub const BlendMode = enum {
    override,
    additive,
};

pub const BoneMask = struct {
    weights: []f32,  // Per-bone weights (0.0 to 1.0)

    pub fn full(skeleton: *Skeleton) BoneMask;
    pub fn upper_body(skeleton: *Skeleton) BoneMask;
    pub fn lower_body(skeleton: *Skeleton) BoneMask;
    pub fn from_bone(skeleton: *Skeleton, root_bone: []const u8, recursive: bool) BoneMask;
};
```

### Animation Blending

#### Blend Tree

```zig
pub const BlendTree = struct {
    root: *BlendNode,
    parameters: std.StringHashMap(f32),

    pub fn init(allocator: Allocator) !BlendTree;
    pub fn setParameter(self: *BlendTree, name: []const u8, value: f32) void;
    pub fn getParameter(self: *BlendTree, name: []const u8) f32;
    pub fn evaluate(self: *BlendTree, out_pose: []Transform) void;
};

pub const BlendNode = union(enum) {
    clip: ClipNode,
    blend_1d: Blend1DNode,
    blend_2d: Blend2DNode,
    additive: AdditiveNode,
    override: OverrideNode,

    pub fn evaluate(self: *BlendNode, params: *std.StringHashMap(f32), out_pose: []Transform) void;
};

pub const ClipNode = struct {
    clip: *AnimationClip,
    time: f32,
    speed: f32,
};

pub const Blend1DNode = struct {
    parameter: []const u8,
    children: []BlendChild1D,

    pub const BlendChild1D = struct {
        node: *BlendNode,
        threshold: f32,
    };
};

pub const Blend2DNode = struct {
    parameter_x: []const u8,
    parameter_y: []const u8,
    children: []BlendChild2D,
    blend_type: Blend2DType,

    pub const BlendChild2D = struct {
        node: *BlendNode,
        position: Vec2,
    };

    pub const Blend2DType = enum {
        simple_directional,
        freeform_directional,
        freeform_cartesian,
    };
};

pub const AdditiveNode = struct {
    base: *BlendNode,
    additive: *BlendNode,
    weight: f32,
};
```

#### Animation State Machine

```zig
pub const AnimatorStateMachine = struct {
    states: std.StringHashMap(*AnimatorState),
    current_state: *AnimatorState,
    parameters: Parameters,

    pub fn init(allocator: Allocator) !AnimatorStateMachine;

    pub fn addState(self: *AnimatorStateMachine, name: []const u8, state: *AnimatorState) void;
    pub fn setDefaultState(self: *AnimatorStateMachine, name: []const u8) void;

    pub fn setBool(self: *AnimatorStateMachine, name: []const u8, value: bool) void;
    pub fn setFloat(self: *AnimatorStateMachine, name: []const u8, value: f32) void;
    pub fn setInt(self: *AnimatorStateMachine, name: []const u8, value: i32) void;
    pub fn setTrigger(self: *AnimatorStateMachine, name: []const u8) void;

    pub fn update(self: *AnimatorStateMachine, dt: f32) void;
    pub fn getCurrentStateName(self: *AnimatorStateMachine) []const u8;
};

pub const AnimatorState = struct {
    name: []const u8,
    motion: Motion,
    speed: f32,
    transitions: []StateTransition,

    // Callbacks
    on_enter: ?fn() void,
    on_exit: ?fn() void,
    on_update: ?fn(f32) void,
};

pub const Motion = union(enum) {
    clip: *AnimationClip,
    blend_tree: *BlendTree,
};

pub const StateTransition = struct {
    target_state: []const u8,
    conditions: []TransitionCondition,
    duration: f32,
    has_exit_time: bool,
    exit_time: f32,
    fixed_duration: bool,
};

pub const TransitionCondition = struct {
    parameter: []const u8,
    mode: ConditionMode,
    threshold: f32,
};

pub const ConditionMode = enum {
    greater,
    less,
    equals,
    not_equal,
    if_true,
    if_false,
    trigger,
};
```

### Inverse Kinematics

```zig
pub const IKChain = struct {
    bones: []u32,
    target: Vec3,
    pole: ?Vec3,
    weight: f32,
    iterations: u32,

    pub fn solve(self: *IKChain, skeleton: *Skeleton, pose: []Transform) void;
};

pub const TwoBoneIK = struct {
    root_bone: u32,
    mid_bone: u32,
    end_bone: u32,
    target: Vec3,
    pole: Vec3,
    weight: f32,

    pub fn solve(self: *TwoBoneIK, skeleton: *Skeleton, pose: []Transform) void;
};

pub const LookAtIK = struct {
    head_bone: u32,
    target: Vec3,
    weight: f32,
    clamp_weight: f32,
    clamp_angle: f32,

    pub fn solve(self: *LookAtIK, skeleton: *Skeleton, pose: []Transform) void;
};

// Full body IK
pub const FullBodyIK = struct {
    spine_chain: []u32,
    left_arm: TwoBoneIK,
    right_arm: TwoBoneIK,
    left_leg: TwoBoneIK,
    right_leg: TwoBoneIK,

    pub fn solve(self: *FullBodyIK, skeleton: *Skeleton, pose: []Transform, targets: IKTargets) void;
};

pub const IKTargets = struct {
    left_hand: ?Vec3,
    right_hand: ?Vec3,
    left_foot: ?Vec3,
    right_foot: ?Vec3,
    look_at: ?Vec3,
};
```

### GPU Skinning

```zig
pub const SkinningComponent = struct {
    skeleton: *Skeleton,
    mesh: *SkinnedMesh,

    // GPU resources
    bone_buffer: *Buffer,           // Skinning matrices
    weights_buffer: *Buffer,        // Vertex bone weights

    pub fn init(device: *Device, skeleton: *Skeleton, mesh: *SkinnedMesh) !SkinningComponent;
    pub fn updateBoneBuffer(self: *SkinningComponent, matrices: []const Mat4) void;
};

// Skinning shader (vertex)
// #version 450
//
// layout(location = 0) in vec3 position;
// layout(location = 1) in vec3 normal;
// layout(location = 2) in vec2 uv;
// layout(location = 3) in ivec4 bone_indices;
// layout(location = 4) in vec4 bone_weights;
//
// layout(set = 0, binding = 0) uniform Matrices {
//     mat4 view_projection;
// };
//
// layout(set = 1, binding = 0) readonly buffer BoneMatrices {
//     mat4 bones[];
// };
//
// void main() {
//     mat4 skin_matrix =
//         bones[bone_indices.x] * bone_weights.x +
//         bones[bone_indices.y] * bone_weights.y +
//         bones[bone_indices.z] * bone_weights.z +
//         bones[bone_indices.w] * bone_weights.w;
//
//     vec4 world_pos = skin_matrix * vec4(position, 1.0);
//     gl_Position = view_projection * world_pos;
// }
```

### Root Motion

```zig
pub const RootMotion = struct {
    delta_position: Vec3,
    delta_rotation: Quat,
};

pub const RootMotionExtractor = struct {
    root_bone: u32,
    extract_position: bool,
    extract_rotation: bool,
    projection_plane: ?Plane,  // For 2D movement

    pub fn extract(
        self: *RootMotionExtractor,
        clip: *AnimationClip,
        prev_time: f32,
        curr_time: f32,
    ) RootMotion;
};

pub fn applyRootMotion(
    entity: Entity,
    scene: *Scene,
    root_motion: RootMotion,
) void {
    const transform = scene.getComponent(entity, TransformComponent) orelse return;

    // Apply rotation first, then position
    const world_rotation = transform.rotation.mul(root_motion.delta_rotation);
    transform.setRotation(world_rotation);

    const rotated_delta = transform.rotation.rotateVec3(root_motion.delta_position);
    transform.translate(rotated_delta);
}
```

### Animation System (ECS)

```zig
pub const AnimationSystem = struct {
    pub fn update(scene: *Scene, dt: f32) void {
        const animators = scene.getComponents(AnimatorComponent);
        const entities = scene.getEntitiesWithComponent(AnimatorComponent);

        for (animators, entities) |animator, entity| {
            // Update animator
            animator.update(dt);

            // Apply root motion if enabled
            if (animator.root_motion_enabled) {
                if (animator.getRootMotionDelta()) |rm| {
                    applyRootMotion(entity, scene, rm);
                }
            }

            // Update skinning matrices
            if (scene.getComponent(entity, SkinningComponent)) |skinning| {
                skinning.updateBoneBuffer(animator.skinning_matrices);
            }
        }
    }
};
```

## Usage Examples

### Basic Animation Playback

```zig
// Setup
const skeleton = try loadSkeleton("character.gltf");
const walk_clip = try loadAnimationClip("walk.gltf");
const run_clip = try loadAnimationClip("run.gltf");

var animator = try AnimatorComponent.init(allocator, skeleton);
try animator.clips.put("walk", walk_clip);
try animator.clips.put("run", run_clip);

try scene.addComponent(character, animator);

// In update
const animator = scene.getComponent(character, AnimatorComponent).?;

if (speed > 5.0) {
    animator.crossFade("run", 0.2);
} else if (speed > 0.1) {
    animator.crossFade("walk", 0.2);
} else {
    animator.crossFade("idle", 0.3);
}
```

### Blend Tree for Locomotion

```zig
var blend_tree = try BlendTree.init(allocator);

// Create 1D blend for walk/run
const locomotion = try Blend1DNode.init(allocator, "Speed");
try locomotion.addChild(idle_node, 0.0);
try locomotion.addChild(walk_node, 0.5);
try locomotion.addChild(run_node, 1.0);

blend_tree.root = locomotion;
animator.blend_tree = blend_tree;

// In update
animator.blend_tree.?.setParameter("Speed", player.speed / player.max_speed);
```

### State Machine Setup

```zig
var state_machine = try AnimatorStateMachine.init(allocator);

// Create states
const idle_state = try AnimatorState.init("Idle", .{ .clip = idle_clip });
const walk_state = try AnimatorState.init("Walk", .{ .clip = walk_clip });
const jump_state = try AnimatorState.init("Jump", .{ .clip = jump_clip });

// Add transitions
try idle_state.addTransition(.{
    .target_state = "Walk",
    .conditions = &.{ .{ .parameter = "Speed", .mode = .greater, .threshold = 0.1 } },
    .duration = 0.2,
});

try walk_state.addTransition(.{
    .target_state = "Idle",
    .conditions = &.{ .{ .parameter = "Speed", .mode = .less, .threshold = 0.1 } },
    .duration = 0.2,
});

try walk_state.addTransition(.{
    .target_state = "Jump",
    .conditions = &.{ .{ .parameter = "Jump", .mode = .trigger } },
    .duration = 0.1,
});

state_machine.addState("Idle", idle_state);
state_machine.addState("Walk", walk_state);
state_machine.addState("Jump", jump_state);
state_machine.setDefaultState("Idle");

animator.state_machine = state_machine;

// In update
animator.state_machine.?.setFloat("Speed", player.velocity.length());
if (input.isKeyPressed(.space)) {
    animator.state_machine.?.setTrigger("Jump");
}
```

### IK for Foot Placement

```zig
// Setup foot IK
const left_foot_ik = TwoBoneIK{
    .root_bone = skeleton.getBoneIndex("LeftUpLeg").?,
    .mid_bone = skeleton.getBoneIndex("LeftLeg").?,
    .end_bone = skeleton.getBoneIndex("LeftFoot").?,
    .target = Vec3.zero(),
    .pole = Vec3.init(0, 0, 1),
    .weight = 1.0,
};

// In update: raycast for ground
const foot_pos = animator.getBoneWorldPosition("LeftFoot");
if (physics.raycast(.{ .origin = foot_pos.add(Vec3.init(0, 0.5, 0)), .direction = Vec3.init(0, -1, 0) }, 1.0, .{})) |hit| {
    left_foot_ik.target = hit.point;
    left_foot_ik.solve(skeleton, animator.current_pose);
}
```

## Implementation Steps

### Phase 1: Foundation
1. Implement skeleton data structure
2. Create animation clip with keyframes
3. Implement transform interpolation
4. Add basic animation sampling

### Phase 2: Skinning
1. Implement CPU skinning for testing
2. Create skinned mesh vertex format
3. Implement GPU skinning shader
4. Add skinning matrix buffer updates

### Phase 3: Playback
1. Create animator component
2. Implement animation layers
3. Add crossfade/blending
4. Implement bone masks

### Phase 4: Blend Trees
1. Implement blend node base
2. Create 1D blend node
3. Create 2D blend node
4. Add blend tree evaluation

### Phase 5: State Machine
1. Create state and transition types
2. Implement condition evaluation
3. Add transition logic
4. Create state machine controller

### Phase 6: IK
1. Implement two-bone IK
2. Add look-at IK
3. Create FABRIK solver
4. Add full-body IK

### Phase 7: Polish
1. Add animation events
2. Implement root motion
3. Add animation compression
4. Optimize for performance

## Performance Considerations

- **GPU Skinning**: Essential for many animated characters
- **Animation Compression**: Reduce memory with curve compression
- **LOD**: Use simpler animations at distance
- **Culling**: Skip animation updates for off-screen characters
- **Batching**: Update multiple animators in parallel
- **Caching**: Cache frequently used poses

## References

- [Game Programming Gems - Animation](https://www.satori.org/game-programming-gems-animation/)
- [GPU Skinning](https://ogldev.org/www/tutorial38/tutorial38.html)
- [Animation Blending](https://runevision.com/thesis/rune_skovbo_johansen_thesis.pdf)
- [Morpheme Animation System](https://www.naturalmotion.com/middleware/morpheme/)
- [GDC Animation Talks](https://www.gdcvault.com/search.php#&category=free&keyword=animation)
