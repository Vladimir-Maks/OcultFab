#!/usr/bin/env bash
# Run VoxelCore with this project.
#
# Overrides:
#   VC_BIN=/path/to/VoxelCore   engine executable (AppImage, AppRun or binary)
#   VC_DIR=/path/to/userdir     user files folder (worlds, settings, logs)
# Extra arguments are passed to the engine as is.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLAUNCHER="$HOME/.local/share/vlauncher"

if [[ -z "${VC_BIN:-}" ]]; then
    # newest vlauncher runtime, then VoxelCore from PATH
    VC_BIN="$(ls -d "$VLAUNCHER"/runtimes/*-linux-x86_64/AppRun 2>/dev/null | sort -V | tail -n 1 || true)"
    if [[ -z "$VC_BIN" ]]; then
        VC_BIN="$(command -v VoxelCore || true)"
    fi
fi
if [[ -z "$VC_BIN" || ! -x "$VC_BIN" ]]; then
    echo "VoxelCore not found, set VC_BIN=/path/to/VoxelCore" >&2
    exit 1
fi

if [[ -z "${VC_DIR:-}" && -d "$VLAUNCHER/profiles/VoxelCore/game" ]]; then
    VC_DIR="$VLAUNCHER/profiles/VoxelCore/game"
fi

args=(--project "$PROJECT_DIR")
if [[ -n "${VC_DIR:-}" ]]; then
    args+=(--dir "$VC_DIR")
fi

cd "${VC_DIR:-$PROJECT_DIR}"
exec "$VC_BIN" "${args[@]}" "$@"
