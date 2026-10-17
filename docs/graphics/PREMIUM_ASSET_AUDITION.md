# Premium 3D vessel audition — NON-PRODUCTION

Owner baseline: `docs/graphics/CINEMATIC_QUALITY_FLOOR.md`, actual owner MP4 SHA-256 `713cd6e90c6f7d589a06eb3bd4b9b2d5ebeb9c0ff711b5de527a68460dfbcb05` (ChatGPT Library `/isles-of-mythos/graphics-references/cinematic-quality-floor-2026-10-17.mp4`).

This is an **actual engine-render evidence pipeline**, not accepted game art. Code, downloaded assets, textures and green CI are not visual-completion evidence. No final accepted visuals exist until the actual Godot PNG or MP4 is inspected and all applicable categories match/exceed the owner's baseline.

## Source and animation truth

- Audition: Poly Haven **Dutch Ship Medium**, official CC0-1.0, 1K glTF and 10 required original PBR dependencies, with original 1K opacity mask for sails. `asset-sources/dutch_ship_medium_audition.json` records exact URLs, publisher sizes and MD5, and independently known source SHA-256 pins on unchanged dependency files. The original glTF SHA-256 must be computed from actual publisher bytes and pinned after first verified receipt. All downloaded resources stay in `client-godot/assets/world_audition/` during CI and never enter `client-godot/assets/external/` or the approved world-content manifest.
- Original ship glTF has *no* `skins` or `animations`: genuine body/sail rigging and naval traversal animation remain **NOT IMPLEMENTED**. The short internal MP4 moves a true imported model and camera only; never call it sail animation, cannon combat or a gameplay slice.
- Poly Haven **Ship Pinnace** and **Cannon 01** are geometry candidates, not animated game rigs; their source glTF also lacks `skins` and `animations`. Poly Haven's realistic rat is a detailed *static* candidate, not admitted as an animated creature.
- Blender Studio Rain is a free, CC-BY studio rig **candidate only**; a Blender-native `.blend` rig is not proof of a commercial-ready Godot rig/LOD/clip set. Do not run untrusted embedded `.blend` scripts or automatically admit it.
- Khronos Fox is a rigged technical glTF example with Survey/Walk/Run but **below owner's premium baseline**, so it must never be accepted or presented as a finished Isles creature.

## Source integrity and visual record

1. Run seven+ negative tests, check original publisher source links, license, byte size, official MD5 metadata and SHA-256 pins, and check complete glTF dependency closure and alpha-capable sails. Preserve derived map/glTF SHA separately with reproducible provenance.
2. Run headless Godot 4.7.2 import, then the **real Godot compatibility-renderer** 30-frame isolated audition script; compare a source-generated still and MP4, reject blank, stale or temporally unchanged captures. Video is encoded from sequential Godot-rendered PNGs, not a synthetic image pan.
3. Save portable `SHA256SUMS`, source receipt, actual screenshot, actual MP4, renderer and exact commit SHA. Keep artifacts internal until visual QA clears them. CI compatibility renderer does **not** prove Android Mobile renderer quality, FPS, memory or thermals.
4. Visual QA views the exact owner reference and true candidate video side by side, records individual verdicts (ship hull, detailed rigging, sails alpha, physically consistent lighting, nautical environment, dynamic sails/wake, creature visuals, moving camera, animation and combat). Mark categories not built as NOT VERIFIED, **never PASS**. Any below-reference quality => FAIL; do not show owner a new sub-baseline preview without an explicit diagnostic request.
5. Only on actually approved premium asset files, capture visible proof, optimize and verify Android LOD0/LOD1 geometry budgets, 1K or justified larger texture mips/compression, near-field preservation, proper skinned animation playback and valid real-device FPS/frame time/thermals. Admission into `world_content.asset_records` requires source SHA, review, exact final SHA gates and video approval. Until then all IDs remain `null` and `available_visual_count()==0`.

No production deployment, no protected backend/transaction/migration edits and no parallel modification of the existing coastal #163 or content #167 owners' write surfaces.
