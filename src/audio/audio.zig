const std = @import("std");
const sdl = @import("sdl3");

/// Audio system for playing sound effects and music
/// Note: This is a simplified audio system. For production use, consider
/// implementing proper stream management and device binding.
pub const Audio = struct {
    allocator: std.mem.Allocator,
    sounds: std.StringHashMap(Sound),

    pub fn init(allocator: std.mem.Allocator) !Audio {
        // Initialize SDL audio subsystem
        try sdl.init(.{ .audio = true });

        return .{
            .allocator = allocator,
            .sounds = std.StringHashMap(Sound).init(allocator),
        };
    }

    pub fn deinit(self: *Audio) void {
        var iter = self.sounds.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.sounds.deinit();
        sdl.quit(.{ .audio = true });
    }

    /// Load a WAV file
    pub fn loadWAV(self: *Audio, name: []const u8, path: []const u8) !void {
        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);

        const sound = try Sound.loadWAV(self.allocator, path);
        try self.sounds.put(name_owned, sound);
    }

    /// Play a sound by name
    pub fn playSound(self: *Audio, name: []const u8, volume: f32) !void {
        if (self.sounds.get(name)) |*sound| {
            try sound.play(volume);
        } else {
            return error.SoundNotFound;
        }
    }

    /// Stop all instances of a sound
    pub fn stopSound(self: *Audio, name: []const u8) void {
        if (self.sounds.getPtr(name)) |sound| {
            sound.stop();
        }
    }

    /// Stop all sounds
    pub fn stopAll(self: *Audio) void {
        var iter = self.sounds.valueIterator();
        while (iter.next()) |sound| {
            sound.stop();
        }
    }
};

/// Individual sound effect or music track
pub const Sound = struct {
    spec: sdl.audio.Spec,
    buffer: []u8,
    allocator: std.mem.Allocator,
    stream: ?sdl.audio.Stream,

    /// Load a WAV file from disk
    pub fn loadWAV(allocator: std.mem.Allocator, path: []const u8) !Sound {
        // Convert path to null-terminated
        var path_z: [std.fs.MAX_PATH_BYTES:0]u8 = undefined;
        const path_z_slice = try std.fmt.bufPrintZ(&path_z, "{s}", .{path});

        const spec, const data = try sdl.audio.loadWav(path_z_slice);

        // Copy the buffer data since SDL's buffer needs to be freed
        const buffer = try allocator.dupe(u8, data);

        // Free SDL's buffer
        sdl.free(data.ptr);

        return .{
            .spec = spec,
            .buffer = buffer,
            .allocator = allocator,
            .stream = null,
        };
    }

    pub fn deinit(self: *Sound) void {
        if (self.stream) |stream| {
            stream.deinit();
        }
        self.allocator.free(self.buffer);
    }

    /// Play the sound once
    pub fn play(self: *Sound, volume: f32) !void {
        // Stop any currently playing instance
        self.stop();

        // Create an audio stream for playback
        // Use default output spec (null)
        const stream = try sdl.audio.Stream.init(self.spec, self.spec);

        // Store the stream
        self.stream = stream;

        // Set volume (0.0 to 1.0)
        try stream.setGain(@max(0.0, @min(1.0, volume)));

        // Put audio data into the stream
        try stream.putData(self.buffer);

        // Flush the stream to ensure it starts playing
        try stream.flush();

        // Resume playback
        try stream.resumeDevice();
    }

    /// Stop the sound (if it has a stream)
    pub fn stop(self: *Sound) void {
        if (self.stream) |stream| {
            stream.deinit();
            self.stream = null;
        }
    }
};
