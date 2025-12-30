const std = @import("std");
const types = @import("types.zig");
const GLTFAsset = types.GLTFAsset;
const AccessorData = types.AccessorData;
const ComponentType = types.ComponentType;
const ElementType = types.ElementType;
const AnimationTargetPath = types.AnimationTargetPath;
const AnimationInterpolation = types.AnimationInterpolation;

const animation = @import("../../animation/animation.zig");
const Skeleton = animation.Skeleton;
const AnimationClip = animation.AnimationClip;
const AnimationChannel = animation.AnimationChannel;
const ChannelTarget = @import("../../animation/animation_clip.zig").ChannelTarget;
const InterpolationType = animation.InterpolationType;
const Transform = animation.Transform;
const BoneIndex = animation.BoneIndex;
const NO_BONE = @import("../../animation/skeleton.zig").NO_BONE;

const math = @import("../../math/math.zig");
const Vec3 = math.Vec3;
const Quat = math.Quat;
const Mat4 = math.Mat4;

/// Load a skeleton from a glTF skin
pub fn loadSkeleton(allocator: std.mem.Allocator, asset: *const GLTFAsset, skin_index: usize) !*Skeleton {
    if (skin_index >= asset.skins.len) return error.InvalidSkinIndex;

    const skin = asset.skins[skin_index];
    const joint_count = skin.joints.len;

    if (joint_count == 0) return error.EmptySkin;

    var skeleton = try allocator.create(Skeleton);
    skeleton.* = try Skeleton.init(allocator, joint_count);

    // Build a map from node index to bone index
    var node_to_bone = std.AutoHashMap(usize, BoneIndex).init(allocator);
    defer node_to_bone.deinit();

    for (skin.joints, 0..) |node_idx, bone_idx| {
        try node_to_bone.put(node_idx, @intCast(bone_idx));
    }

    // Set up each bone
    for (skin.joints, 0..) |node_idx, bone_idx| {
        if (node_idx >= asset.nodes.len) continue;

        const node = asset.nodes[node_idx];
        const transform_data = node.getTransform();

        // Find parent bone index
        var parent_bone: BoneIndex = NO_BONE;
        // Search for parent by checking which node has this node as a child
        for (asset.nodes, 0..) |parent_node, parent_node_idx| {
            for (parent_node.children) |child_idx| {
                if (child_idx == node_idx) {
                    // Found parent node, check if it's a joint
                    if (node_to_bone.get(parent_node_idx)) |pb| {
                        parent_bone = pb;
                    }
                    break;
                }
            }
        }

        const bone_name = node.name orelse "";
        const local_transform = Transform{
            .position = transform_data.position,
            .rotation = transform_data.rotation,
            .scale = transform_data.scale,
        };

        try skeleton.setBone(@intCast(bone_idx), bone_name, parent_bone, local_transform);
    }

    // Load inverse bind matrices
    if (skin.inverse_bind_matrices) |ibm_accessor_idx| {
        if (ibm_accessor_idx < asset.accessors.len) {
            const accessor = asset.accessors[ibm_accessor_idx];
            if (accessor.element_type == .MAT4 and accessor.count == joint_count) {
                const matrices = try readMat4Array(allocator, asset, accessor);
                defer allocator.free(matrices);

                for (matrices, 0..) |mat, i| {
                    skeleton.setInverseBindMatrix(@intCast(i), mat);
                }
            }
        }
    }

    try skeleton.computeRootBones();

    // Set skeleton name
    if (skin.name) |name| {
        skeleton.name = try allocator.dupe(u8, name);
    }

    return skeleton;
}

