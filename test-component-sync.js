// Test component synchronization debugging
import zdl from "zdl";

console.log("=== Component Sync Debug Test ===");

const TransformComp = (x = 0, y = 0, z = 0) => ({
    type: "Transform",
    position: { x, y, z },
    rotation: { x: 0, y: 0, z: 0, w: 1 },
    scale: { x: 1, y: 1, z: 1 },
});

const MeshRendererComp = (meshType) => ({
    type: "MeshRenderer",
    meshType: meshType,
    material: null,
});

function main() {
    const window = zdl.createWindow({ size: "400x300", title: "Test" });
    const world = zdl.createWorld(window);

    world.addComponents([TransformComp, MeshRendererComp]);

    console.log("Creating entity with Transform and MeshRenderer...");
    const entity = world.addEntity(() => ({ name: "test_cube" }))(
        TransformComp(1, 2, 3),
        MeshRendererComp("cube")
    );

    console.log("Entity created:", entity);

    // Check if components are in the store
    if (typeof __component_store !== 'undefined') {
        console.log("Component store exists!");
        console.log("Transform store:", __component_store.Transform);
        console.log("MeshRenderer store:", __component_store.MeshRenderer);
    } else {
        console.log("Component store is undefined!");
    }

    // Add a system to continuously check
    let frameCount = 0;
    world.addSystem(() => {
        frameCount++;
        if (frameCount === 1) {
            console.log("First frame - checking component store...");
            if (typeof __component_store !== 'undefined') {
                const hasTransform = __component_store.Transform && __component_store.Transform[entity.id];
                const hasMesh = __component_store.MeshRenderer && __component_store.MeshRenderer[entity.id];
                console.log("Entity has Transform in store:", !!hasTransform);
                console.log("Entity has MeshRenderer in store:", !!hasMesh);
                if (hasTransform) {
                    console.log("Transform data:", __component_store.Transform[entity.id]);
                }
                if (hasMesh) {
                    console.log("MeshRenderer data:", __component_store.MeshRenderer[entity.id]);
                }
            }
        }
        if (frameCount === 10) {
            console.log("10 frames rendered, quitting...");
            Engine.quit();
        }
    }, "update");

    console.log("Test setup complete!");
}

main;
