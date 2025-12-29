# Physics System

## Overview

Implement a comprehensive physics system for ZDL supporting rigid body dynamics, collision detection, and physics queries. The system should integrate seamlessly with the ECS architecture and provide both realistic simulation and game-friendly controls.

## Current State

ZDL currently has:
- No physics simulation
- No collision detection
- No rigid body dynamics
- Transform updates are purely manual

## Goals

- Rigid body dynamics (velocity, forces, torque)
- Multiple collider shapes (box, sphere, capsule, mesh)
- Collision detection and response
- Physics queries (raycasts, sweeps, overlaps)
- Trigger volumes for game logic
- Constraints and joints
- Character controller
- Integration with transform hierarchy
- Deterministic simulation option

## Approach

Two viable approaches:

1. **Integrate Existing Library**: Use a proven physics engine (Jolt, Box2D, Bullet)
2. **Build Custom**: Implement physics from scratch for full control

Recommendation: **Integrate Jolt Physics** for 3D or build a custom lightweight system for simpler needs.

## Architecture

### Directory Structure

```
src/
├── physics/
│   ├── physics.zig            # Module exports
│   ├── physics_world.zig      # Simulation world
│   ├── rigid_body.zig         # Rigid body component
│   ├── collider.zig           # Collider shapes
│   ├── collision.zig          # Collision detection
│   ├── constraints.zig        # Joints and constraints
│   ├── queries.zig            # Raycasts, sweeps, overlaps
│   ├── character.zig          # Character controller
│   ├── layers.zig             # Collision layers/masks
│   └── debug_draw.zig         # Physics visualization
```

### Core Components

#### Physics World

```zig
pub const PhysicsWorld = struct {
    allocator: Allocator,

    // Simulation
    gravity: Vec3,
    time_step: f32,
    sub_steps: u32,
    accumulated_time: f32,

    // Bodies
    bodies: std.ArrayList(*RigidBody),
    static_bodies: std.ArrayList(*StaticBody),

    // Collision
    broad_phase: BroadPhase,
    narrow_phase: NarrowPhase,
    contact_manager: ContactManager,

    // Constraints
    constraints: std.ArrayList(*Constraint),

    // Queries
    query_filter: QueryFilter,

    pub fn init(allocator: Allocator, config: PhysicsConfig) !PhysicsWorld;
    pub fn deinit(self: *PhysicsWorld) void;

    // Simulation
    pub fn step(self: *PhysicsWorld, delta_time: f32) void;
    pub fn setGravity(self: *PhysicsWorld, gravity: Vec3) void;

    // Body management
    pub fn addBody(self: *PhysicsWorld, body: *RigidBody) void;
    pub fn removeBody(self: *PhysicsWorld, body: *RigidBody) void;

    // Queries
    pub fn raycast(self: *PhysicsWorld, ray: Ray, max_dist: f32, filter: QueryFilter) ?RaycastHit;
    pub fn raycastAll(self: *PhysicsWorld, ray: Ray, max_dist: f32, filter: QueryFilter) []RaycastHit;
    pub fn sphereCast(self: *PhysicsWorld, sphere: Sphere, direction: Vec3, max_dist: f32) ?SweepHit;
    pub fn overlapSphere(self: *PhysicsWorld, center: Vec3, radius: f32, filter: QueryFilter) []Collider;
    pub fn overlapBox(self: *PhysicsWorld, center: Vec3, half_extents: Vec3, rotation: Quat, filter: QueryFilter) []Collider;
};

pub const PhysicsConfig = struct {
    gravity: Vec3 = Vec3.init(0, -9.81, 0),
    time_step: f32 = 1.0 / 60.0,
    sub_steps: u32 = 2,
    velocity_iterations: u32 = 8,
    position_iterations: u32 = 3,
    max_bodies: u32 = 10000,
    max_contacts: u32 = 50000,
};
```

#### Rigid Body Component

