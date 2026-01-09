const Mesh = @import("../../resources/mesh.zig").Mesh;
const Texture = @import("../../resources/texture.zig").Texture;
const Material = @import("../../resources/material.zig").Material;
const asset_handle = @import("../../assets/asset_handle.zig");
pub const MeshHandle = asset_handle.MeshHandle;
pub const TextureHandle = asset_handle.TextureHandle;

/// Mesh renderer component for rendering 3D geometry.
/// Uses asset handles for safe references to mesh and texture data.
/// Handles prevent dangling pointers when assets are unloaded or reloaded.
pub const MeshRendererComponent = struct {
    /// Handle to mesh data (validated through AssetManager)
    mesh_handle: MeshHandle,
    /// Optional texture handle override (invalid handle uses default white texture).
    /// Note: If material is set, material textures take precedence.
    texture_handle: TextureHandle,
    /// Optional PBR material for advanced rendering.
    /// When set, enables PBR pipeline with metallic-roughness workflow.
    material: ?Material,
    /// Whether this renderer is enabled
    enabled: bool,

    // Legacy pointer cache - resolved at render time from handles
    // These are populated by the render system and should not be set directly
    _cached_mesh: ?*Mesh = null,
    _cached_texture: ?*const Texture = null,

    /// Create a mesh renderer with a mesh handle and no texture or material.
    pub fn init(mesh_handle: MeshHandle) MeshRendererComponent {
        return .{
            .mesh_handle = mesh_handle,
            .texture_handle = TextureHandle.invalid,
            .material = null,
            .enabled = true,
            ._cached_mesh = null,
            ._cached_texture = null,
        };
    }

    /// Create a mesh renderer with mesh and texture handles (legacy mode, no PBR).
    pub fn withTexture(mesh_handle: MeshHandle, texture_handle: TextureHandle) MeshRendererComponent {
        return .{
            .mesh_handle = mesh_handle,
            .texture_handle = texture_handle,
            .material = null,
            .enabled = true,
            ._cached_mesh = null,
            ._cached_texture = null,
        };
    }

    /// Create a mesh renderer with a mesh handle and PBR material.
    pub fn withMaterial(mesh_handle: MeshHandle, material: Material) MeshRendererComponent {
        return .{
            .mesh_handle = mesh_handle,
            .texture_handle = TextureHandle.invalid,
            .material = material,
            .enabled = true,
            ._cached_mesh = null,
            ._cached_texture = null,
        };
    }

    // ============================================
    // Legacy API using raw pointers (for compatibility during migration)
    // These create components that store the pointer in the cache field
    // ============================================

    /// Create a mesh renderer from a raw mesh pointer (legacy).
    /// DEPRECATED: Use init(mesh_handle) instead with AssetManager.
    pub fn fromMeshPtr(mesh: *Mesh) MeshRendererComponent {
        return .{
            .mesh_handle = MeshHandle.invalid,
            .texture_handle = TextureHandle.invalid,
            .material = null,
            .enabled = true,
            ._cached_mesh = mesh,
            ._cached_texture = null,
        };
    }

    /// Create a mesh renderer from raw pointers (legacy).
    /// DEPRECATED: Use withTexture(mesh_handle, texture_handle) instead.
    pub fn fromPtrs(mesh: *Mesh, texture: ?*const Texture) MeshRendererComponent {
        return .{
            .mesh_handle = MeshHandle.invalid,
            .texture_handle = TextureHandle.invalid,
            .material = null,
            .enabled = true,
            ._cached_mesh = mesh,
            ._cached_texture = texture,
        };
    }

    /// Create a mesh renderer from raw pointer with material (legacy).
    /// DEPRECATED: Use withMaterial(mesh_handle, material) instead.
    pub fn fromMeshPtrWithMaterial(mesh: *Mesh, material: Material) MeshRendererComponent {
        return .{
            .mesh_handle = MeshHandle.invalid,
            .texture_handle = TextureHandle.invalid,
            .material = material,
            .enabled = true,
            ._cached_mesh = mesh,
            ._cached_texture = null,
        };
    }

    // ============================================
    // Accessor methods
    // ============================================

    /// Enable or disable rendering.
    pub fn setEnabled(self: *MeshRendererComponent, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Set the texture handle (invalid handle for default white texture).
    pub fn setTextureHandle(self: *MeshRendererComponent, texture_handle: TextureHandle) void {
        self.texture_handle = texture_handle;
        self._cached_texture = null; // Invalidate cache
    }

    /// Set the PBR material.
    pub fn setMaterial(self: *MeshRendererComponent, material: ?Material) void {
        self.material = material;
    }

    /// Set the mesh handle.
    pub fn setMeshHandle(self: *MeshRendererComponent, mesh_handle: MeshHandle) void {
        self.mesh_handle = mesh_handle;
        self._cached_mesh = null; // Invalidate cache
    }

    /// Check if this renderer uses PBR material.
    pub fn hasMaterial(self: MeshRendererComponent) bool {
        return self.material != null;
    }

    /// Check if the mesh handle is valid (not invalid sentinel).
    pub fn hasMeshHandle(self: MeshRendererComponent) bool {
        return self.mesh_handle.isValid();
    }

    /// Check if the texture handle is valid.
    pub fn hasTextureHandle(self: MeshRendererComponent) bool {
        return self.texture_handle.isValid();
    }

    /// Get the cached mesh pointer. This is populated by the render system.
    /// Returns null if the handle is stale or the mesh hasn't been resolved.
    pub fn getMesh(self: MeshRendererComponent) ?*Mesh {
        return self._cached_mesh;
    }

    /// Get the cached texture pointer. This is populated by the render system.
    pub fn getTexture(self: MeshRendererComponent) ?*const Texture {
        return self._cached_texture;
    }

    // ============================================
    // Legacy setters (for compatibility)
    // ============================================

    /// Set the texture from a raw pointer (legacy).
    /// DEPRECATED: Use setTextureHandle instead.
    pub fn setTexture(self: *MeshRendererComponent, texture: ?*const Texture) void {
        self._cached_texture = texture;
        self.texture_handle = TextureHandle.invalid;
    }

    /// Set the mesh from a raw pointer (legacy).
    /// DEPRECATED: Use setMeshHandle instead.
    pub fn setMesh(self: *MeshRendererComponent, mesh: *Mesh) void {
        self._cached_mesh = mesh;
        self.mesh_handle = MeshHandle.invalid;
    }

    // ============================================
    // For render system: resolve handles to pointers
    // ============================================

    /// Update cached pointers from handles using the asset manager.
    /// Called by the render system before rendering.
    pub fn resolveHandles(self: *MeshRendererComponent, getMeshFn: *const fn (MeshHandle) ?*Mesh, getTextureFn: *const fn (TextureHandle) ?*const Texture) void {
        // Only resolve if we have valid handles and no cached pointer
        if (self.mesh_handle.isValid() and self._cached_mesh == null) {
            self._cached_mesh = getMeshFn(self.mesh_handle);
        }
        if (self.texture_handle.isValid() and self._cached_texture == null) {
            self._cached_texture = getTextureFn(self.texture_handle);
        }
    }
};

