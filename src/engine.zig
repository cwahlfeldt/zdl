// ZDL Engine - Main module export
pub const Engine = @import("engine/engine.zig").Engine;
pub const EngineConfig = @import("engine/engine.zig").EngineConfig;
pub const Application = @import("engine/application.zig");
pub const Context = Application.Context;

// Subsystems
pub const Input = @import("input/input.zig").Input;
pub const Camera2D = @import("camera.zig").Camera2D;
pub const sprite = @import("renderer/sprite.zig");
pub const SpriteBatch = sprite.SpriteBatch;
pub const Color = sprite.Color;

// Rendering
pub const animation = @import("renderer/animation.zig");
pub const Animation = animation.Animation;
pub const AnimationFrame = animation.AnimationFrame;
pub const Animator = animation.Animator;
pub const tilemap = @import("renderer/tilemap.zig");
pub const Tilemap = tilemap.Tilemap;
pub const Tile = tilemap.Tile;
pub const particles = @import("renderer/particles.zig");
pub const Particle = particles.Particle;
pub const ParticleEmitter = particles.ParticleEmitter;
pub const EmitterConfig = particles.EmitterConfig;

// Math
pub const math = @import("math/math.zig");
pub const Vec2 = math.Vec2;
pub const Vec3 = math.Vec3;
pub const Vec4 = math.Vec4;
pub const Mat4 = math.Mat4;

// Resources
pub const Texture = @import("resources/texture.zig").Texture;

// Audio
pub const audio = @import("audio/audio.zig");
pub const Audio = audio.Audio;
pub const Sound = audio.Sound;

// UI
pub const ui = @import("ui/ui.zig");
pub const BitmapFont = ui.BitmapFont;
pub const HUD = ui.HUD;
