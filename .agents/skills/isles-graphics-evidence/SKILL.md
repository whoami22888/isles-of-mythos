---
name: isles-graphics-evidence
description: Use when integrating or reviewing Isles of Mythos Godot scenes, graphics assets, capture code or visual-quality findings.
---

# Isles graphics evidence

Read live root/scoped AGENTS.md, docs/ART_DIRECTION_STANDARD.md, .project/VERIFICATION-STANDARD.md and current ownership before editing. Use the existing Godot 4.7.2 Mobile Android ARM64 client and authoritative backend; preserve all acceptance budgets and protected gates.

## Apply the structural gate

Run from the repository root:

```sh
python3 -m unittest discover -s scripts -p 'test_isles_graphics_gate.py' -v
python3 scripts/isles_graphics_gate.py --client client-godot
```

The gate is adapted from the owner-supplied isles_graphics_gate_source.txt. It performs source inspection, not engine execution. It fails on no candidate scenes, missing referenced GLTF/GLB models, unsafe inspected resource paths, malformed model JSON and missing attached scripts. GLB support inspects the bounded JSON chunk; it does not validate all binary buffers, images, dependency closure, geometry or Godot import.

Resource discovery follows quoted res:// text, not a full Godot parser: comments can cause false positives; dynamic and uid:// references are not covered. Prototype path checks are also heuristic. Confirm these findings against actual engine dependencies.

Treat prototype, flat-terrain/foam, UV-derived depth, static-ship/water, foliage-alpha and heavy-LOD findings as prompts for source/render diagnosis. These inherited regex/name heuristics can miss indirect code and can flag valid implementations. Reproduce and inspect each finding before altering production art or promoting this gate to mandatory CI. Replace inaccurate heuristics with meaningful regression evidence; do not weaken actual repository acceptance criteria. A zero exit status proves only that these limited checks found no issue.

## Use the evidence to repair the scene

1. Assign one owner to a narrow scene/material/capture seam; preserve active PR-owned paths.
2. Reproduce an observed defect with a regression, inspect actual resource bindings/UV/PBR data, then repair the root cause. Reject palette-only materials, including renamed or upscaled swatches; this script alone does not detect them.
3. Verify source licence, attribution, redistribution, pinned version, SHA-256 and dependency closure with the repository's external-art validator. Do not infer game-asset rights from a plugin licence.
4. Run affected Godot import/scene tests and Android export. Capture fixed seed/time/camera/resolution/renderer at the exact source SHA. Wait for renderer completion and check image content before inspecting actual gameplay and cinematic frames/motion against the supplied reference.
5. Measure scene costs in the stated environment; never infer physical S23 Ultra performance from CI/emulation/software Vulkan.
6. Require configured exact-final-SHA CI, security, performance and distinct review before merge; inspect resulting main. Record evidence under Build & Integrity; Functionality & Integration; Data & Transaction Safety.

Use Game Development Studio's corresponding production, vendoring, visual-debugging or performance workflow when its installed CLI is available. If unavailable, record that limitation and continue supported native Godot work; do not claim plugin receipts. Use Sites only for requested web surfaces and Opera only when connected. Skill selection does not request a new dashboard or release.

The uploaded agent-rules AGENTS.md/plugin.json describe another repository. Do not overwrite Isles instructions, change Renovate configuration, install dependencies or copy upstream plugin code solely because these files were supplied. Preserve MIT and CC-BY-SA conditions separately if actual upstream code/documentation is later vendored.
