# PR 147 evidence repair checkpoint

- Date: 2026-10-17 Australia/Sydney.
- Implementation owner: Integration/Auto-Fix delegated coastal repair agent.
- Source HEAD: `a27792a16bfad305be110212a95ebf8df4506e9b` (historical inspected input, not final verification).
- Branch: `feature/iom-coastal-set-dressing-20261017`; workstream: coastal prototype evidence.
- Files: Godot visual-evidence/client workflows, render capture, coastal smoke test, this checkpoint.

## Root cause and correction

The visual workflow loaded only `island_preview.tscn`, so a successful image upload did not exercise the new `coastal_preview.tscn`. The capture script also assumed the camera was a direct child, whereas coastal composition nests it under `Island`.

Capture now selects an allowlisted scene, resolves the active viewport camera, waits for an actual rendered frame, verifies coastal props exist, and emits both baseline and coastal evidence through a matrix. Each artifact includes the tested head, run, scene, renderer, environment and image SHA-256. The new smoke test checks all six rocks, three palms, meshes, materials, finite transforms and the inherited player/camera; both workflows run it. This is compositional scaffolding evidence, never premium-art approval.

## Verification and blockers

Local source verification used official Godot 4.7.2, binary SHA-256 `cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`: headless import PASS; connection smoke PASS; island navigation smoke PASS; coastal composition smoke PASS. Workflow YAML/matrix and shell syntax checks PASS. These are source checks before commit; final exact-SHA CI, Android export, rendered evidence and distinct AI review remain required. Local Xvfb is unavailable, so local rendered capture is unverified.

Historical performance run `38913710659` failed because 1-player world-chunk HTTP p95 was 153.519 ms, exceeding the unchanged 150 ms limit; WebSocket gameplay p95 was 6.605 ms. Later HTTP p95 values were below 150 ms. A cold-path explanation is a hypothesis requiring a server investigation, not a confirmed root cause. PR base already contains main `43e61a8896213cda604c5568d06c51d41a8460ae`; baseline drift is ruled out. No performance thresholds, timeouts, workload or server code were changed here.

The performance log reports 30.058 Hz and source uses a 33 ms combat timer with an explicit 30–60 Hz combat-range comment, while the current production directive requires 20 Hz. Reconcile this requirement separately without speculative frozen-gameplay changes.

The primitive rocks/palms remain explicitly temporary and below the premium graphics standard. Premium assets, provenance, real Godot visual assessment and physical Android measurements remain required for artistic/device acceptance. No merge/production readiness is asserted. The controller must record final commit/run IDs and read back the Notion milestone; this repository checkpoint preserves the repair record meanwhile.
