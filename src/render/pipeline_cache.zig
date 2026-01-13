const std = @import("std");
const sdl = @import("sdl3");

const ShaderLibrary = @import("shader_library.zig").ShaderLibrary;
const LoadedShader = @import("shader_library.zig").LoadedShader;
const BuiltinShaders = @import("shader_library.zig").BuiltinShaders;
const Mesh = @import("../resources/mesh.zig").Mesh;

/// Pipeline configuration for creating graphics pipelines
pub const PipelineConfig = struct {
    /// Pipeline name for caching
    name: []const u8,

    /// Shader to use
    shader: LoadedShader,

    /// Primitive topology
    primitive_type: sdl.gpu.PrimitiveType = .triangle_list,

    /// Rasterizer settings
    cull_mode: sdl.gpu.CullMode = .back,
    front_face: sdl.gpu.FrontFace = .counter_clockwise,
    fill_mode: sdl.gpu.FillMode = .fill,

    /// Depth/stencil settings
    enable_depth_test: bool = true,
    enable_depth_write: bool = true,
    depth_compare: sdl.gpu.CompareOp = .less,

    /// Blend settings
    enable_blend: bool = false,
    source_color: sdl.gpu.BlendFactor = .one,
    destination_color: sdl.gpu.BlendFactor = .zero,
    source_alpha: sdl.gpu.BlendFactor = .one,
    destination_alpha: sdl.gpu.BlendFactor = .zero,

    /// Depth format
    depth_format: sdl.gpu.TextureFormat = .depth32_float,
};

/// Cached pipeline entry
const CachedPipeline = struct {
    pipeline: sdl.gpu.GraphicsPipeline,
    config: PipelineConfig,
};

/// Manages graphics pipeline creation and caching.
/// Reduces duplicate pipeline creation and centralizes pipeline configuration.
pub const PipelineCache = struct {
    allocator: std.mem.Allocator,
    device: *sdl.gpu.Device,
    shader_library: *ShaderLibrary,
    window: sdl.video.Window,
    pipelines: std.StringHashMap(CachedPipeline),

    /// Swapchain format cached for pipeline creation
    swapchain_format: sdl.gpu.TextureFormat,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        device: *sdl.gpu.Device,
        shader_library: *ShaderLibrary,
        window: sdl.video.Window,
    ) !Self {
        const swapchain_format = try device.getSwapchainTextureFormat(window);

        return .{
            .allocator = allocator,
            .device = device,
            .shader_library = shader_library,
            .window = window,
            .pipelines = std.StringHashMap(CachedPipeline).init(allocator),
            .swapchain_format = swapchain_format,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.pipelines.iterator();
        while (it.next()) |entry| {
            self.device.releaseGraphicsPipeline(entry.value_ptr.pipeline);
        }
        self.pipelines.deinit();
    }

    /// Get or create a pipeline from config
    pub fn getPipeline(self: *Self, config: PipelineConfig) !sdl.gpu.GraphicsPipeline {
        // Check cache first
        if (self.pipelines.get(config.name)) |cached| {
            return cached.pipeline;
        }

        // Create new pipeline
        const pipeline = try self.createPipeline(config);

        // Cache it
        const name_copy = try self.allocator.dupe(u8, config.name);
        errdefer self.allocator.free(name_copy);

        try self.pipelines.put(name_copy, .{
            .pipeline = pipeline,
            .config = config,
        });

        return pipeline;
    }

    /// Create a pipeline from config (internal, doesn't cache)
    fn createPipeline(self: *Self, config: PipelineConfig) !sdl.gpu.GraphicsPipeline {
        const vertex_buffer_desc = Mesh.getVertexBufferDesc();
        const vertex_attributes = Mesh.getVertexAttributes();

        const color_target_desc = sdl.gpu.ColorTargetDescription{
            .format = self.swapchain_format,
            .blend_state = .{
                .enable_blend = config.enable_blend,
                .color_blend = .add,
                .alpha_blend = .add,
                .source_color = config.source_color,
                .source_alpha = config.source_alpha,
                .destination_color = config.destination_color,
                .destination_alpha = config.destination_alpha,
                .enable_color_write_mask = true,
                .color_write_mask = .{ .red = true, .green = true, .blue = true, .alpha = true },
            },
        };

        return try self.device.createGraphicsPipeline(.{
            .vertex_shader = config.shader.vertex,
            .fragment_shader = config.shader.fragment,
            .primitive_type = config.primitive_type,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{vertex_buffer_desc},
                .vertex_attributes = &vertex_attributes,
            },
            .rasterizer_state = .{
                .cull_mode = config.cull_mode,
                .front_face = config.front_face,
                .fill_mode = config.fill_mode,
            },
            .target_info = .{
                .color_target_descriptions = &[_]sdl.gpu.ColorTargetDescription{color_target_desc},
                .depth_stencil_format = config.depth_format,
            },
            .depth_stencil_state = .{
                .enable_depth_test = config.enable_depth_test,
                .enable_depth_write = config.enable_depth_write,
                .compare = config.depth_compare,
                .enable_stencil_test = false,
            },
        });
    }

    /// Get or create the legacy (basic 3D) pipeline
    pub fn getLegacyPipeline(self: *Self) !sdl.gpu.GraphicsPipeline {
        const shader = try self.shader_library.loadLegacy();
        return self.getPipeline(.{
            .name = "legacy",
            .shader = shader,
        });
    }

    /// Get or create the PBR pipeline
    pub fn getPBRPipeline(self: *Self) !sdl.gpu.GraphicsPipeline {
        const shader = try self.shader_library.loadPBR();
        return self.getPipeline(.{
            .name = "pbr",
            .shader = shader,
        });
    }

    /// Get or create the skybox pipeline
    pub fn getSkyboxPipeline(self: *Self) !sdl.gpu.GraphicsPipeline {
        const shader = try self.shader_library.loadSkybox();
        return self.getPipeline(.{
            .name = "skybox",
            .shader = shader,
            // Skybox renders inside-out, so no backface culling
            .cull_mode = .none,
            // Skybox is always at max depth
            .depth_compare = .less_or_equal,
            .enable_depth_write = false,
        });
    }

    /// Check if a pipeline is cached
    pub fn hasPipeline(self: *Self, name: []const u8) bool {
        return self.pipelines.contains(name);
    }

    /// Get the swapchain format
    pub fn getSwapchainFormat(self: *Self) sdl.gpu.TextureFormat {
        return self.swapchain_format;
    }
};
