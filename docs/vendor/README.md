# Vendor source admission

## Kenney H01–H04

The exact official Kenney ZIP archives are admitted as hash-pinned source dependencies only. The raw archives remain under `assets-src/kenney/`; no member has been imported into the Godot project or accepted as premium visual art. The companion admission JSON and quarantine manifest record archive hashes, embedded CC0 notices, member hashes and GLB dependency closure.

## Quaternius H05–H06

The exact official publisher-linked ZIP archives are now admitted as hash-pinned source dependencies only:

| Harvest | Pack | Archive SHA-256 | Verified contents |
|---|---|---|---|
| H05 | Ultimate Monsters (October 2022) | `f444a35e70895f822f3687eb47e608801baf98f2ae86c7ed24b6c017842f006d` | 260 files; ZIP CRC PASS; glTF dependency closure PASS; historical file-count comparison PASS |
| H06 | Cute Animated Monsters (August 2020) | `93bb9e0cdd678ddd4367402a38f931d57fd52280b0c50f5075212a216ae673a3` | 127 files; ZIP CRC PASS; glTF dependency closure PASS; historical file-count comparison PASS |

Pack-specific licence evidence is preserved in `LICENSES/CC0-1.0-Quaternius-H05.txt` and `LICENSES/CC0-1.0-Quaternius-H06.txt` and pinned in `vendor.lock.json`.

- H05's official [publisher page](https://quaternius.com/packs/ultimatemonsters.html) and [22 October 2022 creator announcement](https://www.patreon.com/quaternius/posts/ultimate-50-73633148) identify this exact pack as CC0-1.0 for commercial use. The original archive's embedded `License.txt` heading names "Ultimate Platformer Pack" but its licence section states CC0-1.0; the original member is preserved unchanged and the anomaly is recorded in the evidence file.
- H06's official [publisher page](https://quaternius.com/packs/cutemonsters.html) and [1 August 2020 creator announcement](https://www.patreon.com/quaternius/posts/cute-animated-20-39982825) identify this exact pack as CC0-1.0 for commercial use. No embedded licence file was present; no synthetic `License.txt` was inserted.
- The current Quaternius Asset License v1.0 page is recorded as context, not substituted for the named packs' pack-specific CC0 grants. The publisher's current pack pages still label these releases CC0; QAL v1.0 section 7 says updates are for future releases and are not retroactive to assets obtained under an earlier version. See the captured page/deed hashes in the two evidence files.

Exact publisher "Download all" ZIP bytes were captured by workflow run `44736035009` and retained at quarantine commit `b0c597fb13ff671d43e437a9c84a10dbfb723bec`. H05 and H06 archive hashes above match the corresponding `source_revision` and `sha256` entries in `vendor.lock.json`. The full per-file manifests and page evidence are retained at that quarantine commit.

## Admission boundary

H01–H06 are archive-level source admissions only. The raw ZIPs remain under `assets-src/`; no member is thereby approved for production use. Any selected asset still requires individual source/dependency review, Godot 4.7.2 Mobile import/render evidence, owner-reference visual comparison and applicable Android performance/thermal evidence. No catalogue entry, source archive, licence record, CI result or GLB inspection alone constitutes premium visual acceptance.
