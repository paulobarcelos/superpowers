#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)
source "$REPO_ROOT/skills/google-sheets-api/scripts/env-helpers.sh"
exec "$SHELL" "$@"
