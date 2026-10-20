# Working in this repo

## The one rule

Everything is declarative Nix: images, infrastructure, accounts, identities,
secrets references, roles. An account change is an infra change and goes
through code like anything else.

The owner's only manual action is approving 2FA (a link, a push, a code).
Never hand them a form, a dashboard click-path, a value to copy, or a command
to run. If a step cannot be automated yet, it is a gap: say so plainly, list
it under "Gaps" in `parts/cloudflare/README.md`, and work toward closing it.

## Types

Every value that has a fixed set of possibilities is typed: catalog-backed
enums for CLI options (`parts/_lib/cli.nix`, `catalog/`), nix-effects types
for the identity model (`parts/_lib/types.nix`). A wrong value fails
evaluation, naming the field, before anything runs.

Accounts are typed too (`parts/accounts/`): every account is declared on a
plan, every plan lists its capabilities with the page that states them, and
every module declares what it needs (`accounts.demands`). Never rely on what
an account can do without a capability and a demand for it.

## Secrets

Values live only in Proton Pass; `secretspec.toml` (generated from
`parts/proton/secretspec.nix`) names them. Never print a secret, read a
session's credentials, or pass a value through the terminal: pipe it from the
tool that produced it into `secretspec set`.

## Checks

`nix flake check`; the VM tests need KVM. Commit messages follow
`parts/repo/commits.nix` (`commit-lint --message-file`).
