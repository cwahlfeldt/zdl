# Audio System Enhancement

## Overview

Enhance ZDL's audio system from basic WAV playback to a full-featured spatial audio engine supporting 3D positioning, effects, music systems, and runtime mixing. This enables immersive audio experiences for games.

## Current State

ZDL currently has:
- Basic WAV loading via SDL
- Simple playback with volume control
- Named sound storage
- No spatial audio
- No effects processing
- No streaming support

## Goals

- 3D spatial audio with HRTF support
- Audio streaming for music and long sounds
- Real-time DSP effects (reverb, EQ, etc.)
- Sound categories with mixing buses
- Music system with crossfading
- Audio occlusion and obstruction
- Ambient sound zones
- Audio compression formats (OGG, MP3)
- Runtime parameter control

## Architecture

### Directory Structure

```
src/
├── audio/
│   ├── audio.zig              # Module exports (existing)
│   ├── audio_engine.zig       # Core audio engine
│   ├── sound.zig              # Sound asset
│   ├── sound_instance.zig     # Playing sound instance
│   ├── audio_source.zig       # 3D audio source component
│   ├── audio_listener.zig     # Listener component
│   ├── mixer.zig              # Audio mixing
│   ├── bus.zig                # Mixing buses
│   ├── effects/
│   │   ├── effects.zig        # Effect module
│   │   ├── reverb.zig         # Reverb effect
│   │   ├── lowpass.zig        # Low-pass filter
│   │   ├── delay.zig          # Delay/echo
│   │   └── compressor.zig     # Dynamic compressor
│   ├── spatial/
│   │   ├── spatial.zig        # Spatial audio
│   │   ├── hrtf.zig           # HRTF processing
│   │   └── occlusion.zig      # Audio occlusion
│   ├── music/
│   │   ├── music.zig          # Music system
│   │   ├── music_player.zig   # Streaming playback
│   │   └── playlist.zig       # Playlist management
│   └── streaming.zig          # Audio streaming
```

### Core Components

#### Audio Engine

```zig
pub const AudioEngine = struct {
    allocator: Allocator,
    device: *sdl.audio.Device,
    spec: sdl.audio.Spec,

    // Mixing
    master_bus: *AudioBus,
    buses: std.StringHashMap(*AudioBus),

    // Active sounds
    instances: std.ArrayList(*SoundInstance),
    max_voices: u32,

    // Spatial
    listener: ?*AudioListener,
    spatial_processor: SpatialProcessor,

    // Streaming
    stream_buffer_size: u32,
    stream_pool: StreamPool,

    // Global settings
    master_volume: f32,
    doppler_factor: f32,
    speed_of_sound: f32,

    pub fn init(allocator: Allocator, config: AudioConfig) !AudioEngine;
    pub fn deinit(self: *AudioEngine) void;

    // Sound playback
    pub fn play(self: *AudioEngine, sound: *Sound) *SoundInstance;
    pub fn playAt(self: *AudioEngine, sound: *Sound, position: Vec3) *SoundInstance;
    pub fn playOnBus(self: *AudioEngine, sound: *Sound, bus: []const u8) *SoundInstance;

    // Bus management
    pub fn createBus(self: *AudioEngine, name: []const u8, parent: ?[]const u8) !*AudioBus;
    pub fn getBus(self: *AudioEngine, name: []const u8) ?*AudioBus;

    // Update
    pub fn update(self: *AudioEngine, dt: f32) void;

    // Global control
    pub fn setMasterVolume(self: *AudioEngine, volume: f32) void;
    pub fn pauseAll(self: *AudioEngine) void;
    pub fn resumeAll(self: *AudioEngine) void;
    pub fn stopAll(self: *AudioEngine) void;
};

pub const AudioConfig = struct {
    sample_rate: u32 = 48000,
    channels: u32 = 2,
    buffer_size: u32 = 1024,
    max_voices: u32 = 64,
    stream_buffer_size: u32 = 16384,
    enable_hrtf: bool = true,
};
```

#### Sound Asset

