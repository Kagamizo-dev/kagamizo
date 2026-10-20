#!/bin/bash
# Cloud sessions only: build the pinned session tools from this flake
# (pass-cli, secretspec, the infra app) and put them on PATH.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"
link="$HOME/.cache/nix-images/session-tools"
mkdir -p "$(dirname "$link")"
nix build --out-link "$link" .#session-tools

echo "export PATH=\"$link/bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
