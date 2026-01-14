# Forward+ Renderer Cleanup Plan

## Goals
- Ship a single, high-fidelity, performant Forward+ PBR/IBL/skybox renderer across platforms with professional (non-AAA) quality.
- Remove legacy/PBR-only paths, shaders, and dead code.
- Keep IBL + skybox support as part of Forward+.

## Decisions (Confirmed)
- Remove raymarch example and shaders.
- Keep skinned shader assets for future animation work.
- Initialize Forward+ by default in `Engine.init`.

## Progress
- Removed raymarch demo + shaders and the build target.
- Removed unused shader library and pipeline cache modules.
- Forward+ is now the only render path; legacy/PBR pipeline code removed.
- Legacy and PBR-only shader assets removed.

## Feature scope (Professional, not AAA)
- Forward+ clustered lighting (GPU compute culling with CPU fallback).
- PBR metallic-roughness shading with normal/emissive/AO + alpha mask/blend.
- IBL (irradiance + prefiltered env + BRDF LUT) + skybox.
- HDR + ACES tonemap + gamma correction.
- Mandatory polish: basic shadows (directional + spot), simple fog, lightweight bloom.
- Keep scope lean: no deferred path, no ray tracing, no heavy post stack.

## Shadow defaults (low-fuss, good-looking)
- Directional light: 2-3 cascade CSM with PCF filtering.
- Spot lights: 2D shadow maps, small capped count (2-4), PCF filtering.
- Point lights: no shadows by default (avoid cubemap cost/complexity).
- Default settings:
  - CSM: 3 cascades, shadow distance ~60-100m, split 0.1/0.3/1.0.
  - Map sizes: 2048 (near), 1024 (mid/far) or 2048 across if perf allows.
  - Spot: 1024 map, PCF 3x3 or 5x5.
  - Bias + normal-offset bias tuned once for stability.

## Phase 1: Forward+ correctness and robustness
- Sync camera near/far into Forward+ cluster math.
  - Pass camera `near`/`far` into `ForwardPlusManager.setViewProjection(...)` or a new API.
  - Use camera values in `computeClusterAABBs` and in `pushForwardPlusUniforms`.
- Fix zero-lights path so clusters are valid every frame.
  - CPU mode: clear grid + indices and upload.
  - GPU mode: dispatch compute with `point_light_count=0`/`spot_light_count=0`.
- Make compute dispatch match `ForwardPlusConfig`.
  - Compute `workgroups_x = ceil(cluster_count_x / 16)`, `workgroups_y = ceil(cluster_count_y / 9)`.
  - Keep shader local sizes (16x9) and update dispatch accordingly.
  - Ensure `MAX_LIGHTS_PER_CLUSTER` is consistent across CPU config and compute shaders.

## Phase 2: Forward+ becomes the only 3D pipeline
Status: complete.
- Remove legacy + PBR pipeline selection from the render system.
  - Always bind Forward+ pipeline.
  - For meshes without a material, use a default `Material` and map `renderer.getTexture()` to base color.
- Split PBR resource init from the PBR pipeline.
  - Keep default textures (normal/MR/AO/emissive) for Forward+.
  - Stop loading `pbr.frag`/`pbr.metal` once Forward+ is active.
- Remove `forward_plus_enabled` toggles and PBR-only fields in `RenderManager` and `Engine`.

## Phase 3: Code + shader cleanup
Status: legacy/PBR shader removal complete.
- Remove legacy shader files:
  - `assets/shaders/shaders.metal`
  - `assets/shaders/vertex.vert`
  - `assets/shaders/fragment.frag`
- Remove PBR-only shaders:
  - `assets/shaders/pbr.frag`
  - `assets/shaders/pbr.metal`
- Remove raymarch example + shaders:
  - `examples/raymarch_pbr/main.zig`
  - `assets/shaders/raymarch_pbr.vert`
  - `assets/shaders/raymarch_pbr.frag`
  - `assets/shaders/raymarch_pbr.metal`
- Keep Forward+ shaders and light cull shaders:
  - `assets/shaders/pbr_forward_plus.frag`
  - `assets/shaders/pbr_forward_plus.metal`
  - `assets/shaders/light_cull.comp`
  - `assets/shaders/light_cull.metal`
- Keep skinned shader assets for future animation use:
  - `assets/shaders/skinned_vertex.vert`
  - `assets/shaders/skinned_shaders.metal`
- Remove unused shader systems if they stay unused after refactor:
  - `src/render/shader_library.zig`
  - `src/render/pipeline_cache.zig`

## Phase 4: Engine defaults, examples, and docs
- Initialize Forward+ in `Engine.init` by default.
  - Prefer GPU compute culling; fall back to CPU if unavailable.
  - Provide an Engine config option for CPU vs GPU culling if needed.
- Update examples to use Forward+ materials or remove them.
  - Convert `examples/cube3d/main.zig` to use `Material.init()` (or remove if redundant).
  - Remove raymarch demo entirely.
- Update `examples/README.md` and `build.zig` to reflect the new example set.

## Phase 5: Validation and performance pass
- Verify on macOS and Vulkan targets:
  - Forward+ runs with GPU compute culling.
  - CPU fallback works if compute shaders are unsupported.
- Smoke-test examples with many lights (Forward+ demo).
- Validate shadows/fog/bloom correctness and performance targets.
- Confirm no shader assets are referenced after removal.