/// Load an animation clip from a glTF animation
pub fn loadAnimationClip(
    allocator: std.mem.Allocator,
    asset: *const GLTFAsset,
    animation_index: usize,
    node_to_bone: *const std.AutoHashMap(usize, BoneIndex),
) !*AnimationClip {
    if (animation_index >= asset.animations.len) return error.InvalidAnimationIndex;

    const anim_data = asset.animations[animation_index];

    // Count valid channels (those targeting bones we know about)
    var valid_channel_count: usize = 0;
    for (anim_data.channels) |channel| {
        if (channel.target.node) |node_idx| {
            if (node_to_bone.get(node_idx) != null) {
                // Skip weights for now (morph targets)
                if (channel.target.path != .weights) {
                    valid_channel_count += 1;
                }
            }
        }
    }

    const anim_name = anim_data.name orelse "unnamed";
    var clip = try allocator.create(AnimationClip);
    clip.* = try AnimationClip.init(allocator, anim_name, valid_channel_count);

    var channel_idx: usize = 0;
    for (anim_data.channels) |channel| {
        const node_idx = channel.target.node orelse continue;
        const bone_idx = node_to_bone.get(node_idx) orelse continue;

        // Skip weights for now
        if (channel.target.path == .weights) continue;

        const sampler = anim_data.samplers[channel.sampler];
        const input_accessor = asset.accessors[sampler.input];
        const output_accessor = asset.accessors[sampler.output];

        const keyframe_count = input_accessor.count;

        // Determine channel target
        const target: ChannelTarget = switch (channel.target.path) {
            .translation => .translation,
            .rotation => .rotation,
            .scale => .scale,
            .weights => continue,
        };

        clip.channels[channel_idx] = try AnimationChannel.init(allocator, bone_idx, target, keyframe_count);
        var anim_channel = &clip.channels[channel_idx];

        // Set interpolation
        anim_channel.interpolation = switch (sampler.interpolation) {
            .step => .step,
            .linear => .linear,
            .cubic_spline => .cubic_spline,
        };

        // Read keyframe times
        const times = try readFloatArray(allocator, asset, input_accessor);
        defer allocator.free(times);
        @memcpy(anim_channel.times, times);

        // Read keyframe values based on type
        switch (target) {
            .translation, .scale => {
                const values = try readVec3Array(allocator, asset, output_accessor);
                defer allocator.free(values);

                const target_array = if (target == .translation)
                    anim_channel.translation_values.?
                else
                    anim_channel.scale_values.?;

                @memcpy(target_array, values);
            },
            .rotation => {
                const values = try readQuatArray(allocator, asset, output_accessor);
                defer allocator.free(values);
                @memcpy(anim_channel.rotation_values.?, values);
            },
        }

        channel_idx += 1;
    }

    clip.computeDuration();

    return clip;
}

/// Create a node-to-bone mapping for a skin
pub fn createNodeToBoneMap(allocator: std.mem.Allocator, asset: *const GLTFAsset, skin_index: usize) !std.AutoHashMap(usize, BoneIndex) {
    var map = std.AutoHashMap(usize, BoneIndex).init(allocator);

    if (skin_index < asset.skins.len) {
        const skin = asset.skins[skin_index];
        for (skin.joints, 0..) |node_idx, bone_idx| {
            try map.put(node_idx, @intCast(bone_idx));
        }
    }

    return map;
}

// Helper functions to read accessor data

fn readFloatArray(allocator: std.mem.Allocator, asset: *const GLTFAsset, accessor: AccessorData) ![]f32 {
    const count = accessor.count;
    var result = try allocator.alloc(f32, count);

    const buffer_view = asset.buffer_views[accessor.buffer_view orelse return error.MissingBufferView];
    const buffer = asset.buffers[buffer_view.buffer];

    const byte_offset = buffer_view.byte_offset + accessor.byte_offset;
    const data = buffer[byte_offset..];

    switch (accessor.component_type) {
        .float => {
            const floats = @as([*]const f32, @ptrCast(@alignCast(data.ptr)));
            @memcpy(result, floats[0..count]);
        },
        else => {
            // Convert other types to float
            for (0..count) |i| {
                result[i] = readComponentAsFloat(data, accessor.component_type, i);
            }
        },
    }

    return result;
}

