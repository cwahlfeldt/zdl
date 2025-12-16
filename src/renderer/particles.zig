const std = @import("std");
const sprite = @import("sprite.zig");
const SpriteBatch = sprite.SpriteBatch;
const Color = sprite.Color;
const Vec2 = @import("../math/vec2.zig").Vec2;

/// A single particle
pub const Particle = struct {
    position: Vec2,
    velocity: Vec2,
    color: Color,
    lifetime: f32,
    max_lifetime: f32,
    size: f32,
    active: bool,

    pub fn init(
        position: Vec2,
        velocity: Vec2,
        color: Color,
        lifetime: f32,
        size: f32,
    ) Particle {
        return .{
            .position = position,
            .velocity = velocity,
            .color = color,
            .lifetime = lifetime,
            .max_lifetime = lifetime,
            .size = size,
            .active = true,
        };
    }

    pub fn update(self: *Particle, delta_time: f32) void {
        if (!self.active) return;

        self.lifetime -= delta_time;
        if (self.lifetime <= 0) {
            self.active = false;
            return;
        }

        // Update position based on velocity
        self.position.x += self.velocity.x * delta_time;
        self.position.y += self.velocity.y * delta_time;

        // Fade out alpha as particle dies
        const life_ratio = self.lifetime / self.max_lifetime;
        self.color.a = life_ratio;
    }

    pub fn isActive(self: Particle) bool {
        return self.active;
    }
};

/// Particle emitter configuration
pub const EmitterConfig = struct {
    /// Particles emitted per second
    emission_rate: f32 = 10.0,
    /// Particle lifetime in seconds
    particle_lifetime: f32 = 1.0,
    /// Base color for particles
    color: Color = Color.white(),
    /// Particle size
    size: f32 = 4.0,
    /// Velocity range (min and max)
    velocity_min: Vec2 = Vec2.init(-50, -50),
    velocity_max: Vec2 = Vec2.init(50, 50),
    /// Whether to emit continuously or as a burst
    continuous: bool = true,
};

/// Particle emitter that manages a pool of particles
pub const ParticleEmitter = struct {
    allocator: std.mem.Allocator,
    particles: []Particle,
    position: Vec2,
    config: EmitterConfig,
    emission_timer: f32,
    active: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        position: Vec2,
        max_particles: usize,
        config: EmitterConfig,
    ) !ParticleEmitter {
        const particles = try allocator.alloc(Particle, max_particles);
        @memset(particles, Particle{
            .position = Vec2.zero(),
            .velocity = Vec2.zero(),
            .color = Color.white(),
            .lifetime = 0,
            .max_lifetime = 1,
            .size = 1,
            .active = false,
        });

        return .{
            .allocator = allocator,
            .particles = particles,
            .position = position,
            .config = config,
            .emission_timer = 0,
            .active = true,
        };
    }

    pub fn deinit(self: *ParticleEmitter) void {
        self.allocator.free(self.particles);
    }

    /// Emit a single particle
    fn emitParticle(self: *ParticleEmitter) void {
        // Find an inactive particle
        for (self.particles) |*particle| {
            if (!particle.active) {
                // Random velocity within range
                const vx = self.config.velocity_min.x +
                    (self.config.velocity_max.x - self.config.velocity_min.x) * self.random();
                const vy = self.config.velocity_min.y +
                    (self.config.velocity_max.y - self.config.velocity_min.y) * self.random();

                particle.* = Particle.init(
                    self.position,
                    Vec2.init(vx, vy),
                    self.config.color,
                    self.config.particle_lifetime,
                    self.config.size,
                );
                return;
            }
        }
    }

    /// Emit a burst of particles
    pub fn burst(self: *ParticleEmitter, count: usize) void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            self.emitParticle();
        }
    }

    /// Update all particles
    pub fn update(self: *ParticleEmitter, delta_time: f32) void {
        if (!self.active) return;

        // Update emission timer for continuous emission
        if (self.config.continuous) {
            self.emission_timer += delta_time;
            const emission_interval = 1.0 / self.config.emission_rate;

            while (self.emission_timer >= emission_interval) {
                self.emission_timer -= emission_interval;
                self.emitParticle();
            }
        }

        // Update all active particles
        for (self.particles) |*particle| {
            particle.update(delta_time);
        }
    }

    /// Render all active particles
    pub fn render(self: *ParticleEmitter, batch: *SpriteBatch) !void {
        for (self.particles) |particle| {
            if (particle.active) {
                try batch.addQuad(
                    particle.position.x,
                    particle.position.y,
                    particle.size,
                    particle.size,
                    particle.color,
                );
            }
        }
    }

    /// Set the emitter position
    pub fn setPosition(self: *ParticleEmitter, position: Vec2) void {
        self.position = position;
    }

    /// Start or stop emitting particles
    pub fn setActive(self: *ParticleEmitter, active: bool) void {
        self.active = active;
    }

    /// Get count of active particles
    pub fn getActiveCount(self: ParticleEmitter) usize {
        var count: usize = 0;
        for (self.particles) |particle| {
            if (particle.active) count += 1;
        }
        return count;
    }

    /// Simple random number generator (0.0 to 1.0)
    /// For better randomness, use std.Random
    fn random(self: *ParticleEmitter) f32 {
        _ = self;
        // Simple pseudo-random (not cryptographically secure)
        // In production, use std.Random.DefaultPrng
        const state = struct {
            var seed: u64 = 12345;
        };
        state.seed = state.seed *% 1103515245 +% 12345;
        return @as(f32, @floatFromInt(state.seed & 0x7FFFFFFF)) / 2147483647.0;
    }
};
