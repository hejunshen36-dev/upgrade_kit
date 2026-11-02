#!/usr/bin/env bash
set -euo pipefail
# Defaults to dry-run; upload requires an explicit --publish --package NAME.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/publish.py" "$@"
