# ZDL Engine Structural Review

## Scope and sources

This review is based on:
- Core engine and runtime systems in `src/engine/engine.zig`, `src/engine.zig`, and `src/ecs/`
- Rendering, PBR, IBL, and shader assets in `src/ecs/systems/`, `src/resources/`, `src/ibl/`, and `assets/shaders/`
- Asset pipeline and runtime asset management in `tools/asset_pipeline/` and `src/assets/`
- Scripting, UI, animation, debug tooling, and serialization in `src/scripting/`, `src/ui/`, `src/animation/`, `src/debug/`, and `src/serialization/`
- Roadmap and migration plans in `docs/development-plan/` and `FLECS_MIGRATION_PLAN.md`

## What is working well

- Clear module exports and a discoverable public API surface in `src/engine.zig`.
- The engine already spans major subsystems: ECS, rendering, PBR materials, animation, UI, scripting, input, audio, debug tools, and asset pipeline.
- The asset pipeline exists as a standalone tool with incremental builds and shader validation in `tools/asset_pipeline/`.
- The rendering path supports a legacy and PBR pipeline with automatic switching in `src/ecs/systems/render_system.zig`.
- The ECS is already on Flecs with clean component registration in `src/ecs/scene.zig`.
- Debug tooling is unusually strong for an early engine (profiler, debug draw, stats overlay) in `src/debug/`.
- Examples cover most systems and act as integration tests in `examples/`.
- Documentation is thorough and forward-looking in `docs/development-plan/` and `README.md`.

## Structural issues and risks

These are the highest-impact issues that affect maintainability and production readiness.

1) Flecs migration is incomplete and already causing breakage.
- `src/serialization/scene_serializer.zig` references `scene.root_entities` and `Entity.index`, neither of which exist in the Flecs-based `Scene` and `Entity` types. This likely makes serialization unusable right now.
- The migration plan in `FLECS_MIGRATION_PLAN.md` explicitly calls out serialization and JS bindings as later steps, but the current codebase assumes they are already migrated.

2) The engine core is a single, monolithic orchestrator.
- `src/engine/engine.zig` owns SDL windowing, GPU pipelines, rendering state, input, audio, scripting runtime, and IBL state. This makes it hard to isolate responsibilities, test subsystems, or swap implementations.

3) The ECS is not used for scheduling or system phases.
- `Scene.updateWorldTransforms()` manually recurses the hierarchy and allocates child lists every frame in `src/ecs/scene.zig`.
- Systems like animation and scripting are updated manually instead of running inside a Flecs pipeline, which loses ordering guarantees and makes dependency management brittle.

4) Asset lifetime and ownership are fragile.
- Components store raw pointers to mesh and texture data (for example `MeshRendererComponent` in `src/ecs/components/mesh_renderer.zig`), but there is no handle system or lifetime tracking. Unloading or reloading assets can easily create dangling pointers.

5) Rendering lacks a structured render graph or frame pipeline.
- Rendering is a single pass with manual state switches in `src/ecs/systems/render_system.zig` and `src/engine/engine.zig`. There is no explicit concept of render phases, post-processing, or batching strategy.

6) Time management is minimal and mixes simulation and presentation.
- `Engine.runScene` uses a variable time step with a simple sleep-based cap and no fixed update loop. This will lead to unstable physics and non-determinism once physics or networking are added.

7) Several production-critical systems are partial or missing.
- IBL, skybox environment, and some GLTF rotation handling are marked TODO in `src/ibl/` and `src/assets/gltf/types.zig`.
- There is no physics, navigation, networking, particle system, or robust audio mixing system integrated yet (see `docs/development-plan`).

## Recommended structural improvements

### 1) Finish the Flecs migration and treat it as a spine

Goals:
- Use Flecs for system ordering and for data flow between subsystems.
- Remove manual per-frame recursion and allocation for transforms.

Actions:
- Migrate scene serialization to iterate Flecs entities and relationships (per `FLECS_MIGRATION_PLAN.md`).
- Register transform propagation as a Flecs system using cascade queries instead of `Scene.updateWorldTransforms()`.
- Move animation, scripting, and FPV camera controllers into Flecs systems with explicit phase ordering (PreUpdate, OnUpdate, PostUpdate).
- Ensure JS bindings use Flecs entity IDs rather than legacy indexes.

