#!/usr/bin/env bash
# Compatibility entry point; the packaged installer carries all runtime tools.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec nix run "$ROOT#installer" -- "$@"
