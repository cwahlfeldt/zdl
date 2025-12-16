const std = @import("std");
const zdl = @import("engine");
const Application = zdl.Application;
const Context = zdl.Context;
const Input = zdl.Input;
const Vec2 = zdl.Vec2;
const Color = zdl.Color;
const Tilemap = zdl.Tilemap;
const Tile = zdl.Tile;
const ParticleEmitter = zdl.ParticleEmitter;
const EmitterConfig = zdl.EmitterConfig;
const HUD = zdl.HUD;
const BitmapFont = zdl.BitmapFont;

// Physics constants
const GRAVITY: f32 = 980.0;
const JUMP_VELOCITY: f32 = -600.0;

// Player entity
const Player = struct {
    position: Vec2,
    velocity: Vec2,
    width: f32,
    height: f32,
    speed: f32,
    is_grounded: bool,
    was_grounded: bool,
    just_jumped: bool,
    just_landed: bool,

    fn init() Player {
        return .{
            .position = Vec2.init(0, 0),
            .velocity = Vec2.zero(),
            .width = 50,
            .height = 50,
            .speed = 200,
            .is_grounded = false,
            .was_grounded = false,
            .just_jumped = false,
            .just_landed = false,
        };
    }

    fn update(self: *Player, input: *Input, delta_time: f32, tilemap: *const Tilemap) void {
        self.just_jumped = false;
        self.just_landed = false;

        const wasd = input.getWASD();
        const arrows = input.getArrowKeys();
        const horizontal_input = wasd.x + arrows.x;

        self.velocity.y += GRAVITY * delta_time;
        self.velocity.x = horizontal_input * self.speed;

        // X-axis collision
        var next_pos_x = self.position;
        next_pos_x.x += self.velocity.x * delta_time;

        const half_w = self.width / 2.0;
        const half_h = self.height / 2.0;
        const x_collided = zdl.tilemap.checkAABBCollision(
            tilemap.*,
            next_pos_x.x - half_w,
            next_pos_x.y - half_h,
            self.width,
            self.height,
        );

        if (!x_collided) {
            self.position.x = next_pos_x.x;
        }

        // Y-axis collision
        var next_pos_y = self.position;
        next_pos_y.y += self.velocity.y * delta_time;

        const y_collided = zdl.tilemap.checkAABBCollision(
            tilemap.*,
            next_pos_y.x - half_w,
            next_pos_y.y - half_h,
            self.width,
            self.height,
        );

        self.is_grounded = false;
        if (y_collided) {
            if (self.velocity.y > 0) {
                self.is_grounded = true;
                if (!self.was_grounded) {
                    self.just_landed = true;
                }
            }
            self.velocity.y = 0;
        } else {
            self.position.y = next_pos_y.y;
        }

        // Jump
        if (self.is_grounded and (input.isKeyJustPressed(.space) or input.isKeyJustPressed(.w) or input.isKeyJustPressed(.up))) {
            self.velocity.y = JUMP_VELOCITY;
            self.is_grounded = false;
            self.just_jumped = true;
        }

        self.was_grounded = self.is_grounded;
    }
};

/// Platformer game implementation
pub const PlatformerGame = struct {
    player: Player,
    tilemap: Tilemap,
    jump_particles: ParticleEmitter,
    land_particles: ParticleEmitter,
    hud: HUD,
    score: i32,

    pub fn init(self: *PlatformerGame, ctx: *Context) !void {
        // Create a simple level using string format
        const level_data =
            \\................
            \\................
            \\................
            \\..##........##..
            \\................
            \\...##....##.....
            \\................
            \\....########....
            \\................
            \\#..............#
            \\#..............#
            \\################
        ;

        const tilemap = try Tilemap.fromString(ctx.allocator, level_data, 50.0);

        // Create particle emitters for jump and land effects
        const jump_config = EmitterConfig{
            .emission_rate = 50.0,
            .particle_lifetime = 0.3,
            .color = Color{ .r = 1.0, .g = 0.8, .b = 0.4, .a = 1.0 }, // Orange/yellow
            .size = 6.0,
            .velocity_min = Vec2.init(-100, -150),
            .velocity_max = Vec2.init(100, -50),
            .continuous = false,
        };

        const land_config = EmitterConfig{
            .emission_rate = 100.0,
            .particle_lifetime = 0.5,
            .color = Color{ .r = 0.6, .g = 0.6, .b = 0.6, .a = 1.0 }, // Gray
            .size = 4.0,
            .velocity_min = Vec2.init(-150, -100),
            .velocity_max = Vec2.init(150, 100),
            .continuous = false,
        };

        const jump_particles = try ParticleEmitter.init(
            ctx.allocator,
            Vec2.zero(),
            100,
            jump_config,
        );

        const land_particles = try ParticleEmitter.init(
            ctx.allocator,
            Vec2.zero(),
            100,
            land_config,
        );

        // Create HUD with simple font
        const font = BitmapFont.init(12, 16, 2);
        const hud = HUD.init(font);

        self.* = .{
            .player = Player.init(),
            .tilemap = tilemap,
            .jump_particles = jump_particles,
            .land_particles = land_particles,
            .hud = hud,
            .score = 0,
        };
    }

    pub fn deinit(self: *PlatformerGame, ctx: *Context) void {
        _ = ctx;
        self.land_particles.deinit();
        self.jump_particles.deinit();
        self.tilemap.deinit();
    }

    pub fn update(self: *PlatformerGame, ctx: *Context, delta_time: f32) !void {
        self.player.update(ctx.input, delta_time, &self.tilemap);

        // Trigger particle effects
        if (self.player.just_jumped) {
            self.jump_particles.setPosition(Vec2.init(
                self.player.position.x,
                self.player.position.y + self.player.height / 2,
            ));
            self.jump_particles.burst(10);
            self.score += 1; // Add points for jumping
        }

        if (self.player.just_landed) {
            self.land_particles.setPosition(Vec2.init(
                self.player.position.x,
                self.player.position.y + self.player.height / 2,
            ));
            self.land_particles.burst(15);
        }

        // Update particles
        self.jump_particles.update(delta_time);
        self.land_particles.update(delta_time);

        // Audio example (note: we don't have actual WAV files loaded)
        // In a real game, you would load sounds in init() and play them here:
        // if (self.player.just_jumped) {
        //     try ctx.audio.playSound("jump", 0.5);
        // }
        _ = ctx.audio;
    }

    pub fn render(self: *PlatformerGame, ctx: *Context) !void {
        // Draw tilemap
        try self.tilemap.render(ctx.sprite_batch, null);

        // Draw particles (behind player)
        try self.jump_particles.render(ctx.sprite_batch);
        try self.land_particles.render(ctx.sprite_batch);

        // Draw player
        try ctx.sprite_batch.addQuad(
            self.player.position.x,
            self.player.position.y,
            self.player.width,
            self.player.height,
            Color.red(),
        );

        // Draw HUD
        try self.hud.drawScore(
            ctx.sprite_batch,
            self.score,
            ctx.camera.width,
            ctx.camera.height,
        );

        // Draw instructions
        try self.hud.drawText(
            ctx.sprite_batch,
            "WASD/Arrows + Space to Jump",
            -ctx.camera.width / 2 + 20,
            ctx.camera.height / 2 - 40,
            Color.white(),
        );
    }
};
