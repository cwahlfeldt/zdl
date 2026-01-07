const std = @import("std");
const Scene = @import("../scene.zig").Scene;
const Entity = @import("../entity.zig").Entity;
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

/// Context for rendering iteration
const RenderContext = struct {
    frame: *RenderFrame,
    view: Mat4,
    projection: Mat4,
    has_pbr: bool,
    current_pipeline_is_pbr: ?bool,
};

/// Context for light update iteration
const LightContext = struct {
    engine: *Engine,
    camera_pos: Vec3,
};

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

        // Render skybox first (depth write disabled).
        frame.drawSkybox(view, projection);

        // Iterate all mesh renderers
        var ctx = RenderContext{
            .frame = frame,
            .view = view,
            .projection = projection,
            .has_pbr = has_pbr,
            .current_pipeline_is_pbr = null,
        };
        scene.iterateMeshRenderers(renderMesh, @ptrCast(&ctx));
    }

    /// Callback for rendering a single mesh
    fn renderMesh(entity: Entity, transform: *TransformComponent, renderer: *MeshRendererComponent, userdata: *anyopaque) void {
        _ = entity;
        const ctx: *RenderContext = @ptrCast(@alignCast(userdata));

        if (!renderer.enabled) return;

        // Decide which pipeline to use
        const use_pbr = ctx.has_pbr and renderer.hasMaterial();

        if (use_pbr) {
            // PBR rendering path
            if (ctx.current_pipeline_is_pbr != true) {
                _ = ctx.frame.bindPBRPipeline();
                ctx.current_pipeline_is_pbr = true;
            }

            var material = renderer.material.?;
            if (material.base_color_texture == null) {
                if (renderer.texture) |tex| {
                    material.base_color_texture = tex;
                }
            }

            // Push MVP uniforms
            const uniforms = Uniforms.init(transform.world_matrix, ctx.view, ctx.projection);
            ctx.frame.pushUniforms(uniforms);

            // Push material uniforms
            const mat_uniforms = MaterialUniforms.fromMaterial(material);
            ctx.frame.pushMaterialUniforms(mat_uniforms);

            // Push light uniforms
            ctx.frame.pushLightUniforms(ctx.frame.engine.light_uniforms);

            // Bind textures
            ctx.frame.bindPBRTextures(material);

            // Bind IBL textures (slots 5-7)
            ctx.frame.bindIBLTextures();

            // Draw mesh
            ctx.frame.drawMesh(renderer.mesh.*);
        } else {
            // Legacy rendering path
            if (ctx.current_pipeline_is_pbr != false) {
                ctx.frame.bindPipeline();
                ctx.current_pipeline_is_pbr = false;
            }

            // Bind texture
            if (renderer.texture) |tex| {
                ctx.frame.bindTexture(tex.*);
            } else {
                ctx.frame.bindDefaultTexture();
            }

            // Push uniforms with world matrix
            const uniforms = Uniforms.init(transform.world_matrix, ctx.view, ctx.projection);
            ctx.frame.pushUniforms(uniforms);

            // Draw mesh
            ctx.frame.drawMesh(renderer.mesh.*);
        }
    }

    /// Collect lights from the scene and update engine's light uniforms.
    fn updateLightsFromScene(scene: *Scene, engine: *Engine, camera_pos: Vec3) void {
        // Reset light uniforms
        engine.light_uniforms.clearDynamicLights();
        engine.light_uniforms.setCameraPosition(camera_pos);

        // Iterate all lights
        var ctx = LightContext{
            .engine = engine,
            .camera_pos = camera_pos,
        };
        scene.iterateLights(processLight, @ptrCast(&ctx));
    }

    /// Callback for processing a single light
    fn processLight(entity: Entity, transform: *TransformComponent, light: *LightComponent, userdata: *anyopaque) void {
        _ = entity;
        const ctx: *LightContext = @ptrCast(@alignCast(userdata));

        // Get light position from world matrix
        const light_pos = Vec3.init(
            transform.world_matrix.data[12],
            transform.world_matrix.data[13],
            transform.world_matrix.data[14],
        );

        // Get light direction (forward vector)
        const light_dir = Vec3.init(
            transform.world_matrix.data[8],
            transform.world_matrix.data[9],
            transform.world_matrix.data[10],
        ).normalize();

        // Add light based on type
        switch (light.light_type) {
            .directional => {
                ctx.engine.light_uniforms.setDirectionalLight(light_dir, light.color, light.intensity);
            },
            .point => {
                _ = ctx.engine.light_uniforms.addPointLight(light_pos, light.range, light.color, light.intensity);
            },
            .spot => {
                _ = ctx.engine.light_uniforms.addSpotLight(
                    light_pos,
                    light_dir,
                    light.range,
                    light.color,
                    light.intensity,
                    light.inner_angle,
                    light.outer_angle,
                );
            },
        }
    }
};
