# Isles of Mythos: Sunken Tides
## Master AI Software, Gameplay, Graphics and Engineering Specification

**Project:** Isles of Mythos: Sunken Tides  
**Repository:** <https://github.com/whoami22888/isles-of-mythos>  
**Software type:** Mobile-first persistent 3D strategy MMORPG  
**Game engine:** Godot 4.7.2 Mobile Renderer  
**Primary platform:** Android ARM64  
**Development model:** Server-authoritative multiplayer game with AI-assisted engineering

> **Scope and authority.** This document describes the intended product and mandatory engineering outcomes. It does not assert that every feature is implemented, measured or accepted. The live source, applicable AGENTS.md instructions, frozen gate decisions, exact-head verification and referenced project standards remain authoritative for implementation details. This specification is additive, never permission to weaken an existing gate.

---

## 1. Project identity

Isles of Mythos: Sunken Tides is a commercially oriented, persistent, open-world fantasy strategy MMORPG.

The world consists of tropical islands, oceans, kingdoms, settlements, ruins, creatures, resources, armies, ships and competing factions.

Players develop settlements, expand territory, collect and train creatures, build military forces, manage resources and economies, join guilds, participate in large-scale warfare, and explore a persistent world.

**The primary genre is strategy MMORPG, not pirate simulation.** Piracy, ships, naval exploration and sea battles are important gameplay components but are not the entire game.

Core characteristics:

- Persistent online multiplayer world.
- Server-versus-server and guild-versus-guild warfare as long-term gameplay goals.
- Strategic territory capture and defence.
- Player settlements and expandable bases.
- Armies, troops, formations and military upgrades.
- Resources, harvesting, manufacturing, crafting and trading.
- Creatures, monsters, dragons and flying mounts.
- Creature capture, training, breeding and evolution.
- Technology, research and progression unlocks.
- Ships, shipbuilding, maritime exploration and naval combat.
- Social systems, alliances, guilds, trading and cooperative activities.
- Daily challenges, world events, bosses and seasonal warfare.
- Progression systems supporting sustained long-term play.

Every subsystem must integrate into the larger persistent strategy game.

## 2. Approved software stack

### Client

- Godot Engine 4.7.2.
- GDScript for client gameplay presentation and engine integration.
- Godot 3D scene system and Mobile Renderer.
- Godot shaders and shader materials.
- Android ARM64 builds.
- Touch-first interface with responsive UI scaling.
- Real-time interpolation and presentation of authoritative server state.

The client is responsible for display, animations, sound, camera, touch input, visual effects and user interface. The client does not independently determine persistent gameplay results.

### Server

- Node.js runtime.
- TypeScript for the active backend implementation.
- Fastify HTTP framework.
- Authenticated WebSocket transport.
- PostgreSQL for durable persistent data.
- Redis for appropriate ephemeral state, caching and coordination.
- JWT-based authentication and permission enforcement.
- Existing server-owned combat, economy, inventory and gameplay systems.

Preserve established API contracts and transport behaviour. ENet/UDP may be evaluated only within an authorized, compatible workstream. Do not presume it is already deployed or replace the existing WebSocket contract without testing.

### Development software

- Blender for authored 3D models, skeletal rigging, animation and asset preparation.
- glTF 2.0 / GLB for interoperable 3D assets.
- Git and GitHub for source control.
- GitHub Actions for automated builds and verification.
- Docker for supported backend environments.
- Vitest, TypeScript checking, linting and the project's existing engine-specific tests.

Legacy Phaser and TypeScript client files may remain for compatibility or historical work. They do not define the approved production 3D rendering engine.

**Do not replace Godot with Unity, Unreal, Phaser or a custom engine.**

## 3. Engineering architecture

Use a server-authoritative client/server model.

Client → authenticated network connection → Fastify server → authoritative game systems → PostgreSQL/Redis → validated state updates → client rendering.

The server owns:

- Player accounts and permissions.
- Character data and progression.
- Resources, harvesting and inventory.
- Crafting and production results.
- Building upgrades and settlement state.
- Currency and economic transactions.
- Combat, health, damage and status effects.
- Creature ownership, capture and evolution.
- Troops, guilds, alliances and territory.
- Ships, naval combat and persistent progression.
- Rewards, quests, events and rankings.

