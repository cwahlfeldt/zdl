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

        // Get camera position and forward direction from world matrix
        const Vec3 = @import("../../math/math.zig").Vec3;
        const cam_pos = Vec3.init(
            camera_transform.world_matrix.data[12],
            camera_transform.world_matrix.data[13],
            camera_transform.world_matrix.data[14],
        );
        // Forward direction is the negated Z column of the world matrix (OpenGL convention)
        const cam_forward = Vec3.init(
            -camera_transform.world_matrix.data[8],
            -camera_transform.world_matrix.data[9],
            -camera_transform.world_matrix.data[10],
        );
        const cam_target = cam_pos.add(cam_forward);
        const cam_up = Vec3.init(0, 1, 0);

        const view = Mat4.lookAt(cam_pos, cam_target, cam_up);
        const projection = camera.getProjectionMatrix(aspect);

        // Iterate all mesh renderers
        const renderers = scene.getMeshRenderers();

        for (renderers.items, renderers.entities) |*renderer, entity| {
            if (!renderer.enabled) continue;

            // Get world transform
            const transform = scene.getComponent(TransformComponent, entity) orelse continue;

            // Bind pipeline for each mesh
            frame.bindPipeline();

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
