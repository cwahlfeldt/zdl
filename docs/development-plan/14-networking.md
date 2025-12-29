# Networking System

## Overview

Implement a networking system for ZDL supporting multiplayer games with client-server and peer-to-peer architectures. This includes reliable/unreliable messaging, state synchronization, client-side prediction, and lag compensation.

## Current State

ZDL currently has:
- No networking capability
- No serialization for network transmission
- No multiplayer support

## Goals

- TCP and UDP socket abstraction
- Reliable and unreliable message channels
- Entity state synchronization
- Client-side prediction and server reconciliation
- Lag compensation for hit detection
- Lobby and matchmaking support
- NAT traversal (optional)
- WebSocket support for browser clients (optional)

## Architecture

### Directory Structure

```
src/
├── network/
│   ├── network.zig            # Module exports
│   ├── socket.zig             # Socket abstraction
│   ├── connection.zig         # Connection management
│   ├── channel.zig            # Reliable/unreliable channels
│   ├── packet.zig             # Packet formatting
│   ├── server.zig             # Game server
│   ├── client.zig             # Game client
│   ├── replication.zig        # State replication
│   ├── prediction.zig         # Client-side prediction
│   ├── lag_compensation.zig   # Server lag compensation
│   ├── lobby.zig              # Lobby system
│   └── rpc.zig                # Remote procedure calls
```

### Core Components

#### Socket Abstraction

```zig
pub const Socket = struct {
    handle: SocketHandle,
    socket_type: SocketType,
    blocking: bool,

    pub fn createTCP() !Socket;
    pub fn createUDP() !Socket;

    pub fn bind(self: *Socket, address: Address) !void;
    pub fn listen(self: *Socket, backlog: u32) !void;
    pub fn accept(self: *Socket) !Socket;
    pub fn connect(self: *Socket, address: Address) !void;

    pub fn send(self: *Socket, data: []const u8) !usize;
    pub fn sendTo(self: *Socket, data: []const u8, address: Address) !usize;
    pub fn recv(self: *Socket, buffer: []u8) !usize;
    pub fn recvFrom(self: *Socket, buffer: []u8) !struct { usize, Address };

    pub fn setNonBlocking(self: *Socket, non_blocking: bool) !void;
    pub fn setNoDelay(self: *Socket, no_delay: bool) !void;
    pub fn close(self: *Socket) void;
};

pub const Address = struct {
    ip: [4]u8,
    port: u16,

    pub fn parse(str: []const u8) !Address;
    pub fn toString(self: Address) []const u8;
    pub fn any(port: u16) Address;
    pub fn localhost(port: u16) Address;
};

pub const SocketType = enum {
    tcp,
    udp,
};
```

#### Connection

```zig
pub const Connection = struct {
    id: ConnectionId,
    socket: *Socket,
    remote_address: Address,
    state: ConnectionState,

    // Reliability
    reliable_channel: ReliableChannel,
    unreliable_channel: UnreliableChannel,

    // Statistics
    rtt: f32,
    packet_loss: f32,
    bytes_sent: u64,
    bytes_received: u64,

    // Timing
    last_receive_time: i64,
    last_send_time: i64;

    pub fn init(socket: *Socket, address: Address) Connection;

    pub fn send(self: *Connection, data: []const u8, reliable: bool) !void;
    pub fn receive(self: *Connection) ?Packet;

    pub fn update(self: *Connection, dt: f32) void;
    pub fn disconnect(self: *Connection) void;

    pub fn isConnected(self: *Connection) bool;
    pub fn getRTT(self: *Connection) f32;
};

pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    disconnecting,
};

pub const ConnectionId = u32;
```

#### Reliable Channel

```zig
pub const ReliableChannel = struct {
    sequence: u16,
    ack: u16,
    ack_bits: u32,

    // Send queue
    pending_packets: std.ArrayList(PendingPacket),
    send_buffer: RingBuffer([]const u8),

    // Receive
    received_packets: std.AutoHashMap(u16, []const u8),
    next_receive_sequence: u16,

    // Timing
    resend_time: f32,

    pub fn init(allocator: Allocator) ReliableChannel;

    pub fn send(self: *ReliableChannel, data: []const u8) void;
    pub fn receive(self: *ReliableChannel) ?[]const u8;

    pub fn processAck(self: *ReliableChannel, ack: u16, ack_bits: u32) void;
    pub fn update(self: *ReliableChannel, dt: f32) void;
};

pub const PendingPacket = struct {
    sequence: u16,
    data: []const u8,
    send_time: f32,
    resend_count: u32,
};

pub const UnreliableChannel = struct {
    sequence: u16,
    received_sequence: u16,

    pub fn send(self: *UnreliableChannel, data: []const u8) []const u8;
    pub fn receive(self: *UnreliableChannel, packet: []const u8) ?[]const u8;
};
```

