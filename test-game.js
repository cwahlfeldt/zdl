// Simple test game to verify JavaScript entry point works
// Usage: ./zig-out/bin/zdl run test-game.js

import zdl from "zdl";

console.log("=== ZDL JavaScript Entry Point Test ===");
console.log("This script tests that JavaScript can be the game entry point.");

// Main entry point
function main() {
    console.log("main() called!");
    console.log("Creating window...");

    const window = zdl.createWindow({
        size: "800x600",
        title: "ZDL JS Test"
    });

    console.log("Window config created:", window);

    console.log("Creating world...");
    const world = zdl.createWorld(window);
    console.log("World created:", world);

    // Define a simple component
    const Position = (x = 0, y = 0, z = 0) => ({
        type: "Position",
        x, y, z
    });

    // Register components
    console.log("Registering components...");
    world.addComponents([Position]);

    // Create an entity
    console.log("Creating entity...");
    const entity = world.addEntity((ctx) => ({
        description: "Test entity",
        name: "test"
    }))(Position(1, 2, 3));

    console.log("Entity created:", entity);

    // Create a simple system
    function testSystem(world) {
        console.log("Test system running!");
        const results = world.query(Position);
        for (const ent of results) {
            if (world.hasComponent(ent, Position)) {
                const pos = world.getComponent(ent, Position);
                console.log("Entity", ent, "position:", pos);
            }
        }
    }

    // Register the system
    console.log("Registering system...");
    world.addSystem(testSystem, "init");

    console.log("Setup complete! Game should start now...");
}

// Export main so the engine can call it
main;
