const std = @import("std");
const Scene = @import("../scene.zig").Scene;
const Entity = @import("../entity.zig").Entity;
const RenderFrame = @import("../../render/render_manager.zig").RenderFrame;
const RenderManager = @import("../../render/render_manager.zig").RenderManager;
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
    pipeline_bound: bool,
};

    /// Context for light update iteration
    const LightContext = struct {
        manager: *RenderManager,
        camera_pos: Vec3,
    };

    /// Convert a transform orientation into a light direction (engine uses -Z forward).
    fn getLightDirection(transform: *const TransformComponent) Vec3 {
        const forward = Vec3.init(
            transform.world_matrix.data[8],
            transform.world_matrix.data[9],
            transform.world_matrix.data[10],
        ).normalize();
        return forward.mul(-1.0);
    }

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

        if (!manager.hasForwardPlus()) {
            std.debug.print("Forward+ renderer not initialized; skipping render.\n", .{});
            return;
        }

        // Update light uniforms from scene
        updateLightsFromScene(scene, manager, cam_pos);

        // Render shadow maps first (if shadows are enabled)
        if (manager.hasShadows()) {
            renderShadowPass(scene, manager, camera, camera_transform, view, projection);
        }

        // Populate the Forward+ light lists
        if (manager.getForwardPlusManager()) |fp| {
            fp.clearLights();
            fp.setViewProjection(view, projection, manager.window_width, manager.window_height, camera.near, camera.far);

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

        // Render skybox first (depth write disabled).
        frame.drawSkybox(view, projection);

        // Iterate all mesh renderers
        var ctx = RenderContext{
            .frame = frame,
            .view = view,
            .projection = projection,
            .pipeline_bound = false,
        };
        scene.iterateMeshRenderers(renderMesh, @ptrCast(&ctx));
    }

    /// Context for finding directional light
    const DirectionalLightContext = struct {
        found: bool = false,
        direction: Vec3 = Vec3.init(0.3, -1.0, 0.3),
    };

    /// Render shadow maps for directional light
    fn renderShadowPass(
        scene: *Scene,
        manager: *RenderManager,
        camera: *const CameraComponent,
        camera_transform: *const TransformComponent,
        view: Mat4,
        projection: Mat4,
    ) void {
        const shadow_mgr = manager.getShadowManager() orelse return;

        // Find directional light in scene
        var dir_light_ctx = DirectionalLightContext{};
        scene.iterateLights(findDirectionalLight, @ptrCast(&dir_light_ctx));
        const dir_light_dir = dir_light_ctx.direction.normalize();

        // Calculate cascade matrices
        shadow_mgr.updateCascades(
            dir_light_dir,
            view,
            projection,
            camera.near,
            camera.far,
        );

        // Render shadow maps
        var mutable_device = manager.device;
        const cmd = mutable_device.acquireCommandBuffer() catch return;
        defer cmd.submit() catch {};

        shadow_mgr.renderShadows(&mutable_device, cmd, scene, renderMeshToShadowMap) catch return;

        _ = camera_transform; // Future use for camera position
    }

    /// Context for shadow rendering iteration
    const ShadowRenderContext = struct {
        cascade_idx: u32,
        cmd: @import("sdl3").gpu.CommandBuffer,
        pass: @import("sdl3").gpu.RenderPass,
        shadow_mgr: *@import("../../render/shadow_manager.zig").ShadowManager,
        scene: *Scene,
    };

    /// Callback to render meshes to shadow map
    fn renderMeshToShadowMap(cascade_idx: u32, cmd: @import("sdl3").gpu.CommandBuffer, pass: @import("sdl3").gpu.RenderPass, shadow_mgr: *@import("../../render/shadow_manager.zig").ShadowManager, scene: *Scene) void {
        var ctx = ShadowRenderContext{
            .cascade_idx = cascade_idx,
            .cmd = cmd,
            .pass = pass,
            .shadow_mgr = shadow_mgr,
            .scene = scene,
        };
        scene.iterateMeshRenderers(renderMeshToShadow, @ptrCast(&ctx));
    }

    /// Callback for rendering a single mesh to shadow map
    fn renderMeshToShadow(entity: Entity, transform: *TransformComponent, renderer: *MeshRendererComponent, userdata: *anyopaque) void {
        _ = entity;
        const ctx: *ShadowRenderContext = @ptrCast(@alignCast(userdata));

        if (!renderer.enabled) return;

        // Get the mesh
        const mesh = renderer.getMesh() orelse return;
        if (mesh.vertex_buffer == null) return; // Skip if not uploaded to GPU

        // Render the mesh to the shadow map
        ctx.shadow_mgr.renderMeshToShadowMap(ctx.cmd, ctx.pass, mesh.*, transform.world_matrix, ctx.cascade_idx) catch return;
    }

    /// Callback to find the directional light
    fn findDirectionalLight(entity: Entity, transform: *TransformComponent, light: *LightComponent, userdata: *anyopaque) void {
        _ = entity;
        const ctx: *DirectionalLightContext = @ptrCast(@alignCast(userdata));

        if (light.light_type == .directional and !ctx.found) {
            ctx.direction = getLightDirection(transform);
            ctx.found = true;
        }
    }

    /// Callback for rendering a single mesh
    fn renderMesh(entity: Entity, transform: *TransformComponent, renderer: *MeshRendererComponent, userdata: *anyopaque) void {
        _ = entity;
        const ctx: *RenderContext = @ptrCast(@alignCast(userdata));

        if (!renderer.enabled) return;

        // Get the mesh from cached pointer (set by legacy API or resolved from handle)
        const mesh = renderer.getMesh() orelse return;

        if (!ctx.pipeline_bound) {
            if (!ctx.frame.bindForwardPlusPipeline()) return;
            ctx.frame.bindShadowResources(); // Bind shadow map textures if available
            ctx.pipeline_bound = true;
        }

        var material = renderer.material orelse Material.init();
        if (material.base_color_texture == null) {
            if (renderer.getTexture()) |tex| {
                material.base_color_texture = tex;
            }
        }

        ctx.frame.drawMeshForwardPlus(mesh.*, material, transform.world_matrix, ctx.view, ctx.projection);
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
        const light_dir = getLightDirection(transform);

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
        const light_dir = getLightDirection(transform);

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