```zig
pub const RigidBodyComponent = struct {
    body_type: BodyType,

    // Motion
    velocity: Vec3,
    angular_velocity: Vec3,

    // Properties
    mass: f32,
    inv_mass: f32,
    inertia_tensor: Mat3,
    inv_inertia_tensor: Mat3,

    // Damping
    linear_damping: f32,
    angular_damping: f32,

    // Constraints
    freeze_rotation: FreezeFlags,
    freeze_position: FreezeFlags,

    // State
    is_sleeping: bool,
    is_kinematic: bool,
    use_gravity: bool,

    // Collision
    collision_layer: u32,
    collision_mask: u32,

    pub fn init(body_type: BodyType) RigidBodyComponent;

    // Force application
    pub fn addForce(self: *RigidBodyComponent, force: Vec3) void;
    pub fn addForceAtPoint(self: *RigidBodyComponent, force: Vec3, point: Vec3) void;
    pub fn addTorque(self: *RigidBodyComponent, torque: Vec3) void;
    pub fn addImpulse(self: *RigidBodyComponent, impulse: Vec3) void;
    pub fn addImpulseAtPoint(self: *RigidBodyComponent, impulse: Vec3, point: Vec3) void;

    // Velocity
    pub fn setVelocity(self: *RigidBodyComponent, velocity: Vec3) void;
    pub fn setAngularVelocity(self: *RigidBodyComponent, angular_velocity: Vec3) void;

    // Sleep
    pub fn wake(self: *RigidBodyComponent) void;
    pub fn sleep(self: *RigidBodyComponent) void;
};

pub const BodyType = enum {
    dynamic,    // Fully simulated
    kinematic,  // Moved by user, affects dynamics
    static,     // Never moves
};

pub const FreezeFlags = packed struct {
    x: bool = false,
    y: bool = false,
    z: bool = false,
};
```

#### Collider Component

```zig
pub const ColliderComponent = struct {
    shape: ColliderShape,
    offset: Vec3,
    rotation: Quat,

    // Physics material
    friction: f32,
    restitution: f32,

    // Behavior
    is_trigger: bool,
    contact_offset: f32,

    pub fn init(shape: ColliderShape) ColliderComponent;
    pub fn setMaterial(self: *ColliderComponent, material: PhysicsMaterial) void;

    // Bounds
    pub fn getBounds(self: *ColliderComponent, transform: *TransformComponent) AABB;
    pub fn getWorldShape(self: *ColliderComponent, transform: *TransformComponent) ColliderShape;
};

pub const ColliderShape = union(enum) {
    box: BoxShape,
    sphere: SphereShape,
    capsule: CapsuleShape,
    cylinder: CylinderShape,
    mesh: MeshShape,
    convex_hull: ConvexHullShape,

    pub fn getVolume(self: ColliderShape) f32;
    pub fn getInertia(self: ColliderShape, mass: f32) Mat3;
};

pub const BoxShape = struct {
    half_extents: Vec3,
};

pub const SphereShape = struct {
    radius: f32,
};

pub const CapsuleShape = struct {
    radius: f32,
    height: f32,
    direction: CapsuleDirection,
};

pub const CapsuleDirection = enum {
    x,
    y,
    z,
};

pub const MeshShape = struct {
    vertices: []const Vec3,
    indices: []const u32,
    convex: bool,
};

pub const PhysicsMaterial = struct {
    friction: f32 = 0.5,
    restitution: f32 = 0.0,
    friction_combine: CombineMode = .average,
    restitution_combine: CombineMode = .average,
};

pub const CombineMode = enum {
    average,
    minimum,
    maximum,
    multiply,
};
```

### Collision Detection

#### Broad Phase

```zig
pub const BroadPhase = struct {
    // Spatial acceleration structure
    bvh: DynamicBVH,

    pub fn init(allocator: Allocator) BroadPhase;

    pub fn insert(self: *BroadPhase, body: *RigidBody, aabb: AABB) BroadPhaseId;
    pub fn update(self: *BroadPhase, id: BroadPhaseId, new_aabb: AABB) void;
    pub fn remove(self: *BroadPhase, id: BroadPhaseId) void;

    pub fn getPotentialPairs(self: *BroadPhase) []CollisionPair;
    pub fn query(self: *BroadPhase, aabb: AABB) []BroadPhaseId;
};

pub const DynamicBVH = struct {
    nodes: std.ArrayList(BVHNode),
    root: ?u32,

    // ...
};
```

