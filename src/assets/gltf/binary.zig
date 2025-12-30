const std = @import("std");
const GLTFError = @import("types.zig").GLTFError;

/// GLB file magic number ("glTF" in little-endian)
const GLB_MAGIC: u32 = 0x46546C67;

/// GLB version we support
const GLB_VERSION: u32 = 2;

/// JSON chunk type
const CHUNK_TYPE_JSON: u32 = 0x4E4F534A; // "JSON"

/// Binary chunk type
const CHUNK_TYPE_BIN: u32 = 0x004E4942; // "BIN\0"

/// GLB file header (12 bytes)
pub const GLBHeader = extern struct {
    magic: u32,
    version: u32,
    length: u32,
};

/// GLB chunk header (8 bytes)
pub const GLBChunkHeader = extern struct {
    chunk_length: u32,
    chunk_type: u32,
};

/// Result of parsing a GLB file
pub const GLBParseResult = struct {
    json_data: []const u8,
    bin_data: ?[]const u8,
};

/// Parse a GLB (binary glTF) file
/// Returns slices into the input data - does not allocate
pub fn parseGLB(data: []const u8) GLTFError!GLBParseResult {
    if (data.len < @sizeOf(GLBHeader)) {
        return GLTFError.InvalidMagic;
    }

    // Read header
    const header = std.mem.bytesAsValue(GLBHeader, data[0..@sizeOf(GLBHeader)]);

    if (header.magic != GLB_MAGIC) {
        return GLTFError.InvalidMagic;
    }

    if (header.version != GLB_VERSION) {
        return GLTFError.UnsupportedVersion;
    }

    if (header.length > data.len) {
        return GLTFError.BufferOutOfBounds;
    }

    var offset: usize = @sizeOf(GLBHeader);
    var json_data: ?[]const u8 = null;
    var bin_data: ?[]const u8 = null;

    // Read chunks
    while (offset + @sizeOf(GLBChunkHeader) <= data.len) {
        const chunk_header = std.mem.bytesAsValue(
            GLBChunkHeader,
            data[offset..][0..@sizeOf(GLBChunkHeader)],
        );
        offset += @sizeOf(GLBChunkHeader);

        const chunk_end = offset + chunk_header.chunk_length;
        if (chunk_end > data.len) {
            return GLTFError.BufferOutOfBounds;
        }

        const chunk_data = data[offset..chunk_end];

        switch (chunk_header.chunk_type) {
            CHUNK_TYPE_JSON => {
                json_data = chunk_data;
            },
            CHUNK_TYPE_BIN => {
                bin_data = chunk_data;
            },
            else => {
                // Unknown chunk type - skip (per spec, unknown chunks should be ignored)
            },
        }

        offset = chunk_end;

        // Chunks are 4-byte aligned
        offset = (offset + 3) & ~@as(usize, 3);
    }

    if (json_data == null) {
        return GLTFError.InvalidJSON;
    }

    return .{
        .json_data = json_data.?,
        .bin_data = bin_data,
    };
}

/// Check if data starts with GLB magic number
pub fn isGLB(data: []const u8) bool {
    if (data.len < 4) return false;
    const magic = std.mem.readInt(u32, data[0..4], .little);
    return magic == GLB_MAGIC;
}

/// Check if a file path is a GLB file based on extension
pub fn isGLBPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".glb") or std.mem.endsWith(u8, path, ".GLB");
}

test "GLB header size" {
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(GLBHeader));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(GLBChunkHeader));
}

test "isGLB detection" {
    // Valid GLB magic
    const valid = [_]u8{ 0x67, 0x6C, 0x54, 0x46, 0x02, 0x00, 0x00, 0x00 };
    try std.testing.expect(isGLB(&valid));

    // Invalid data
    const invalid = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expect(!isGLB(&invalid));

    // Too short
    const short = [_]u8{ 0x67, 0x6C };
    try std.testing.expect(!isGLB(&short));
}
