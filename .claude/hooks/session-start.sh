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

# Pull from the build cache (modules/cache) once its key is declared; root
# is a trusted user here, so the lines take effect at once (no daemon).
conf=$(nix build --no-link --print-out-paths .#cache-nix-conf)
if [ -s "$conf" ] && ! grep -qF "$(head -1 "$conf")" /etc/nix/nix.custom.conf 2>/dev/null; then
  cat "$conf" >>/etc/nix/nix.custom.conf
fi

# Reject commits that break the message convention (modules/repo/commits.nix).
"$link/bin/commit-lint" --install-hook >/dev/null
# Reject commits that add bash, Python, JavaScript or inline code, or that
# leave Nix unformatted (modules/repo/languages.nix).
"$link/bin/lang-scan" install-hook >/dev/null