Every important mutation must be validated, authorized, replay-protected where applicable, and persisted transactionally. Use idempotency keys, concurrency controls and appropriate transaction isolation to prevent duplication, inconsistent balances or lost progression.

**The client sends player intent. It displays authoritative results.**

### Multiplayer simulation

Preserve the approved **20 Hz authoritative simulation target** and existing timing contracts.

Retain established performance acceptance criteria, including:

- Gameplay mutation p95 latency no greater than 150 ms.
- Gameplay mutation p99 latency no greater than 300 ms.
- Existing tick-latency and load-testing gates.
- Deterministic or reproducible simulation behaviour where specified.

Do not treat these targets as measured success unless supported by actual evidence.

The current effectively single-region architecture must not be misrepresented as an operational global MMO fleet. Multi-region coordination, regional transfers and server-versus-server topology require separate implementation and verification.

## 4. Gameplay design

### World and exploration

Build an interconnected fantasy world containing tropical archipelagos, forests, cliffs, beaches, reefs, underwater areas, ruins, settlements and contested regions.

Support world streaming, exploration, resource discovery and changing territorial ownership.

### Settlement development

Players can construct and upgrade town halls, barracks, resource buildings, research facilities, walls, ports, shipyards and defensive structures.

Building levels affect production, storage, defences, troop capacity and available strategic options.

### Resources and economy

Include appropriate resources such as timber, stone, ore, metals, food, rare materials and mythical resources.

Gathering, transport, consumption and production form an interconnected strategic economy. Maintain persistent inventories, transaction histories and server-authoritative balances.

### Armies and warfare

Support military recruitment, upgrading, troop specialties, army compositions, movement, attacks, defences, sieges and coordinated guild warfare.

Battle outcomes must remain server-authoritative.

### Creatures and mythical progression

Support discovering, capturing, taming, training and upgrading animals and mythical creatures.

Include dragons, flying creatures, land creatures and specialized support creatures. Research can unlock higher-level capture, breeding, evolution and combat abilities.

### Ships and naval gameplay

Support multiple ship classes, upgrades, sailing, maritime transport, naval warfare, raids and piracy.

Ships must have believable movement and clearly represented gameplay capabilities.

### Social and persistent endgame

Support guild management, alliances, territory seasons, world bosses, trading, realm warfare, rankings and competitive cooperation.

Ensure progression remains meaningful for both active and casual players.

New systems must integrate with existing persistent game state rather than creating isolated demonstrations.

## 5. Graphics style and art direction

**Visual classification:** Premium stylized-realistic 3D tropical fantasy MMORPG.

The visual style combines high-fidelity fantasy art direction with believable materials, terrain, lighting, atmospheric depth and animations. The quality target is a cohesive, richly detailed world rather than basic low-poly mobile artwork.

### Terrain

Use actual three-dimensional terrain geometry, including:

- Natural irregular coastlines and island silhouettes.
- Sculpted cliffs, rocky formations and eroded shorelines.
- Layered terrain elevations.
- Sand, soil, grass, rock and vegetation materials.
- Smooth biome and terrain transitions.
- Realistic proportions and environmental composition.
- Terrain appropriate for both cinematic and gameplay cameras.

Flat circular islands, block terrain and primitive placeholders are not acceptable final artwork.

### Ocean rendering

The ocean is a major visual priority. Implement convincing real-time water with:

- Animated wave movement.
- Visually meaningful shallow-to-deep water transitions.
- Turquoise coastal water and deeper offshore colouring.
- Surface normal detail and changing reflections.
- Shoreline foam that follows the actual coastline.
- Wave interaction with rocks and beaches.
- Foam, wakes, bow spray and ship-water contact effects.
- Depth-aware colour and transparency behaviour.
- Continuous motion without obvious looping, freezing or flicker.

Select mobile-compatible techniques that preserve the approved look. Avoid simplistic flat blue surfaces and static foam rings.

### Vegetation

