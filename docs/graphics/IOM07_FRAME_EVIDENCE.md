# IOM-07 — Godot mobile optimization evidence sector

**Purpose:** Make graphics optimization evidence-based without reducing the owner's premium visual quality floor or changing any existing graphics PR author's surfaces.

## Implemented

- `client-godot/scripts/mobile_frame_metrics.gd` validates **received sample intervals** with deterministic nearest-rank p50/p95/p99, mean, min, max and sample count. Fails closed for empty, non-finite, negative or unreasonable sample sets.
- `client-godot/tests/mobile_frame_metrics_test.gd` exercises boundary percentiles, slow-frame tails and invalid input in the actual Godot GDScript runtime.
- `client-godot/tests/mobile_frame_capture.gd` opens an actual existing Godot 3D terrain scene, requires an active camera, discards warmup frames, measures **180 actual successive engine frame intervals**, process CPU timing and peak 3D draw calls, and writes immutable-context JSON.
- `.github/workflows/iom07-mobile-frame-evidence.yml` pins the repository's Godot 4.7.2 Linux release and SHA-256, runs the test and Xvfb engine capture, verifies the generated report's commit SHA and hard-coded non-Android verdict, writes SHA-256 provenance, then uploads an inspectable build artifact.

## Critical evidence boundaries

- The runner is **Linux Xvfb using OpenGL compatibility**. These observations are real Godot execution measurements but **NOT Mobile renderer FPS**, **NOT Samsung Galaxy S23 Ultra / Android thermals**, **NOT a GPU timing profile**, and **NOT gameplay-frame responsiveness on a device**. The report permanently says `physical_android_measurement: false`.
- The captured existing sculpted island is an original prototype fixture. It is **not premium visual art**, not proof of ocean, ship, island foliage or lighting acceptance and is never shown to the owner as an approved rendering. The JSON must say `graphics_quality_verdict: NOT_VERIFIED` and `mobile_acceptance_verdict: NOT_VERIFIED`.
- **No existing visual art, shaders, ships, scene layouts, asset-import surfaces or server-tick code were changed.** Separate graphics PRs #181–#184 and performance PR #179 retain exclusive ownership. These metrics are intended to help subsequent precise measured optimizations, not to grant automatic quality acceptance.
- Godot tests/CI are necessary but not sufficient. Full exact-head CI/security/Performance Acceptance and AI review remain required. Device optimization requires a real S23 Ultra build, 30/60 FPS target tracking, frame p95/p99, thermal/memory evidence, responsiveness and a comparison with the hash-verified owner master reference; 20 Hz server cadence and 150ms p95/300ms p99 must remain unchanged.

## Follow-on optimization workflow (only after evidence)

1. Capture the updated coastal ship/water/terrain scene in actual Godot 4.7.2 with fixed camera and licensed PBR assets, record source SHA, renderer and frame-time profile; compare engine frames to owner movie SHA-256 `713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05`.
2. On actual Galaxy S23 Ultra, collect frame intervals, draw calls, GPU/CPU timings where supported, texture/mesh residency, memory, thermals, input latency, network reconnect and first-play session traces.
3. Identify the largest *measured* bottleneck and apply scene-appropriate instancing, licensed texture compression, mesh LOD for **distant** objects, occlusion/culling and bounded water shaders **without lowering foreground fidelity or reducing required scene realism**.
4. Compare before and after on the **same camera and phone**. Reject optimizations that reduce target-quality visual categories even if benchmark improves. Record player trial feedback and accessibility, not invented retention.

No mobile/server/gameplay performance pass or player-satisfaction outcome is claimed by this foundational slice.

## Observed clock divergence and evidence interpretation

At commit `7cf4ec3d4333753ad9516dd034751e81e8b4380f`, real Linux Xvfb frame intervals had p95 14.859 ms and p99 16.304 ms, while Godot `Performance.TIME_PROCESS` p95 read 674.273 ms. Since these clocks disagree substantially, **the CPU process monitor is not a reliable same-frame bottleneck measurement in this environment**. The evidence now includes a `engine_process_clock_check` with `comparable=false` and the explicit `PROCESS_MONITOR_CLOCK_DIVERGENCE` reason where applicable; raw monitor values remain visible rather than being changed, hidden, or represented as real Android CPU stalls. A prototype with peak two draw calls does not represent approved premium ship, ocean, foliage or client gameplay performance. Investigate valid frame/GPU metrics on the actual Android device and moving coastal scene before optimising.
