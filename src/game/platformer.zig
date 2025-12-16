const std = @import("std");
const Application = @import("../engine/application.zig");
const Context = Application.Context;
const Input = @import("../input/input.zig").Input;
const math = @import("../math/math.zig");
const Vec2 = math.Vec2;
const sprite = @import("../renderer/sprite.zig");
const Color = sprite.Color;

// Simple AABB for collision detection
const AABB = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    fn intersects(self: AABB, other: AABB) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    fn fromCenter(x: f32, y: f32, width: f32, height: f32) AABB {
        return .{
            .x = x - width / 2.0,
            .y = y - height / 2.0,
            .width = width,
            .height = height,
        };
    }
};

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

    fn init() Player {
        return .{
            .position = Vec2.init(0, 0),
            .velocity = Vec2.zero(),
            .width = 50,
            .height = 50,
            .speed = 200,
            .is_grounded = false,
        };
    }

    fn update(self: *Player, input: *Input, delta_time: f32, platforms: []const AABB) void {
        const wasd = input.getWASD();
        const arrows = input.getArrowKeys();
        const horizontal_input = wasd.x + arrows.x;

        self.velocity.y += GRAVITY * delta_time;
        self.velocity.x = horizontal_input * self.speed;

        var next_pos_x = self.position;
        next_pos_x.x += self.velocity.x * delta_time;

        const player_aabb_x = AABB.fromCenter(next_pos_x.x, next_pos_x.y, self.width, self.height);
        var x_collided = false;
        for (platforms) |platform| {
            if (player_aabb_x.intersects(platform)) {
                x_collided = true;
                break;
            }
        }

        if (!x_collided) {
            self.position.x = next_pos_x.x;
        }

        var next_pos_y = self.position;
        next_pos_y.y += self.velocity.y * delta_time;

        const player_aabb_y = AABB.fromCenter(next_pos_y.x, next_pos_y.y, self.width, self.height);
        var y_collided = false;
        self.is_grounded = false;

        for (platforms) |platform| {
            if (player_aabb_y.intersects(platform)) {
                y_collided = true;
                if (self.velocity.y > 0) {
                    self.is_grounded = true;
                }
                self.velocity.y = 0;
                break;
            }
        }

        if (!y_collided) {
            self.position.y = next_pos_y.y;
        }

        if (self.is_grounded and (input.isKeyJustPressed(.space) or input.isKeyJustPressed(.w) or input.isKeyJustPressed(.up))) {
            self.velocity.y = JUMP_VELOCITY;
            self.is_grounded = false;
        }
    }

    fn getAABB(self: Player) AABB {
        return AABB.fromCenter(self.position.x, self.position.y, self.width, self.height);
    }
};

/// Platformer game implementation
pub const PlatformerGame = struct {
    player: Player,
    platforms: [6]AABB,

    pub fn init(self: *PlatformerGame, ctx: *Context) !void {
        _ = ctx;
        self.* = .{
            .player = Player.init(),
            .platforms = [_]AABB{
                .{ .x = -300, .y = 200, .width = 600, .height = 50 },
                .{ .x = -200, .y = 50, .width = 150, .height = 30 },
                .{ .x = 50, .y = 50, .width = 150, .height = 30 },
                .{ .x = -100, .y = -100, .width = 200, .height = 30 },
                .{ .x = -350, .y = -200, .width = 50, .height = 400 },
                .{ .x = 300, .y = -200, .width = 50, .height = 400 },
            },
        };
    }

    pub fn deinit(self: *PlatformerGame, ctx: *Context) void {
        _ = self;
        _ = ctx;
    }

    pub fn update(self: *PlatformerGame, ctx: *Context, delta_time: f32) !void {
        self.player.update(ctx.input, delta_time, &self.platforms);
    }

    pub fn render(self: *PlatformerGame, ctx: *Context) !void {
        // Draw platforms
        for (self.platforms) |platform| {
            try ctx.sprite_batch.addQuad(
                platform.x + platform.width / 2.0,
                platform.y + platform.height / 2.0,
                platform.width,
                platform.height,
                Color.blue(),
            );
        }

        // Draw player
        try ctx.sprite_batch.addQuad(
            self.player.position.x,
            self.player.position.y,
            self.player.width,
            self.player.height,
            Color.red(),
        );
    }
};
