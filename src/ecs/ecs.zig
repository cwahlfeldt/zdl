// ECS module exports (Flecs-based)

// Core
pub const Entity = @import("entity.zig").Entity;
pub const Scene = @import("scene.zig").Scene;

// Components
pub const components = @import("components/components.zig");
pub const Transform = components.Transform;
pub const TransformComponent = components.TransformComponent;
pub const CameraComponent = components.CameraComponent;
pub const MeshRendererComponent = components.MeshRendererComponent;
pub const LightComponent = components.LightComponent;
pub const LightType = components.LightType;
pub const FpvCameraController = components.FpvCameraController;

// Systems
pub const systems = @import("systems/systems.zig");
pub const RenderSystem = systems.RenderSystem;
