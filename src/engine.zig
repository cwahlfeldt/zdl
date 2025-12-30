// ZDL Engine - 3D Game Engine
// Main module export

// Core Engine
pub const Engine = @import("engine/engine.zig").Engine;
pub const EngineConfig = @import("engine/engine.zig").EngineConfig;
pub const RenderFrame = @import("engine/engine.zig").RenderFrame;
pub const Color = @import("engine/engine.zig").Color;

// Subsystems
pub const Input = @import("input/input.zig").Input;
pub const MouseButton = @import("input/input.zig").MouseButton;

// Math
pub const math = @import("math/math.zig");
pub const Vec2 = math.Vec2;
pub const Vec3 = math.Vec3;
pub const Vec4 = math.Vec4;
pub const Mat4 = math.Mat4;
pub const Quat = math.Quat;

// 3D Graphics
pub const Mesh = @import("resources/mesh.zig").Mesh;
pub const Vertex3D = @import("resources/mesh.zig").Vertex3D;
pub const primitives = @import("resources/primitives.zig");
pub const Uniforms = @import("gpu/uniforms.zig").Uniforms;

// Resources
pub const Texture = @import("resources/texture.zig").Texture;

// Asset Management
pub const AssetManager = @import("assets/asset_manager.zig").AssetManager;
pub const gltf = @import("assets/asset_manager.zig").gltf;
pub const GLTFLoader = gltf.GLTFLoader;
pub const GLTFAsset = gltf.GLTFAsset;

// Audio
pub const audio = @import("audio/audio.zig");
pub const Audio = audio.Audio;
pub const Sound = audio.Sound;

// ECS (Entity Component System)
pub const ecs = @import("ecs/ecs.zig");
pub const Scene = ecs.Scene;
pub const Entity = ecs.Entity;
pub const TransformComponent = ecs.TransformComponent;
pub const CameraComponent = ecs.CameraComponent;
pub const MeshRendererComponent = ecs.MeshRendererComponent;
pub const FpvCameraController = ecs.FpvCameraController;

// Scene Serialization
pub const serialization = @import("serialization/serialization.zig");
pub const SceneSerializer = serialization.SceneSerializer;

// Debug and Profiling
pub const debug = @import("debug/debug.zig");
pub const DebugDraw = debug.DebugDraw;
pub const Profiler = debug.Profiler;
pub const StatsOverlay = debug.StatsOverlay;
pub const scopedZone = debug.scopedZone;
