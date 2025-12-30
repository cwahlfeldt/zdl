const std = @import("std");
const Scene = @import("../scene.zig").Scene;
const RenderFrame = @import("../../engine/engine.zig").RenderFrame;
const Engine = @import("../../engine/engine.zig").Engine;
const Uniforms = @import("../../gpu/uniforms.zig").Uniforms;
const LightUniforms = @import("../../gpu/uniforms.zig").LightUniforms;
const MaterialUniforms = @import("../../resources/material.zig").MaterialUniforms;
const Material = @import("../../resources/material.zig").Material;
const math = @import("../../math/math.zig");
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;

const components = @import("../components/components.zig");
const TransformComponent = components.TransformComponent;
const CameraComponent = components.CameraComponent;
const MeshRendererComponent = components.MeshRendererComponent;
const LightComponent = components.LightComponent;

/// Render system that draws all MeshRenderer components in the scene.
pub const RenderSystem = struct {
    /// Render all mesh renderers in the scene using the active camera.
    /// Automatically uses PBR pipeline for entities with materials, legacy pipeline otherwise.
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

        // Check if PBR is available
        const has_pbr = frame.engine.hasPBR();

        // If PBR available, update light uniforms from scene
        if (has_pbr) {
            updateLightsFromScene(scene, frame.engine, cam_pos);
        }

        // Track current pipeline state: null = none bound, false = legacy, true = pbr
        var current_pipeline_is_pbr: ?bool = null;

        // Iterate all mesh renderers
        const renderers = scene.getMeshRenderers();

        for (renderers.items, renderers.entities) |*renderer, entity| {
            if (!renderer.enabled) continue;

            // Get world transform
            const transform = scene.getComponent(TransformComponent, entity) orelse continue;

            // Decide which pipeline to use
            const use_pbr = has_pbr and renderer.hasMaterial();

            if (use_pbr) {
                // PBR rendering path
                if (current_pipeline_is_pbr != true) {
                    _ = frame.bindPBRPipeline();
                    current_pipeline_is_pbr = true;
                }

                const material = renderer.material.?;

                // Push MVP uniforms
                const uniforms = Uniforms.init(transform.world_matrix, view, projection);
                frame.pushUniforms(uniforms);

                // Push material uniforms
                const mat_uniforms = MaterialUniforms.fromMaterial(material);
                frame.pushMaterialUniforms(mat_uniforms);

                // Push light uniforms
                frame.pushLightUniforms(frame.engine.light_uniforms);

                // Bind textures
                frame.bindPBRTextures(material);

                // Draw mesh
                frame.drawMesh(renderer.mesh.*);
            } else {
                // Legacy rendering path
                if (current_pipeline_is_pbr != false) {
                    frame.bindPipeline();
                    current_pipeline_is_pbr = false;
                }

                // Bind texture
                if (renderer.texture) |tex| {
                    frame.bindTexture(tex.*);
                } else {
                    frame.bindDefaultTexture();
                }

                // Push uniforms with world matrix
                const uniforms = Uniforms.init(transform.world_matrix, view, projection);
                frame.pushUniforms(uniforms);

                // Draw mesh
                frame.drawMesh(renderer.mesh.*);
            }
        }
    }

    /// Collect lights from the scene and update engine's light uniforms.
    fn updateLightsFromScene(scene: *Scene, engine: *Engine, camera_pos: Vec3) void {
        // Reset light uniforms
        engine.light_uniforms.clearDynamicLights();
        engine.light_uniforms.setCameraPosition(camera_pos);

        // Get all lights from scene
        const lights_data = scene.getLights();

        // Iterate all lights
        for (lights_data.items, lights_data.entities) |light, entity| {
            const transform = scene.getComponent(TransformComponent, entity) orelse continue;

            // Get light position from world matrix
            const pos = Vec3.init(
                transform.world_matrix.data[12],
                transform.world_matrix.data[13],
                transform.world_matrix.data[14],
            );

            // Get light direction (forward vector, negated Z axis)
            const dir = Vec3.init(
                -transform.world_matrix.data[8],
                -transform.world_matrix.data[9],
                -transform.world_matrix.data[10],
            );

            switch (light.light_type) {
                .directional => {
                    // Directional light uses direction only
                    engine.light_uniforms.setDirectionalLight(dir, light.color, light.intensity);
                },
                .point => {
                    _ = engine.light_uniforms.addPointLight(pos, light.range, light.color, light.intensity);
                },
                .spot => {
                    _ = engine.light_uniforms.addSpotLight(
                        pos,
                        dir,
                        light.range,
                        light.color,
                        light.intensity,
                        light.inner_angle,
                        light.outer_angle,
                    );
                },
            }
        }
    }
};
