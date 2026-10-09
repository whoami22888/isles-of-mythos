# Production Rendering and MMO Architecture

**Status:** Design proposal only. Not implemented or production-verified.  
**Design source:** Master Build Prompt/PDF §102, pages 117–118; PDF §103, pages 54–55.  
**Repository source baseline:** `main` at `d4de5d278369b5dc3d57aeee13c86bb4bec70c8e` on 2026-10-09. Post-merge verification for this baseline must be read from its exact-SHA workflow records; no result is inherited from a parent commit.

## 1. Current State and Boundaries

The repository currently contains a Phaser 4.2.1 + TypeScript/Vite prototype client, a Fastify backend, authenticated WebSocket gameplay transport, and PostgreSQL persistence. The deployment is effectively single-server/single-region.

The renderer batching change in PR #91 is a bounded prototype optimization: one terrain Graphics object and one entity-marker Graphics object per loaded chunk. It does not implement the production atlas/tilemap pipeline, LOD, asset streaming, cross-region services, or global-MMO deployment.

**Authority boundary:** the client handles input, presentation, interpolation and rendering. The server remains authoritative for movement, combat, inventory, currency, creature ownership, progression and persistent world state. Render objects are never the source of gameplay truth.

## 2. Rendering Architecture

Separate the client renderer into explicit layers:

1. **Static terrain:** deterministic world chunks rendered through atlas-backed tilemaps or chunk-batched static geometry. Avoid one primitive draw command per tile as the production default.
2. **Dynamic world entities:** atlas-backed sprites for creatures, resources, ships, bases and players, with shared materials/textures where possible.
3. **Priority entities:** local player, nearby players, combat targets and immediate gameplay threats receive the highest visual detail.
4. **Transient effects:** pooled projectiles, impacts and particles with strict lifetime and count budgets.
5. **Screen-space UI:** HUD, touch controls, menus, accessibility settings and debug overlays remain separate from world-space transforms.

Keep a renderer adapter boundary around Phaser-specific creation/destruction and keep world-state indexing independent of display objects. The current Graphics batching is an incremental transition step. Evaluate Phaser's WebGPU-capable path and WebGL fallback against actual Android/iOS devices before committing to a renderer migration. Do not migrate engines without measured evidence that the existing stack cannot meet the target.

## 3. Network Architecture

- Keep authenticated WebSocket as the current transport.
- Keep server-authoritative validation, sequence numbers, bounded payloads/rates, reconnect and resynchronization.
- Introduce a transport interface only when it can be tested without changing gameplay semantics.
- Benchmark WebSocket against an appropriate QUIC/UDP-oriented transport for real-time movement/combat. Keep economy, inventory, purchases and other durable mutations on reliable transactional transport.
- Measure RTT, jitter, packet loss, bandwidth, battery impact and large-battle behavior. No transport change is accepted on theoretical performance claims alone.

## 4. Server Topology

**Current:** single-server/single-region.

**Target:** a global control plane with regional gateways and game servers. Global services own accounts, characters, guild identity, economy/marketplace and other globally consistent records. Regional services own local movement, AI, combat, world chunks and nearby-entity simulation. Battle/session coordinators may allocate isolated battle servers where load warrants it.

Regional assignment must consider geography, measured latency, capacity, availability, active sessions and world ownership. Containers or a region identifier alone do not constitute a regional MMO implementation.

## 5. World Partitioning and Ownership

Preserve the existing deterministic 32×32 chunk contract unless a separately tested migration changes it. Define chunk-to-region ownership, authority epochs/leases, durable persistence boundaries, and explicit transfer protocols before distributing simulation.

Ownership transfer must fence the previous owner, be idempotent, and prove no duplication or state loss across retries and failures. Region transitions require session resynchronization and clear handling for entities, inventory, combat, and persistent mutations.

## 6. LOD, Culling and Interest Management

Choose detail from player/gameplay importance, distance, projected screen size, device capability, network conditions and server load. Use simplified sprites/animations and reduced effects for distant or non-interactive entities. Do not reduce the whole world to one low-quality setting.

Cull objects outside the camera frustum and remove non-relevant entities from the client update set. Separate rendering relevance from simulation authority: a culled entity can remain authoritative on the server.

Interest management should use chunks/regions and entity relevance to send only state that is visible, affects the player, is gameplay-relevant or can be afforded by the device. Bound subscriptions, update frequency, active simulation, payload sizes and outbound work. Support enter/leave-interest events and resynchronization after reconnect.

## 7. Asset Streaming and Memory

