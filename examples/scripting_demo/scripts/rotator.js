// Simple rotation script
// Rotates the entity continuously on multiple axes

class Rotator {
    constructor() {
        this.rotationSpeed = 1.0;
        this.time = 0;
    }

    onStart() {
        console.log("Rotator started on entity");
    }

    onUpdate(dt) {
        this.time += dt;

        var transform = this.transform;
        if (!transform) return;

        // Rotate continuously
        transform.setRotationEuler(
            this.time * this.rotationSpeed * 0.7,
            this.time * this.rotationSpeed,
            this.time * this.rotationSpeed * 0.5
        );
    }

    onDestroy() {
        console.log("Rotator destroyed");
    }
}

Rotator;
