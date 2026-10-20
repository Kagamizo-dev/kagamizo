#!/bin/bash
# Cloud sessions only: build the pinned session tools from this flake
# (pass-cli, secretspec, the infra/registrar/proton apps, commit-lint), put them
# on PATH, and install the commit-msg hook.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"
link="$HOME/.cache/nix-images/session-tools"
mkdir -p "$(dirname "$link")"
nix build --out-link "$link" .#session-tools

echo "export PATH=\"$link/bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
# Containers have no OS keyring. Without this, pass-cli finds no key, treats
# the session as tampered with and logs out.
echo "export PROTON_PASS_KEY_PROVIDER=fs" >>"$CLAUDE_ENV_FILE"

# Reject commits that break the message convention (parts/repo/commits.nix).
"$link/bin/commit-lint" --install-hook >/dev/null

