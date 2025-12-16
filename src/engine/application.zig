const std = @import("std");
const sdl = @import("sdl3");
const Input = @import("../input/input.zig").Input;
const Camera2D = @import("../camera.zig").Camera2D;
const SpriteBatch = @import("../renderer/sprite.zig").SpriteBatch;

/// Application interface that games must implement
pub const Application = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init: *const fn (ptr: *anyopaque, ctx: *Context) anyerror!void,
        deinit: *const fn (ptr: *anyopaque, ctx: *Context) void,
        update: *const fn (ptr: *anyopaque, ctx: *Context, delta_time: f32) anyerror!void,
        render: *const fn (ptr: *anyopaque, ctx: *Context) anyerror!void,
    };

    pub fn init(self: Application, ctx: *Context) !void {
        return self.vtable.init(self.ptr, ctx);
    }

    pub fn deinit(self: Application, ctx: *Context) void {
        return self.vtable.deinit(self.ptr, ctx);
    }

    pub fn update(self: Application, ctx: *Context, delta_time: f32) !void {
        return self.vtable.update(self.ptr, ctx, delta_time);
    }

    pub fn render(self: Application, ctx: *Context) !void {
        return self.vtable.render(self.ptr, ctx);
    }
};

/// Context provided to the application with access to engine systems
pub const Context = struct {
    allocator: std.mem.Allocator,
    input: *Input,
    camera: *Camera2D,
    sprite_batch: *SpriteBatch,
    device: *sdl.gpu.Device,
    window: *sdl.video.Window,

    // Cached resources (for advanced usage)
    vertex_buffer: *sdl.gpu.Buffer,
    transfer_buffer: *sdl.gpu.TransferBuffer,
    pipeline: *sdl.gpu.GraphicsPipeline,
    white_texture: *const anyopaque, // Will be Texture type
    sampler: *sdl.gpu.Sampler,
};

/// Helper to create an Application from a concrete type
pub fn createApplication(comptime T: type, instance: *T) Application {
    const gen = struct {
        fn init(ptr: *anyopaque, ctx: *Context) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.init(ctx);
        }

        fn deinit(ptr: *anyopaque, ctx: *Context) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.deinit(ctx);
        }

        fn update(ptr: *anyopaque, ctx: *Context, delta_time: f32) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.update(ctx, delta_time);
        }

        fn render(ptr: *anyopaque, ctx: *Context) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.render(ctx);
        }
    };

    return .{
        .ptr = instance,
        .vtable = &.{
            .init = gen.init,
            .deinit = gen.deinit,
            .update = gen.update,
            .render = gen.render,
        },
    };
}
