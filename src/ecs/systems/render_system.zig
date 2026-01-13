const std = @import("std");
const Scene = @import("../scene.zig").Scene;
const Entity = @import("../entity.zig").Entity;
const RenderFrame = @import("../../render/render_manager.zig").RenderFrame;
const RenderManager = @import("../../render/render_manager.zig").RenderManager;
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

/// Pipeline mode for rendering
const PipelineMode = enum {
    legacy,
    pbr,
    forward_plus,
};

/// Context for rendering iteration
const RenderContext = struct {
    frame: *RenderFrame,
    view: Mat4,
    projection: Mat4,
    has_pbr: bool,
    has_forward_plus: bool,
    current_pipeline: ?PipelineMode,
};

/// Context for light update iteration
const LightContext = struct {
    manager: *RenderManager,
    camera_pos: Vec3,
};

/// Forward+ manager import
const ForwardPlusManager = @import("../../render/forward_plus.zig").ForwardPlusManager;

/// Context for Forward+ light iteration
const ForwardPlusLightContext = struct {
    fp: *ForwardPlusManager,
};

/// Render system that draws all MeshRenderer components in the scene.
/// Now decoupled from Engine - uses RenderManager instead.
pub const RenderSystem = struct {
    /// Render all mesh renderers in the scene using the active camera.
    /// Automatically uses PBR pipeline for entities with materials, legacy pipeline otherwise.
    /// This overload gets the manager from the frame for backwards compatibility.
    pub fn render(scene: *Scene, frame: *RenderFrame) void {
        renderWithManager(scene, frame, frame.manager);
    }

    /// Render all mesh renderers with an explicit RenderManager reference.
    pub fn renderWithManager(scene: *Scene, frame: *RenderFrame, manager: *RenderManager) void {
        // Get active camera
        const camera_entity = scene.getActiveCamera();
        if (!camera_entity.isValid()) return;

        const camera = scene.getComponent(CameraComponent, camera_entity) orelse return;
        const camera_transform = scene.getComponent(TransformComponent, camera_entity) orelse return;

        // Compute view and projection matrices
        const width: f32 = @floatFromInt(manager.window_width);
        const height: f32 = @floatFromInt(manager.window_height);
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

        // Check what features are available
        const has_pbr = manager.hasPBR();
        const has_forward_plus = manager.hasForwardPlus();

        // Update light uniforms from scene
        if (has_pbr or has_forward_plus) {
            updateLightsFromScene(scene, manager, cam_pos);
        }

        // If Forward+ is enabled, also populate the Forward+ light lists
        if (has_forward_plus) {
            if (manager.getForwardPlusManager()) |fp| {
                fp.clearLights();
                fp.setViewProjection(view, projection, manager.window_width, manager.window_height);

                // Add lights to Forward+ manager
                var fp_ctx = ForwardPlusLightContext{
                    .fp = fp,
                };
                scene.iterateLights(addForwardPlusLight, @ptrCast(&fp_ctx));

                const cull_cmd = manager.device.acquireCommandBuffer() catch |err| {
                    std.debug.print("Forward+ cull: acquire command buffer failed: {}\n", .{err});
                    return;
                };
                if (fp.cullLights(&manager.device, cull_cmd)) |_| {
                    cull_cmd.submit() catch |err| {
                        std.debug.print("Forward+ cull: submit failed: {}\n", .{err});
                    };
                } else |err| {
                    std.debug.print("Forward+ cull failed: {}\n", .{err});
                    _ = cull_cmd.submit() catch {};
                }
            }
        }

        // Render skybox first (depth write disabled).
        frame.drawSkybox(view, projection);

        // Iterate all mesh renderers
        var ctx = RenderContext{
            .frame = frame,
            .view = view,
            .projection = projection,
            .has_pbr = has_pbr,
            .has_forward_plus = has_forward_plus,
            .current_pipeline = null,
        };
        scene.iterateMeshRenderers(renderMesh, @ptrCast(&ctx));
    }

    /// Callback for rendering a single mesh
    fn renderMesh(entity: Entity, transform: *TransformComponent, renderer: *MeshRendererComponent, userdata: *anyopaque) void {
        _ = entity;
        const ctx: *RenderContext = @ptrCast(@alignCast(userdata));

        if (!renderer.enabled) return;

        // Get the mesh from cached pointer (set by legacy API or resolved from handle)
        const mesh = renderer.getMesh() orelse return;

        // Decide which pipeline to use
        const has_material = renderer.hasMaterial();
        const use_forward_plus = ctx.has_forward_plus and has_material;
        const use_pbr = ctx.has_pbr and has_material and !use_forward_plus;

        if (use_forward_plus) {
            // Forward+ rendering path (clustered lighting)
            if (ctx.current_pipeline != .forward_plus) {
                _ = ctx.frame.bindForwardPlusPipeline();
                ctx.current_pipeline = .forward_plus;
            }

            var material = renderer.material.?;
            if (material.base_color_texture == null) {
                if (renderer.getTexture()) |tex| {
                    material.base_color_texture = tex;
                }
            }

            ctx.frame.drawMeshForwardPlus(mesh.*, material, transform.world_matrix, ctx.view, ctx.projection);
        } else if (use_pbr) {
            // PBR rendering path
            if (ctx.current_pipeline != .pbr) {
                _ = ctx.frame.bindPBRPipeline();
                ctx.current_pipeline = .pbr;
            }

            var material = renderer.material.?;
            if (material.base_color_texture == null) {
                if (renderer.getTexture()) |tex| {
                    material.base_color_texture = tex;
                }
            }

            // Push MVP uniforms
            const uniforms = Uniforms.init(transform.world_matrix, ctx.view, ctx.projection);
            ctx.frame.pushUniforms(uniforms);

            // Push material uniforms
            const mat_uniforms = MaterialUniforms.fromMaterial(material);
            ctx.frame.pushMaterialUniforms(mat_uniforms);

            // Push light uniforms (from manager, not engine)
            ctx.frame.pushLightUniforms(ctx.frame.manager.light_uniforms);

            // Bind textures
            ctx.frame.bindPBRTextures(material);

            // Bind IBL textures (slots 5-7)
            ctx.frame.bindIBLTextures();

            // Draw mesh
            ctx.frame.drawMesh(mesh.*);
        } else {
            // Legacy rendering path
            if (ctx.current_pipeline != .legacy) {
                ctx.frame.bindPipeline();
                ctx.current_pipeline = .legacy;
            }

            // Bind texture
            if (renderer.getTexture()) |tex| {
                ctx.frame.bindTexture(tex.*);
            } else {
                ctx.frame.bindDefaultTexture();
            }

            // Push uniforms with world matrix
            const uniforms = Uniforms.init(transform.world_matrix, ctx.view, ctx.projection);
            ctx.frame.pushUniforms(uniforms);

            // Draw mesh
            ctx.frame.drawMesh(mesh.*);
        }
    }

    /// Collect lights from the scene and update manager's light uniforms.
    fn updateLightsFromScene(scene: *Scene, manager: *RenderManager, camera_pos: Vec3) void {
        // Reset light uniforms
        manager.light_uniforms.clearDynamicLights();
        manager.light_uniforms.setCameraPosition(camera_pos);

        // Iterate all lights
        var ctx = LightContext{
            .manager = manager,
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
                ctx.manager.light_uniforms.setDirectionalLight(light_dir, light.color, light.intensity);
            },
            .point => {
                _ = ctx.manager.light_uniforms.addPointLight(light_pos, light.range, light.color, light.intensity);
            },
            .spot => {
                _ = ctx.manager.light_uniforms.addSpotLight(
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

    /// Callback for adding a light to Forward+ manager
    fn addForwardPlusLight(entity: Entity, transform: *TransformComponent, light: *LightComponent, userdata: *anyopaque) void {
        _ = entity;
        const ctx: *ForwardPlusLightContext = @ptrCast(@alignCast(userdata));

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

        // Add light based on type (Forward+ handles point and spot lights)
        switch (light.light_type) {
            .directional => {
                // Directional lights are handled via uniforms, not clustered
            },
            .point => {
                ctx.fp.addPointLight(light_pos, light.range, light.color, light.intensity) catch {};
            },
            .spot => {
                ctx.fp.addSpotLight(
                    light_pos,
                    light.range,
                    light_dir,
                    light.outer_angle,
                    light.inner_angle,
                    light.color,
                    light.intensity,
                ) catch {};
            },
        }
    }
};
