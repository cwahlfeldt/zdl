//! Core module - foundational types with minimal dependencies
//!
//! This module contains common types that can be used by any layer
//! without introducing circular dependencies. All types here only
//! depend on the standard library.

// Handle types for resource management
pub const handles = @import("handles.zig");
pub const Handle = handles.Handle;
pub const Slot = handles.Slot;
pub const Storage = handles.Storage;

// Common handle types
pub const MeshHandle = handles.MeshHandle;
pub const TextureHandle = handles.TextureHandle;
pub const MaterialHandle = handles.MaterialHandle;
pub const AnimationHandle = handles.AnimationHandle;
pub const SkeletonHandle = handles.SkeletonHandle;

// Tests
test {
    _ = handles;
}