```zig
pub const Sound = struct {
    name: []const u8,
    format: AudioFormat,

    // Data
    samples: ?[]f32,           // Decoded PCM (for short sounds)
    stream_path: ?[]const u8,  // Path for streaming

    // Properties
    duration: f32,
    channels: u32,
    sample_rate: u32,

    // Playback defaults
    default_volume: f32,
    default_pitch: f32,
    is_3d: bool,
    loop: bool,

    // 3D settings
    min_distance: f32,
    max_distance: f32,
    rolloff: RolloffMode,

    pub fn loadFromFile(allocator: Allocator, path: []const u8) !Sound;
    pub fn loadWAV(allocator: Allocator, path: []const u8) !Sound;
    pub fn loadOGG(allocator: Allocator, path: []const u8) !Sound;
    pub fn createStreaming(path: []const u8) Sound;
    pub fn deinit(self: *Sound) void;
};

pub const AudioFormat = enum {
    wav,
    ogg,
    mp3,
    flac,
};

pub const RolloffMode = enum {
    linear,
    logarithmic,
    inverse,
    custom,
};
```

#### Sound Instance

```zig
pub const SoundInstance = struct {
    sound: *Sound,
    state: PlayState,

    // Playback
    position_samples: u64,
    volume: f32,
    pitch: f32,
    pan: f32,

    // 3D
    spatial: ?SpatialState,

    // Looping
    loop: bool,
    loop_start: u64,
    loop_end: u64,

    // Fading
    fade_target: ?f32,
    fade_duration: f32,
    fade_time: f32,

    // Bus routing
    bus: *AudioBus,

    // Streaming state
    stream: ?*AudioStream,

    pub fn play(self: *SoundInstance) void;
    pub fn pause(self: *SoundInstance) void;
    pub fn stop(self: *SoundInstance) void;

    pub fn setVolume(self: *SoundInstance, volume: f32) void;
    pub fn setPitch(self: *SoundInstance, pitch: f32) void;
    pub fn setPosition(self: *SoundInstance, position: Vec3) void;
    pub fn setVelocity(self: *SoundInstance, velocity: Vec3) void;

    pub fn fadeIn(self: *SoundInstance, duration: f32) void;
    pub fn fadeOut(self: *SoundInstance, duration: f32) void;
    pub fn fadeTo(self: *SoundInstance, target: f32, duration: f32) void;

    pub fn isPlaying(self: *SoundInstance) bool;
    pub fn getTime(self: *SoundInstance) f32;
    pub fn setTime(self: *SoundInstance, time: f32) void;
};

pub const PlayState = enum {
    stopped,
    playing,
    paused,
    fading_out,
};

pub const SpatialState = struct {
    position: Vec3,
    velocity: Vec3,
    direction: Vec3,
    cone_inner_angle: f32,
    cone_outer_angle: f32,
    cone_outer_gain: f32,
};
```

#### Audio Source Component

```zig
pub const AudioSourceComponent = struct {
    // Sound reference
    sound: ?*Sound,
    instance: ?*SoundInstance,

    // Playback settings
    play_on_start: bool,
    volume: f32,
    pitch: f32,
    loop: bool,

    // 3D settings
    spatial: bool,
    min_distance: f32,
    max_distance: f32,
    rolloff: RolloffMode,

    // Directional
    directional: bool,
    cone_inner_angle: f32,
    cone_outer_angle: f32,
    cone_outer_volume: f32,

    // Bus routing
    bus: []const u8,

    pub fn init() AudioSourceComponent;
    pub fn play(self: *AudioSourceComponent, engine: *AudioEngine) void;
    pub fn stop(self: *AudioSourceComponent) void;
    pub fn setVolume(self: *AudioSourceComponent, volume: f32) void;
};

pub const AudioListenerComponent = struct {
    // Usually attached to camera entity
    active: bool,

    pub fn init() AudioListenerComponent;
};
```

### Mixing System

#### Audio Bus

