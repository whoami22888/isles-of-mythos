# Isles of Mythos — Premium Graphics Quality Standard

Mandatory acceptance criteria for Godot 4.7.2 Android ARM64 graphics production. The intended aesthetic is premium stylized-realistic fantasy pirate survival, grounded in the owner's three island/ship reference images and the mandatory pinned 2026-10-17 cinematic reference video. Reviewers must see those actual references; this text does not substitute for them.

## Owner-mandated cinematic video quality floor (2026-10-17)

**BINDING RULE — NOTHING LOWER QUALITY THAN THE MASTER REFERENCE:** Before any premium graphics, environmental, ship, ocean, cannon/destruction or cinematic acceptance, inspect the owner's exact uploaded 10-second video and enforce [the pinned cinematic quality floor](graphics/CINEMATIC_QUALITY_FLOOR.md), including its measured SHA-256, frame-level targets and mandatory category-by-category side-by-side comparisons. The reference and its contact sheet are archived in ChatGPT Library under `/isles-of-mythos/graphics-references/`; verify the *video itself*, not just its descriptions. No basic procedural/low-poly/palette-only scene or offline concept animation qualifies as a finished in-game render. When the master is inaccessible, the Godot view does not attain its observable visual quality, or real Godot footage is absent, mark the visual gate **NOT VERIFIED or FAIL**, do not promote the milestone as premium or merge a premium graphics feature, and continue building. Fix the master video's duplicated “OF” title defect: the title in-game must read **ISLES OF MYTHOS**. This rule does not assert that the generated reference is actual Godot/Android footage; original exact-SHA CI, licensing, security, Android and performance requirements remain mandatory.

## Art direction and hybrid production
- Rich tropical terrain, coherent beaches, rocks, cliffs, ruins, dense foliage and convincing water.
- Detailed pirate ships with believable hulls, sails, fittings, wood and rigging.
- Proportionate, detailed characters, creatures, buildings, equipment and polished animation.
- Cohesive PBR roughness, normal maps, lighting, shadows, atmospheric depth, reflection and grading.
- Low-poly/basic primitive meshes are *temporary scaffolding only*, never final production art.
- Retain the existing Godot client, Android build workflow, gameplay and server-authoritative networking. Use appropriately licensed high-quality third-party art alongside original custom production, not a duplicate project.

## Asset admission — mandatory pass/fail gates
For every candidate, document geometry/fidelity, PBR maps and texture quality, pirate fantasy style fit, rigging and animation where relevant, license and commercial redistribution rights, source and author provenance, dependencies and content SHA-256, Godot 4.7.2 import compatibility, Android rendering/memory/performance, and scene scale/lighting/material compatibility.
Use the external asset manifest and provenance validation. No unverified license, unknown redistribution grant, missing dependency or unverified hash may pass. Reject unsuitable candidates in `docs/GRAPHICS_ASSET_DECISIONS.md` with concrete reasons, rather than retrying inferior packs.

## Proposed visual-quality scoring rubric (NOT measured results)
- Art direction and visual fidelity: **35%**
- Materials, textures and lighting: **25%**
- Environmental cohesion: **20%**
- Animation and detail: **10%**
- Mobile visual stability: **10%**

Score each criterion 0–10 against real in-engine captures, apply weighted total out of 10, and attach the individual marks, reviewer, image evidence and reasons. This is a proposed review weighting, **not a verified or previously measured score**. A numeric score never overrides a mandatory licensing, import, security, performance or AI-review pass/fail gate; final artistic acceptance still requires Graphics Director and AI visual QA assessment. Do not invent a pass threshold; record the agreed threshold before using scoring as an automated acceptance gate.

## Mobile optimisation without visual downgrade
Target Samsung Galaxy S23 Ultra before lower-end presets. Use asset-specific mesh LOD, texture compression/mipmaps, instancing, culling, material reuse, controlled draw calls, distance-based shadow/effect changes and scalable graphics settings. Preserve high-fidelity near-field characters, ships and scenery. Measure FPS, frame-time distribution, memory and thermal behaviour on the physical device before claiming device-level acceptance. Desktop or CI results are not substitutes.

## Evidence required for each graphics PR
- **Actual Godot-rendered screenshots** of relevant island, water, vegetation, terrain, ship or creature views (not promotional pictures or AI concept artwork).
- Fixed camera angle and lighting for comparisons; evidence for material import, texture mapping and scale.
- Verified exact SHA of headless import, scene-load/smoke tests, Android build, relevant gameplay and security tests.
- Available rendering/performance measurements with environment and device stated. Physical-device measurements mandatory for device claims.
- AI visual review and asset-license/provenance review, including records of rejection and remediation.

Do **not** approve or merge when visual quality is below standard; provenance/licensing is unresolved; Godot import, rendering or gameplay tests fail; required real performance metrics or exact-SHA CI/AI review are absent. Continue independent safe work when premium assets cannot be sourced; never quietly replace them with poorer art.

## Build agent ownership and order
- **Graphics Director:** owns visual criteria and asset rejection.
- **Harvest Agent:** searches reputable creator distribution and verifies licensing, dependencies and hashes.
- **Godot Integration Agent:** imports and adjusts approved art in existing scenes.
- **Performance Agent:** optimises with measured near-field fidelity preserved.
- **Visual QA Agent:** independently inspects real Godot output.
- **Build Controller:** assigns one owner per write surface, coordinates exact-SHA tests, reviews, commits and PRs.

Next task: admit verified premium **terrain, vegetation, rocks, coast and water**; subsequently ships, buildings, creatures and characters. Use smallest meaningful test cycles and fix root causes without repeating previously verified work.

## Mandatory actual still-image / MP4 deliverable (owner instruction 2026-10-18)

Do not call any graphics, asset admission, rigged character/creature, ship, environment, water, lighting, animation, battle or cinematic milestone visually **implemented**, ready or accepted based on code, raw 3D source files, preview thumbnails, checklists, CI or test counts. **Produce a real Godot 4.7.2 image (PNG) or MP4 sourced from actual sequential engine-rendered frames**, available for direct inspection. If the feature moves, changes expression/pose, emits particles, sails, collides, fights or changes camera, it requires moving footage or a verified engine-frame sequence; one still cannot establish animation.

Every image/video must identify actual PR HEAD SHA, scene, engine/renderer, original asset hashes, export settings, capture hash and downloadable artifact. Compare decoded frames with the owner's exact reference video (`713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05`) and the existing three owner island/ship images. **Lower-quality, flat, untextured, visibly unfinished or substantially inferior work must not be surfaced as a new visual deliverable**, including labels such as WIP or concept, unless the owner explicitly requests failed evidence for debugging. Missing artifact or parity evidence = FAIL or NOT VERIFIED, and premium visual acceptance/merge is blocked. Technical scaffolding may progress in an isolated branch with explicit infrastructure-only status and no premium completion claim. Do not weaken licensing, security, server or Android performance rules.
