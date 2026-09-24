# Mobile Graphics and Performance Architecture

## Production client decision

The production client is being designed around **Unity 6 + Universal Render Pipeline (URP)** for Android and iOS, with the existing Phaser client treated as the early network/gameplay prototype until the Unity migration boundary is reached.

The uploaded master development directive requires a high-fidelity client while keeping the game viable on Android/iOS and explicitly permits evaluating Unity when Phaser cannot meet the required fidelity or large-world performance. The agreed project direction is now Unity URP.

## Baseline devices

The performance floor is a mid-range Android/iPhone approximately 3–4 years old. Newer devices may unlock higher quality, but gameplay simulation must remain identical.

## Rendering requirements

- URP only for the production Unity client.
- 30 FPS battery/thermal cap and 60 FPS performance cap; never ship an uncapped mobile frame rate.
- Adaptive quality presets: Ultra, Very High, High, Medium, Low, Very Low and Battery Saver.
- Runtime performance director monitors frame time and reduces visual cost before reducing simulation quality.
- Texture atlases for buildings, ships, resource nodes, environment and unit families.
- ASTC texture compression for supported Android/iOS targets, with a compatibility fallback strategy where required.
- SRP Batcher for compatible materials/shaders.
- GPU instancing / GPU-driven rendering for repeated meshes where profiling proves it is beneficial.
- LOD groups and distance-based rendering.
- Billboard or simplified representations for distant/background units and gatherers.
- Chunk/sector streaming and frustum/distance culling.
- Pooled particles and pooled transient effects.
- Dynamic resolution as an adaptive fallback.
- Separate static and dynamic UI canvases.
- Disable UI raycast targets on non-interactive graphics.
- Avoid expensive per-frame allocations and layout rebuilds.

## Large battles

The renderer must be able to display large armies without treating every visible soldier as a full-detail character.

Near units can use full animation and effects. Mid-range units use reduced animation/detail. Far units use billboards, impostors or simplified meshes. Extremely distant entities are grouped or culled.

Visual LOD must never alter authoritative gameplay outcomes.

## Network/render separation

The renderer is not the simulation.

The server remains authoritative for:

- currency
- inventory
- combat
- player movement validation
- bases
- armies
- resource ownership
- purchases
- upgrades
- territory
- guild state

The client interpolates and predicts presentation only.

## Mobile network policy

Real-time movement/combat transport must use a UDP-oriented transport abstraction. QUIC or LiteNetLib may be selected after Android/iOS profiling and NAT/reliability testing.

Replication is interest-managed:

- active nearby combat: approximately 20–30 Hz where required
- nearby armies/NPCs: approximately 10–15 Hz
- distant movement: approximately 2–5 Hz
- static structures: event driven
- inventory, purchases and upgrades: event driven

Client interpolation hides the lower replication rate on 60 Hz/120 Hz displays.

## Thermal and battery policy

The client may reduce:

1. particles
2. shadow distance/resolution
3. water effects
4. vegetation density
5. far-object LOD
6. draw distance
7. resolution scale

before reducing gameplay simulation fidelity.

## Free/low-cost development policy

Prefer free/open-source tooling for server, CI, content pipelines and development utilities. Unity licensing/build services must remain within the project's available free tier where eligible; paid cloud infrastructure is not a prerequisite for local development.

The authoritative server must continue to build and run locally with PostgreSQL and Redis through Docker.

## Validation gates

A mobile optimisation is not considered complete because it exists in code. It must be profiled on representative Android/iOS hardware or equivalent GPU/CPU performance profiles.

Required measurements include:

- average FPS
- 1% low FPS
- frame-time variance
- CPU frame time
- GPU frame time
- draw calls
- batches
- visible entities
- texture memory
- total memory
- network RTT
- packet loss
- replication bandwidth
- thermal behaviour during sustained battles