```zig
pub const AudioBus = struct {
    name: []const u8,
    parent: ?*AudioBus,
    children: std.ArrayList(*AudioBus),

    // Volume
    volume: f32,
    muted: bool,

    // Effects chain
    effects: std.ArrayList(*AudioEffect),

    // Output buffer
    buffer: []f32,

    // Metering
    peak_level: f32,
    rms_level: f32,

    pub fn init(allocator: Allocator, name: []const u8) !AudioBus;

    pub fn setVolume(self: *AudioBus, volume: f32) void;
    pub fn setMuted(self: *AudioBus, muted: bool) void;

    pub fn addEffect(self: *AudioBus, effect: *AudioEffect) void;
    pub fn removeEffect(self: *AudioBus, effect: *AudioEffect) void;
    pub fn bypassEffect(self: *AudioBus, index: u32, bypass: bool) void;

    pub fn process(self: *AudioBus, samples: u32) void;
    pub fn getEffectiveVolume(self: *AudioBus) f32;
};

// Standard bus hierarchy
pub const StandardBuses = struct {
    pub const master = "Master";
    pub const music = "Music";
    pub const sfx = "SFX";
    pub const voice = "Voice";
    pub const ambient = "Ambient";
    pub const ui = "UI";
};
```

### Audio Effects

```zig
pub const AudioEffect = struct {
    effect_type: EffectType,
    bypassed: bool,
    params: EffectParams,
    state: *anyopaque,

    pub fn process(self: *AudioEffect, buffer: []f32, channels: u32) void;
    pub fn setParameter(self: *AudioEffect, param: []const u8, value: f32) void;
    pub fn reset(self: *AudioEffect) void;
};

pub const EffectType = enum {
    reverb,
    delay,
    lowpass,
    highpass,
    bandpass,
    compressor,
    limiter,
    chorus,
    distortion,
    eq,
};

pub const ReverbEffect = struct {
    room_size: f32,
    damping: f32,
    wet: f32,
    dry: f32,
    width: f32,
    pre_delay: f32,

    // Internal state
    comb_filters: [8]CombFilter,
    allpass_filters: [4]AllpassFilter,

    pub fn init() ReverbEffect;
    pub fn process(self: *ReverbEffect, buffer: []f32) void;
};

pub const LowpassEffect = struct {
    cutoff: f32,
    resonance: f32,

    // State
    z1: [2]f32,
    z2: [2]f32,

    pub fn init(cutoff: f32) LowpassEffect;
    pub fn process(self: *LowpassEffect, buffer: []f32) void;
};

pub const CompressorEffect = struct {
    threshold: f32,
    ratio: f32,
    attack: f32,
    release: f32,
    makeup_gain: f32,

    // State
    envelope: f32,

    pub fn init() CompressorEffect;
    pub fn process(self: *CompressorEffect, buffer: []f32) void;
};
```

### Spatial Audio

```zig
pub const SpatialProcessor = struct {
    hrtf_enabled: bool,
    hrtf_data: ?*HRTFData,

    pub fn init(allocator: Allocator, enable_hrtf: bool) !SpatialProcessor;

    pub fn processSource(
        self: *SpatialProcessor,
        source: *SoundInstance,
        listener: *AudioListener,
        output: []f32,
    ) void;

    fn calculateAttenuation(
        distance: f32,
        min_dist: f32,
        max_dist: f32,
        rolloff: RolloffMode,
    ) f32;

    fn calculatePan(direction: Vec3) f32;
    fn calculateDoppler(source_vel: Vec3, listener_vel: Vec3, direction: Vec3) f32;
};

pub const HRTFData = struct {
    // Head-Related Transfer Function data
    ir_left: [][]f32,   // Impulse responses per direction
    ir_right: [][]f32,
    elevation_count: u32,
    azimuth_count: u32,

    pub fn loadFromFile(allocator: Allocator, path: []const u8) !HRTFData;
    pub fn getIR(self: *HRTFData, azimuth: f32, elevation: f32) struct { []f32, []f32 };
};

pub const AudioOcclusion = struct {
    physics_world: *PhysicsWorld,

    pub fn calculateOcclusion(
        self: *AudioOcclusion,
        source_pos: Vec3,
        listener_pos: Vec3,
    ) OcclusionResult;
};

pub const OcclusionResult = struct {
    direct: f32,       // Direct path attenuation (0-1)
    indirect: f32,     // Indirect/reflection level
    lowpass: f32,      // Muffling amount (cutoff frequency factor)
};
```

