// Helmet Cube Click - JavaScript Implementation
// A port of the helmet_cube_click example using ZDL's JavaScript API
// Click the red cube to move the helmet to it

import zdl from "zdl";

// Game state
const state = {
    cubeEntity: null,
    helmetRoot: null,
    cameraEntity: null,
    helmetTarget: { x: -3, y: 0, z: 0 },
    helmetMoving: false,
    helmetMoveSpeed: 2.4,
    prevMouseLeft: false,
};

// Component factories
const TransformComp = (x = 0, y = 0, z = 0) => ({
    type: "Transform",
    position: { x, y, z },
    rotation: { x: 0, y: 0, z: 0, w: 1 },
    scale: { x: 1, y: 1, z: 1 },
});

const CameraComp = () => ({
    type: "Camera",
    fov: 1.0472, // 60 degrees in radians
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

// Material helper
const Material = {
    metal: (r, g, b, roughness) => ({
        baseColor: { x: r, y: g, z: b, w: 1 },
        metallic: 1.0,
        roughness: roughness,
    }),
    dielectric: (r, g, b, roughness) => ({
        baseColor: { x: r, y: g, z: b, w: 1 },
        metallic: 0.0,
        roughness: roughness,
    }),
};

// Ray structure
class Ray {
    constructor(origin, direction) {
        this.origin = origin;
        this.direction = direction;
    }
}

// Ray-AABB intersection test
function rayIntersectsAABB(ray, center, halfExtents) {
    const min = {
        x: center.x - halfExtents.x,
        y: center.y - halfExtents.y,
        z: center.z - halfExtents.z,
    };
    const max = {
        x: center.x + halfExtents.x,
        y: center.y + halfExtents.y,
        z: center.z + halfExtents.z,
    };

    let tmin = -Infinity;
    let tmax = Infinity;

    // Test X slab
    if (!updateSlab(ray.origin.x, ray.direction.x, min.x, max.x)) return false;
    const [newTminX, newTmaxX] = getSlabIntersection(ray.origin.x, ray.direction.x, min.x, max.x);
    tmin = Math.max(tmin, newTminX);
    tmax = Math.min(tmax, newTmaxX);
    if (tmax < tmin) return false;

    // Test Y slab
    if (!updateSlab(ray.origin.y, ray.direction.y, min.y, max.y)) return false;
    const [newTminY, newTmaxY] = getSlabIntersection(ray.origin.y, ray.direction.y, min.y, max.y);
    tmin = Math.max(tmin, newTminY);
    tmax = Math.min(tmax, newTmaxY);
    if (tmax < tmin) return false;

    // Test Z slab
    if (!updateSlab(ray.origin.z, ray.direction.z, min.z, max.z)) return false;
    const [newTminZ, newTmaxZ] = getSlabIntersection(ray.origin.z, ray.direction.z, min.z, max.z);
    tmin = Math.max(tmin, newTminZ);
    tmax = Math.min(tmax, newTmaxZ);

    return tmax >= Math.max(tmin, 0.0);
}

function updateSlab(origin, dir, min, max) {
    if (Math.abs(dir) < 0.0001) {
        return origin >= min && origin <= max;
    }
    return true;
}

function getSlabIntersection(origin, dir, min, max) {
    const invDir = 1.0 / dir;
    let t1 = (min - origin) * invDir;
    let t2 = (max - origin) * invDir;
    if (t1 > t2) {
        [t1, t2] = [t2, t1];
    }
    return [t1, t2];
}

// Build a ray from screen coordinates
function buildMouseRay(camTransform, cameraComp, mouseX, mouseY) {
    const width = Engine.windowWidth;
    const height = Engine.windowHeight;
    const aspect = width / height;

    // Convert to NDC (-1 to 1)
    const ndcX = (mouseX / width) * 2.0 - 1.0;
    const ndcY = 1.0 - (mouseY / height) * 2.0;

    // Build ray direction in camera space
    const tanHalfFov = Math.tan(cameraComp.fov * 0.5);
    const dirCameraX = ndcX * aspect * tanHalfFov;
    const dirCameraY = ndcY * tanHalfFov;
    const dirCameraZ = -1.0;

    // Normalize camera space direction
    const len = Math.sqrt(dirCameraX * dirCameraX + dirCameraY * dirCameraY + dirCameraZ * dirCameraZ);
    const dirCamera = {
        x: dirCameraX / len,
        y: dirCameraY / len,
        z: dirCameraZ / len,
    };

    // Rotate by camera rotation to get world space direction
    const rot = camTransform.rotation;
    const dirWorld = rotateVec3ByQuat(dirCamera, rot);

    return new Ray(camTransform.position, dirWorld);
}

// Rotate a vector by a quaternion
function rotateVec3ByQuat(v, q) {
    // q * v * q^-1
    const qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    const vx = v.x, vy = v.y, vz = v.z;

    // First: q * v (treating v as quaternion with w=0)
    const tx = qw * vx + qy * vz - qz * vy;
    const ty = qw * vy + qz * vx - qx * vz;
    const tz = qw * vz + qx * vy - qy * vx;
    const tw = -qx * vx - qy * vy - qz * vz;

    // Second: result * q^-1 (conjugate since unit quaternion)
    return {
        x: tx * qw - tw * qx + ty * (-qz) - tz * (-qy),
        y: ty * qw - tw * qy + tz * (-qx) - tx * (-qz),
        z: tz * qw - tw * qz + tx * (-qy) - ty * (-qx),
    };
}

// Normalize a vector
function normalize(v) {
    const len = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return len > 0 ? { x: v.x / len, y: v.y / len, z: v.z / len } : v;
}

// Vector subtraction
function sub(a, b) {
    return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z };
}

// Vector length
function length(v) {
    return Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

// Main entry point
function main() {
    console.log("=== Helmet Cube Click (JavaScript) ===");
    console.log("Click the red cube to move the helmet to it.");

    // Create world and window
    const window = zdl.createWindow({ size: "1440x900", title: "ZDL - Helmet Cube Click (JS)" });
    const world = zdl.createWorld(window);

    // Register components
    world.addComponents([TransformComp, CameraComp, MeshRendererComp, LightComp]);

    // Create camera
    state.cameraEntity = world.addEntity((ctx) => ({
        name: "camera",
        description: "Main camera",
    }))(
        TransformComp(0, 1.8, 7.5),
        CameraComp()
    );

    Scene.setActiveCamera(state.cameraEntity);

    // Create sun light
    const sunTransform = TransformComp(0, 0, 0);
    sunTransform.rotation = { x: -0.85, y: 0.4, z: 0, w: 1 }; // Approximate euler to quat
    world.addEntity(() => ({ name: "sun" }))(
        sunTransform,
        LightComp("directional", { x: 1.0, y: 0.98, z: 0.93 }, 2.0)
    );

    // Create rim light
    world.addEntity(() => ({ name: "rimLight" }))(
        TransformComp(-4.0, 3.5, 3.5),
        LightComp("point", { x: 0.4, y: 0.6, z: 1.0 }, 18.0, 25.0)
    );

    // Create warm light
    world.addEntity(() => ({ name: "warmLight" }))(
        TransformComp(4.5, 2.2, 2.0),
        LightComp("point", { x: 1.0, y: 0.6, z: 0.35 }, 14.0, 22.0)
    );

    // Create ground plane
    const floorTransform = TransformComp(0, 0, 0);
    floorTransform.scale = { x: 18, y: 1, z: 18 };
    world.addEntity(() => ({ name: "floor" }))(
        floorTransform,
        MeshRendererComp("plane", Material.dielectric(0.18, 0.2, 0.24, 0.9))
    );

    // Create clickable cube
    const cubeTransform = TransformComp(3.0, 0.75, 0.0); // 1.5 * 0.5 = 0.75 for half height
    cubeTransform.scale = { x: 1.5, y: 1.5, z: 1.5 };
    state.cubeEntity = world.addEntity(() => ({ name: "cube" }))(
        cubeTransform,
        MeshRendererComp("cube", Material.metal(0.9, 0.2, 0.1, 0.2))
    );

    // Create helmet root (placeholder - would load GLTF in full version)
    state.helmetRoot = world.addEntity(() => ({ name: "helmet" }))(
        TransformComp(-3, 0, 0),
        MeshRendererComp("cube", Material.metal(0.7, 0.7, 0.7, 0.3))
    );

    console.log("Scene created successfully!");
    console.log("Entities:", Scene.entityCount());

    // Register update system
    world.addSystem(updateSystem, "update");
}

// Update system
function updateSystem(world) {
    const dt = Engine.deltaTime;

    // Handle mouse click for raycasting
    const mouseDown = Input.isMouseButtonDown("left");
    const mouseClicked = mouseDown && !state.prevMouseLeft;
    state.prevMouseLeft = mouseDown;

    if (mouseClicked) {
        const camTransform = world.getComponent(state.cameraEntity, TransformComp);
        const cameraComp = world.getComponent(state.cameraEntity, CameraComp);

        if (camTransform && cameraComp) {
            const mousePos = Input.getMousePosition();
            const ray = buildMouseRay(camTransform, cameraComp, mousePos.x, mousePos.y);

            const cubeTransform = world.getComponent(state.cubeEntity, TransformComp);
            if (cubeTransform) {
                const cubeCenter = cubeTransform.position;
                const cubeHalfExtents = {
                    x: cubeTransform.scale.x * 0.5,
                    y: cubeTransform.scale.y * 0.5,
                    z: cubeTransform.scale.z * 0.5,
                };

                if (rayIntersectsAABB(ray, cubeCenter, cubeHalfExtents)) {
                    console.log("Cube clicked! Moving helmet...");
                    state.helmetTarget = cubeCenter;
                    state.helmetMoving = true;
                }
            }
        }
    }

    // Move helmet towards target
    if (state.helmetMoving) {
        const helmetTransform = world.getComponent(state.helmetRoot, TransformComp);
        if (helmetTransform) {
            const current = helmetTransform.position;
            const toTarget = sub(state.helmetTarget, current);
            const distance = length(toTarget);
            const step = state.helmetMoveSpeed * dt;

            if (distance <= step || distance < 0.01) {
                helmetTransform.position = state.helmetTarget;
                world.updateComponent(state.helmetRoot, helmetTransform);
                state.helmetMoving = false;
                console.log("Helmet arrived at target!");
            } else {
                const direction = normalize(toTarget);
                helmetTransform.position = {
                    x: current.x + direction.x * step,
                    y: current.y + direction.y * step,
                    z: current.z + direction.z * step,
                };
                world.updateComponent(state.helmetRoot, helmetTransform);
            }
        }
    }
}

// Export main
main;
