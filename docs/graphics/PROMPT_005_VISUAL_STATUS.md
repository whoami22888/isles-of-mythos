# Prompt 005 visual status

The cel-stylized PBR shader (desktop `light()` path and mobile vertex-lighting path) is implemented and covered by the existing Vulkan Mobile compile/ramp regression.

A second capture, `cel_stylized_pbr_visual_preview.gd`, now loads the admitted Poly Haven coastal slice (`realistic_coastal_fx_slice.tscn`), applies the cel shader to opaque hull/rock/terrain-style materials only, and writes a real Godot PNG. Water, wake/bow FX, and alpha-tested sails/leaves are left on their existing materials.

**This is work-in-progress evidence, not premium visual admission.** The owner cinematic quality floor (`graphics-references/cinematic-quality-floor-2026-10-17.mp4`, SHA-256 `713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05`) has not been declared met. Galaxy S23 30fps+ remains **NOT VERIFIED** until a physical-device capture exists. CI Vulkan Mobile captures use lavapipe and must not be treated as device performance proof.