Create visually rich tropical ecosystems with palm trees, shrubs, grasses, bushes and biome-specific foliage.

Use believable models, proper normals, appropriate roughness and consistent lighting. Optimize vegetation through instancing, spatial culling and level-of-detail selection without destroying near-field quality.

### Ships

Ships require convincing high-detail geometry and materials:

- Hull geometry, planking and timbers.
- Masts, sails, ropes and rigging.
- Railings, deck fittings and cannons.
- Metal fittings and decorative details.
- Animated sails, flags and steering elements.
- Movement, wake and water contact.
- Readable silhouettes at different gameplay camera distances.

Do not accept a simplified geometric boat as the final premium ship asset.

### Buildings and settlements

Build detailed, coherent architectural sets appropriate to tropical fantasy settlements. Buildings must communicate purpose and upgrade level through visible geometry and materials.

### Creatures and characters

Use appropriate authored meshes, skeletons, rigs and animation systems.

Animations must support relevant states such as idle, locomotion, combat, interaction, flight, attack, damage and death. Characters and creatures must look consistent with the surrounding world.

### Lighting and atmosphere

Use coherent cinematic lighting and believable light response. Include physically appropriate PBR interactions, directional sunlight, shadows, atmospheric haze, distance falloff and consistent colour grading.

Avoid flat lighting, harsh material inconsistencies, excessive bloom or unrealistic colour palettes.

## 6. 3D asset and material pipeline

Use Blender and the existing Godot import pipeline. Preferred transferable assets are GLB/glTF files with correct units, transforms, mesh structure, UV coordinates and materials.

PBR materials should include, where appropriate:

- Base colour/albedo.
- Normal maps.
- Roughness.
- Metallic parameters.
- Ambient occlusion.
- Emission and opacity where required.

Assets must have adequate geometric detail for their intended on-screen scale. Create multiple LOD levels where useful, with detail concentrated in the visible near field.

### Asset quality rules

Before admitting an asset to the game:

1. Confirm its specific gameplay or scene purpose.
2. Check author, original source and commercial redistribution rights.
3. Record exact source hashes and dependencies.
4. Inspect geometry, UVs, material maps and animation.
5. Verify Godot 4.7.2 import.
6. Test correct scale, orientation and lighting in the real scene.
7. Measure relevant rendering costs.
8. Compare rendered results against approved reference footage.

Reuse already approved assets rather than regenerating equivalent content.

AI-created concept images are not substitutes for actual engine-ready 3D assets or rendered gameplay evidence.

## 7. Camera and visual presentation

Use appropriate cameras for strategic and immersive gameplay. Target a continuous transition between closer 3D world interaction and elevated strategic viewing.

Camera design should support:

- Detailed close-up views of characters, ships and settlements.
- Elevated strategic control and map awareness.
- Smooth zoom and camera movement.
- Cinematic tracking shots.
- Reliable touch controls.
- Proper geometry visibility without camera clipping.
- Smooth LOD transitions and stable lighting.

The game must retain attractive graphics through the normal player-facing gameplay camera, not only during cinematics.

## 8. Mobile rendering and optimization

The primary performance reference device is the **Samsung Galaxy S23 Ultra**.

Target responsive **60 FPS** gameplay where supported, corresponding to approximately **16.67 ms per displayed frame**. This is an engineering objective, not an already verified result.

Optimization techniques may include:

- Frustum and visibility culling.
- Mesh LOD and impostors.
- MultiMesh instancing.
- Texture compression, mipmaps and streaming.
- Material and shader reuse.
- Geometry batching where supported.
- Particle and VFX pooling.
- Controlled lighting and shadow complexity.
- Bounded draw calls and triangle counts.
- Background loading and prewarming of reusable resources.
- Strategic reduction of unnecessary overdraw.
- Bounded cache sizes and memory allocation.
- Device-appropriate adaptive quality settings.

Avoid repeatedly generating or loading identical assets.

Reduce initial startup cost through measured caching, staged loading and reusable validated resource bundles.

Do not solve performance problems by knowingly downgrading foreground graphics below the approved reference standard.

