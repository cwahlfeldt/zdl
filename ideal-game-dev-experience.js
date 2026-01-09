// Ideal game dev experience.
//
// Built on the custom ZDL engine.
//
// The ECS handles game logic and is tightly integrated with the
// rendering system to enable fast iteration and rapid development.
//
// For example: A rendered camera is created and registered with the ECS,
// allowing full control of camera data through components, while also ading
// it to our 3d world.
//
// Includes a `zdl` CLI for common workflows:
// 1. Create a project: `zdl create <filepath>`
// 2. Run the game: `zdl run [optional-file-path]`
// 3. Build the game: `zdl build [optional-file-path]`

import zdl from "zdl";

/* ============================
 * Components
 * ============================ */

// Tag-style component
const Player = () => ({
  type: "Player",
  name: "Player",
});

// Data component
const Position = (x = 0, y = 0, z = 0) => ({
  type: "Position",
  position: { x, y, z },
});

const Camera = ({ fov = 60, near = 0.1, far = 1000, active = true }) => ({
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

// additional components can exist here
// const Velocity = ...
// const Light = ...
// ...

/* ============================
 * Scene setup
 * ============================ */

export function initialSceneMain() {
  // initialize the window
  const window = zdl.createWindow({
    size: "1920x1080",
    title: "ZDL Example Game",
  });

  // create the world (ecs + render world)
  const world = zdl.createWorld(window);

  // register components with the world
  world.addComponents([Player, Position, Camera, Mesh]);

  // create player entity
  const player = world.addEntity((ctx) => ({
    description: "Main player entity",
    name: "player",
  }))(Player(), Position(0, 0, 0), Mesh("assets/player.glb"));

  // create camera entity
  const camera = world.addEntity((ctx) => ({
    description: "Main camera",
    name: "camera",
  }))(Camera({ fov: 75 }), Position(0, 2, 5));

  // create a cube mesh entity
  const cubeMesh = world.addEntity((ctx) => ({
    description: "Test cube",
    name: "cube",
  }))(Position(2, 0, 0), Mesh("assets/cube.glb"));

  // register systems
  world.addSystem(moveSystem, "update");
  world.addSystem(otherInitSystem, "init");
  world.addSystem(otherDestroySystem, "destroy");

  console.log("World populated with a player, a camera, and a mesh");
  console.log("Run with `zdl play` in the root of the game directory");
  console.log("A window should open showing the scene through the camera");
}

/* ============================
 * Systems
 * ============================ */

export function moveSystem(world) {
  const results = world.query(Player, Position);

  for (const entity of results) {
    if (world.hasComponent(entity, Position)) {
      const pos = world.getComponent(entity, Position);

      world.updateComponent(
        entity,
        Position(pos.position.x + 1, pos.position.y, pos.position.z)
      );
    }
  }
}

function otherInitSystem(world) {
  console.log("Init system ran");
}

function otherDestroySystem(world) {
  console.log("Destroy system ran");
}
