# Particle System

## Overview

Implement a GPU-accelerated particle system for visual effects like fire, smoke, sparks, magic effects, and environmental particles. The system should support large particle counts with minimal CPU overhead.

## Current State

ZDL currently has:
- No particle system
- No GPU compute capabilities
- Basic mesh rendering only

## Goals

- GPU-based particle simulation
- Support 100,000+ particles at 60fps
- Flexible emitter configuration
- Particle physics (gravity, wind, collision)
- Visual variety (sprites, meshes, trails)
- Burst and continuous emission
- Sub-emitters for complex effects
- Integration with scene lighting

## Architecture

### Directory Structure

```
src/
├── particles/
│   ├── particles.zig          # Module exports
│   ├── particle_system.zig    # Core system
│   ├── emitter.zig            # Particle emitter
│   ├── modules/
│   │   ├── module.zig         # Base module interface
│   │   ├── emission.zig       # Emission patterns
│   │   ├── velocity.zig       # Velocity over lifetime
│   │   ├── color.zig          # Color over lifetime
│   │   ├── size.zig           # Size over lifetime
│   │   ├── rotation.zig       # Rotation over lifetime
│   │   ├── noise.zig          # Turbulence/noise
│   │   ├── collision.zig      # World collision
│   │   ├── force.zig          # Forces (gravity, wind)
│   │   └── attraction.zig     # Attractor/repeller
│   ├── gpu/
│   │   ├── compute_sim.zig    # GPU compute simulation
│   │   ├── sort.zig           # Depth sorting
│   │   └── indirect_draw.zig  # Indirect rendering
│   └── renderers/
│       ├── billboard.zig      # Billboard sprites
│       ├── mesh.zig           # Mesh particles
│       └── trail.zig          # Trail rendering
```

### Core Components

#### Particle Data

```zig
pub const Particle = struct {
    // Position and velocity
    position: Vec3,
    velocity: Vec3,

    // Lifetime
    age: f32,
    lifetime: f32,

    // Visual
    color: Vec4,
    size: Vec2,
    rotation: f32,
    angular_velocity: f32,

    // Custom data
    custom: [4]f32,

    // State
    alive: bool,

    pub fn normalizedAge(self: Particle) f32 {
        return self.age / self.lifetime;
    }
};

// GPU-friendly packed format
pub const GPUParticle = extern struct {
    position: [3]f32,
    age: f32,
    velocity: [3]f32,
    lifetime: f32,
    color: [4]f32,
    size: [2]f32,
    rotation: f32,
    flags: u32,
};
```

#### Particle Emitter

```zig
pub const ParticleEmitter = struct {
    allocator: Allocator,

    // Particles
    particles: []Particle,
    alive_count: u32,
    max_particles: u32,

    // GPU resources
    particle_buffer: *Buffer,
    alive_buffer: *Buffer,
    dead_buffer: *Buffer,
    counter_buffer: *Buffer,

    // Emission
    emission_config: EmissionConfig,
    accumulated_time: f32,

    // Modules
    modules: std.ArrayList(*ParticleModule),

    // Rendering
    renderer: ParticleRenderer,
    material: *ParticleMaterial,

    // Transform
    world_transform: Mat4,
    simulation_space: SimulationSpace,

    // State
    playing: bool,
    looping: bool;
    duration: f32;
    time: f32;

    pub fn init(allocator: Allocator, config: EmitterConfig) !ParticleEmitter;
    pub fn deinit(self: *ParticleEmitter) void;

    // Playback
    pub fn play(self: *ParticleEmitter) void;
    pub fn stop(self: *ParticleEmitter) void;
    pub fn pause(self: *ParticleEmitter) void;
    pub fn restart(self: *ParticleEmitter) void;

    // Emission
    pub fn emit(self: *ParticleEmitter, count: u32) void;
    pub fn emitAt(self: *ParticleEmitter, position: Vec3, count: u32) void;
    pub fn burst(self: *ParticleEmitter, count: u32) void;

    // Update
    pub fn update(self: *ParticleEmitter, dt: f32) void;
    pub fn render(self: *ParticleEmitter, frame: *RenderFrame, camera: *Camera) void;

    // Modules
    pub fn addModule(self: *ParticleEmitter, module: *ParticleModule) void;
    pub fn removeModule(self: *ParticleEmitter, module: *ParticleModule) void;
    pub fn getModule(self: *ParticleEmitter, comptime T: type) ?*T;
};

pub const EmitterConfig = struct {
    max_particles: u32 = 1000,
    duration: f32 = 5.0,
    looping: bool = true,
    play_on_awake: bool = true,
    simulation_space: SimulationSpace = .local,
    renderer_type: RendererType = .billboard,
};

pub const SimulationSpace = enum {
    local,      // Particles move with emitter
    world,      // Particles stay in world space
};
```

