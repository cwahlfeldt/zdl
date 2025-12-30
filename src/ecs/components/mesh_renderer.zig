const Mesh = @import("../../resources/mesh.zig").Mesh;
const Texture = @import("../../resources/texture.zig").Texture;
const Material = @import("../../resources/material.zig").Material;

/// Mesh renderer component for rendering 3D geometry.
/// References a mesh and optional texture/material for rendering.
pub const MeshRendererComponent = struct {
    /// Pointer to mesh data (not owned by this component)
    mesh: *Mesh,
    /// Optional texture override (null uses default white texture).
    /// Note: If material is set, material textures take precedence.
    texture: ?*const Texture,
    /// Optional PBR material for advanced rendering.
    /// When set, enables PBR pipeline with metallic-roughness workflow.
    material: ?Material,
    /// Whether this renderer is enabled
    enabled: bool,

    /// Create a mesh renderer with no texture or material.
    pub fn init(mesh: *Mesh) MeshRendererComponent {
        return .{
            .mesh = mesh,
            .texture = null,
            .material = null,
            .enabled = true,
        };
    }

    /// Create a mesh renderer with a texture (legacy mode, no PBR).
    pub fn withTexture(mesh: *Mesh, texture: *const Texture) MeshRendererComponent {
        return .{
            .mesh = mesh,
            .texture = texture,
            .material = null,
            .enabled = true,
        };
    }

    /// Create a mesh renderer with a PBR material.
    pub fn withMaterial(mesh: *Mesh, material: Material) MeshRendererComponent {
        return .{
            .mesh = mesh,
            .texture = null,
            .material = material,
            .enabled = true,
        };
    }

    /// Enable or disable rendering.
    pub fn setEnabled(self: *MeshRendererComponent, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Set the texture (null for default white texture).
    pub fn setTexture(self: *MeshRendererComponent, texture: ?*const Texture) void {
        self.texture = texture;
    }

    /// Set the PBR material.
    pub fn setMaterial(self: *MeshRendererComponent, material: ?Material) void {
        self.material = material;
    }

    /// Set the mesh.
    pub fn setMesh(self: *MeshRendererComponent, mesh: *Mesh) void {
        self.mesh = mesh;
    }

    /// Check if this renderer uses PBR material.
    pub fn hasMaterial(self: MeshRendererComponent) bool {
        return self.material != null;
    }
};
