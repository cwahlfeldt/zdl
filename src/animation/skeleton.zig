const std = @import("std");
const math = @import("../math/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Quat = math.Quat;
const Transform = @import("../ecs/components/transform_component.zig").Transform;

/// Index type for bones (u8 supports up to 256 bones, typical for characters)
pub const BoneIndex = u8;

/// Special value indicating no bone
pub const NO_BONE: BoneIndex = std.math.maxInt(BoneIndex);

/// Maximum bones supported (limited by GPU uniform buffer constraints)
pub const MAX_BONES: usize = 128;

/// A single bone in the skeleton hierarchy
pub const Bone = struct {
    /// Name of the bone (for lookup and debugging)
    name: []const u8,

    /// Parent bone index (NO_BONE if root)
    parent: BoneIndex,

    /// Local bind pose transform (rest position relative to parent)
    local_bind_transform: Transform,

    pub fn init(name: []const u8, parent: BoneIndex) Bone {
        return .{
            .name = name,
            .parent = parent,
            .local_bind_transform = Transform.init(),
        };
    }

    pub fn isRoot(self: Bone) bool {
        return self.parent == NO_BONE;
    }
};

/// Skeleton containing bone hierarchy and bind pose data
pub const Skeleton = struct {
    allocator: std.mem.Allocator,

    /// All bones in the skeleton
    bones: []Bone,

    /// Map from bone name to index for fast lookup
    bone_names: std.StringHashMap(BoneIndex),

    /// Inverse bind pose matrices (used for skinning)
    /// These transform from mesh space to bone space at bind time
    inverse_bind_matrices: []Mat4,

    /// Root bone indices (skeletons can have multiple roots)
    root_bones: []BoneIndex,

    /// Name of the skeleton (from glTF skin name or generated)
    name: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, bone_count: usize) !Self {
        const bones = try allocator.alloc(Bone, bone_count);
        const inverse_bind_matrices = try allocator.alloc(Mat4, bone_count);

        // Initialize to identity
        for (bones) |*bone| {
            bone.* = Bone.init("", NO_BONE);
        }
        for (inverse_bind_matrices) |*mat| {
            mat.* = Mat4.identity();
        }

        return .{
            .allocator = allocator,
            .bones = bones,
            .bone_names = std.StringHashMap(BoneIndex).init(allocator),
            .inverse_bind_matrices = inverse_bind_matrices,
            .root_bones = &.{},
            .name = "",
        };
    }

    pub fn deinit(self: *Self) void {
        // Free bone name strings if we own them
        for (self.bones) |bone| {
            if (bone.name.len > 0) {
                self.allocator.free(bone.name);
            }
        }
        self.allocator.free(self.bones);
        self.allocator.free(self.inverse_bind_matrices);

        if (self.root_bones.len > 0) {
            self.allocator.free(self.root_bones);
        }

        if (self.name.len > 0) {
            self.allocator.free(self.name);
        }

        self.bone_names.deinit();
    }

    /// Set bone data at the given index
    pub fn setBone(self: *Self, index: BoneIndex, name: []const u8, parent: BoneIndex, local_transform: Transform) !void {
        if (index >= self.bones.len) return error.BoneIndexOutOfBounds;

        // Store a copy of the name
        const name_copy = try self.allocator.dupe(u8, name);

        self.bones[index] = .{
            .name = name_copy,
            .parent = parent,
            .local_bind_transform = local_transform,
        };

        try self.bone_names.put(name_copy, index);
    }

    /// Set the inverse bind matrix for a bone
    pub fn setInverseBindMatrix(self: *Self, index: BoneIndex, matrix: Mat4) void {
        if (index < self.inverse_bind_matrices.len) {
            self.inverse_bind_matrices[index] = matrix;
        }
    }

    /// Get bone index by name
    pub fn getBoneIndex(self: *const Self, name: []const u8) ?BoneIndex {
        return self.bone_names.get(name);
    }

    /// Get bone by index
    pub fn getBone(self: *const Self, index: BoneIndex) ?*const Bone {
        if (index >= self.bones.len) return null;
        return &self.bones[index];
    }

    /// Number of bones in the skeleton
    pub fn boneCount(self: *const Self) usize {
        return self.bones.len;
    }

    /// Compute root bones (bones with no parent)
    pub fn computeRootBones(self: *Self) !void {
        var root_count: usize = 0;
        for (self.bones) |bone| {
            if (bone.parent == NO_BONE) {
                root_count += 1;
            }
        }

        if (self.root_bones.len > 0) {
            self.allocator.free(self.root_bones);
        }

        self.root_bones = try self.allocator.alloc(BoneIndex, root_count);
        var idx: usize = 0;
        for (self.bones, 0..) |bone, i| {
            if (bone.parent == NO_BONE) {
                self.root_bones[idx] = @intCast(i);
                idx += 1;
            }
        }
    }

    /// Compute world transforms from local pose transforms
    /// local_pose: current local transforms for each bone (animated)
    /// out_world: output world transforms for each bone
    pub fn computeWorldTransforms(
        self: *const Self,
        local_pose: []const Transform,
        out_world: []Mat4,
    ) void {
        std.debug.assert(local_pose.len == self.bones.len);
        std.debug.assert(out_world.len == self.bones.len);

        // Process bones in order (assumes parent indices are always less than child indices)
        for (self.bones, 0..) |bone, i| {
            const local_matrix = local_pose[i].getMatrix();

            if (bone.parent == NO_BONE) {
                // Root bone - local is world
                out_world[i] = local_matrix;
            } else {
                // Child bone - multiply by parent's world transform
                out_world[i] = out_world[bone.parent].mul(local_matrix);
            }
        }
    }

    /// Compute skinning matrices from world transforms
    /// These are the final matrices sent to the GPU shader:
    /// skinning_matrix = world_transform * inverse_bind_matrix
    pub fn computeSkinningMatrices(
        self: *const Self,
        world_transforms: []const Mat4,
        out_skinning: []Mat4,
    ) void {
        std.debug.assert(world_transforms.len == self.bones.len);
        std.debug.assert(out_skinning.len == self.bones.len);

        for (0..self.bones.len) |i| {
            out_skinning[i] = world_transforms[i].mul(self.inverse_bind_matrices[i]);
        }
    }

    /// Get the bind pose as an array of Transforms
    pub fn getBindPose(self: *const Self, out_pose: []Transform) void {
        std.debug.assert(out_pose.len == self.bones.len);
        for (self.bones, 0..) |bone, i| {
            out_pose[i] = bone.local_bind_transform;
        }
    }
};

test "skeleton basic operations" {
    const allocator = std.testing.allocator;

    var skeleton = try Skeleton.init(allocator, 3);
    defer skeleton.deinit();

    // Set up a simple hierarchy: root -> child1 -> child2
    try skeleton.setBone(0, "root", NO_BONE, Transform.init());
    try skeleton.setBone(1, "child1", 0, Transform.withPosition(Vec3.init(1, 0, 0)));
    try skeleton.setBone(2, "child2", 1, Transform.withPosition(Vec3.init(0, 1, 0)));

    try skeleton.computeRootBones();

    try std.testing.expectEqual(@as(usize, 1), skeleton.root_bones.len);
    try std.testing.expectEqual(@as(BoneIndex, 0), skeleton.root_bones[0]);
    try std.testing.expectEqual(@as(?BoneIndex, 1), skeleton.getBoneIndex("child1"));
}
