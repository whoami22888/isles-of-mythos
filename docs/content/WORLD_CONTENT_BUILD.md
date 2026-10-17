# Isles of Mythos — Independent World Content Build (2026-10-18)

**Workstream:** Non-production, isolated from PR #163's coastal renderer and the existing backend. Implementations and checks here create a new **content orchestration seam**, not a finished graphics showcase or a server-side spawn system.

## Concrete code shipped on this branch

- `client-godot/content/world_population.json`: 61 proposed visual archetypes across creatures, characters, vessels, environment sets; 11 encounter camera/cast briefs; five time/lighting profiles with **real, officially published HDRI metadata**. All 61 archetype `asset_id`s are currently null by design. This prevents any placeholder from reaching the player through the director.
- `scripts/world_content.py`: strict schema, duplicate/type/biome and reference validation, premium-model admission contract, SHA-256 byte verification, symlink/path rejection, distance-sorted capped visual selection and near/far LOD hints. It is a **visual-only selector**; it never creates enemies, combat outcomes, loot or persistence.
- `scripts/harvest_world_lighting.py`: bounded stream downloader from exactly allowlisted Poly Haven URLs. Validates publisher content length and MD5; computes receipt SHA-256; rejects off-publisher redirects, symlinks, mismatched and oversized bytes. Saves content to **isolated staging**, never injects into the Godot resources or existing asset manifest.
- `client-godot/scripts/world_content_director.gd`: bounded 20-visible-node presentation director. Reads only catalogued, explicitly admitted, hash-described, review-approved PackedScenes. Without approved art, returns an empty plan rather than a flat mesh fallback. Reads server-originated visual snapshots only; no combat or economy authority.
- `client-godot/tests/world_content_director_test.gd`: real Godot headless scene/catalogue smoke, verify no visual placeholders rendered.
- `.github/workflows/iom-world-content.yml`: exact-SHA PR job running Python tests, pinned Godot 4.7.2 import/smoke, staging 5 official HDRI source files, SHA256SUMS, uploaded artifact and source receipt. The job is not proof that Android renders meet the owner reference.

## Actual publisher candidates — not admitted into gameplay

