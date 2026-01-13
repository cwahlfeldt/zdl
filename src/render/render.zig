//! Render module - handles all rendering concerns
//!
//! This module provides rendering management including:
//! - GPU device and pipeline management
//! - Frame lifecycle (begin/end)
//! - PBR and IBL rendering support
//! - Forward+ clustered rendering
//! - Skybox rendering
//! - Shader loading and caching
//! - Pipeline creation and caching

pub const RenderManager = @import("render_manager.zig").RenderManager;
pub const RenderFrame = @import("render_manager.zig").RenderFrame;
pub const Color = @import("render_manager.zig").Color;

// Shader management
pub const ShaderLibrary = @import("shader_library.zig").ShaderLibrary;
pub const LoadedShader = @import("shader_library.zig").LoadedShader;
pub const ShaderDef = @import("shader_library.zig").ShaderDef;
pub const BuiltinShaders = @import("shader_library.zig").BuiltinShaders;
pub const ShaderFormat = @import("shader_library.zig").ShaderFormat;

// Pipeline management
pub const PipelineCache = @import("pipeline_cache.zig").PipelineCache;
pub const PipelineConfig = @import("pipeline_cache.zig").PipelineConfig;

// Forward+ rendering
pub const ForwardPlusManager = @import("forward_plus.zig").ForwardPlusManager;
pub const ForwardPlusConfig = @import("forward_plus.zig").ForwardPlusConfig;
pub const GPUPointLight = @import("forward_plus.zig").GPUPointLight;
pub const GPUSpotLight = @import("forward_plus.zig").GPUSpotLight;
pub const ClusterUniforms = @import("forward_plus.zig").ClusterUniforms;
