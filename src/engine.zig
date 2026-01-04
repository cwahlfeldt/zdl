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
pub const InputDevice = @import("input/input.zig").InputDevice;

// Gamepad
pub const Gamepad = @import("input/input.zig").Gamepad;
pub const GamepadManager = @import("input/input.zig").GamepadManager;
pub const GamepadButton = @import("input/input.zig").GamepadButton;
pub const GamepadAxis = @import("input/input.zig").GamepadAxis;
pub const GamepadType = @import("input/input.zig").GamepadType;
pub const HapticPresets = @import("input/input.zig").HapticPresets;
pub const StickValue = @import("input/input.zig").StickValue;

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
pub const LightUniforms = @import("gpu/uniforms.zig").LightUniforms;

// Resources
pub const Texture = @import("resources/texture.zig").Texture;

// Materials (PBR)
pub const Material = @import("resources/material.zig").Material;
pub const MaterialUniforms = @import("resources/material.zig").MaterialUniforms;
pub const AlphaMode = @import("resources/material.zig").AlphaMode;

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
pub const LightComponent = ecs.LightComponent;
pub const LightType = ecs.LightType;

// Scene Serialization
pub const serialization = @import("serialization/serialization.zig");
pub const SceneSerializer = serialization.SceneSerializer;

// Debug and Profiling
pub const debug = @import("debug/debug.zig");
pub const DebugDraw = debug.DebugDraw;
pub const Profiler = debug.Profiler;
pub const StatsOverlay = debug.StatsOverlay;
pub const scopedZone = debug.scopedZone;

// Animation
pub const animation = @import("animation/animation.zig");
pub const Skeleton = animation.Skeleton;
pub const AnimationClip = animation.AnimationClip;
pub const Animator = animation.Animator;
pub const AnimatorComponent = animation.AnimatorComponent;
pub const AnimationSystem = animation.AnimationSystem;
pub const SkinnedMesh = animation.SkinnedMesh;
pub const SkinnedVertex = animation.SkinnedVertex;
pub const BoneMatrixBuffer = animation.BoneMatrixBuffer;

// UI System
pub const ui = @import("ui/ui.zig");
pub const UIContext = ui.UIContext;
pub const UIRenderer = ui.UIRenderer;
pub const Font = ui.Font;
pub const Theme = ui.Theme;
pub const Style = ui.Style;
pub const Rect = ui.Rect;

// Scripting
pub const scripting = @import("scripting/scripting.zig");
pub const ScriptComponent = scripting.ScriptComponent;
pub const ScriptSystem = scripting.ScriptSystem;
