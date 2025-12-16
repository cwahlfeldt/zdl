const std = @import("std");
const zdl = @import("engine");
const Application = zdl.Application;
const Context = zdl.Context;
const Input = zdl.Input;
const Vec2 = zdl.Vec2;
const Color = zdl.Color;
const Tilemap = zdl.Tilemap;
const Tile = zdl.Tile;

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

    fn update(self: *Player, input: *Input, delta_time: f32, tilemap: *const Tilemap) void {
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
            }
            self.velocity.y = 0;
        } else {
            self.position.y = next_pos_y.y;
        }

        // Jump
        if (self.is_grounded and (input.isKeyJustPressed(.space) or input.isKeyJustPressed(.w) or input.isKeyJustPressed(.up))) {
            self.velocity.y = JUMP_VELOCITY;
            self.is_grounded = false;
        }
    }
};

/// Platformer game implementation
pub const PlatformerGame = struct {
    player: Player,
    tilemap: Tilemap,

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

        self.* = .{
            .player = Player.init(),
            .tilemap = tilemap,
        };
    }

    pub fn deinit(self: *PlatformerGame, ctx: *Context) void {
        _ = ctx;
        self.tilemap.deinit();
    }

    pub fn update(self: *PlatformerGame, ctx: *Context, delta_time: f32) !void {
        self.player.update(ctx.input, delta_time, &self.tilemap);
    }

    pub fn render(self: *PlatformerGame, ctx: *Context) !void {
        // Draw tilemap
        try self.tilemap.render(ctx.sprite_batch, null);

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
