# Vendor source admission

## Kenney H01–H04

The exact official Kenney ZIP archives are admitted as hash-pinned source dependencies only. The raw archives remain under `assets-src/kenney/`; no member has been imported into the Godot project or accepted as premium visual art. The companion admission JSON and quarantine manifest record archive hashes, embedded CC0 notices, member hashes and GLB dependency closure.

## Quaternius H05–H06 — quarantined, not admitted

The two exact publisher-linked source archives were previously acquired and independently hash/ZIP/dependency checked. Their hashes and the conflicting licence evidence are retained in `quarantine/quaternius-h05-h06.json`.

| Harvest | Pack | Archive SHA-256 | Verified contents | Current disposition |
|---|---|---|---:|---|
| H05 | Ultimate Monsters (October 2022) | `f444a35e70895f822f3687eb47e608801baf98f2ae86c7ed24b6c017842f006d` | 260 files; ZIP CRC PASS; glTF dependency closure PASS | LICENSE REVIEW REQUIRED |
| H06 | Cute Animated Monsters (August 2020) | `93bb9e0cdd678ddd4367402a38f931d57fd52280b0c50f5075212a216ae673a3` | 127 files; ZIP CRC PASS; glTF dependency closure PASS | LICENSE REVIEW REQUIRED |

The legacy pack pages and creator announcements still describe these named packs as CC0 and permit commercial use. The current Quaternius Asset License v1.0 page (updated 28 August 2026) prohibits standalone redistribution of the Assets in Section 3(a), while Section 7 says the version in effect when an asset was obtained governs. The repository does not contain a dated acquisition-time licence receipt or written confirmation that a post-28-August-2026 download of these exact packs remains under the older CC0 grant.

**Fail-closed disposition:** H05/H06 are not active entries in `vendor.lock.json`, their raw ZIPs and CC0-labelled evidence files have been removed from the current branch tree, and they are not admitted for public source redistribution or production use. Re-admission requires written vendor confirmation for the exact packs and acquisition scope, or an owner-approved private-source arrangement. Do not infer legal admission from the archive hash, the CC0 badge alone, or the current QAL page.

**History limitation:** the archives were committed in earlier public commits on this PR branch. This commit removes them from the current tree but does not rewrite Git history or purge those historical blobs. They may remain retrievable by historical commit SHA; complete historical removal is NOT VERIFIED and requires a separate owner-controlled repository-history remediation.

## Admission boundary

H01–H04, Poly Haven and Corsairs entries are independently pinned in `vendor.lock.json`. Archive-level source admission does not approve individual assets for production use. Any selected asset still requires individual source/dependency review, Godot 4.7.2 Mobile import/render evidence, owner-reference visual comparison and applicable Android performance/thermal evidence. No catalogue entry, source archive, licence record, CI result or GLB inspection alone constitutes premium visual acceptance.
