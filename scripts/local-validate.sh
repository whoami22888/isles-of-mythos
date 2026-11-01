#!/usr/bin/env bash
set -euo pipefail

# 1. Dynamic Godot binary resolution
if [ -n "${GODOT_BIN:-}" ]; then
    GODOT="$GODOT_BIN"
elif command -v godot &>/dev/null; then
    GODOT="$(command -v godot)"
elif [ -x /usr/local/bin/godot ]; then
    GODOT="/usr/local/bin/godot"
else
    GODOT="${HOME}/.local/godot/godot"
fi

if ! command -v "$GODOT" &>/dev/null && [ ! -x "$GODOT" ]; then
    echo "FATAL: Godot binary not found or not executable at '$GODOT'."
    echo "Export GODOT_BIN or install godot into PATH."
    exit 1
fi

echo "Using Godot executable: $GODOT"

# 2. Cleanup generated clutter while preserving locked assets
git clean -fdX -e "!client-godot/assets/external-assets.json" -e "!client-godot/assets/external/**"

# 3. Headless project import
"$GODOT" --headless --rendering-method mobile --path client-godot --editor --import

# 4. Provenance and regression checks
python3 scripts/validate_godot_assets.py
"$GODOT" --headless --rendering-method mobile --path client-godot --script tests/realistic_coastal_slice_test.gd