#### Narrow Phase

```zig
pub const NarrowPhase = struct {
    pub fn collide(
        shape_a: ColliderShape,
        transform_a: Transform,
        shape_b: ColliderShape,
        transform_b: Transform,
    ) ?ContactManifold;

    // Shape-specific collision functions
    fn sphereVsSphere(a: SphereShape, ta: Transform, b: SphereShape, tb: Transform) ?ContactManifold;
    fn sphereVsBox(sphere: SphereShape, ts: Transform, box: BoxShape, tb: Transform) ?ContactManifold;
    fn boxVsBox(a: BoxShape, ta: Transform, b: BoxShape, tb: Transform) ?ContactManifold;
    fn capsuleVsSphere(capsule: CapsuleShape, tc: Transform, sphere: SphereShape, ts: Transform) ?ContactManifold;
    // ... more combinations
};

pub const ContactManifold = struct {
    points: [4]ContactPoint,
    point_count: u32,
    normal: Vec3,

    body_a: *RigidBody,
    body_b: *RigidBody,
};

pub const ContactPoint = struct {
    position: Vec3,
    normal: Vec3,
    penetration: f32,
    feature_a: u32,
    feature_b: u32,
};
```

### Collision Callbacks

```zig
pub const CollisionListener = struct {
    on_collision_enter: ?fn(Collision) void,
    on_collision_stay: ?fn(Collision) void,
    on_collision_exit: ?fn(Entity, Entity) void,
    on_trigger_enter: ?fn(Entity, Entity) void,
    on_trigger_exit: ?fn(Entity, Entity) void,
};

pub const Collision = struct {
    entity_a: Entity,
    entity_b: Entity,
    contacts: []ContactPoint,
    impulse: Vec3,
    relative_velocity: Vec3,
};
```

### Constraints and Joints

```zig
pub const Constraint = union(enum) {
    distance: DistanceConstraint,
    hinge: HingeConstraint,
    ball_socket: BallSocketConstraint,
    slider: SliderConstraint,
    fixed: FixedConstraint,
    spring: SpringConstraint,
};

pub const DistanceConstraint = struct {
    body_a: *RigidBody,
    body_b: *RigidBody,
    anchor_a: Vec3,
    anchor_b: Vec3,
    distance: f32,
    min_distance: ?f32,
    max_distance: ?f32,
};

pub const HingeConstraint = struct {
    body_a: *RigidBody,
    body_b: *RigidBody,
    anchor: Vec3,
    axis: Vec3,
    limits: ?AngleLimits,
    motor: ?ConstraintMotor,
};

pub const AngleLimits = struct {
    min: f32,
    max: f32,
    softness: f32,
};

pub const ConstraintMotor = struct {
    target_velocity: f32,
    max_force: f32,
    enabled: bool,
};

pub const SpringConstraint = struct {
    body_a: *RigidBody,
    body_b: *RigidBody,
    anchor_a: Vec3,
    anchor_b: Vec3,
    rest_length: f32,
    stiffness: f32,
    damping: f32,
};
```

### Physics Queries

```zig
pub const Ray = struct {
    origin: Vec3,
    direction: Vec3,
};

pub const RaycastHit = struct {
    entity: Entity,
    collider: *ColliderComponent,
    point: Vec3,
    normal: Vec3,
    distance: f32,
    face_index: ?u32,  // For mesh colliders
};

pub const SweepHit = struct {
    entity: Entity,
    collider: *ColliderComponent,
    point: Vec3,
    normal: Vec3,
    distance: f32,
    fraction: f32,
};

pub const QueryFilter = struct {
    layer_mask: u32 = 0xFFFFFFFF,
    ignore_triggers: bool = true,
    ignore_entities: ?[]Entity = null,

    pub fn default() QueryFilter;
    pub fn withLayer(layer: u32) QueryFilter;
    pub fn withMask(mask: u32) QueryFilter;
};
```

