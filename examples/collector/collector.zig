const std = @import("std");
const zdl = @import("engine");
const Application = zdl.Application;
const Context = zdl.Context;
const Input = zdl.Input;
const Vec2 = zdl.Vec2;
const Color = zdl.Color;
const ParticleEmitter = zdl.ParticleEmitter;
const EmitterConfig = zdl.EmitterConfig;
const HUD = zdl.HUD;
const BitmapFont = zdl.BitmapFont;

// Game constants
const PLAYER_SPEED: f32 = 300.0;
const COIN_COUNT: usize = 10;
const WORLD_WIDTH: f32 = 800.0;
const WORLD_HEIGHT: f32 = 600.0;

/// Simple 2D coin collector game demonstrating Phase 3 features:
/// - Particle effects when collecting coins
/// - UI/HUD with score, timer, and health bar
/// - Audio system ready for sound effects (WAV files not included)
pub const CollectorGame = struct {
    // Player
    player_pos: Vec2,
    player_health: f32,
    max_health: f32,
    player_size: f32,

    // Coins
    coins: []Coin,
    coins_collected: usize,

    // Particles
    collect_particles: ParticleEmitter,
    trail_particles: ParticleEmitter,

    // UI
    hud: HUD,
    score: i32,
    time_remaining: f32,
    game_over: bool,
    won: bool,

    const Coin = struct {
        pos: Vec2,
        collected: bool,
        rotation: f32,
    };

    pub fn init(self: *CollectorGame, ctx: *Context) !void {
        // Initialize player
        const player_pos = Vec2.zero();
        const player_health = 100.0;
        const player_size = 40.0;

        // Create coins in random positions
        const coins = try ctx.allocator.alloc(Coin, COIN_COUNT);
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();

        for (coins, 0..) |*coin, i| {
            const angle = @as(f32, @floatFromInt(i)) * (std.math.pi * 2.0) / @as(f32, @floatFromInt(COIN_COUNT));
            const radius = 200.0 + random.float(f32) * 100.0;
            coin.* = .{
                .pos = Vec2.init(
                    @cos(angle) * radius,
                    @sin(angle) * radius,
                ),
                .collected = false,
                .rotation = 0,
            };
        }

        // Create particle emitter for coin collection
        const collect_config = EmitterConfig{
            .emission_rate = 200.0,
            .particle_lifetime = 0.8,
            .color = Color{ .r = 1.0, .g = 0.9, .b = 0.2, .a = 1.0 }, // Gold
            .size = 8.0,
            .velocity_min = Vec2.init(-200, -200),
            .velocity_max = Vec2.init(200, -100),
            .continuous = false,
        };

        const collect_particles = try ParticleEmitter.init(
            ctx.allocator,
            Vec2.zero(),
            200,
            collect_config,
        );

        // Create trail particle emitter
        const trail_config = EmitterConfig{
            .emission_rate = 30.0,
            .particle_lifetime = 0.5,
            .color = Color{ .r = 0.3, .g = 0.6, .b = 1.0, .a = 0.7 }, // Blue trail
            .size = 4.0,
            .velocity_min = Vec2.init(-30, -30),
            .velocity_max = Vec2.init(30, 30),
            .continuous = true,
        };

        const trail_particles = try ParticleEmitter.init(
            ctx.allocator,
            Vec2.zero(),
            150,
            trail_config,
        );

        // Create HUD
        const font = BitmapFont.init(10, 14, 2);
        const hud = HUD.init(font);

        self.* = .{
            .player_pos = player_pos,
            .player_health = player_health,
            .max_health = player_health,
            .player_size = player_size,
            .coins = coins,
            .coins_collected = 0,
            .collect_particles = collect_particles,
            .trail_particles = trail_particles,
            .hud = hud,
            .score = 0,
            .time_remaining = 30.0, // 30 seconds to collect all coins
            .game_over = false,
            .won = false,
        };

        // Note: In a real game, you would load sound effects here:
        // try ctx.audio.loadWAV("collect", "assets/sounds/collect.wav");
        // try ctx.audio.loadWAV("win", "assets/sounds/win.wav");
        // try ctx.audio.loadWAV("lose", "assets/sounds/lose.wav");
        _ = ctx.audio;
    }

    pub fn deinit(self: *CollectorGame, ctx: *Context) void {
        self.trail_particles.deinit();
        self.collect_particles.deinit();
        ctx.allocator.free(self.coins);
    }

    pub fn update(self: *CollectorGame, ctx: *Context, delta_time: f32) !void {
        if (self.game_over) return;

        // Update timer
        self.time_remaining -= delta_time;
        if (self.time_remaining <= 0) {
            self.time_remaining = 0;
            self.game_over = true;
            self.won = false;
            // try ctx.audio.playSound("lose", 0.7);
            return;
        }

        // Player movement
        const wasd = ctx.input.getWASD();
        const arrows = ctx.input.getArrowKeys();
        const input_vec = Vec2.init(
            wasd.x + arrows.x,
            wasd.y + arrows.y,
        );

        if (input_vec.x != 0 or input_vec.y != 0) {
            const normalized = input_vec.normalize();
            self.player_pos.x += normalized.x * PLAYER_SPEED * delta_time;
            self.player_pos.y += normalized.y * PLAYER_SPEED * delta_time;

            // Clamp to world bounds
            const half_world_w = WORLD_WIDTH / 2.0;
            const half_world_h = WORLD_HEIGHT / 2.0;
            self.player_pos.x = @max(-half_world_w, @min(half_world_w, self.player_pos.x));
            self.player_pos.y = @max(-half_world_h, @min(half_world_h, self.player_pos.y));
        }

        // Update trail particles to follow player
        self.trail_particles.setPosition(self.player_pos);
        self.trail_particles.update(delta_time);

        // Update collect particles
        self.collect_particles.update(delta_time);

        // Rotate coins and check for collection
        for (self.coins) |*coin| {
            if (coin.collected) continue;

            coin.rotation += delta_time * 2.0;

            // Check collision with player
            const dx = coin.pos.x - self.player_pos.x;
            const dy = coin.pos.y - self.player_pos.y;
            const dist_sq = dx * dx + dy * dy;
            const collect_dist = (self.player_size + 20.0) / 2.0;

            if (dist_sq < collect_dist * collect_dist) {
                coin.collected = true;
                self.coins_collected += 1;
                self.score += 100;

                // Trigger particle burst
                self.collect_particles.setPosition(coin.pos);
                self.collect_particles.burst(30);

                // Play sound effect (if loaded)
                // try ctx.audio.playSound("collect", 0.6);

                // Check for win condition
                if (self.coins_collected >= COIN_COUNT) {
                    self.game_over = true;
                    self.won = true;
                    // try ctx.audio.playSound("win", 0.8);
                }
            }
        }

        // Lose health over time (to demo health bar)
        self.player_health = @max(0, self.player_health - delta_time * 2.0);
    }

    pub fn render(self: *CollectorGame, ctx: *Context) !void {
        const screen_w = ctx.camera.width;
        const screen_h = ctx.camera.height;

        // Draw background grid
        try self.drawBackground(ctx);

        // Draw coins
        for (self.coins) |coin| {
            if (coin.collected) continue;

            // Draw coin as rotating square
            const half_size: f32 = 15.0;
            const rot_scale = @abs(@cos(coin.rotation));
            try ctx.sprite_batch.addQuad(
                coin.pos.x,
                coin.pos.y,
                half_size * 2.0 * rot_scale,
                half_size * 2.0,
                Color{ .r = 1.0, .g = 0.85, .b = 0.1, .a = 1.0 }, // Gold
            );
        }

        // Draw trail particles
        try self.trail_particles.render(ctx.sprite_batch);

        // Draw player
        try ctx.sprite_batch.addQuad(
            self.player_pos.x,
            self.player_pos.y,
            self.player_size,
            self.player_size,
            Color{ .r = 0.2, .g = 0.8, .b = 0.3, .a = 1.0 }, // Green player
        );

        // Draw collection particles (on top of everything)
        try self.collect_particles.render(ctx.sprite_batch);

        // Draw HUD
        try self.hud.drawScore(ctx.sprite_batch, self.score, screen_w, screen_h);

        // Draw timer
        var timer_buf: [32]u8 = undefined;
        const timer_text = try std.fmt.bufPrint(&timer_buf, "Time: {d:.1}", .{self.time_remaining});
        try self.hud.drawText(
            ctx.sprite_batch,
            timer_text,
            -screen_w / 2 + 20,
            -screen_h / 2 + 40,
            if (self.time_remaining < 10.0)
                Color{ .r = 1.0, .g = 0.3, .b = 0.3, .a = 1.0 }
            else
                Color.white(),
        );

        // Draw coins collected
        var coins_buf: [32]u8 = undefined;
        const coins_text = try std.fmt.bufPrint(&coins_buf, "Coins: {d}/{d}", .{ self.coins_collected, COIN_COUNT });
        try self.hud.drawText(
            ctx.sprite_batch,
            coins_text,
            -screen_w / 2 + 20,
            -screen_h / 2 + 60,
            Color.white(),
        );

        // Draw health bar
        try self.hud.drawHealthBar(
            ctx.sprite_batch,
            self.player_health,
            self.max_health,
            0,
            screen_h / 2 - 30,
            200,
            20,
        );

        // Draw game over message
        if (self.game_over) {
            const msg = if (self.won) "YOU WIN!" else "TIME'S UP!";
            try self.hud.drawTextCentered(
                ctx.sprite_batch,
                msg,
                -20,
                if (self.won)
                    Color{ .r = 0.2, .g = 1.0, .b = 0.2, .a = 1.0 }
                else
                    Color{ .r = 1.0, .g = 0.2, .b = 0.2, .a = 1.0 },
            );

            try self.hud.drawTextCentered(
                ctx.sprite_batch,
                "Press ESC to quit",
                20,
                Color{ .r = 0.7, .g = 0.7, .b = 0.7, .a = 1.0 },
            );
        } else {
            // Draw instructions
            try self.hud.drawTextCentered(
                ctx.sprite_batch,
                "WASD/Arrows to move - Collect all coins!",
                screen_h / 2 - 60,
                Color{ .r = 0.8, .g = 0.8, .b = 0.8, .a = 1.0 },
            );
        }
    }

    fn drawBackground(self: *CollectorGame, ctx: *Context) !void {
        _ = self;
        // Draw grid lines
        const grid_size: f32 = 100.0;
        const line_thickness: f32 = 2.0;
        const grid_color = Color{ .r = 0.15, .g = 0.15, .b = 0.2, .a = 1.0 };

        // Vertical lines
        var x: f32 = -WORLD_WIDTH / 2.0;
        while (x <= WORLD_WIDTH / 2.0) : (x += grid_size) {
            try ctx.sprite_batch.addQuad(
                x,
                0,
                line_thickness,
                WORLD_HEIGHT,
                grid_color,
            );
        }

        // Horizontal lines
        var y: f32 = -WORLD_HEIGHT / 2.0;
        while (y <= WORLD_HEIGHT / 2.0) : (y += grid_size) {
            try ctx.sprite_batch.addQuad(
                0,
                y,
                WORLD_WIDTH,
                line_thickness,
                grid_color,
            );
        }
    }
};