Profile actual bottlenecks before optimization. Record FPS distributions, frame-time p95/p99, GPU/CPU workload, draw calls, triangle counts, RAM consumption, asset loading delays and thermal behaviour.

Physical Android measurements are required before claiming successful hardware acceptance.

## 9. Graphics reference requirement

The mandatory quality reference is defined in:

- [Art Direction Standard](ART_DIRECTION_STANDARD.md)
- [Cinematic Quality Floor](graphics/CINEMATIC_QUALITY_FLOOR.md)
- [Real Render Deliverable Gate](graphics/REAL_RENDER_DELIVERABLE_GATE.md)

**Approved cinematic master SHA-256:**

713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05

**Catalogued master:**

/isles-of-mythos/graphics-references/cinematic-quality-floor-2026-10-17.mp4

This is a ChatGPT Library location, not a guaranteed local filesystem path for every AI environment.

Obtain the real master video, verify its hash and inspect its actual moving frames before judging visual parity.

### Reference comparison categories

- Tropical island terrain and settlements.
- Ship hulls, sails and rigging.
- Realistic materials, textures and reflections.
- Animated ocean, coastline and wakes.
- Camera movement, framing and depth.
- Lighting, atmosphere and colour coherence.
- Cannon firing, smoke, destruction and debris.
- Consistent temporal motion.
- Normal player-facing gameplay visuals.

Every applicable category must achieve at least the quality of the approved master.

Do not claim parity if the reference or engine-rendered comparison is unavailable.

## 10. Real Godot render acceptance

All accepted game visuals require genuine **Godot 4.7.2** rendering evidence.

For static scenes, materials and objects, provide actual engine-rendered PNG evidence.

For animated water, ships, creatures, cameras, combat or effects, provide a real MP4 encoded from sequential Godot-rendered frames.

An animation must show independently verifiable motion.

Every rendering receipt must record:

- Exact Git commit SHA.
- Source asset hashes and licences.
- Godot version and renderer.
- Source scene and camera.
- Capture command and settings.
- Resolution and frame rate.
- Rendered artifact checksum.
- Visual reference comparison.
- Technical and visual review outcomes.

Offline Blender previews, concept images, synthetic footage, static frames converted into a moving slideshow and fabricated screenshots do not prove Godot implementation.

Quality verdicts:

- **PASS:** Required real evidence proves applicable technical and visual acceptance.
- **FAIL:** Confirmed quality or technical failure.
- **NOT VERIFIED:** Required evidence is missing or inconclusive.
- **NOT IN SCOPE:** Legitimately unrelated future functionality.

Do not merge inferior premium graphics or represent unverifiable graphics as completed production work.

## 11. Mobile user interface

Build a mobile-first interface with readable typography, scalable panels and appropriately sized touch targets.

Required interfaces include:

- Initial loading and server connection.
- New player registration.
- Username/password authentication.
- Player account and character selection.
- Role-protected administration.
- World and strategic map.
- Inventory and resources.
- Settlement construction and upgrades.
- Research and technology progression.
- Army and troop management.
- Creature and ship management.
- Guilds, alliances and warfare.
- Trading, rewards, quests and daily activities.
- Graphics, audio and accessibility settings.

Players should not be required to manually paste backend JWTs or temporary authentication tokens.

Deployable client configurations must use appropriate HTTPS/WSS backend endpoints.

Credentials and administrative secrets must never be embedded in APK resources.

## 12. Software quality and security

Maintain a secure, testable and modular codebase.

Requirements:

- Clear subsystem boundaries.
- Type-safe backend interfaces.
- Validated client/server messages.
- Proper errors and structured diagnostics.
- Appropriate retry and reconnect behaviour.
- Strict authorization and role checks.
- Transactionally safe persistence.
- Replay and duplication protection.
- Safe database migrations.
- Regression tests for every confirmed defect.
- No credentials or personal identifiers in diagnostic output.

Do not silently change approved architecture, engine versions, database schemas or network contracts.

Read repository-specific instructions before editing code.

## 13. AI development workflow

At the start of a task:

