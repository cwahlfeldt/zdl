const std = @import("std");
const Scene = @import("../scene.zig").Scene;
const RenderFrame = @import("../../engine/engine.zig").RenderFrame;
const Engine = @import("../../engine/engine.zig").Engine;
const Uniforms = @import("../../gpu/uniforms.zig").Uniforms;
const Mat4 = @import("../../math/math.zig").Mat4;

const components = @import("../components/components.zig");
const TransformComponent = components.TransformComponent;
const CameraComponent = components.CameraComponent;
const MeshRendererComponent = components.MeshRendererComponent;

/// Render system that draws all MeshRenderer components in the scene.
pub const RenderSystem = struct {
    /// Render all mesh renderers in the scene using the active camera.
    pub fn render(scene: *Scene, frame: *RenderFrame) void {
        // Get active camera
        const camera_entity = scene.getActiveCamera();
        if (!camera_entity.isValid()) return;

        const camera = scene.getComponent(CameraComponent, camera_entity) orelse return;
        const camera_transform = scene.getComponent(TransformComponent, camera_entity) orelse return;

        // Compute view and projection matrices
        const width: f32 = @floatFromInt(frame.engine.window_width);
        const height: f32 = @floatFromInt(frame.engine.window_height);
        const aspect = width / height;

        const view = CameraComponent.getViewMatrix(camera_transform.world_matrix);
        const projection = camera.getProjectionMatrix(aspect);

        // Bind pipeline once
        frame.bindPipeline();

        // Iterate all mesh renderers
        const renderers = scene.getMeshRenderers();

        for (renderers.items, renderers.entities) |*renderer, entity| {
            if (!renderer.enabled) continue;

            // Get world transform
            const transform = scene.getComponent(TransformComponent, entity) orelse continue;

            // Bind texture
            if (renderer.texture) |tex| {
                frame.bindTexture(tex.*);
            } else {
                frame.bindDefaultTexture();
            }

            // Push uniforms with world matrix
            const uniforms = Uniforms.init(
                transform.world_matrix,
                view,
                projection,
            );
            frame.pushUniforms(uniforms);

            // Draw mesh
            frame.drawMesh(renderer.mesh.*);
        }
    }
};
