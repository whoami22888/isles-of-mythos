# Mobile Graphics and Performance Architecture

## Production client decision

The approved production client is **Godot 4.7.2 with its Mobile renderer**, targeting Android ARM64; the Samsung Galaxy S23 Ultra is the primary physical acceptance device. The existing Phaser client is historical prototype code and not the production renderer. Do not introduce a Unity/URP migration, change the pinned engine, or treat a desktop render as Android performance evidence.

Use the current authoritative architecture and acceptance controls in `AGENTS.md`, `.project/VERIFICATION-STANDARD.md`, `docs/PLAYER_EXPERIENCE_QUALITY_STANDARD.md`, `docs/ART_DIRECTION_STANDARD.md`, `docs/graphics/CINEMATIC_QUALITY_FLOOR.md`, and `docs/graphics/REAL_RENDER_DELIVERABLE_GATE.md`. The owner reference video and real Godot capture requirements apply independently of technical test results.

## Baseline devices

The performance floor remains representative mid-range mobile hardware approximately 3–4 years old, with Android ARM64 as the approved shipping target and Galaxy S23 Ultra as the primary measured acceptance device. An iOS port needs a separately verified target and export pipeline. Quality profiles may vary visual detail; they must not change authoritative simulation or gameplay results.

## Rendering requirements

- Pin Godot 4.7.2 **Mobile renderer** and Android ARM64 exports; reject renderer fallbacks in visual evidence.
- Offer measured 30 FPS battery/thermal and 60 FPS performance caps; do not ship an uncapped mobile frame rate.
- Support Battery Saver, Low, Medium, High and Ultra quality profiles without reducing server-authoritative gameplay fidelity.
- Adapt visual workload based on measured frame time and thermals; keep simulation and network validation independent.
- Evaluate texture atlases for buildings, ships, resources, environments and units without breaking authored PBR detail.
- Use ASTC texture compression on supported Android targets with verified ETC2-compatible fallbacks where required.
- Reuse compatible Godot StandardMaterial3D/ShaderMaterial resources to reduce material switching where profiling justifies it.
- Use Godot MultiMeshInstance3D for repeated meshes where applicable and where measured to improve performance.
- Apply mesh LOD, distance-based visibility and suitable impostors for distant objects without degrading foreground visual acceptance.
- Stream chunks and assets within bounded memory budgets; use frustum, distance and supported occlusion culling where effective.
- Pool transient particles and effects where profiling demonstrates allocation or lifecycle pressure.
- Use supported Godot render scaling or other measured resolution controls as a quality fallback.
- Build responsive Godot Control/CanvasLayer interfaces with safe-area handling and carefully bounded layout updates.
- Set non-interactive Control mouse_filter appropriately so decorative HUD elements do not intercept touch input.
- Avoid unnecessary per-frame allocations and UI relayouts; verify changes through Godot and Android instrumentation.

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

The existing supported gameplay path uses **authenticated WebSockets** and the already implemented server-authoritative action transport. Preserve the actual wire contract, replay/idempotency checks, validation and reconnect semantics. A UDP/ENet/QUIC replacement must be demonstrated compatible and approved as a separately verified architectural change; it is not implied by this rendering document. Preserve the authoritative **20 Hz** simulation and its protected mutation latency gates.

Replication is interest-managed. The following are architectural targets, **not measured or accepted transport rates**:

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

Prefer free/open-source Godot, Blender, server, CI, content-pipeline and development tooling. Paid cloud infrastructure or proprietary engine licensing is not a prerequisite for local development.

The authoritative server must continue to build and run locally with PostgreSQL and Redis through Docker.

## Validation gates

A mobile optimisation is not accepted solely because code or a synthetic benchmark exists. Measure actual Godot 4.7.2 Mobile behavior on representative Android devices, including the Galaxy S23 Ultra, and preserve the existing exact-SHA build, security, performance, transaction, gameplay and AI-review gates. Emulated or desktop results may diagnose defects but cannot substitute for required physical-device measurements. Premium visuals also require real hash-pinned Godot PNG/motion video and inspected parity with the owner master.

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
