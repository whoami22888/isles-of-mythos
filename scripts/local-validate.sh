#!/usr/bin/env bash
set -euo pipefail

# 1. Anchor execution to repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f "client-godot/project.godot" ]; then
    echo "FATAL: Invalid repository root. 'client-godot/project.godot' missing." >&2
    exit 1
fi

# 2. Dynamic Godot binary resolution
GODOT="${GODOT_BIN:-$(command -v godot 2>/dev/null || echo "/usr/local/bin/godot")}"

if ! command -v "$GODOT" &>/dev/null && [ ! -x "$GODOT" ]; then
    echo "FATAL: Godot executable not found at '$GODOT'." >&2
    exit 1
fi

# 3. Enforce Godot 4.7.2 version match
ENGINE_VERSION="$("$GODOT" --version 2>&1 || true)"
if [[ "$ENGINE_VERSION" != *"4.7.2"* ]]; then
    echo "FATAL: Incompatible Godot version '$ENGINE_VERSION'. Required: 4.7.2" >&2
    exit 1
fi

echo "Using Godot executable: $GODOT ($ENGINE_VERSION)"

# 4. Target ONLY Godot import cache (NO DESTRUCTIVE git clean)
echo "Clearing Godot import cache..."
rm -rf client-godot/.godot client-godot/.import

# 5. Headless project import & validation
"$GODOT" --headless --rendering-method mobile --path client-godot --editor --import
python3 scripts/validate_godot_assets.py
"$GODOT" --headless --rendering-method mobile --path client-godot --script tests/realistic_coastal_slice_test.gd