- Use versioned manifests, content hashes and atlas metadata.
- Preload only login, HUD, local-player and minimum gameplay assets.
- Stream biome, chunk, creature, ship and effect assets on demand.
- Track references and active use; cancel stale requests and evict least-recently-used unreferenced assets within a defined memory budget.
- Handle missing/corrupt assets and offline cache misses deterministically.
- Instrument memory usage and asset load/decode times. Never evict assets still referenced by visible or active entities.

## 8. Mobile Performance and Graphics Preferences

Target representative classes specified by PDF §94: low-end Android, mid-range Android, high-end Android, older iPhone/iPad, and modern iPhone/iPad.

Persist graphics preferences locally as required by PDF §95, including quality, resolution scale, shadows/effects, water, view distance and FPS cap. Include the audit-required UI scaling, high contrast, reduced effects, screen-shake, audio, touch scaling, Battery Saver and thermal adaptation.

On first launch, perform short hardware/quality detection, choose a starting profile and monitor real performance (PDF §96). Adapt only within defined safe bounds and avoid long startup benchmarks.

## 9. GPU and Render-Object Budgets

Priorities:
- atlas-backed sprites and tilemap/chunk batching;
- bounded transient-effect pools;
- distance/frustum culling and LOD;
- limited render-object counts per chunk and scene;
- minimal state/material changes where the renderer allows it;
- memory and fill-rate budgets appropriate to each device class.

A development overlay must report LOD level, draw calls, triangles, textures, visible/culled entities, particles, lights/shadow casters and GPU timing as required by PDF §98. Measure frame time, FPS, CPU/GPU, memory, battery and thermal behavior on physical devices before claiming an improvement.

## 10. Server Tick and Simulation

Use server-owned monotonic time and bounded authoritative simulation ticks. Client-provided delta time must not determine authoritative displacement. Bound per-tick work and instrument tick latency, entity counts and queue depth.

Separate critical authoritative transactions from noncritical ambient/visual simulation. Preserve deterministic command ordering, validation and replay/idempotency protections. Rendering frequency and client FPS must not control server simulation correctness.

## 11. Cross-Server Synchronization and Failover

**Classification: FUTURE GATE; not implemented.**

Before coding, specify single-writer authority, ordered durable events, idempotent event consumption, transfer fencing, consistency guarantees, duplicate prevention, regional failure recovery, observability and reconciliation procedures. Global services must not infer cross-region consistency merely from `region_id` fields or PostgreSQL persistence.

## 12. Load and Acceptance Testing

Use the PDF's workload scenarios: 50 players, 250 players, 1,000 players, large guild battle, large naval battle, world boss, and thousands of player bases.

Measure FPS/frame time, CPU/GPU, memory, bandwidth, server tick/tick latency, packet rate, entity count, battle instances, database/Redis latency, RTT/jitter/loss and mobile battery/thermal impact. Include network impairment and representative mobile device classes.

Set numerical acceptance thresholds before the production engine implementation. Report device, build, commit, scenario, measurement method and raw evidence. A green CI run alone does not establish production mobile or global-MMO readiness.

## 13. Implementation Sequence and Stop Gate

1. Complete exact-SHA verification of the current prototype batching change and verify its actual merge SHA.
2. Keep the current prototype operational while establishing renderer metrics and reproducible baseline scenarios.
3. Implement tilemap/atlas terrain migration behind focused regression tests and an explicit compatibility boundary.
4. Add entity pooling, LOD, culling and persistent graphics preferences in independently verifiable increments.
5. Run physical-device profiling and the mobile/load matrix before claiming production acceptance.
6. Design and implement distributed regional services only under an explicitly authorized future workstream.

The Master Build Prompt §102 requires all twelve architecture areas above to be produced before implementing the production graphical engine, then says to stop and wait for **`START STEP 1`**. This document is the design proposal; it does not authorize or claim completion of the production engine. After review and baseline verification, do not begin that engine implementation until the explicit start command is received.

## 14. Known Risks and Open Decisions

- WebGPU support/performance varies by browser and device; WebGL fallback must remain viable.
- Atlas/tilemap migration can change tile seams, coordinate handling, depth ordering and chunk unload behavior.
- LOD/culling must not hide combat-critical entities or alter authoritative gameplay.
- Streaming can cause memory spikes, visible pop-in or stale assets unless cancellation and ownership are correct.
- Regional ownership transfer and cross-server consistency require dedicated distributed failure testing.
- Numerical frame-time, memory, battery and network budgets must be set from measured supported-device baselines, not invented.