| Lighting identity | Publisher's asset | Target file (1K HDR) | Official file metadata | Purpose |
| --- | --- | --- | --- | --- |
| `harbour_sunset` | [Venice Sunset](https://polyhaven.com/a/venice_sunset) | `venice_sunset_1k.hdr` | 1,440,400 bytes; MD5 `a5ec4d30fc3421c214a17b208fb66d5f` | Harbour golden-hour rim and sky reflections |
| `volcanic_golden` | [Rogland Sunset](https://polyhaven.com/a/rogland_sunset) | `rogland_sunset_1k.hdr` | 1,487,232 bytes; MD5 `992d5f4103d7054fa7a9ea41e0bd8ad3` | High-contrast volcano/cannon compositions |
| `moonlit_reef` | [Rogland Moonlit Night](https://polyhaven.com/a/rogland_moonlit_night) | `rogland_moonlit_night_1k.hdr` | 1,723,744 bytes; MD5 `19bcd78f82342c992ac2e01c3f65e1e3` | Night sea creatures, moonlit coves |
| `night_overcast` | [Kloppenheim 07](https://polyhaven.com/a/kloppenheim_07) | `kloppenheim_07_1k.hdr` | 1,666,505 bytes; MD5 `168da9f0bf4310eb845a40c26fa26196` | Subdued storm/nocturnal encounters |
| `tropical_daylight` | [Ticknock 03](https://polyhaven.com/a/ticknock_03) | `ticknock_03_1k.hdr` | 1,601,735 bytes; MD5 `87dbb5362b223340adf47215903185f9` | Sunlit island, ship and foliage showcase |

Pinned content SHA256 (independently computed from downloaded bytes):

- Harbour sunset: `92fe2b29b1957828fb8925a57633540bbba5bf380d9285ed553443e834249352`
- Volcanic sunset: `60282c7b0a78882cbdae07052132fdbeee15e4f996c413f5598b05ee8b0e2d43`
- Moonlit reef: `7ef7e14f6c0b6f1065ddd31b0abc0aaa719df9f5b858912108a4c0c6ec219dc8`
- Overcast night: `2e0aff0a24ff254925ea99cbc3a94477056ab6081f9607258c4daa38161a3d75`
- Tropical daylight: `3424af311a0230251146f2869e7369529d41d5d186c819aa4867339d5e227190`

The publisher grants CC0, enabling commercial use and redistribution. Official URLs and size/MD5 are verified from the public Poly Haven Files API. All five files were **actually downloaded** on exact PR HEAD `c0bec4781c473aeab3c9146c5d4858fac475ce7e` in workflow `39037691008`, artifact `12102458779`. The ZIP itself was independently downloaded and SHA-256 verified as `f3c0902cd35ace6ffdeac331a6865e869e5a44dbac4c85b1a3fa5da8edf988c9`; the five internal Radiance byte streams matched the publisher sizes/MD5 and their newly recorded SHA256 pins. This commit now enforces those SHA256 pins on all future source retrievals. HDRI rendering quality and real Android runtime remain **NOT VERIFIED**. Never misreport the metadata listing as a downloaded file. Post-harvest a reviewer must inspect the full HDRI, its sky/reflection behaviour, artistic suitability and Android resource cost. A photo HDRI is lighting input, not a final game landscape, ship, person or creature.

## Prospective characters/creatures/vessels — no art acceptance yet

The 61 archetype slots cover pirates, sailors, guards, merchants, merfolk, sirens, sea dragons, leviathans, krakens, tropical wildlife, frigates, galleons, corsairs, ruins, volcanoes, jungles and many more. These are **content requirements, not fake assets or verified models**. Find professionally detailed rigged/PBR geometry and lawful commercial licenses, package a lower LOD, then source-byte-hash it and review actual Godot output before setting `asset_id` and importing. Existing PR #163 owns the immediate ship/coast meshes and must not be overwritten or falsely marked accepted.

Potential source screening (not admitted): [Poly Haven Street Rat](https://polyhaven.com/a/street_rat) is a detailed CC0 static small-wildlife model; animation, performance and source-byte closure remain unverified. [Blender Studio Human Base Meshes](https://www.blender.org/download/demo-files/#assets) may support rigging workflows but a bare base mannequin is **not** approved final character art. Paid character packs require separate owner approval; no purchases are authorized.

## Visual/commercial acceptance sequence

1. Record actual staged HDRI receipts and their SHA-256 from CI, independently verify source bytes, Godot HDR environment import and licence.
2. Admit premium rigged/animated characters/creatures and readable ships with mesh LODs; each full asset dependency closure and source hash must be pinned, with world-lighting skins and gameplay-camera inspection against the owner's original reference.
3. Connect the visual director to the existing **server-authoritative** world and player snapshots only once the authenticated protocol and authorized integration seam are proven. No locally invented creature spawn, capture or combat outcome.
4. Implement actual ship wakes, cannon-fire response, debris, battle scene staging, creature animation and animation interruptions using server events and bounded VFX pooling. Include art and battle look under daylight, sunset, storm and night, not simply color changes.
5. Obtain exact-SHA Godot evidence, protected Build & Integrity, Functionality & Integration and Data & Transaction Safety gates, and distinct AI review before integration. Profile draw calls, total triangles, texture VRAM, shader compilation, CPU/GPU frame times, streaming hitching and thermals on actual Android hardware before claiming lag-free performance.

**Owner's non-negotiable 2026-10-17 render:** `docs/graphics/CINEMATIC_QUALITY_FLOOR.md` remains binding. There is no certification that these proposed archetypes or staged HDRIs meet it. No lower-fidelity replacement may be presented as finished game art.

## Reproducible commands

```bash
PYTHONPATH=scripts python3 -m unittest discover -s scripts -p 'test_*world*.py' -v
PYTHONPATH=scripts python3 - <<'PY'
from pathlib import Path
from world_content import load_catalog
x=load_catalog(Path('client-godot/content/world_population.json'))
print(len(x['archetypes']), len(x['encounter_shots']))
PY
# Actual Godot 4.7.2, when available:
godot --headless --path client-godot --script res://tests/world_content_director_test.gd
# Source bytes only staged outside project resources:
PYTHONPATH=scripts python3 scripts/harvest_world_lighting.py --staging-dir /tmp/iom-content-staging --ids harbour_sunset volcanic_golden moonlit_reef night_overcast tropical_daylight
```
