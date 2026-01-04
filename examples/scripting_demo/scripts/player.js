// Player FPS camera controller
// This script handles WASD movement and mouse look

class PlayerController {
    constructor() {
        this.moveSpeed = 5.0;
        this.lookSensitivity = 0.003;
        this.pitch = 0;
        this.yaw = 0;
        this.jumpVelocity = 0;
        this.gravity = 15;
        this.jumpForce = 5;
        this.grounded = true;
    }

    onStart() {
        console.log("PlayerController started!");
        console.log("  - Click to capture mouse");
        console.log("  - WASD to move, Space to jump");
        console.log("  - ESC to release mouse");
    }

    onUpdate(dt) {
        var transform = this.transform;
        if (!transform) return;

        // Get unified input
        var move = Input.getMoveVector();
        var look = Input.getLookVector();

        // Mouse look
        if (Engine.isMouseCaptured()) {
            this.yaw -= look.x * this.lookSensitivity;
            this.pitch -= look.y * this.lookSensitivity;

            // Clamp pitch
            if (this.pitch > 1.5) this.pitch = 1.5;
            if (this.pitch < -1.5) this.pitch = -1.5;

            transform.setRotationEuler(this.pitch, this.yaw, 0);
        }

        // Movement
        if (move.x !== 0 || move.y !== 0) {
            var forward = transform.forward();
            var right = transform.right();

            // Project forward onto horizontal plane
            forward = new Vec3(forward.x, 0, forward.z).normalize();
            right = new Vec3(right.x, 0, right.z).normalize();

            var velocity = right.mul(move.x).add(forward.mul(-move.y));
            velocity = velocity.normalize().mul(this.moveSpeed * dt);
            transform.translate(velocity);
        }

        // Jump
        if (Input.isJumpPressed() && this.grounded) {
            this.jumpVelocity = this.jumpForce;
            this.grounded = false;
        }

        // Apply gravity
        if (!this.grounded) {
            this.jumpVelocity -= this.gravity * dt;
            transform.translate(new Vec3(0, this.jumpVelocity * dt, 0));

            // Simple ground check
            var pos = transform.position;
            if (pos.y <= 2) {
                transform.position = new Vec3(pos.x, 2, pos.z);
                this.jumpVelocity = 0;
                this.grounded = true;
            }
        }

        // Capture mouse on click
        if (Input.isMouseButtonPressed('left') && !Engine.isMouseCaptured()) {
            Engine.setMouseCapture(true);
        }

        // Release mouse on escape
        if (Input.isKeyPressed('escape') && Engine.isMouseCaptured()) {
            Engine.setMouseCapture(false);
        }
    }

    onDestroy() {
        console.log("PlayerController destroyed");
    }
}

PlayerController;
