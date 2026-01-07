// Orbiter script
// Makes the entity orbit around the origin

class Orbiter {
  constructor() {
    this.orbitRadius = 5.0;
    this.orbitSpeed = 1.5;
    this.bobSpeed = 3.0;
    this.bobAmount = 0.5;
    this.time = 0;
  }

  onStart() {
    console.log("Orbiter started - circling around origin");
  }

  onUpdate(dt) {
    this.time += dt;

    var transform = this.transform;
    if (!transform) return;

    // Calculate orbit position
    var angle = this.time * this.orbitSpeed;
    var x = Math.cos(angle) * this.orbitRadius;
    var z = Math.sin(angle) * this.orbitRadius;

    // Add vertical bobbing
    var y = 1.0 + Math.sin(this.time * this.bobSpeed) * this.bobAmount;

    transform.position = new Vec3(x, y, z);

    // Make the sphere spin
    transform.setRotationEuler(this.time * 2, this.time * 3, 0);
  }

  onDestroy() {
    console.log("Orbiter destroyed");
  }
}

Orbiter;