### Character Controller

```zig
pub const CharacterController = struct {
    // Shape
    height: f32,
    radius: f32,
    skin_width: f32,

    // Movement
    velocity: Vec3,
    ground_velocity: Vec3,  // Velocity of platform we're standing on

    // Ground detection
    is_grounded: bool,
    ground_normal: Vec3,
    ground_entity: ?Entity,

    // Configuration
    slope_limit: f32,         // Max walkable slope angle
    step_offset: f32,         // Max step height
    min_move_distance: f32,

    // Collision
    collision_layer: u32,
    collision_mask: u32,

    pub fn init(height: f32, radius: f32) CharacterController;

    // Movement
    pub fn move(self: *CharacterController, world: *PhysicsWorld, motion: Vec3, dt: f32) CollisionFlags;
    pub fn simpleMove(self: *CharacterController, world: *PhysicsWorld, direction: Vec3, dt: f32) void;

    // State
    pub fn isGrounded(self: *CharacterController) bool;
    pub fn getGroundHit(self: *CharacterController) ?GroundHit;
};

pub const CollisionFlags = packed struct {
    sides: bool,
    above: bool,
    below: bool,
};

pub const GroundHit = struct {
    point: Vec3,
    normal: Vec3,
    entity: ?Entity,
    move_direction: Vec3,
};
```

### Physics System (ECS)

```zig
pub const PhysicsSystem = struct {
    world: *PhysicsWorld,

    pub fn init(allocator: Allocator, config: PhysicsConfig) !PhysicsSystem;

    pub fn update(self: *PhysicsSystem, scene: *Scene, dt: f32) void {
        // Sync transforms from scene to physics
        self.syncToPhysics(scene);

        // Step simulation
        self.world.step(dt);

        // Sync transforms from physics to scene
        self.syncFromPhysics(scene);

        // Process callbacks
        self.processCallbacks(scene);
    }

    fn syncToPhysics(self: *PhysicsSystem, scene: *Scene) void {
        // For kinematic bodies, update physics from transform
        const kinematics = scene.query(.{ RigidBodyComponent, TransformComponent });
        for (kinematics) |entity, rb, transform| {
            if (rb.is_kinematic) {
                self.world.setKinematicTarget(rb, transform.getWorldPosition());
            }
        }
    }

    fn syncFromPhysics(self: *PhysicsSystem, scene: *Scene) void {
        // Update transforms from physics simulation
        const dynamics = scene.query(.{ RigidBodyComponent, TransformComponent });
        for (dynamics) |entity, rb, transform| {
            if (rb.body_type == .dynamic) {
                transform.setWorldPosition(rb.position);
                transform.setWorldRotation(rb.rotation);
            }
        }
    }
};
```

### Collision Layers

```zig
pub const CollisionLayers = struct {
    pub const default: u32 = 1 << 0;
    pub const player: u32 = 1 << 1;
    pub const enemy: u32 = 1 << 2;
    pub const projectile: u32 = 1 << 3;
    pub const trigger: u32 = 1 << 4;
    pub const terrain: u32 = 1 << 5;
    pub const interactable: u32 = 1 << 6;

    pub const all: u32 = 0xFFFFFFFF;
    pub const none: u32 = 0;
};

// Collision matrix (what collides with what)
pub const CollisionMatrix = struct {
    layers: [32]u32,

    pub fn init() CollisionMatrix {
        var matrix = CollisionMatrix{ .layers = undefined };
        // Default: everything collides with everything
        for (&matrix.layers) |*layer| {
            layer.* = CollisionLayers.all;
        }
        return matrix;
    }

    pub fn setCollision(self: *CollisionMatrix, layer_a: u32, layer_b: u32, collide: bool) void;
    pub fn canCollide(self: *CollisionMatrix, layer_a: u32, layer_b: u32) bool;
};
```

### Debug Visualization

