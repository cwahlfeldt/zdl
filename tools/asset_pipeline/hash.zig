const std = @import("std");

/// Compute a hash of file contents for change detection
pub fn hashFile(path: []const u8) !u64 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return hashFileHandle(file);
}

/// Hash from an open file handle
pub fn hashFileHandle(file: std.fs.File) !u64 {
    var hasher = std.hash.XxHash64.init(0);

    var buf: [8192]u8 = undefined;
    while (true) {
        const bytes_read = try file.read(&buf);
        if (bytes_read == 0) break;
        hasher.update(buf[0..bytes_read]);
    }

    return hasher.final();
}

/// Hash arbitrary bytes
pub fn hashBytes(data: []const u8) u64 {
    var hasher = std.hash.XxHash64.init(0);
    hasher.update(data);
    return hasher.final();
}

/// Hash a string (for path-based lookups)
pub fn hashString(s: []const u8) u64 {
    return hashBytes(s);
}

/// Get file modification time
pub fn getFileModTime(path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.mtime;
}

/// Check if a file exists
pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

test "hashBytes" {
    const testing = std.testing;

    const hash1 = hashBytes("hello");
    const hash2 = hashBytes("hello");
    const hash3 = hashBytes("world");

    try testing.expectEqual(hash1, hash2);
    try testing.expect(hash1 != hash3);
}
