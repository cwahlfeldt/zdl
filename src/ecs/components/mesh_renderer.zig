const Mesh = @import("../../resources/mesh.zig").Mesh;
const Texture = @import("../../resources/texture.zig").Texture;

/// Mesh renderer component for rendering 3D geometry.
/// References a mesh and optional texture for rendering.
pub const MeshRendererComponent = struct {
    /// Pointer to mesh data (not owned by this component)
    mesh: *Mesh,
    /// Optional texture override (null uses default white texture)
    texture: ?*const Texture,
    /// Whether this renderer is enabled
    enabled: bool,

    /// Create a mesh renderer with no texture.
    pub fn init(mesh: *Mesh) MeshRendererComponent {
        return .{
            .mesh = mesh,
            .texture = null,
            .enabled = true,
        };
    }

    /// Create a mesh renderer with a texture.
    pub fn withTexture(mesh: *Mesh, texture: *const Texture) MeshRendererComponent {
        return .{
            .mesh = mesh,
            .texture = texture,
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

    /// Set the mesh.
    pub fn setMesh(self: *MeshRendererComponent, mesh: *Mesh) void {
        self.mesh = mesh;
    }
};