#### Packet Format

```zig
pub const PacketHeader = packed struct {
    protocol_id: u32,
    sequence: u16,
    ack: u16,
    ack_bits: u32,
    packet_type: PacketType,
    channel: Channel,
};

pub const PacketType = enum(u8) {
    connection_request,
    connection_accept,
    connection_deny,
    disconnect,
    heartbeat,
    data,
    fragment,
};

pub const Channel = enum(u8) {
    reliable_ordered,
    reliable_unordered,
    unreliable,
};

pub const Packet = struct {
    header: PacketHeader,
    payload: []const u8,

    pub fn serialize(self: *Packet) []const u8;
    pub fn deserialize(data: []const u8) !Packet;
};
```

#### Game Server

```zig
pub const GameServer = struct {
    allocator: Allocator,
    socket: Socket,
    connections: std.AutoHashMap(ConnectionId, *Connection),
    next_connection_id: ConnectionId,

    // Game state
    world_state: *WorldState,
    tick_rate: u32,
    tick: u64,

    // Callbacks
    on_client_connect: ?fn(ConnectionId) void,
    on_client_disconnect: ?fn(ConnectionId) void,
    on_message: ?fn(ConnectionId, []const u8) void,

    pub fn init(allocator: Allocator, config: ServerConfig) !GameServer;
    pub fn deinit(self: *GameServer) void;

    pub fn start(self: *GameServer, port: u16) !void;
    pub fn stop(self: *GameServer) void;

    pub fn update(self: *GameServer, dt: f32) void;
    pub fn tick(self: *GameServer) void;

    // Messaging
    pub fn broadcast(self: *GameServer, data: []const u8, reliable: bool) void;
    pub fn send(self: *GameServer, client: ConnectionId, data: []const u8, reliable: bool) void;
    pub fn kick(self: *GameServer, client: ConnectionId, reason: []const u8) void;

    // State
    pub fn getClientCount(self: *GameServer) usize;
    pub fn getClients(self: *GameServer) []ConnectionId;
};

pub const ServerConfig = struct {
    max_clients: u32 = 32,
    tick_rate: u32 = 60,
    timeout: f32 = 10.0,
    port: u16 = 7777,
};
```

#### Game Client

```zig
pub const GameClient = struct {
    allocator: Allocator,
    socket: Socket,
    connection: ?Connection,
    state: ClientState,

    // Prediction
    prediction: ClientPrediction,
    input_buffer: RingBuffer(InputState),

    // Interpolation
    interpolation_buffer: InterpolationBuffer,
    interpolation_delay: f32,

    // Callbacks
    on_connect: ?fn() void,
    on_disconnect: ?fn(DisconnectReason) void,
    on_message: ?fn([]const u8) void,
    on_state_update: ?fn(*WorldState) void,

    pub fn init(allocator: Allocator, config: ClientConfig) !GameClient;
    pub fn deinit(self: *GameClient) void;

    pub fn connect(self: *GameClient, address: Address) !void;
    pub fn disconnect(self: *GameClient) void;

    pub fn update(self: *GameClient, dt: f32) void;

    pub fn send(self: *GameClient, data: []const u8, reliable: bool) void;
    pub fn sendInput(self: *GameClient, input: InputState) void;

    pub fn isConnected(self: *GameClient) bool;
    pub fn getServerTick(self: *GameClient) u64;
    pub fn getRTT(self: *GameClient) f32;
};

pub const ClientState = enum {
    disconnected,
    connecting,
    connected,
    loading,
    playing,
};

pub const ClientConfig = struct {
    timeout: f32 = 10.0,
    interpolation_delay: f32 = 0.1,
    prediction_enabled: bool = true,
};
```

### State Replication

