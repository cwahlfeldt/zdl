// Test rendering with native components
import zdl from "zdl";

console.log("=== Test Rendering ===");

// Component factories
const TransformComp = (x = 0, y = 0, z = 0) => ({
    type: "Transform",
    position: { x, y, z },
    rotation: { x: 0, y: 0, z: 0, w: 1 },
    scale: { x: 1, y: 1, z: 1 },
});

const CameraComp = () => ({
    type: "Camera",
    fov: 1.0472, // 60 degrees
    near: 0.1,
    far: 1000.0,
});

const MeshRendererComp = (meshType, material = null) => ({
    type: "MeshRenderer",
    meshType: meshType,
    material: material,
});

const LightComp = (lightType, color, intensity, range = 0) => ({
    type: "Light",
    lightType: lightType,
    color: color,
    intensity: intensity,
    range: range,
});

const Material = {
    metal: (r, g, b, roughness) => ({
        baseColor: { x: r, y: g, z: b, w: 1 },
        metallic: 1.0,
        roughness: roughness,
    }),
};

function main() {
    console.log("Creating window and world...");
    const window = zdl.createWindow({ size: "800x600", title: "Render Test" });
    const world = zdl.createWorld(window);

    // Register components
    world.addComponents([TransformComp, CameraComp, MeshRendererComp, LightComp]);

    // Create camera
    console.log("Creating camera...");
    const camera = world.addEntity(() => ({ name: "camera" }))(
        TransformComp(0, 2, 5),
        CameraComp()
    );
    Scene.setActiveCamera(camera);

    // Create a light
    console.log("Creating light...");
    world.addEntity(() => ({ name: "sun" }))(
        TransformComp(0, 5, 0),
        LightComp("directional", { x: 1, y: 1, z: 1 }, 2.0)
    );

    // Create a cube
    console.log("Creating cube...");
    const cube = world.addEntity(() => ({ name: "cube" }))(
        TransformComp(0, 0, 0),
        MeshRendererComp("cube", Material.metal(0.9, 0.1, 0.1, 0.2))
    );

    console.log("Scene setup complete!");
    console.log("Camera:", camera);
    console.log("Cube:", cube);
    console.log("Entity count:", Scene.entityCount());

    // Add a simple rotation system
    let time = 0;
    world.addSystem((world) => {
        time += Engine.deltaTime;

        // Rotate the cube
        const transform = world.getComponent(cube, TransformComp);
        if (transform) {
            transform.rotation.y = time;
            world.updateComponent(cube, transform);
        }
    }, "update");

    console.log("Game ready!");
}

main;