### 2) Split Engine into focused subsystems

Goals:
- Make ownership and responsibilities explicit.
- Allow testing and integration per subsystem.

Suggested split of `Engine`:
- `WindowSystem` (SDL window and event plumbing)
- `Renderer` (pipelines, frame submission, render graph, GPU resources)
- `InputSystem` (already exists, but keep the owner separate from rendering)
- `AudioSystem` (device ownership and mixer)
- `ScriptingSystem` (runtime and bindings)
- `AssetSystem` (lifetime-managed asset handles and streaming)
- `SceneSystem` (world, ECS systems, and scene lifecycle)

A thin `Engine` can then orchestrate these with a clear update order.

### 3) Introduce a frame pipeline and fixed-step update

Goals:
- Separate simulation from presentation.
- Provide deterministic updates for physics and networking.

Actions:
- Add a fixed-step accumulator for simulation updates.
- Provide standard stages: PreUpdate -> FixedUpdate -> Update -> LateUpdate -> Render.
- Tie Flecs phases to those stages and run `ecs.progress()` in the appropriate stage.

### 4) Replace raw asset pointers with handles

Goals:
- Prevent dangling pointers and enable hot reload or streaming.

Actions:
- Add an `AssetHandle` type that uses IDs and reference counting.
- `MeshRendererComponent` should store a handle rather than a raw pointer.
- AssetManager should manage refcounts and explicit release.
- Integrate asset pipeline metadata for versioning and load validation.

### 5) Rendering architecture improvements

Goals:
- Improve extensibility, batching, and future features.

Actions:
- Introduce a render graph or at least explicit render passes (shadow, skybox, opaque, transparent, UI, post).
- Add frustum culling, simple draw sorting, and instancing for repeated meshes.
- Build a material system that separates shader selection, state, and textures from entity data.
- Decide on a convention for coordinate system and camera forward vector, and enforce it in both math and shaders.

### 6) Formalize configuration and capability flags

Goals:
- Avoid manual init ordering and hidden prerequisites.

Actions:
- Add explicit flags in `EngineConfig` for optional subsystems (PBR, IBL, scripting, debug tools).
- Keep `Engine.init()` as a single entry point that respects those flags.

## Additional systems needed for production readiness

These are the systems that typically define a production-ready engine. Many are already listed in `docs/development-plan`, but they are not yet integrated end-to-end.

Core runtime:
- Physics and collision (consider a well-maintained external library).
- Animation state machine and animation events (not just clips).
- Entity prefab system with versioning and nested prefabs.
- Scene streaming and background loading.
- Save/load with migration support across versions.

Rendering:
- Completed IBL pipeline (irradiance, prefiltered env, BRDF LUT).
- Shadow mapping (directional, spot, and point lights).
- Post-processing stack (tone mapping, bloom, TAA or FXAA).
- GPU-driven data updates for animation skinning (already started but not fully integrated with render scheduling).

Tooling and workflow:
- Asset validation and error reporting in the editor/runtime.
- Live hot reload for assets beyond scripting (shaders, textures, meshes).
- Editor or CLI tooling for scene creation, not just serialization.
- Automated integration tests for examples and serialization.

Platform and performance:
- Job system for parallel asset loading and heavy CPU tasks.
- Central logging and diagnostic channels (info/warn/error/perf).
- GPU/CPU profiling hooks at the frame and system level.

## Suggested near-term stabilization plan

1) Complete Flecs migration for serialization and scripting bindings. This removes current breakage and sets a stable base.
2) Replace transform recursion with a Flecs cascade system to remove per-frame allocations.
3) Introduce an asset handle system and convert `MeshRendererComponent` to use it.
4) Add a fixed timestep update loop and wire Flecs phases to it.
5) Establish a render pass structure (even if minimal) to unlock shadow maps and post-processing later.

## Summary

ZDL already demonstrates a surprisingly broad feature set for a Zig engine, with strong documentation and practical demos. The largest risk is architectural drift introduced during the Flecs migration and the growing responsibility pile in `Engine`. By finishing the migration, separating core subsystems, and formalizing the update pipeline and asset lifetimes, the engine will move from a feature-rich prototype to a stable foundation for production work.