fn readVec3Array(allocator: std.mem.Allocator, asset: *const GLTFAsset, accessor: AccessorData) ![]Vec3 {
    const count = accessor.count;
    var result = try allocator.alloc(Vec3, count);

    const buffer_view = asset.buffer_views[accessor.buffer_view orelse return error.MissingBufferView];
    const buffer = asset.buffers[buffer_view.buffer];

    const byte_offset = buffer_view.byte_offset + accessor.byte_offset;
    const stride = buffer_view.byte_stride orelse (accessor.component_type.byteSize() * 3);

    for (0..count) |i| {
        const offset = byte_offset + i * stride;
        const data = buffer[offset..];

        if (accessor.component_type == .float) {
            const floats = @as([*]const f32, @ptrCast(@alignCast(data.ptr)));
            result[i] = Vec3.init(floats[0], floats[1], floats[2]);
        } else {
            result[i] = Vec3.init(
                readComponentAsFloat(data, accessor.component_type, 0),
                readComponentAsFloat(data, accessor.component_type, 1),
                readComponentAsFloat(data, accessor.component_type, 2),
            );
        }
    }

    return result;
}

fn readQuatArray(allocator: std.mem.Allocator, asset: *const GLTFAsset, accessor: AccessorData) ![]Quat {
    const count = accessor.count;
    var result = try allocator.alloc(Quat, count);

    const buffer_view = asset.buffer_views[accessor.buffer_view orelse return error.MissingBufferView];
    const buffer = asset.buffers[buffer_view.buffer];

    const byte_offset = buffer_view.byte_offset + accessor.byte_offset;
    const stride = buffer_view.byte_stride orelse (accessor.component_type.byteSize() * 4);

    for (0..count) |i| {
        const offset = byte_offset + i * stride;
        const data = buffer[offset..];

        if (accessor.component_type == .float) {
            const floats = @as([*]const f32, @ptrCast(@alignCast(data.ptr)));
            // glTF quaternions are stored as (x, y, z, w)
            result[i] = Quat.init(floats[0], floats[1], floats[2], floats[3]);
        } else {
            result[i] = Quat.init(
                readComponentAsFloat(data, accessor.component_type, 0),
                readComponentAsFloat(data, accessor.component_type, 1),
                readComponentAsFloat(data, accessor.component_type, 2),
                readComponentAsFloat(data, accessor.component_type, 3),
            );
        }
    }

    return result;
}

fn readMat4Array(allocator: std.mem.Allocator, asset: *const GLTFAsset, accessor: AccessorData) ![]Mat4 {
    const count = accessor.count;
    var result = try allocator.alloc(Mat4, count);

    const buffer_view = asset.buffer_views[accessor.buffer_view orelse return error.MissingBufferView];
    const buffer = asset.buffers[buffer_view.buffer];

    const byte_offset = buffer_view.byte_offset + accessor.byte_offset;
    const stride = buffer_view.byte_stride orelse (accessor.component_type.byteSize() * 16);

    for (0..count) |i| {
        const offset = byte_offset + i * stride;
        const data = buffer[offset..];

        if (accessor.component_type == .float) {
            const floats = @as([*]const f32, @ptrCast(@alignCast(data.ptr)));
            var mat_data: [16]f32 = undefined;
            @memcpy(&mat_data, floats[0..16]);
            result[i] = .{ .data = mat_data };
        } else {
            var mat_data: [16]f32 = undefined;
            for (0..16) |j| {
                mat_data[j] = readComponentAsFloat(data, accessor.component_type, j);
            }
            result[i] = .{ .data = mat_data };
        }
    }

    return result;
}

fn readComponentAsFloat(data: []const u8, component_type: ComponentType, index: usize) f32 {
    const byte_size = component_type.byteSize();
    const offset = index * byte_size;

    return switch (component_type) {
        .float => @as(*const f32, @ptrCast(@alignCast(data[offset..].ptr))).*,
        .byte => @as(f32, @floatFromInt(@as(*const i8, @ptrCast(data[offset..].ptr)).*)) / 127.0,
        .unsigned_byte => @as(f32, @floatFromInt(data[offset])) / 255.0,
        .short => @as(f32, @floatFromInt(@as(*const i16, @ptrCast(@alignCast(data[offset..].ptr))).*)) / 32767.0,
        .unsigned_short => @as(f32, @floatFromInt(@as(*const u16, @ptrCast(@alignCast(data[offset..].ptr))).*)) / 65535.0,
        .unsigned_int => @as(f32, @floatFromInt(@as(*const u32, @ptrCast(@alignCast(data[offset..].ptr))).*)),
    };
}