#### Emission Configuration

```zig
pub const EmissionConfig = struct {
    // Rate
    rate_over_time: f32,           // Particles per second
    rate_over_distance: f32,       // Particles per unit moved

    // Bursts
    bursts: []Burst,

    // Shape
    shape: EmissionShape,

    // Initial values
    start_lifetime: ValueRange,
    start_speed: ValueRange,
    start_size: ValueRange,
    start_rotation: ValueRange,
    start_color: ColorRange,

    pub fn emit(self: *EmissionConfig, count: u32, particles: []Particle) void;
};

pub const Burst = struct {
    time: f32,
    count: ValueRange,
    cycles: u32,
    interval: f32,
    probability: f32,
};

pub const EmissionShape = union(enum) {
    point,
    sphere: SphereShape,
    hemisphere: HemisphereShape,
    cone: ConeShape,
    box: BoxShape,
    circle: CircleShape,
    edge: EdgeShape,
    mesh: MeshShape,

    pub fn getPosition(self: EmissionShape) Vec3;
    pub fn getDirection(self: EmissionShape) Vec3;
};

pub const SphereShape = struct {
    radius: f32,
    emit_from_shell: bool,
    randomize_direction: bool,
};

pub const ConeShape = struct {
    angle: f32,
    radius: f32,
    length: f32,
    emit_from: EmitFrom,

    pub const EmitFrom = enum {
        base,
        volume,
        shell,
    };
};

pub const ValueRange = union(enum) {
    constant: f32,
    random_between: struct { min: f32, max: f32 },
    curve: *AnimationCurve,

    pub fn evaluate(self: ValueRange, t: f32) f32;
    pub fn random(self: ValueRange) f32;
};

pub const ColorRange = union(enum) {
    constant: Vec4,
    random_between: struct { min: Vec4, max: Vec4 },
    gradient: *Gradient,
};
```

### Particle Modules

```zig
pub const ParticleModule = struct {
    enabled: bool,
    updateFn: fn(*ParticleModule, []Particle, f32) void,

    pub fn update(self: *ParticleModule, particles: []Particle, dt: f32) void {
        if (self.enabled) {
            self.updateFn(self, particles, dt);
        }
    }
};

// Velocity over lifetime
pub const VelocityOverLifetime = struct {
    base: ParticleModule,
    velocity: Vec3ValueRange,
    space: SimulationSpace,
    orbital_velocity: Vec3ValueRange,
    radial_velocity: ValueRange,

    pub fn init() VelocityOverLifetime;
    fn update(module: *ParticleModule, particles: []Particle, dt: f32) void;
};

// Color over lifetime
pub const ColorOverLifetime = struct {
    base: ParticleModule,
    gradient: Gradient,

    pub fn init() ColorOverLifetime;
    fn update(module: *ParticleModule, particles: []Particle, dt: f32) void;
};

// Size over lifetime
pub const SizeOverLifetime = struct {
    base: ParticleModule,
    size: ValueRange,
    separate_axes: bool,
    size_xyz: Vec3ValueRange,

    pub fn init() SizeOverLifetime;
    fn update(module: *ParticleModule, particles: []Particle, dt: f32) void;
};

// Noise/Turbulence
pub const NoiseModule = struct {
    base: ParticleModule,
    strength: f32,
    frequency: f32,
    scroll_speed: f32,
    octaves: u32,
    position_amount: Vec3,
    rotation_amount: f32,
    size_amount: f32;

    pub fn init() NoiseModule;
    fn update(module: *ParticleModule, particles: []Particle, dt: f32) void;
};

// Force field
pub const ForceOverLifetime = struct {
    base: ParticleModule,
    force: Vec3,
    space: SimulationSpace,
    randomize: Vec3,

    pub fn init() ForceOverLifetime;
    fn update(module: *ParticleModule, particles: []Particle, dt: f32) void;
};

// Collision
pub const CollisionModule = struct {
    base: ParticleModule,
    physics_world: *PhysicsWorld,
    bounce: f32,
    lifetime_loss: f32,
    min_kill_speed: f32,
    collision_mask: u32,

    // Callbacks
    on_collision: ?fn(*Particle, CollisionInfo) void,

    pub fn init(physics: *PhysicsWorld) CollisionModule;
    fn update(module: *ParticleModule, particles: []Particle, dt: f32) void;
};

// Attractor
pub const AttractorModule = struct {
    base: ParticleModule,
    attractors: std.ArrayList(Attractor),

    pub const Attractor = struct {
        position: Vec3,
        strength: f32,
        radius: f32,
        falloff: Falloff,
    };

    pub fn init() AttractorModule;
    fn update(module: *ParticleModule, particles: []Particle, dt: f32) void;
};
```

