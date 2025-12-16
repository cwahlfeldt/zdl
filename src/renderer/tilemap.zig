const std = @import("std");
const sprite = @import("sprite.zig");
const SpriteBatch = sprite.SpriteBatch;
const Color = sprite.Color;

/// A tile in the tilemap
pub const Tile = enum(u8) {
    empty = 0,
    solid = 1,
    platform = 2,
    _,

    pub fn isSolid(self: Tile) bool {
        return @intFromEnum(self) != 0;
    }
};

/// Tilemap for 2D grid-based levels
pub const Tilemap = struct {
    tiles: []Tile,
    width: u32,
    height: u32,
    tile_size: f32,
    allocator: std.mem.Allocator,

    /// Create a new tilemap
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, tile_size: f32) !Tilemap {
        const tiles = try allocator.alloc(Tile, width * height);
        @memset(tiles, .empty);

        return .{
            .tiles = tiles,
            .width = width,
            .height = height,
            .tile_size = tile_size,
            .allocator = allocator,
        };
    }

    /// Load a tilemap from a simple string format
    /// Each character represents a tile: '.' = empty, '#' = solid, '-' = platform
    /// Rows are separated by newlines
    pub fn fromString(allocator: std.mem.Allocator, data: []const u8, tile_size: f32) !Tilemap {
        var lines = std.ArrayList([]const u8){};
        defer lines.deinit(allocator);

        var line_iter = std.mem.splitScalar(u8, data, '\n');
        while (line_iter.next()) |line| {
            if (line.len > 0) {
                try lines.append(allocator, line);
            }
        }

        if (lines.items.len == 0) {
            return error.InvalidTilemapData;
        }

        const height: u32 = @intCast(lines.items.len);
        const width: u32 = @intCast(lines.items[0].len);

        // Verify all rows have the same width
        for (lines.items) |line| {
            if (line.len != width) {
                return error.InconsistentRowWidth;
            }
        }

        var tilemap = try init(allocator, width, height, tile_size);

        for (lines.items, 0..) |line, row| {
            for (line, 0..) |char, col| {
                const tile: Tile = switch (char) {
                    '.' => .empty,
                    '#' => .solid,
                    '-' => .platform,
                    else => .empty,
                };
                tilemap.setTile(@intCast(col), @intCast(row), tile);
            }
        }

        return tilemap;
    }

    pub fn deinit(self: *Tilemap) void {
        self.allocator.free(self.tiles);
    }

    /// Get a tile at the given position
    pub fn getTile(self: Tilemap, x: u32, y: u32) Tile {
        if (x >= self.width or y >= self.height) {
            return .empty;
        }
        return self.tiles[y * self.width + x];
    }

    /// Set a tile at the given position
    pub fn setTile(self: *Tilemap, x: u32, y: u32, tile: Tile) void {
        if (x >= self.width or y >= self.height) {
            return;
        }
        self.tiles[y * self.width + x] = tile;
    }

    /// Get tile coordinates from world position
    pub fn worldToTile(self: Tilemap, world_x: f32, world_y: f32) struct { x: i32, y: i32 } {
        // Center the tilemap around (0, 0)
        const offset_x = @as(f32, @floatFromInt(self.width)) * self.tile_size / 2.0;
        const offset_y = @as(f32, @floatFromInt(self.height)) * self.tile_size / 2.0;

        const tile_x = @floor((world_x + offset_x) / self.tile_size);
        const tile_y = @floor((world_y + offset_y) / self.tile_size);

        return .{
            .x = @intFromFloat(tile_x),
            .y = @intFromFloat(tile_y),
        };
    }

    /// Get world position from tile coordinates (returns center of tile)
    pub fn tileToWorld(self: Tilemap, tile_x: u32, tile_y: u32) struct { x: f32, y: f32 } {
        const offset_x = @as(f32, @floatFromInt(self.width)) * self.tile_size / 2.0;
        const offset_y = @as(f32, @floatFromInt(self.height)) * self.tile_size / 2.0;

        return .{
            .x = @as(f32, @floatFromInt(tile_x)) * self.tile_size + self.tile_size / 2.0 - offset_x,
            .y = @as(f32, @floatFromInt(tile_y)) * self.tile_size + self.tile_size / 2.0 - offset_y,
        };
    }

    /// Check if a tile is solid at the given world position
    pub fn isSolidAtPosition(self: Tilemap, world_x: f32, world_y: f32) bool {
        const tile_pos = self.worldToTile(world_x, world_y);
        if (tile_pos.x < 0 or tile_pos.y < 0) return false;

        const tile_x: u32 = @intCast(tile_pos.x);
        const tile_y: u32 = @intCast(tile_pos.y);

        return self.getTile(tile_x, tile_y).isSolid();
    }

    /// Render the tilemap using colored quads
    /// tile_id_to_uv can be used to map tile types to UV coordinates for textured rendering
    pub fn render(self: Tilemap, batch: *SpriteBatch, tile_color: ?fn (Tile) Color) !void {
        const default_color = tile_color orelse defaultTileColor;

        for (0..self.height) |row| {
            for (0..self.width) |col| {
                const tile = self.getTile(@intCast(col), @intCast(row));
                if (@intFromEnum(tile) == 0) continue; // Skip empty tiles

                const world_pos = self.tileToWorld(@intCast(col), @intCast(row));
                const color = default_color(tile);

                try batch.addQuad(
                    world_pos.x,
                    world_pos.y,
                    self.tile_size,
                    self.tile_size,
                    color,
                );
            }
        }
    }

    /// Render the tilemap with texture support
    /// uv_fn should return UV coordinates for the given tile type
    pub fn renderTextured(
        self: Tilemap,
        batch: *SpriteBatch,
        uv_fn: fn (Tile) struct { left: f32, top: f32, right: f32, bottom: f32 },
        tint: Color,
    ) !void {
        for (0..self.height) |row| {
            for (0..self.width) |col| {
                const tile = self.getTile(@intCast(col), @intCast(row));
                if (@intFromEnum(tile) == 0) continue;

                const world_pos = self.tileToWorld(@intCast(col), @intCast(row));
                const uv = uv_fn(tile);

                try batch.addQuadUV(
                    world_pos.x,
                    world_pos.y,
                    self.tile_size,
                    self.tile_size,
                    tint,
                    uv.left,
                    uv.top,
                    uv.right,
                    uv.bottom,
                );
            }
        }
    }

    fn defaultTileColor(tile: Tile) Color {
        return switch (tile) {
            .empty => Color.white(),
            .solid => Color.blue(),
            .platform => Color.green(),
            _ => Color.white(),
        };
    }
};

/// Simple AABB collision check against tilemap
pub fn checkAABBCollision(
    tilemap: Tilemap,
    aabb_x: f32,
    aabb_y: f32,
    aabb_width: f32,
    aabb_height: f32,
) bool {
    // Get tile bounds for the AABB
    const min_tile = tilemap.worldToTile(aabb_x, aabb_y);
    const max_tile = tilemap.worldToTile(aabb_x + aabb_width, aabb_y + aabb_height);

    // Check all tiles that the AABB overlaps
    const start_x = @max(0, min_tile.x);
    const start_y = @max(0, min_tile.y);
    const end_x = @min(@as(i32, @intCast(tilemap.width)) - 1, max_tile.x);
    const end_y = @min(@as(i32, @intCast(tilemap.height)) - 1, max_tile.y);

    var y = start_y;
    while (y <= end_y) : (y += 1) {
        var x = start_x;
        while (x <= end_x) : (x += 1) {
            const tile = tilemap.getTile(@intCast(x), @intCast(y));
            if (tile.isSolid()) {
                return true;
            }
        }
    }

    return false;
}