```zig
pub const Replicator = struct {
    allocator: Allocator,
    replicated_entities: std.AutoHashMap(NetworkId, ReplicatedEntity),
    dirty_entities: std.ArrayList(NetworkId),

    pub fn init(allocator: Allocator) Replicator;

    // Server-side
    pub fn registerEntity(self: *Replicator, entity: Entity, owner: ?ConnectionId) NetworkId;
    pub fn unregisterEntity(self: *Replicator, network_id: NetworkId) void;
    pub fn markDirty(self: *Replicator, network_id: NetworkId) void;
    pub fn generateSnapshot(self: *Replicator) WorldSnapshot;
    pub fn generateDelta(self: *Replicator, baseline: u64) DeltaSnapshot;

    // Client-side
    pub fn applySnapshot(self: *Replicator, snapshot: WorldSnapshot, scene: *Scene) void;
    pub fn applyDelta(self: *Replicator, delta: DeltaSnapshot, scene: *Scene) void;
};

pub const NetworkId = u32;

pub const ReplicatedEntity = struct {
    network_id: NetworkId,
    entity: Entity,
    owner: ?ConnectionId,
    relevance: RelevanceSet,
    priority: f32,
    last_update_tick: u64,
};

pub const WorldSnapshot = struct {
    tick: u64,
    timestamp: i64,
    entities: []EntitySnapshot,
};

pub const EntitySnapshot = struct {
    network_id: NetworkId,
    component_data: []ComponentSnapshot,
};

pub const ComponentSnapshot = struct {
    component_type: ComponentTypeId,
    data: []const u8,
};

// Replicated component trait
pub fn ReplicatedComponent(comptime T: type) type {
    return struct {
        pub fn serialize(self: *T, writer: *PacketWriter) void;
        pub fn deserialize(reader: *PacketReader) T;
        pub fn interpolate(a: T, b: T, t: f32) T;
    };
}
```

### Client-Side Prediction

```zig
pub const ClientPrediction = struct {
    allocator: Allocator,

    // Input history
    pending_inputs: std.ArrayList(TimestampedInput),
    last_acknowledged_input: u32,

    // State history for reconciliation
    state_history: RingBuffer(PredictedState),

    pub fn init(allocator: Allocator) ClientPrediction;

    // Record input
    pub fn recordInput(self: *ClientPrediction, input: InputState, tick: u64) void;

    // Predict locally
    pub fn predict(self: *ClientPrediction, entity: Entity, scene: *Scene) void;

    // Server reconciliation
    pub fn reconcile(
        self: *ClientPrediction,
        server_state: EntitySnapshot,
        acknowledged_tick: u64,
        scene: *Scene,
    ) void;
};

pub const TimestampedInput = struct {
    input: InputState,
    tick: u64,
    sequence: u32,
};

pub const PredictedState = struct {
    tick: u64,
    position: Vec3,
    velocity: Vec3,
    // Other predicted state...
};

pub const InputState = struct {
    move_direction: Vec2,
    look_direction: Vec2,
    buttons: ButtonState,
    sequence: u32,
    tick: u64,
};
```

### Lag Compensation

```zig
pub const LagCompensator = struct {
    allocator: Allocator,

    // History
    world_history: RingBuffer(HistoryFrame),
    max_rewind_time: f32,

    pub fn init(allocator: Allocator, max_rewind: f32) LagCompensator;

    // Record frame
    pub fn recordFrame(self: *LagCompensator, tick: u64, scene: *Scene) void;

    // Rewind and check
    pub fn rewindAndCheck(
        self: *LagCompensator,
        client_tick: u64,
        ray: Ray,
        shooter: Entity,
    ) ?HitResult;

    // Get state at tick
    pub fn getStateAtTick(self: *LagCompensator, tick: u64) ?*HistoryFrame;
};

pub const HistoryFrame = struct {
    tick: u64,
    entities: []EntityHistoryState,
};

pub const EntityHistoryState = struct {
    entity: Entity,
    position: Vec3,
    bounds: AABB,
};

pub const HitResult = struct {
    entity: Entity,
    position: Vec3,
    normal: Vec3,
    distance: f32,
};
```

### Remote Procedure Calls (RPC)

```zig
pub const RPC = struct {
    pub fn call(
        comptime name: []const u8,
        connection: *Connection,
        args: anytype,
    ) void {
        var writer = PacketWriter.init();
        writer.writeString(name);
        inline for (std.meta.fields(@TypeOf(args))) |field| {
            writer.write(@field(args, field.name));
        }
        connection.send(writer.getBytes(), true);
    }

    pub fn register(
        comptime name: []const u8,
        comptime handler: anytype,
    ) void {
        rpc_handlers.put(name, wrap(handler));
    }
};

// Usage example:
// Server
RPC.register("player_shoot", struct {
    fn handler(client: ConnectionId, direction: Vec3) void {
        // Handle shooting on server
        const player = getPlayerEntity(client);
        spawnProjectile(player, direction);
    }
}.handler);

// Client
RPC.call("player_shoot", connection, .{ .direction = aim_direction });
```

### Lobby System