### Music System

```zig
pub const MusicPlayer = struct {
    current_track: ?*MusicTrack,
    next_track: ?*MusicTrack,

    volume: f32,
    crossfade_duration: f32,
    crossfade_time: f32,

    playlist: ?*Playlist,
    shuffle: bool,
    repeat: RepeatMode,

    // Streaming
    stream: *AudioStream,
    buffer_ahead: f32,

    pub fn init(allocator: Allocator) !MusicPlayer;

    pub fn play(self: *MusicPlayer, track: *MusicTrack) void;
    pub fn playWithFade(self: *MusicPlayer, track: *MusicTrack, duration: f32) void;
    pub fn stop(self: *MusicPlayer) void;
    pub fn stopWithFade(self: *MusicPlayer, duration: f32) void;
    pub fn pause(self: *MusicPlayer) void;
    pub fn resume(self: *MusicPlayer) void;

    pub fn setPlaylist(self: *MusicPlayer, playlist: *Playlist) void;
    pub fn next(self: *MusicPlayer) void;
    pub fn previous(self: *MusicPlayer) void;

    pub fn setVolume(self: *MusicPlayer, volume: f32) void;
    pub fn getTime(self: *MusicPlayer) f32;
    pub fn setTime(self: *MusicPlayer, time: f32) void;

    pub fn update(self: *MusicPlayer, dt: f32) void;
};

pub const MusicTrack = struct {
    name: []const u8,
    path: []const u8,
    duration: f32,

    // Looping
    loop: bool,
    loop_start: f32,
    loop_end: f32,

    // Intensity layers (for adaptive music)
    layers: ?[]MusicLayer,

    // Beat sync
    bpm: ?f32,
    time_signature: ?struct { u32, u32 },
};

pub const MusicLayer = struct {
    path: []const u8,
    intensity_min: f32,
    intensity_max: f32,
    fade_in: f32,
    fade_out: f32,
};

pub const Playlist = struct {
    tracks: std.ArrayList(*MusicTrack),
    current_index: usize,

    pub fn add(self: *Playlist, track: *MusicTrack) void;
    pub fn remove(self: *Playlist, index: usize) void;
    pub fn shuffle(self: *Playlist) void;
    pub fn next(self: *Playlist) ?*MusicTrack;
    pub fn previous(self: *Playlist) ?*MusicTrack;
};

pub const RepeatMode = enum {
    none,
    one,
    all,
};
```

### Audio System (ECS)

```zig
pub const AudioSystem = struct {
    engine: *AudioEngine,

    pub fn init(engine: *AudioEngine) AudioSystem;

    pub fn update(self: *AudioSystem, scene: *Scene, dt: f32) void {
        // Find active listener
        const listeners = scene.query(.{ AudioListenerComponent, TransformComponent });
        var active_listener: ?struct { Vec3, Vec3, Quat } = null;

        for (listeners) |listener_comp, transform| {
            if (listener_comp.active) {
                active_listener = .{
                    transform.getWorldPosition(),
                    transform.velocity,  // If available
                    transform.getWorldRotation(),
                };
                break;
            }
        }

        if (active_listener) |listener| {
            self.engine.listener.position = listener[0];
            self.engine.listener.velocity = listener[1];
            self.engine.listener.rotation = listener[2];
        }

        // Update audio sources
        const sources = scene.query(.{ AudioSourceComponent, TransformComponent });

        for (sources) |source, transform| {
            if (source.instance) |instance| {
                if (source.spatial) {
                    instance.setPosition(transform.getWorldPosition());
                }
            }
        }

        // Update engine
        self.engine.update(dt);
    }

    pub fn onEntityCreated(self: *AudioSystem, entity: Entity, scene: *Scene) void {
        if (scene.getComponent(entity, AudioSourceComponent)) |source| {
            if (source.play_on_start and source.sound != null) {
                source.play(self.engine);
            }
        }
    }
};
```

