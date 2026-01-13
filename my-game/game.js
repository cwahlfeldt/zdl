// my-game - ZDL Game
//
// This is your game's main entry point.
// Run with: zdl run

// Note: zdl is available as a global object, no need to import

/* ============================
 * Components
 * ============================ */

const Player = () => ({
  type: "Player",
  name: "Player",
});

const Position = (x = 0, y = 0, z = 0) => ({
  type: "Position",
  position: { x, y, z },
});

const Camera = ({ fov = 60, near = 0.1, far = 1000, active = true } = {}) => ({
  type: "Camera",
  fov,
  near,
  far,
  active,
});

const Mesh = (path = "assets/cube.glb") => ({
  type: "Mesh",
  path,
});

/* ============================
 * Systems
 * ============================ */

function moveSystem(world) {
  const results = world.query(Player, Position);

  for (const entity of results) {
    if (world.hasComponent(entity, Position)) {
      const pos = world.getComponent(entity, Position);

      world.updateComponent(
        entity,
        Position(pos.position.x + 0.01, pos.position.y, pos.position.z)
      );
    }
  }
}

function initSystem(world) {
  console.log("Game initialized!");
}

function destroySystem(world) {
  console.log("Game shutting down");
}

/* ============================
 * Scene Setup
 * ============================ */

function main() {
  // Initialize the window
  const window = zdl.createWindow({
    size: "1280x720",
    title: "my-game",
  });

  // Create the world (ECS + render world)
  const world = zdl.createWorld(window);

  // Register components with the world
  // TEMPORARILY DISABLED due to QuickJS recursion bug
  // world.addComponents([Player, Position, Camera, Mesh]);

  // Manual registration as workaround:
  Component.register("Player", {}, true);
  Component.register("Position", { position: "object" }, false);
  Component.register("Camera", { fov: "number", near: "number", far: "number", active: "boolean" }, false);
  Component.register("Mesh", { path: "string" }, false);

  // Create player entity
  const player = world.addEntity((ctx) => ({
    description: "Main player entity",
    name: "player",
  }))(Player(), Position(0, 0, 0), Mesh("assets/player.glb"));

  // Create camera entity
  const camera = world.addEntity((ctx) => ({
    description: "Main camera",
    name: "camera",
  }))(Camera({ fov: 75 }), Position(0, 2, 5));

  // Create a cube mesh entity
  const cubeMesh = world.addEntity((ctx) => ({
    description: "Test cube",
    name: "cube",
  }))(Position(2, 0, 0), Mesh("assets/cube.glb"));

  // Register systems
  world.addSystem(moveSystem, "update");
  world.addSystem(initSystem, "init");
  world.addSystem(destroySystem, "destroy");

  console.log("World populated with entities");
  console.log("Run with `zdl run` in the project directory");
}