### GPU Simulation

```zig
pub const GPUParticleSimulator = struct {
    device: *Device,

    // Compute pipelines
    emit_pipeline: *ComputePipeline,
    simulate_pipeline: *ComputePipeline,
    sort_pipeline: *ComputePipeline,
    compact_pipeline: *ComputePipeline,

    // Buffers
    particle_buffer_a: *Buffer,
    particle_buffer_b: *Buffer,
    alive_list: *Buffer,
    dead_list: *Buffer,
    counters: *Buffer,
    indirect_args: *Buffer;

    pub fn init(device: *Device, max_particles: u32) !GPUParticleSimulator;

    pub fn emit(self: *GPUParticleSimulator, cmd: *CommandBuffer, config: EmissionConfig, count: u32) void;
    pub fn simulate(self: *GPUParticleSimulator, cmd: *CommandBuffer, dt: f32) void;
    pub fn sort(self: *GPUParticleSimulator, cmd: *CommandBuffer, camera_pos: Vec3) void;
};

// Emit compute shader (GLSL)
// layout(local_size_x = 64) in;
//
// layout(set = 0, binding = 0) buffer Particles { GPUParticle particles[]; };
// layout(set = 0, binding = 1) buffer DeadList { uint dead_indices[]; };
// layout(set = 0, binding = 2) buffer Counters { uint alive_count; uint dead_count; uint emit_count; };
//
// void main() {
//     uint idx = gl_GlobalInvocationID.x;
//     if (idx >= emit_count) return;
//
//     uint particle_idx = atomicAdd(dead_count, -1) - 1;
//     if (particle_idx < 0) return;
//
//     uint slot = dead_indices[particle_idx];
//
//     // Initialize particle
//     particles[slot].position = emitPosition();
//     particles[slot].velocity = emitVelocity();
//     particles[slot].age = 0.0;
//     particles[slot].lifetime = randomLifetime();
//     particles[slot].color = startColor;
//     particles[slot].size = vec2(startSize);
//     particles[slot].flags = PARTICLE_ALIVE;
// }

// Simulate compute shader
// void main() {
//     uint idx = gl_GlobalInvocationID.x;
//     if (idx >= alive_count) return;
//
//     GPUParticle p = particles[idx];
//     if ((p.flags & PARTICLE_ALIVE) == 0) return;
//
//     // Update age
//     p.age += dt;
//     if (p.age >= p.lifetime) {
//         p.flags &= ~PARTICLE_ALIVE;
//         uint dead_idx = atomicAdd(dead_count, 1);
//         dead_indices[dead_idx] = idx;
//         return;
//     }
//
//     float t = p.age / p.lifetime;
//
//     // Apply modules
//     p.velocity += gravity * dt;
//     p.velocity += noise(p.position * frequency) * noiseStrength;
//     p.position += p.velocity * dt;
//     p.color = sampleGradient(colorOverLifetime, t);
//     p.size = mix(startSize, endSize, sizeOverLifetime(t));
//
//     particles[idx] = p;
// }
```

### Renderers