## Usage Examples

### Basic Sound Playback

```zig
// Load sound
const explosion_sound = try audio.loadSound("sounds/explosion.wav");

// Play once
audio.play(explosion_sound);

// Play with settings
const instance = audio.play(explosion_sound);
instance.setVolume(0.8);
instance.setPitch(1.2);
```

### 3D Spatial Audio

```zig
// Create audio source entity
const enemy = try scene.createEntity();
try scene.addComponent(enemy, TransformComponent.withPosition(Vec3.init(10, 0, 5)));
try scene.addComponent(enemy, AudioSourceComponent{
    .sound = growl_sound,
    .spatial = true,
    .min_distance = 1.0,
    .max_distance = 50.0,
    .loop = true,
});

// Create listener (usually on camera)
const camera = try scene.createEntity();
try scene.addComponent(camera, AudioListenerComponent{ .active = true });
try scene.addComponent(camera, TransformComponent.init());
try scene.addComponent(camera, CameraComponent.init());
```

### Bus-Based Mixing

```zig
// Create buses
const sfx_bus = try audio.createBus("SFX", "Master");
const music_bus = try audio.createBus("Music", "Master");
const ambient_bus = try audio.createBus("Ambient", "Master");

// Add reverb to ambient bus
const reverb = ReverbEffect.init();
reverb.room_size = 0.8;
reverb.wet = 0.3;
ambient_bus.addEffect(&reverb);

// Play on specific bus
const rain = audio.playOnBus(rain_sound, "Ambient");

// Control bus volume
audio.getBus("Music").?.setVolume(0.5);
audio.getBus("SFX").?.setMuted(true);  // Mute during cutscene
```

### Music System

```zig
// Setup music player
const music = try MusicPlayer.init(allocator);
music.crossfade_duration = 2.0;

// Create playlist
var playlist = Playlist.init(allocator);
try playlist.add(battle_theme);
try playlist.add(exploration_theme);
try playlist.add(boss_theme);

music.setPlaylist(&playlist);
music.shuffle = true;
music.repeat = .all;

// Play
music.play();

// Crossfade to new track
music.playWithFade(tense_music, 1.5);
```

## Implementation Steps

### Phase 1: Core Enhancement
1. Refactor existing audio system
2. Add audio format detection
3. Implement OGG/Vorbis loading
4. Create sound instance management

### Phase 2: Mixing
1. Implement audio buses
2. Create bus hierarchy
3. Add per-bus volume control
4. Implement bus effects chain

### Phase 3: Effects
1. Implement low-pass filter
2. Add reverb effect
3. Create delay/echo
4. Add compressor/limiter

### Phase 4: Spatial Audio
1. Implement distance attenuation
2. Add stereo panning
3. Implement Doppler effect
4. Add HRTF support (optional)

### Phase 5: ECS Integration
1. Create AudioSource component
2. Create AudioListener component
3. Implement AudioSystem
4. Add occlusion queries

### Phase 6: Music System
1. Implement streaming playback
2. Create music player
3. Add crossfading
4. Implement playlists

### Phase 7: Advanced
1. Add audio occlusion
2. Implement ambient zones
3. Add adaptive music layers
4. Create audio snapshots

## Performance Considerations

- **Streaming**: Stream large files, cache short sounds
- **Voice Limiting**: Cap concurrent sounds
- **Distance Culling**: Skip far sounds
- **Update Rate**: Audio at 60Hz, not every frame
- **SIMD**: Use vector ops for mixing
- **Threading**: Mix on dedicated thread

## References

- [FMOD](https://www.fmod.com/) - Industry standard audio middleware
- [Wwise](https://www.audiokinetic.com/products/wwise/) - Professional game audio
- [OpenAL Soft](https://openal-soft.org/) - Open source 3D audio
- [Game Audio Programming](https://www.gameaudiogems.com/)
- [HRTF Databases](https://www.sofaconventions.org/)
