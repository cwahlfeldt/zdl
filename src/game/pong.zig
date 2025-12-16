const std = @import("std");
const Application = @import("../engine/application.zig");
const Context = Application.Context;
const Input = @import("../input/input.zig").Input;
const math = @import("../math/math.zig");
const Vec2 = math.Vec2;
const sprite = @import("../renderer/sprite.zig");
const Color = sprite.Color;

const PADDLE_WIDTH: f32 = 20;
const PADDLE_HEIGHT: f32 = 100;
const PADDLE_SPEED: f32 = 400;
const BALL_SIZE: f32 = 15;
const BALL_SPEED: f32 = 300;

const Paddle = struct {
    y: f32,

    fn update(self: *Paddle, input: *Input, delta_time: f32, is_left: bool) void {
        var dy: f32 = 0;

        if (is_left) {
            if (input.isKeyDown(.w)) dy -= 1;
            if (input.isKeyDown(.s)) dy += 1;
        } else {
            if (input.isKeyDown(.up)) dy -= 1;
            if (input.isKeyDown(.down)) dy += 1;
        }

        self.y += dy * PADDLE_SPEED * delta_time;

        // Clamp to screen bounds
        const half_height = PADDLE_HEIGHT / 2.0;
        if (self.y < -270 + half_height) self.y = -270 + half_height;
        if (self.y > 270 - half_height) self.y = 270 - half_height;
    }
};

const Ball = struct {
    position: Vec2,
    velocity: Vec2,

    fn reset(self: *Ball) void {
        self.position = Vec2.zero();
        self.velocity = Vec2.init(BALL_SPEED, BALL_SPEED * 0.5);
    }

    fn update(self: *Ball, delta_time: f32, left_paddle: *Paddle, right_paddle: *Paddle, score_left: *u32, score_right: *u32) void {
        self.position.x += self.velocity.x * delta_time;
        self.position.y += self.velocity.y * delta_time;

        // Bounce off top/bottom
        if (self.position.y < -270 or self.position.y > 270) {
            self.velocity.y = -self.velocity.y;
        }

        // Paddle collision
        const paddle_x_left: f32 = -450;
        const paddle_x_right: f32 = 450;

        // Left paddle
        if (self.position.x - BALL_SIZE / 2 < paddle_x_left + PADDLE_WIDTH / 2) {
            if (self.position.y > left_paddle.y - PADDLE_HEIGHT / 2 and
                self.position.y < left_paddle.y + PADDLE_HEIGHT / 2) {
                self.velocity.x = @abs(self.velocity.x);
            }
        }

        // Right paddle
        if (self.position.x + BALL_SIZE / 2 > paddle_x_right - PADDLE_WIDTH / 2) {
            if (self.position.y > right_paddle.y - PADDLE_HEIGHT / 2 and
                self.position.y < right_paddle.y + PADDLE_HEIGHT / 2) {
                self.velocity.x = -@abs(self.velocity.x);
            }
        }

        // Scoring
        if (self.position.x < -480) {
            score_right.* += 1;
            self.reset();
        } else if (self.position.x > 480) {
            score_left.* += 1;
            self.reset();
        }
    }
};

/// Simple Pong game implementation
pub const PongGame = struct {
    left_paddle: Paddle,
    right_paddle: Paddle,
    ball: Ball,
    score_left: u32,
    score_right: u32,

    pub fn init(self: *PongGame, ctx: *Context) !void {
        _ = ctx;
        self.* = .{
            .left_paddle = .{ .y = 0 },
            .right_paddle = .{ .y = 0 },
            .ball = .{
                .position = Vec2.zero(),
                .velocity = Vec2.init(BALL_SPEED, BALL_SPEED * 0.5),
            },
            .score_left = 0,
            .score_right = 0,
        };
    }

    pub fn deinit(self: *PongGame, ctx: *Context) void {
        _ = self;
        _ = ctx;
    }

    pub fn update(self: *PongGame, ctx: *Context, delta_time: f32) !void {
        self.left_paddle.update(ctx.input, delta_time, true);
        self.right_paddle.update(ctx.input, delta_time, false);
        self.ball.update(delta_time, &self.left_paddle, &self.right_paddle, &self.score_left, &self.score_right);
    }

    pub fn render(self: *PongGame, ctx: *Context) !void {
        // Draw paddles
        try ctx.sprite_batch.addQuad(
            -450,
            self.left_paddle.y,
            PADDLE_WIDTH,
            PADDLE_HEIGHT,
            Color.white(),
        );

        try ctx.sprite_batch.addQuad(
            450,
            self.right_paddle.y,
            PADDLE_WIDTH,
            PADDLE_HEIGHT,
            Color.white(),
        );

        // Draw ball
        try ctx.sprite_batch.addQuad(
            self.ball.position.x,
            self.ball.position.y,
            BALL_SIZE,
            BALL_SIZE,
            Color.white(),
        );

        // Draw center line (dashed)
        var y: f32 = -270;
        while (y < 270) : (y += 30) {
            try ctx.sprite_batch.addQuad(0, y, 4, 20, Color.white());
        }
    }
};