1. Read applicable AGENTS.md instructions and relevant documentation.
2. Verify current main, PR heads, exact SHAs and existing work ownership.
3. Read only the source, tests, assets and documentation needed for the task.
4. Identify the intended gameplay or technical outcome.
5. Check existing implementations and avoid duplicate work.
6. Assign a single implementation owner to each writable scope.
7. Implement the smallest complete root-cause correction or bounded new feature.
8. Run relevant tests and inspect actual output.
9. Record remaining issues and regressions.
10. Verify all required exact-head checks before any authorized merge.

The project's legacy Gates 1–16 remain frozen. Protected gameplay, migration, deployment and release requirements remain subject to their own authority controls.

AI code review must be performed on the final exact PR SHA by a distinct reviewing agent.

Do not manufacture CI, performance, review, installation or rendering results.

### Verification categories

Maintain the existing three groups:

1. **Build & Integrity:** Compilation, imports, linting, typing, build provenance, artifact integrity and source validation.
2. **Functionality & Integration:** Gameplay, networking, rendering, UI, persistence interactions and end-to-end behaviour.
3. **Data & Transaction Safety:** Authorization, persistent state consistency, replay protection, economy correctness, migrations and concurrent mutation safety.

Additionally enforce all applicable security, performance, graphics, licensing, Android and final AI-review checks.

A missing, stale, skipped, cancelled or failed required check is not a pass.

## 14. Required AI deliverables

When completing a development task, provide:

- What was implemented or repaired.
- Exact files changed.
- Git branch and final commit SHA.
- Root cause of any repaired defect.
- Tests and verification actually performed.
- CI/security/performance outcomes tied to the exact SHA.
- Real rendered PNG/MP4 evidence for applicable graphics work.
- Device measurements where applicable.
- Remaining blockers and precise next action.

For game features, include evidence demonstrating that the feature is genuinely playable and integrated into the existing server-authoritative system.

For graphics changes, include both the imported source assets and actual rendering proof.

Do not report future features, prototypes or unsupported simulations as finished production capabilities.

## 15. Development priorities

Prioritize work according to dependencies and the current verified repository state.

**A. Working game foundation:** Reliable Android boot, backend connectivity, account registration/login, persistence, player controls and functional gameplay.

**B. Premium visible world:** Accepted tropical terrain, coastline, water, vegetation, lighting, ships and responsive camera presentation.

**C. Strategy gameplay integration:** Resources, settlements, crafting, armies, research, creatures, economy and ship systems connected to authoritative server state.

**D. Multiplayer and persistent warfare:** Guilds, territory, raids, naval battles, cooperative gameplay and larger-scale combat, with future regional features tracked separately.

**E. Performance and player experience:** Real Android profiling, quality-preserving optimization, responsive touch control, reconnect reliability and long-term progression.

**F. Production readiness:** Verified CI, security, performance, deployments, real-device testing, multiplayer load validation, monitoring and authorized release processes.

These are priority categories, not a claim that every prerequisite is unimplemented or a replacement for the repository's live task queue.

## 16. Final mission to the AI

Your responsibility is to develop Isles of Mythos: Sunken Tides into a cohesive, high-quality, mobile-first, persistent strategy MMORPG using its existing approved architecture.

Build usable integrated features—not disconnected demonstrations.

Preserve existing verified work.

Prioritize believable premium 3D graphics, meaningful strategy gameplay, secure server authority, persistent progression and high-performance Android execution.

Reuse approved assets, scenes, code and validation infrastructure. Fix root causes rather than hiding defects or weakening checks.

Require genuine Godot-rendered evidence for every applicable graphics milestone.

Never claim that a feature, APK, deployment, graphics benchmark or production release has passed without direct verification.

Continue authorized, dependency-ready development systematically, and report only demonstrable progress.

**The finished product must be a playable, visually convincing, commercially viable 3D strategy MMORPG—not merely a collection of successful CI workflows, concepts or isolated code features.**

---

**Recommended usage:** Give this specification to another AI as its project brief and instruct it to treat current repository instructions and verified source as authoritative for implementation details. This specification explains what the software is supposed to become; it does not assert that every described gameplay system or visual standard is already implemented and verified.
