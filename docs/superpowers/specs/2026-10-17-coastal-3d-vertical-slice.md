# Coastal 3D Vertical Slice

## Purpose

Create a deterministic, reviewable Godot Mobile-renderer scene that demonstrates
the intended premium nautical presentation using the existing sculpted island
terrain, shoreline water, atmosphere, and licensed pirate assets. The scene is
an integration slice for visual and performance evidence; it is not a gameplay
authority or a replacement for the server.

## Scope and ownership

- Add one dedicated coastal showcase scene and its integration script under
  `client-godot/scenes/` and `client-godot/scripts/`.
- Add focused scene smoke/capture assertions under `client-godot/tests/`.
- Keep admitted asset manifests, water shader implementation, lighting branch,
  LOD implementation, server code, and active performance work unchanged.
- Use only assets already present on the exact base SHA, with their existing
  provenance and import settings.

## Visual contract

The scene must contain real `Node3D` geometry for terrain, a visible shoreline
water surface with depth/foam cues, a ship or other admitted pirate asset,
physically based material assignments, directional lighting, and bounded
atmospheric depth. Camera position, seed, viewport, and renderer are fixed by
the capture harness. HUD text may remain 2D and must not be used as visual
evidence for the 3D scene.

## Runtime and performance contract

- Target Godot 4.7.2 Mobile renderer and Android ARM64 compatibility.
- Do not generate meshes, allocate large collections, or compile unbounded
  shader work in repeated frame paths.
- Preserve the 150 ms p95 world-chunk and existing 20 Hz/server acceptance
  budgets. This slice must not change server or economy behavior.
- Capture software/CI measurements separately from physical-device evidence.
  Report frame-time p50/p95/p99, draw calls, triangles, and memory only when
  the harness actually measures them.

## Verification

1. Headless scene import and resource-load smoke test.
2. Deterministic capture at the pinned camera, seed, and resolution.
3. Assertions for terrain, water, material, lighting, and admitted-asset
   attachment; fail if the capture is empty or the base scene is captured.
4. Raster/telemetry checks for visible shoreline/depth/foam signals where the
   existing capture tooling supports them.
5. Focused Godot tests, then the configured exact-SHA build, security,
   performance, and independent review checks.

The slice is complete only when the actual rendered artifact and its SHA256
manifest are present and reproducible. Reference JPGs or concept art cannot
substitute for a rendered capture.

## Out of scope

No production deployment, protected migration, new network transport, runtime
procedural world generation, unverified third-party asset download, or device
performance claim is part of this slice.
