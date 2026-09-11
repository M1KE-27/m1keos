#!/bin/bash
# ==============================================================================
# MIKE OS - Launch MIKE Desktop in 1920x1080 Full HD
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

exec "$PROJECT_ROOT/scripts/run-qemu.sh" --gui --1080p "$@"