```zig
pub const Lobby = struct {
    id: LobbyId,
    name: []const u8,
    host: ConnectionId,
    players: std.ArrayList(LobbyPlayer),
    max_players: u32,
    state: LobbyState,
    settings: LobbySettings,

    pub fn create(host: ConnectionId, settings: LobbySettings) !Lobby;
    pub fn join(self: *Lobby, player: ConnectionId) !void;
    pub fn leave(self: *Lobby, player: ConnectionId) void;
    pub fn kick(self: *Lobby, player: ConnectionId) void;
    pub fn setReady(self: *Lobby, player: ConnectionId, ready: bool) void;
    pub fn start(self: *Lobby) !void;

    pub fn canStart(self: *Lobby) bool;
};

pub const LobbyPlayer = struct {
    connection: ConnectionId,
    name: []const u8,
    ready: bool,
    team: ?u32,
};

pub const LobbyState = enum {
    waiting,
    countdown,
    starting,
    in_game,
};

pub const LobbyManager = struct {
    lobbies: std.AutoHashMap(LobbyId, *Lobby),

    pub fn createLobby(self: *LobbyManager, host: ConnectionId, settings: LobbySettings) !*Lobby;
    pub fn findLobby(self: *LobbyManager, id: LobbyId) ?*Lobby;
    pub fn listLobbies(self: *LobbyManager, filter: ?LobbyFilter) []LobbyInfo;
    pub fn destroyLobby(self: *LobbyManager, id: LobbyId) void;
};
```

## Usage Examples

### Simple Server

```zig
var server = try GameServer.init(allocator, .{
    .max_clients = 16,
    .tick_rate = 60,
    .port = 7777,
});

server.on_client_connect = struct {
    fn handler(client: ConnectionId) void {
        std.log.info("Client {d} connected", .{client});
        // Spawn player entity
    }
}.handler;

server.on_message = struct {
    fn handler(client: ConnectionId, data: []const u8) void {
        // Process client message
        const msg = Message.deserialize(data);
        switch (msg.type) {
            .input => handleInput(client, msg.input),
            .chat => handleChat(client, msg.text),
        }
    }
}.handler;

try server.start(7777);

// Game loop
while (running) {
    server.update(dt);

    if (tick_accumulator >= tick_time) {
        server.tick();
        tick_accumulator -= tick_time;
    }
}
```

### Simple Client

```zig
var client = try GameClient.init(allocator, .{
    .prediction_enabled = true,
    .interpolation_delay = 0.1,
});

client.on_connect = struct {
    fn handler() void {
        std.log.info("Connected to server!");
    }
}.handler;

client.on_state_update = struct {
    fn handler(state: *WorldState) void {
        // Apply server state with interpolation
    }
}.handler;

try client.connect(Address.parse("127.0.0.1:7777"));

// Game loop
while (running) {
    client.update(dt);

    // Send input
    const input = gatherInput();
    client.sendInput(input);

    // Predict local player
    client.prediction.predict(local_player, scene);
}
```

## Implementation Steps

### Phase 1: Socket Layer
1. Create socket abstraction
2. Implement TCP and UDP sockets
3. Add address parsing
4. Test basic connectivity

### Phase 2: Connection Management
1. Create connection structure
2. Implement reliable channel
3. Add unreliable channel
4. Handle connection lifecycle

### Phase 3: Server/Client
1. Create game server
2. Create game client
3. Implement connection flow
4. Add message handling

### Phase 4: State Replication
1. Create replication system
2. Implement snapshots
3. Add delta compression
4. Handle entity spawning/despawning

### Phase 5: Prediction
1. Implement input buffering
2. Add client-side prediction
3. Implement server reconciliation
4. Handle misprediction

### Phase 6: Lag Compensation
1. Create state history
2. Implement rewind system
3. Add hit verification
4. Test with latency

### Phase 7: Lobby System
1. Create lobby structure
2. Implement matchmaking
3. Add team management
4. Handle game start flow

## Performance Considerations

- **Bandwidth**: Delta compression, interest management
- **Latency**: Client prediction, interpolation
- **CPU**: Efficient serialization, minimal allocations
- **Scalability**: Connection pooling, spatial partitioning

## Security Considerations

- **Validation**: Validate all client inputs
- **Rate Limiting**: Prevent spam/DoS
- **Authority**: Server authoritative for game state
- **Encryption**: Consider TLS for sensitive data

## References

- [Gaffer On Games](https://gafferongames.com/) - Networking articles
- [Valve Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking)
- [Overwatch Netcode](https://www.gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and)
- [ENet](http://enet.bespin.org/) - Reliable UDP library
