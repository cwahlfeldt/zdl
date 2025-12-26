// ECS module exports

// Core
pub const Entity = @import("entity.zig").Entity;
pub const EntityManager = @import("entity.zig").EntityManager;
pub const Scene = @import("scene.zig").Scene;

// Components
pub const components = @import("components/components.zig");
pub const Transform = components.Transform;
pub const TransformComponent = components.TransformComponent;
pub const CameraComponent = components.CameraComponent;
pub const MeshRendererComponent = components.MeshRendererComponent;
pub const LightComponent = components.LightComponent;
pub const LightType = components.LightType;
pub const FpsCameraController = components.FpsCameraController;

// Systems
pub const systems = @import("systems/systems.zig");
pub const RenderSystem = systems.RenderSystem;

// Generic storage (for advanced use)
pub const ComponentStorage = @import("component_storage.zig").ComponentStorage;
