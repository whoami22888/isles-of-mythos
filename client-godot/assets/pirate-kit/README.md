# IOM-01 Pirate Kit import (non-production)

This directory tracks the November 2023 Quaternius Pirate Kit source and four verified file hashes, not a blanket licence approval for other Quaternius packs. The original publisher announcement https://www.patreon.com/quaternius/posts/pirate-kit-70-92300290 identifies this release as CC0; the pack page https://quaternius.com/packs/piratekit.html lists 71 assets, glTF/OBJ/FBX/Blend and CC0. The newer publisher licence https://quaternius.com/license.html has different standalone redistribution restrictions. Preserve both dated sources and recheck the specific downloaded archive's applicable licence before committing raw models or distributing standalone asset packs.

Download the source from the original publisher-linked Drive folder. Use a corrected isles_pirate_asset_starter.zip with the four exact filenames in manifest.json. From the repository root:

    python3 scripts/import_pirate_assets.py /path/to/isles_pirate_asset_starter.zip
    python3 scripts/import_pirate_assets.py /path/to/isles_pirate_asset_starter.zip --install

Verification rejects missing, duplicate, renamed, changed, or externally dependent glTF files. --install never overwrites a changed asset. Imported binaries are ignored by Git pending the asset admission decision. This step verifies file integrity and glTF structure; it does not prove Godot 4.7.2 Mobile import, Android ARM64 rendering, performance, visual quality or a debug APK.

Ownership: IOM-01 asset pipeline only; do not modify the Codex-owned latency branch or authoritative server gameplay/economy.