```zig
pub const ParticleRenderer = union(enum) {
    billboard: BillboardRenderer,
    stretched_billboard: StretchedBillboardRenderer,
    mesh: MeshRenderer,
    trail: TrailRenderer,
};

pub const BillboardRenderer = struct {
    pipeline: *Pipeline,
    vertex_buffer: *Buffer,
    instance_buffer: *Buffer,

    // Settings
    alignment: BillboardAlignment,
    sort_mode: SortMode,
    blend_mode: BlendMode,

    pub fn init(device: *Device) !BillboardRenderer;
    pub fn render(
        self: *BillboardRenderer,
        frame: *RenderFrame,
        particles: []Particle,
        camera: *Camera,
        texture: *Texture,
    ) void;
};

pub const BillboardAlignment = enum {
    view,           // Face camera
    world,          // Fixed orientation
    velocity,       // Align to velocity
    stretched,      // Stretch along velocity
};

pub const StretchedBillboardRenderer = struct {
    base: BillboardRenderer,
    length_scale: f32,
    speed_scale: f32,

    pub fn init(device: *Device) !StretchedBillboardRenderer;
};

pub const MeshParticleRenderer = struct {
    pipeline: *Pipeline,
    mesh: *Mesh,
    instance_buffer: *Buffer,

    // Settings
    alignment: MeshAlignment,
    render_mode: MeshRenderMode,

    pub fn init(device: *Device, mesh: *Mesh) !MeshParticleRenderer;
    pub fn render(
        self: *MeshParticleRenderer,
        frame: *RenderFrame,
        particles: []Particle,
        camera: *Camera,
    ) void;
};

pub const TrailRenderer = struct {
    pipeline: *Pipeline,
    trail_buffer: *Buffer;

    // Settings
    width: ValueRange,
    color: Gradient,
    texture_mode: TextureMode,
    min_vertex_distance: f32;

    // Per-particle trails
    trails: std.AutoHashMap(u32, Trail),

    pub fn init(device: *Device) !TrailRenderer;
    pub fn update(self: *TrailRenderer, particles: []Particle, dt: f32) void;
    pub fn render(self: *TrailRenderer, frame: *RenderFrame, camera: *Camera) void;
};

pub const Trail = struct {
    points: RingBuffer(TrailPoint),
    total_length: f32,
};

pub const TrailPoint = struct {
    position: Vec3,
    width: f32,
    color: Vec4,
    age: f32;
};
```

### Particle Component

```zig
pub const ParticleSystemComponent = struct {
    emitters: std.ArrayList(*ParticleEmitter),

    // Playback
    playing: bool,
    playback_speed: f32,

    // Culling
    bounds: AABB,
    auto_bounds: bool,

    // LOD
    lod_bias: f32,

    pub fn init(allocator: Allocator) ParticleSystemComponent;
    pub fn deinit(self: *ParticleSystemComponent) void;

    pub fn addEmitter(self: *ParticleSystemComponent, emitter: *ParticleEmitter) void;
    pub fn removeEmitter(self: *ParticleSystemComponent, emitter: *ParticleEmitter) void;

    pub fn play(self: *ParticleSystemComponent) void;
    pub fn stop(self: *ParticleSystemComponent) void;
    pub fn clear(self: *ParticleSystemComponent) void;

    pub fn update(self: *ParticleSystemComponent, dt: f32) void;
};

pub const ParticleSystem = struct {
    pub fn update(scene: *Scene, dt: f32) void {
        const systems = scene.getComponents(ParticleSystemComponent);
        const transforms = scene.getComponents(TransformComponent);

        for (systems, transforms) |particle_sys, transform| {
            particle_sys.world_transform = transform.getWorldMatrix();

            if (particle_sys.playing) {
                for (particle_sys.emitters.items) |emitter| {
                    emitter.world_transform = particle_sys.world_transform;
                    emitter.update(dt * particle_sys.playback_speed);
                }
            }
        }
    }

    pub fn render(scene: *Scene, frame: *RenderFrame, camera: *Camera) void {
        const systems = scene.getComponents(ParticleSystemComponent);

        for (systems) |particle_sys| {
            for (particle_sys.emitters.items) |emitter| {
                emitter.render(frame, camera);
            }
        }
    }
};
```

## Usage Examples

### Fire Effect

