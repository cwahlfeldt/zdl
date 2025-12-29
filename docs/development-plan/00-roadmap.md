# ZDL Engine Development Roadmap

## Executive Summary

This document outlines the comprehensive development plan to evolve ZDL from its current state as a functional 3D rendering foundation into a production-ready game engine. The plan is organized into phases that can be implemented incrementally without breaking core engine abstractions.

## Current Engine State

ZDL is a Zig-based 3D game engine built on SDL3 with the following implemented features:

**Implemented:**

- Entity Component System (ECS) with generational indexing
- Sparse-set component storage for O(1) operations
- Parent-child entity hierarchy with world transform propagation
- Perspective camera with quaternion-based rotation
- Mesh rendering with multiple meshes and textures
- FPS-style camera controller
- Basic audio (WAV playback)
- Cross-platform support (Linux/Vulkan, macOS/Metal)

**Architecture Strengths:**

- Clean separation between engine and game code
- Allocator-first design with explicit memory management
- Compile-time type safety via Zig's comptime
- Well-documented codebase with tests for critical components

## Development Phases

### Phase 1: Core Infrastructure (Foundation)

Essential systems that other features depend on.

| System                                           | Priority | Effort | Dependencies   |
| ------------------------------------------------ | -------- | ------ | -------------- |
| [Asset Pipeline](12-asset-pipeline.md)           | Critical | High   | None           |
| [Scene Serialization](08-scene-serialization.md) | Critical | Medium | Asset Pipeline |
| [Debug & Profiling](13-debug-profiling.md)       | High     | Medium | None           |

**Rationale:** These systems enable productive development of all other features. The asset pipeline provides optimized assets, serialization enables saving/loading, and debug tools accelerate iteration.

### Phase 2: Content Creation

Systems for creating game content.

| System                                         | Priority | Effort | Dependencies   |
| ---------------------------------------------- | -------- | ------ | -------------- |
| [glTF Asset Loading](02-gltf-asset-loading.md) | Critical | High   | Asset Pipeline |
| [Animation System](10-animation-system.md)     | Critical | High   | glTF Loading   |
| [UI System](01-ui-system.md)                   | High     | High   | None           |

**Rationale:** glTF support unlocks industry-standard 3D content. Animation brings characters to life. UI enables menus, HUDs, and debug interfaces.

### Phase 3: Visual Quality

Systems that enhance visual fidelity.

| System                                               | Priority | Effort    | Dependencies       |
| ---------------------------------------------------- | -------- | --------- | ------------------ |
| [Advanced Rendering (PBR)](03-advanced-rendering.md) | Critical | Very High | glTF (materials)   |
| [Skybox & Environment](04-skybox-environment.md)     | High     | Medium    | Advanced Rendering |
| [Particle System](15-particle-system.md)             | High     | High      | None               |

**Rationale:** PBR rendering is the industry standard for realistic materials. Environment rendering provides visual context. Particles enable effects like fire, smoke, and magic.

### Phase 4: Interactivity

Systems that enable gameplay.

| System                                           | Priority | Effort    | Dependencies |
| ------------------------------------------------ | -------- | --------- | ------------ |
| [Physics System](09-physics-system.md)           | Critical | Very High | None         |
| [Controller & Gamepad](05-controller-gamepad.md) | High     | Medium    | Input System |
| [Audio Enhancement](11-audio-enhancement.md)     | High     | Medium    | None         |

**Rationale:** Physics enables collision, movement, and interactions. Gamepad support is essential for console-style games. Enhanced audio provides immersion.

### Phase 5: Extensibility

Systems that enable customization and iteration.

| System                                             | Priority | Effort    | Dependencies       |
| -------------------------------------------------- | -------- | --------- | ------------------ |
| [JavaScript Scripting](07-javascript-scripting.md) | High     | High      | Scene, ECS         |
| [Networking](14-networking.md)                     | Medium   | Very High | Physics (optional) |

**Rationale:** Scripting enables rapid iteration and modding. Networking unlocks multiplayer games.

### Phase 6: Platform Expansion

Reaching additional platforms.

| System                                    | Priority | Effort    | Dependencies     |
| ----------------------------------------- | -------- | --------- | ---------------- |
| [Mobile Platforms](06-mobile-platform.md) | Medium   | Very High | All Core Systems |

**Rationale:** Mobile expands the audience but requires optimization work across all systems.

## System Dependencies Graph

```
                    ┌─────────────────┐
                    │  Asset Pipeline │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
      ┌───────────┐  ┌──────────────┐  ┌─────────┐
      │   glTF    │  │ Serialization│  │ Shaders │
      └─────┬─────┘  └──────────────┘  └────┬────┘
            │                               │
    ┌───────┴───────┐                       │
    ▼               ▼                       ▼
┌─────────┐  ┌───────────┐         ┌────────────────┐
│Animation│  │ Materials │────────▶│ Adv. Rendering │
└─────────┘  └───────────┘         └───────┬────────┘
                                           │
                                   ┌───────┴───────┐
                                   ▼               ▼
                               ┌───────┐    ┌───────────┐
                               │Skybox │    │ Particles │
                               └───────┘    └───────────┘

┌─────────┐       ┌───────────┐       ┌──────────┐
│ Physics │       │   Input   │       │  Audio   │
└─────────┘       └─────┬─────┘       └──────────┘
                        │
                ┌───────┴───────┐
                ▼               ▼
          ┌──────────┐   ┌───────────┐
          │ Gamepad  │   │    UI     │
          └──────────┘   └───────────┘

         ┌───────────────────────┐
         │      Scripting        │
         │  (depends on most     │
         │   systems for API)    │
         └───────────────────────┘
```

