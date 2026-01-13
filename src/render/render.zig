//! Render module - handles all rendering concerns
//!
//! This module provides rendering management including:
//! - GPU device and pipeline management
//! - Frame lifecycle (begin/end)
//! - PBR and IBL rendering support
//! - Skybox rendering

pub const RenderManager = @import("render_manager.zig").RenderManager;
pub const RenderFrame = @import("render_manager.zig").RenderFrame;
pub const Color = @import("render_manager.zig").Color;
