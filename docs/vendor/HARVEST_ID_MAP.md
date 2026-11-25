# Harvest ID mapping

Two ID schemes existed for Isles of Mythos source packs. This document picks one rule and keeps both readable.

## Canonical IDs for Prompt 001 and `vendor.lock.json`

Issue [#283](https://github.com/whoami22888/isles-of-mythos/issues/283) Prompt 001 IDs are the canonical pack IDs in `vendor.lock.json` `pack_id` values and in this vendor directory:

| Prompt-local ID | Pack | `pack_id` | Licence | Status |
|---|---|---|---|---|
| H01 | Kenney Pirate Kit 2.1 | `kenney:H01-pirate-kit-2.1` | CC0-1.0 | Admitted |
| H02 | Kenney Watercraft Kit 2.1 | `kenney:H02-watercraft-kit-2.1` | CC0-1.0 | Admitted |
| H03 | Kenney Fantasy Town Kit 2.0 | `kenney:H03-fantasy-town-kit-2.0` | CC0-1.0 | Admitted |
| H04 | Kenney UI Pack - Adventure 1.1 | `kenney:H04-ui-pack-adventure-1.1` | CC0-1.0 | Admitted |
| H05 | Quaternius Ultimate Monsters | `quaternius:H05-ultimate-monsters` | CC0-1.0 | Admitted (2026-11-26) |
| H06 | Quaternius Cute Animated Monsters | `quaternius:H06-cute-animated-monsters` | CC0-1.0 | Admitted (2026-11-26) |

## Frozen Harvest Parts register (not renumbered)

The Notion Harvest Parts page remains a legacy code/tool shortlist. Its H01–H11 numbers are **not** rewritten:

| Harvest Parts ID | Entry | Maps to prompt-local ID |
|---|---|---|
| H01 | Godot 3D Multiplayer Template | (code harvest, not a Prompt 001 pack) |
| H02 | Corsairs: Wind of Freedom | Corsairs naval-math sources in the lock (no Prompt 001 H-ID) |
| H03 | Open RTS | (code harvest) |
| H04 | Grid Base Builder | (code harvest) |
| H05 | Godot Imposter | (tool harvest; **not** Quaternius) |
| H06 | QuestSystem | (tool harvest; **not** Quaternius) |
| H07 | Dialogue Manager | (code harvest) |
| H08 | Virtual Joystick | (code harvest) |
| H09 | Kenney Pirate Kit | Prompt-local **H01** |
| H10 | Quaternius Ultimate Monsters | Prompt-local **H05** |
| H11 | Optional Godot water shader | (shader harvest) |
| — | Quaternius Cute Animated Monsters | Prompt-local **H06** (no Harvest Parts H-ID was assigned) |

Do not silently reuse Harvest Parts H05/H06 for the Quaternius packs. When a document says H05 or H06 without a qualifier, treat it as the Prompt 001 / vendor.lock ID unless it explicitly says "Harvest Parts".