```zig
var fire = try ParticleEmitter.init(allocator, .{
    .max_particles = 1000,
    .renderer_type = .billboard,
});

fire.emission_config = .{
    .rate_over_time = 50,
    .shape = .{ .cone = .{
        .angle = 15,
        .radius = 0.1,
        .length = 0.5,
        .emit_from = .base,
    }},
    .start_lifetime = .{ .random_between = .{ .min = 0.5, .max = 1.5 } },
    .start_speed = .{ .random_between = .{ .min = 1.0, .max = 3.0 } },
    .start_size = .{ .random_between = .{ .min = 0.1, .max = 0.3 } },
    .start_color = .{ .constant = Vec4.init(1, 0.5, 0, 1) },
};

// Color over lifetime (orange to red to black)
var color_module = ColorOverLifetime.init();
color_module.gradient = Gradient.create(&.{
    .{ 0.0, Vec4.init(1.0, 0.8, 0.2, 1.0) },
    .{ 0.5, Vec4.init(1.0, 0.3, 0.0, 0.8) },
    .{ 1.0, Vec4.init(0.1, 0.0, 0.0, 0.0) },
});
fire.addModule(&color_module.base);

// Size over lifetime
var size_module = SizeOverLifetime.init();
size_module.size = .{ .curve = sizeUpThenDown };
fire.addModule(&size_module.base);

// Gravity
var force_module = ForceOverLifetime.init();
force_module.force = Vec3.init(0, 2, 0); // Upward fire
fire.addModule(&force_module.base);

fire.play();
```

### Sparks Effect

```zig
var sparks = try ParticleEmitter.init(allocator, .{
    .max_particles = 500,
    .looping = false,
    .renderer_type = .stretched_billboard,
});

sparks.emission_config = .{
    .rate_over_time = 0,
    .bursts = &.{
        .{ .time = 0, .count = .{ .random_between = .{ .min = 20, .max = 50 } } },
    },
    .shape = .{ .sphere = .{ .radius = 0.1, .emit_from_shell = true } },
    .start_lifetime = .{ .random_between = .{ .min = 0.3, .max = 0.8 } },
    .start_speed = .{ .random_between = .{ .min = 5.0, .max = 15.0 } },
    .start_size = .{ .constant = 0.02 },
    .start_color = .{ .constant = Vec4.init(1, 0.8, 0.3, 1) },
};

// Gravity
var gravity = ForceOverLifetime.init();
gravity.force = Vec3.init(0, -9.81, 0);
sparks.addModule(&gravity.base);

// Collision with bounce
var collision = CollisionModule.init(physics_world);
collision.bounce = 0.3;
collision.lifetime_loss = 0.2;
sparks.addModule(&collision.base);
```

## Implementation Steps

### Phase 1: CPU Particles
1. Create particle data structures
2. Implement basic emitter
3. Add emission shapes
4. Create billboard renderer

### Phase 2: Modules
1. Implement color over lifetime
2. Add size over lifetime
3. Create velocity module
4. Add force/gravity module

### Phase 3: Advanced Modules
1. Implement noise/turbulence
2. Add collision module
3. Create attractor system
4. Add sub-emitters

### Phase 4: GPU Simulation
1. Create compute shaders
2. Implement emit shader
3. Create simulate shader
4. Add sorting for transparency

### Phase 5: Advanced Rendering
1. Implement mesh particles
2. Add trail renderer
3. Create soft particles
4. Add lighting integration

### Phase 6: Polish
1. Add LOD system
2. Implement culling
3. Create effect presets
4. Add editor tools

## Performance Considerations

- **GPU Compute**: Move simulation to GPU for large counts
- **Instancing**: Batch render calls
- **Sorting**: Only sort when needed (transparent particles)
- **Culling**: Skip off-screen emitters
- **LOD**: Reduce particle count at distance
- **Memory**: Pool particle arrays

## References

- [Unity Particle System](https://docs.unity3d.com/Manual/PartSysReference.html)
- [Unreal Niagara](https://docs.unrealengine.com/5.0/en-US/niagara-visual-effects-in-unreal-engine/)
- [GPU Gems 3 - Particles](https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-23-high-speed-screen-particles)
- [Compute Particle Systems](https://wickedengine.net/2017/11/07/gpu-based-particle-simulation/)
