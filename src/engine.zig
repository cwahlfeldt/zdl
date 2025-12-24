// ZDL Engine - 3D Game Engine
// Main module export

// Core Engine
pub const Engine = @import("engine/engine.zig").Engine;
pub const EngineConfig = @import("engine/engine.zig").EngineConfig;
pub const RenderFrame = @import("engine/engine.zig").RenderFrame;
pub const Color = @import("engine/engine.zig").Color;
pub const Application = @import("engine/application.zig");
pub const Context = Application.Context;

// Subsystems
pub const Input = @import("input/input.zig").Input;
pub const Camera = @import("camera.zig").Camera;

// Math
pub const math = @import("math/math.zig");
pub const Vec2 = math.Vec2;
pub const Vec3 = math.Vec3;
pub const Vec4 = math.Vec4;
pub const Mat4 = math.Mat4;
pub const Quat = math.Quat;

// 3D Graphics
pub const Transform = @import("transform.zig").Transform;
pub const Mesh = @import("resources/mesh.zig").Mesh;
pub const Vertex3D = @import("resources/mesh.zig").Vertex3D;
pub const primitives = @import("resources/primitives.zig");
pub const Uniforms = @import("gpu/uniforms.zig").Uniforms;

// Resources
pub const Texture = @import("resources/texture.zig").Texture;

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
pub const LightComponent = ecs.LightComponent;
pub const LightType = ecs.LightType;
