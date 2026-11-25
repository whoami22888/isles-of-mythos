# Vendor source admission

## Kenney H01–H04

The exact official Kenney ZIP archives are admitted as hash-pinned source dependencies only. The raw archives remain under `assets-src/kenney/`; no member has been imported into the Godot project or accepted as premium visual art. The companion admission JSON and quarantine manifest record archive hashes, embedded CC0 notices, member hashes and GLB dependency closure.

## Quaternius H05–H06 — admitted CC0 (2026-11-26)

The two exact publisher-linked source archives are admitted as hash-pinned CC0 source dependencies, matching the Kenney H01–H04 pattern. Official pack pages and the Ultimate Monsters creator announcement identify the packs as CC0 for personal and commercial use. Raw archives live under `assets-src/quaternius/`; no member has been imported into the Godot project or accepted as premium visual art.

| Prompt-local ID | Pack | Archive SHA-256 | Disposition |
|---|---|---|---|
| H05 | Ultimate Monsters (October 2022) | `f444a35e70895f822f3687eb47e608801baf98f2ae86c7ed24b6c017842f006d` | ADMITTED CC0 |
| H06 | Cute Animated Monsters (August 2020) | `93bb9e0cdd678ddd4367402a38f931d57fd52280b0c50f5075212a216ae673a3` | ADMITTED CC0 |

Known archive anomalies are retained as provenance and do not block this admission: H05's embedded License.txt is headed “Ultimate Platformer Pack” while the archive is Ultimate Monsters (the licence section still states CC0 1.0); H06 has no embedded licence file. Supplemental licence evidence is in `LICENSES/CC0-1.0-Quaternius-H05.txt` and `LICENSES/CC0-1.0-Quaternius-H06.txt`.

Prompt-local H05/H06 IDs from issue #283 are canonical in `vendor.lock.json`. The frozen Harvest Parts H01–H11 register is not renumbered; see `HARVEST_ID_MAP.md`.

**History limitation:** earlier public commits on this PR branch also contain these archive blobs. This admission restores them to the current tree at the pinned hashes; no Git-history rewrite was performed.

## Admission boundary

H01–H04, Poly Haven and Corsairs entries are independently pinned in `vendor.lock.json`. Archive-level source admission does not approve individual assets for production use. Any selected asset still requires individual source/dependency review, Godot 4.7.2 Mobile import/render evidence, owner-reference visual comparison and applicable Android performance/thermal evidence. No catalogue entry, source archive, licence record, CI result or GLB inspection alone constitutes premium visual acceptance.
