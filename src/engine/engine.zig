const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl3");
const input_module = @import("../input/input.zig");
const Input = input_module.Input;
const MouseButton = input_module.MouseButton;
const GamepadButton = input_module.GamepadButton;
const GamepadAxis = input_module.GamepadAxis;
const Audio = @import("../audio/audio.zig").Audio;

// New modular imports
const WindowManager = @import("../window/window_manager.zig").WindowManager;
const WindowConfig = @import("../window/window_manager.zig").WindowConfig;
const render_mod = @import("../render/render_manager.zig");
const RenderManager = render_mod.RenderManager;

// Re-export Color and RenderFrame for backwards compatibility
pub const Color = render_mod.Color;
pub const RenderFrame = render_mod.RenderFrame;

// ECS imports
const Scene = @import("../ecs/scene.zig").Scene;
const RenderSystem = @import("../ecs/systems/render_system.zig").RenderSystem;

// Scripting imports
const ScriptSystem = @import("../scripting/script_system.zig").ScriptSystem;
const ScriptContext = @import("../scripting/script_context.zig").ScriptContext;

// IBL imports
const EnvironmentMap = @import("../ibl/environment_map.zig").EnvironmentMap;

pub const EngineConfig = struct {
    window_title: [:0]const u8 = "ZDL Game",
    window_width: u32 = 1280,
    window_height: u32 = 720,
    target_fps: u32 = 60,
    clear_color: Color = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 },
    app_name: ?[:0]const u8 = null,
    app_version: ?[:0]const u8 = null,
    app_identifier: ?[:0]const u8 = "com.zdl.engine",
};