## Effort Estimation

| Effort Level | Meaning                            |
| ------------ | ---------------------------------- |
| Low          | 1-2 weeks for core implementation  |
| Medium       | 2-4 weeks for core implementation  |
| High         | 1-2 months for core implementation |
| Very High    | 2-4 months for core implementation |

_Note: Estimates assume full-time development by a single experienced developer. Polish, edge cases, and testing may double these estimates._

## Suggested Implementation Order

### Milestone 1: Developer Experience

1. Debug & Profiling Tools (13)
2. Asset Pipeline (12)
3. Scene Serialization (08)

_Outcome: Efficient development workflow with visual debugging, optimized assets, and save/load capability._

### Milestone 2: Content Pipeline

4. glTF Asset Loading (02)
5. Animation System (10)
6. UI System (01)

_Outcome: Load industry-standard 3D models with animations. Create menus and HUDs._

### Milestone 3: Visual Fidelity

7. Advanced Rendering/PBR (03)
8. Skybox & Environment (04)
9. Particle System (15)

_Outcome: Photorealistic materials, atmospheric environments, visual effects._

### Milestone 4: Gameplay Systems

10. Physics System (09)
11. Controller Support (05)
12. Audio Enhancement (11)

_Outcome: Physical interactions, gamepad input, immersive audio._

### Milestone 5: Extensibility

13. JavaScript Scripting (07)
14. Networking (14)

_Outcome: Rapid gameplay iteration, multiplayer capability._

### Milestone 6: Platform Expansion

15. Mobile Platforms (06)

_Outcome: Reach iOS and Android audiences._

## Risk Assessment

### Technical Risks

| Risk                        | Impact | Mitigation                                             |
| --------------------------- | ------ | ------------------------------------------------------ |
| Physics performance         | High   | Consider integrating Jolt Physics instead of custom    |
| Mobile GPU compatibility    | High   | Early testing on target devices, fallback shaders      |
| Network latency handling    | Medium | Proven netcode patterns (prediction, interpolation)    |
| Animation system complexity | Medium | Start with linear blending, add features incrementally |

### Scope Risks

| Risk                   | Impact | Mitigation                                           |
| ---------------------- | ------ | ---------------------------------------------------- |
| Feature creep          | High   | Strict prioritization, MVP for each system           |
| Integration complexity | Medium | Design APIs before implementation, integration tests |
| Platform fragmentation | Medium | Abstract platform differences early                  |

## Quality Gates

Each system should meet these criteria before being considered complete:

1. **Functional:** Core features work as designed
2. **Tested:** Unit tests for critical paths, integration tests for system boundaries
3. **Documented:** API documentation, usage examples
4. **Performant:** Meets target benchmarks (defined per system)
5. **Integrated:** Works with existing systems without breaking changes

## Maintenance Considerations

- **API Stability:** Minimize breaking changes to existing systems
- **Backwards Compatibility:** Scene files should remain loadable across versions
- **Deprecation:** Mark deprecated APIs, provide migration paths
- **Documentation:** Keep CLAUDE.md and inline docs updated

## Success Metrics

A production-ready engine should demonstrate:

1. **Complete Game:** Build a small but complete game using all systems
2. **Performance:** 60 FPS with realistic scenes (thousands of triangles, dozens of entities)
3. **Stability:** No crashes in normal operation, graceful error handling
4. **Accessibility:** Clear documentation, intuitive APIs
5. **Portability:** Run on all target platforms

## Document Index

| #   | Document                                           | Description                              |
| --- | -------------------------------------------------- | ---------------------------------------- |
| 00  | [Roadmap](00-roadmap.md)                           | This document - overview and planning    |
| 01  | [UI System](01-ui-system.md)                       | User interface rendering and interaction |
| 02  | [glTF Loading](02-gltf-asset-loading.md)           | Industry-standard 3D asset import        |
| 03  | [Advanced Rendering](03-advanced-rendering.md)     | PBR, shadows, post-processing            |
| 04  | [Skybox & Environment](04-skybox-environment.md)   | Environment rendering and IBL            |
| 05  | [Controller Support](05-controller-gamepad.md)     | Gamepad and controller input             |
| 06  | [Mobile Platforms](06-mobile-platform.md)          | iOS and Android support                  |
| 07  | [JavaScript Scripting](07-javascript-scripting.md) | QuickJS embedded scripting               |
| 08  | [Scene Serialization](08-scene-serialization.md)   | Save/load scenes and prefabs             |
| 09  | [Physics System](09-physics-system.md)             | Collision and dynamics                   |
| 10  | [Animation System](10-animation-system.md)         | Skeletal animation and blending          |
| 11  | [Audio Enhancement](11-audio-enhancement.md)       | Spatial audio and mixing                 |
| 12  | [Asset Pipeline](12-asset-pipeline.md)             | Asset processing and bundling            |
| 13  | [Debug & Profiling](13-debug-profiling.md)         | Development tools                        |
| 14  | [Networking](14-networking.md)                     | Multiplayer support                      |
| 15  | [Particle System](15-particle-system.md)           | GPU particle effects                     |

## Getting Started

1. Read this roadmap to understand the overall plan
2. Review the current codebase via CLAUDE.md
3. Start with Milestone 1 (Developer Experience)
4. Implement systems incrementally, testing integration at each step
5. Use the example projects to validate implementations

## Conclusion

This roadmap provides a clear path from ZDL's current foundation to a full-featured game engine. The phased approach allows for incremental progress while maintaining stability. Each system builds on previous work, creating a cohesive and extensible architecture.

The key to success is disciplined execution: complete each system to production quality before moving to the next, maintain backwards compatibility, and keep documentation current.