```zig
pub const PhysicsDebugDraw = struct {
    enabled: bool,
    draw_colliders: bool,
    draw_contacts: bool,
    draw_constraints: bool,
    draw_velocities: bool,
    draw_aabbs: bool,

    collider_color: Color,
    trigger_color: Color,
    contact_color: Color,
    velocity_color: Color,

    pub fn draw(self: *PhysicsDebugDraw, world: *PhysicsWorld, renderer: *DebugRenderer) void;
};
```

## Implementation Steps

### Phase 1: Core Structures
1. Create physics world container
2. Implement rigid body component
3. Create basic collider shapes (sphere, box)
4. Set up physics-transform synchronization

### Phase 2: Collision Detection
1. Implement sphere-sphere collision
2. Implement sphere-box collision
3. Implement box-box collision (SAT)
4. Create broad phase (BVH or grid)

### Phase 3: Dynamics
1. Implement velocity integration
2. Add force and impulse application
3. Implement contact resolution
4. Add friction and restitution

### Phase 4: Advanced Colliders
1. Implement capsule collider
2. Implement cylinder collider
3. Add convex hull support
4. Add mesh collider (static only)

### Phase 5: Queries
1. Implement raycasting
2. Add sphere/box sweep tests
3. Implement overlap queries
4. Add layer filtering

### Phase 6: Constraints
1. Implement distance constraint
2. Add hinge joint
3. Add ball socket joint
4. Implement spring constraint

### Phase 7: Character Controller
1. Create capsule-based controller
2. Implement ground detection
3. Add slope handling
4. Implement step climbing

### Phase 8: Polish
1. Add debug visualization
2. Implement sleeping/islands
3. Add continuous collision detection
4. Optimize broad phase

## Performance Considerations

- **Broad Phase**: Use BVH or spatial hash for large worlds
- **Sleeping**: Deactivate stationary bodies
- **Islands**: Solve connected bodies together
- **SIMD**: Use vector instructions for math
- **Parallelism**: Multi-thread constraint solver
- **Fixed Timestep**: Use accumulator for consistent simulation

## Integration Example

```zig
pub fn setupPhysicsScene(scene: *Scene, physics: *PhysicsWorld) !void {
    // Create ground
    const ground = try scene.createEntity();
    try scene.addComponent(ground, TransformComponent.withPosition(Vec3.init(0, -1, 0)));
    try scene.addComponent(ground, ColliderComponent.init(.{ .box = .{
        .half_extents = Vec3.init(50, 1, 50),
    }}));
    try scene.addComponent(ground, RigidBodyComponent.init(.static));

    // Create falling box
    const box = try scene.createEntity();
    try scene.addComponent(box, TransformComponent.withPosition(Vec3.init(0, 5, 0)));
    try scene.addComponent(box, ColliderComponent.init(.{ .box = .{
        .half_extents = Vec3.init(0.5, 0.5, 0.5),
    }}));
    try scene.addComponent(box, RigidBodyComponent.init(.dynamic));
    try scene.addComponent(box, MeshRendererComponent.init(&cube_mesh));
}

// In game update
pub fn update(engine: *Engine, scene: *Scene, input: *Input, dt: f32) !void {
    // Physics system updates automatically via engine

    // Apply player input as forces
    if (scene.getComponent(player, RigidBodyComponent)) |rb| {
        if (input.isKeyDown(.w)) {
            rb.addForce(Vec3.init(0, 0, -move_force));
        }
        if (input.isKeyDown(.space) and isGrounded(scene, player)) {
            rb.addImpulse(Vec3.init(0, jump_impulse, 0));
        }
    }
}
```

## References

- [Jolt Physics](https://github.com/jrouwe/JoltPhysics) - Modern C++ physics engine
- [Box2D](https://box2d.org/) - 2D physics (principles apply to 3D)
- [Game Physics Engine Development](https://www.routledge.com/Game-Physics-Engine-Development/Millington/p/book/9780123819765)
- [Real-Time Collision Detection](https://realtimecollisiondetection.net/)
- [Physics for Game Programmers](https://www.gdcvault.com/search.php#&category=free&firstfocus=&keyword=physics)