/// Main engine that coordinates subsystems and runs the game loop.
/// This is now a thin coordinator that delegates to specialized managers.
pub const Engine = struct {
    allocator: std.mem.Allocator,

    // Subsystem managers (new modular design)
    window_manager: WindowManager,
    render_manager: RenderManager,
    input: Input,
    audio: Audio,

    // Backwards compatibility - direct access to window and device
    // These are stored references for code that uses eng.window and eng.device
    window: sdl.video.Window,
    device: sdl.gpu.Device,

    // Backwards compatibility - window dimensions
    window_width: u32,
    window_height: u32,

    // Timing
    last_time: u64,
    target_frame_time: u64,

    // FPS Counter
    show_fps: bool,
    fps_frame_count: u32,
    fps_last_update: u64,
    fps_current: f32,
    original_window_title: [:0]const u8,
    total_time: f64,

    // Scripting
    script_system: ?*ScriptSystem,

    // Quit flag (can be set by scripts)
    should_quit: bool,

    // Backwards compatibility: expose light_uniforms directly
    // Note: This is a copy. For modifications, use render_manager.light_uniforms
    light_uniforms: @import("../gpu/uniforms.zig").LightUniforms,

    // Backwards compatibility: expose white_texture and sampler
    white_texture: @import("../resources/texture.zig").Texture,
    sampler: sdl.gpu.Sampler,

    // Backwards compatibility: PBR textures
    default_normal_texture: ?@import("../resources/texture.zig").Texture,
    default_mr_texture: ?@import("../resources/texture.zig").Texture,
    default_ao_texture: ?@import("../resources/texture.zig").Texture,
    default_emissive_texture: ?@import("../resources/texture.zig").Texture,
    pbr_pipeline: ?sdl.gpu.GraphicsPipeline,
    skybox_pipeline: ?sdl.gpu.GraphicsPipeline,
    skybox_mesh: ?@import("../resources/mesh.zig").Mesh,
    brdf_lut: ?*@import("../ibl/brdf_lut.zig").BrdfLut,
    current_environment: ?*EnvironmentMap,
    default_environment: ?*EnvironmentMap,
    ibl_enabled: bool,

    pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Engine {
        const app_name = config.app_name orelse config.window_title;
        try sdl.setAppMetadata(app_name, config.app_version, config.app_identifier);

        // Initialize window manager
        var window_manager = try WindowManager.init(.{
            .title = config.window_title,
            .width = config.window_width,
            .height = config.window_height,
            .resizable = true,
        });
        errdefer window_manager.deinit();

        // Initialize render manager
        var render_manager = try RenderManager.init(
            allocator,
            window_manager.window,
            config.window_width,
            config.window_height,
        );
        errdefer render_manager.deinit();
        render_manager.setClearColor(config.clear_color);

        // Initialize input
        var input = Input.init(allocator);
        errdefer input.deinit();

        // Initialize audio
        var audio = try Audio.init(allocator);
        errdefer audio.deinit();

        const last_time = sdl.timer.getMillisecondsSinceInit();
        const target_frame_time = 1000 / config.target_fps;

        return .{
            .allocator = allocator,
            .window_manager = window_manager,
            .render_manager = render_manager,
            .input = input,
            .audio = audio,
            // Backwards compatibility fields
            .window = window_manager.window,
            .device = render_manager.device,
            .window_width = config.window_width,
            .window_height = config.window_height,
            .light_uniforms = render_manager.light_uniforms,
            .white_texture = render_manager.white_texture,
            .sampler = render_manager.sampler,
            .default_normal_texture = null,
            .default_mr_texture = null,
            .default_ao_texture = null,
            .default_emissive_texture = null,
            .pbr_pipeline = null,
            .skybox_pipeline = null,
            .skybox_mesh = null,
            .brdf_lut = null,
            .current_environment = null,
            .default_environment = null,
            .ibl_enabled = false,
            // Timing and state
            .last_time = last_time,
            .target_frame_time = target_frame_time,
            .show_fps = false,
            .fps_frame_count = 0,
            .fps_last_update = last_time,
            .fps_current = 0.0,
            .original_window_title = config.window_title,
            .total_time = 0.0,
            .script_system = null,
            .should_quit = false,
        };
    }

    /// Initialize the scripting system.
    pub fn initScripting(self: *Engine) !void {
        if (self.script_system != null) return;

        const script_sys = try self.allocator.create(ScriptSystem);
        script_sys.* = try ScriptSystem.init(self.allocator);
        self.script_system = script_sys;
    }

    /// Check if scripting is available.
    pub fn hasScripting(self: *Engine) bool {
        return self.script_system != null;
    }

    /// Initialize the PBR rendering pipeline.
    pub fn initPBR(self: *Engine) !void {
        try self.render_manager.initPBR();
        // Sync backwards compat fields
        self.pbr_pipeline = self.render_manager.pbr_pipeline;
        self.default_normal_texture = self.render_manager.default_normal_texture;
        self.default_mr_texture = self.render_manager.default_mr_texture;
        self.default_ao_texture = self.render_manager.default_ao_texture;
        self.default_emissive_texture = self.render_manager.default_emissive_texture;
    }

    /// Check if PBR rendering is available.
    pub fn hasPBR(self: *Engine) bool {
        return self.render_manager.hasPBR();
    }

    /// Initialize Image-Based Lighting support.
    pub fn initIBL(self: *Engine) !void {
        try self.render_manager.initIBL();
        // Sync backwards compat fields
        self.brdf_lut = self.render_manager.brdf_lut;
        self.current_environment = self.render_manager.current_environment;
        self.default_environment = self.render_manager.default_environment;
        self.ibl_enabled = self.render_manager.ibl_enabled;
        self.skybox_pipeline = self.render_manager.skybox_pipeline;
        self.skybox_mesh = self.render_manager.skybox_mesh;
    }

    /// Check if IBL is available.
    pub fn hasIBL(self: *Engine) bool {
        return self.render_manager.hasIBL();
    }

    /// Set the active environment map.
    pub fn setEnvironmentMap(self: *Engine, env: *EnvironmentMap) void {
        self.render_manager.setEnvironmentMap(env);
        self.current_environment = env;
    }

    /// Load HDR environment map from equirectangular .hdr file.
    pub fn loadHDREnvironment(self: *Engine, path: []const u8) !*EnvironmentMap {
        const env = try self.render_manager.loadHDREnvironment(path);
        self.current_environment = env;
        return env;
    }

    /// Initialize Forward+ clustered rendering (CPU culling mode).
    /// This enables efficient rendering of many dynamic lights.
    /// Uses CPU-based culling which is more compatible but less performant.
    pub fn initForwardPlus(self: *Engine) !void {
        try self.render_manager.initForwardPlus();
    }

    /// Initialize Forward+ with GPU compute culling.
    /// This uses a GPU compute shader for light culling, which is faster
    /// but requires proper driver support for compute shaders.
    pub fn initForwardPlusGPU(self: *Engine) !void {
        try self.render_manager.initForwardPlusGPU();
    }

    /// Check if Forward+ rendering is available.
    pub fn hasForwardPlus(self: *Engine) bool {
        return self.render_manager.hasForwardPlus();
    }

    /// Enable or disable Forward+ rendering.
    /// When disabled, falls back to standard PBR rendering.
    pub fn setForwardPlusEnabled(self: *Engine, enabled: bool) void {
        self.render_manager.setForwardPlusEnabled(enabled);
    }

    pub fn deinit(self: *Engine) void {
        // Clean up scripting
        if (self.script_system) |script_sys| {
            script_sys.deinit(&self.render_manager.device);
            self.allocator.destroy(script_sys);
        }

        self.audio.deinit();
        self.input.deinit();
        self.render_manager.deinit();
        self.window_manager.deinit();
    }

    /// Set mouse capture mode (hides cursor and captures relative motion)
    pub fn setMouseCapture(self: *Engine, captured: bool) void {
        self.input.mouse_captured = captured;
        sdl.mouse.setWindowRelativeMode(self.window_manager.window, captured) catch {};
    }

    /// Run the game loop with a scene and optional update callback.
    pub fn runScene(
        self: *Engine,
        scene: *Scene,
        update_fn: ?*const fn (*Engine, *Scene, *Input, f32) anyerror!void,
    ) !void {
        var running = true;
        while (running) {
            const frame_start = sdl.timer.getMillisecondsSinceInit();
            const delta_time = @as(f32, @floatFromInt(frame_start - self.last_time)) / 1000.0;
            self.last_time = frame_start;
            self.total_time += delta_time;

            self.input.update();

            // Process SDL events and translate to Input state-setters
            // This decouples Input from direct SDL event processing
            while (sdl.events.poll()) |event| {
                switch (event) {
                    .quit => running = false,
                    .key_down => |key_event| {
                        const scancode = key_event.scancode orelse continue;
                        // Engine-level key handling
                        if (scancode == .escape) {
                            if (self.input.mouse_captured) {
                                self.setMouseCapture(false);
                            } else {
                                running = false;
                            }
                        }
                        if (scancode == .func3) {
                            self.show_fps = !self.show_fps;
                            std.debug.print("FPS counter: {s}\n", .{if (self.show_fps) "ON" else "OFF"});

                            if (!self.show_fps) {
                                self.window_manager.setTitle(self.original_window_title);
                            }
                        }
                        // Forward to Input via state-setter
                        self.input.setKeyDown(scancode, key_event.repeat);
                    },
                    .key_up => |key_event| {
                        if (key_event.scancode) |scancode| {
                            self.input.setKeyUp(scancode);
                        }
                    },
                    .mouse_motion => |motion| {
                        self.input.setMousePosition(motion.x, motion.y);
                        self.input.setMouseDelta(motion.x_rel, motion.y_rel);
                    },
                    .mouse_button_down => |button| {
                        const mb = MouseButton.fromSdl(button.button) orelse continue;
                        self.input.setMouseButton(mb, true);
                    },
                    .mouse_button_up => |button| {
                        const mb = MouseButton.fromSdl(button.button) orelse continue;
                        self.input.setMouseButton(mb, false);
                    },
                    .gamepad_added => |gp_event| {
                        self.input.gamepads.handleGamepadAdded(gp_event.id) catch {};
                    },
                    .gamepad_removed => |gp_event| {
                        self.input.gamepads.handleGamepadRemoved(gp_event.id);
                    },
                    .gamepad_button_down => |gp_event| {
                        self.input.last_input_device = .gamepad;
                        if (self.input.gamepads.getById(gp_event.id)) |gamepad| {
                            gamepad.handleButtonDown(GamepadButton.fromSdl(gp_event.button));
                        }
                    },
                    .gamepad_button_up => |gp_event| {
                        if (self.input.gamepads.getById(gp_event.id)) |gamepad| {
                            gamepad.handleButtonUp(GamepadButton.fromSdl(gp_event.button));
                        }
                    },
                    .gamepad_axis_motion => |gp_event| {
                        self.input.last_input_device = .gamepad;
                        if (self.input.gamepads.getById(gp_event.id)) |gamepad| {
                            gamepad.handleAxisMotion(GamepadAxis.fromSdl(gp_event.axis), gp_event.value);
                        }
                    },
                    else => {},
                }
            }

            if (!running) {
                break;
            }

            // Update FPS counter
            self.fps_frame_count += 1;
            if (frame_start - self.fps_last_update >= 1000) {
                self.fps_current = @as(f32, @floatFromInt(self.fps_frame_count)) * 1000.0 / @as(f32, @floatFromInt(frame_start - self.fps_last_update));
                self.fps_frame_count = 0;
                self.fps_last_update = frame_start;

                if (self.show_fps) {
                    var title_buffer: [256]u8 = undefined;
                    const title = std.fmt.bufPrintZ(&title_buffer, "ZDL - FPS: {d:.1}", .{self.fps_current}) catch "ZDL";
                    self.window_manager.setTitle(title);
                }
            }

            // Call user update function if provided
            if (update_fn) |update_callback| {
                try update_callback(self, scene, &self.input, delta_time);
            }

            // Update scripts
            if (self.script_system) |script_sys| {
                // Create ScriptContext to decouple ScriptSystem from Engine
                const script_ctx = ScriptContext{
                    .delta_time = delta_time,
                    .total_time = self.total_time,
                    .fps = self.fps_current,
                    .window_width = self.window_width,
                    .window_height = self.window_height,
                    .mouse_captured = self.input.mouse_captured,
                    .device = @ptrCast(&self.render_manager.device),
                    .engine_ptr = @ptrCast(self),
                    .set_mouse_capture_fn = &setMouseCaptureCallback,
                    .request_quit_fn = &requestQuitCallback,
                };
                script_sys.update(scene, &script_ctx, &self.input, delta_time);
            }

            // Check if script requested quit
            if (self.should_quit) {
                running = false;
            }

            // Update world transforms
            scene.updateWorldTransforms();

            // Sync window dimensions from render manager
            self.window_width = self.render_manager.window_width;
            self.window_height = self.render_manager.window_height;

            // Render scene
            if (try self.render_manager.beginFrame()) |frame_value| {
                var frame = frame_value;
                RenderSystem.render(scene, &frame);
                try frame.end();
            }

            // Frame rate limiting
            const frame_end = sdl.timer.getMillisecondsSinceInit();
            const frame_time = frame_end - frame_start;
            if (frame_time < self.target_frame_time) {
                sdl.timer.delayMilliseconds(@intCast(self.target_frame_time - frame_time));
            }
        }

        // Shutdown scripts before scene cleanup
        if (self.script_system) |script_sys| {
            script_sys.shutdown(scene);
        }
    }

    /// Begin a render frame - returns RenderFrame if successful.
    pub fn beginFrame(self: *Engine) !?RenderFrame {
        return self.render_manager.beginFrame();
    }

    /// Set the clear color.
    pub fn setClearColor(self: *Engine, color: Color) void {
        self.render_manager.setClearColor(color);
    }
};

// Callback functions for ScriptContext (defined outside Engine to get proper fn pointer types)
fn setMouseCaptureCallback(engine_ptr: *anyopaque, captured: bool) void {
    const engine: *Engine = @ptrCast(@alignCast(engine_ptr));
    engine.setMouseCapture(captured);
}

fn requestQuitCallback(engine_ptr: *anyopaque) void {
    const engine: *Engine = @ptrCast(@alignCast(engine_ptr));
    engine.should_quit = true;
}
