# Working in this repo

## The one rule

Everything is declarative Nix: images, infrastructure, accounts, identities,
secrets references, roles. An account change is an infra change and goes
through code like anything else.

The owner's only manual action is approving 2FA (a link, a push, a code).
Never hand them a form, a dashboard click-path, a value to copy, or a command
to run. If a step cannot be automated yet, it is a gap: say so plainly, list
it under "Gaps" in `modules/cloudflare/README.md`, and work toward closing it.

## Layout

One `modules/` tree, loaded by import-tree into flake-parts. Each module is a
self-contained unit owning its account, secrets, packages, checks and
deployment targets; files under a `_` path (`_nixos.nix`, `_test.nix`,
`_assets/`, `_json/`) are its NixOS-side and data files. Nothing but the
flake, `secretspec.toml`, docs and `.github/` at the top level.

## Types

Every value that has a fixed set of possibilities is typed: catalog-backed
enums for CLI options (`modules/_lib/cli.nix`, `modules/catalog/_json/`),
nix-effects types for the identity model (`modules/_lib/types.nix`). A wrong
value fails evaluation, naming the field, before anything runs.

Accounts are typed too (`modules/accounts/`; each provider's module declares
its own): every account is declared on a plan, every plan lists its
capabilities with the page that states them, and every module declares what it
needs (`accounts.demands`). Never rely on what
an account can do without a capability and a demand for it.

## Legal identities

People and companies are the same kind of thing: an entity with a typed
legal record (`identity.entities.<e>.legal`) and the account slots its kind
requires (`modules/identity/lifecycle.nix`). A new company, domain or login
starts as a declaration on its owner, never as an account made first.
Every wrapper that acts on an account asks `governance-authorize`
(`modules/governance`), and every operation it exposes is a typed action.

## Secrets

Values live only in Proton Pass; `secretspec.toml` (generated from each
module's `secrets.profiles` by `modules/proton/secretspec.nix`) names them.
Never print a secret, read a session's credentials, or pass a value through the terminal: pipe it from the
tool that produced it into `secretspec set`.

## Checks

`nix flake check`; the VM tests need KVM. Commit messages follow
`modules/repo/commits.nix` (`commit-lint --message-file`).

## Ending a session

The owner starts a new session for one reason only: the network allowlist
missed a host. Every session ends by giving the owner exactly two things,
each in one code block ready to paste:

1. **The full allowlist**, one host per line: everything
   `nix build .#claude-allowed-domains` prints plus every host found this
   session and not yet declared. The whole list, never a diff, and only
   when it changed.
2. **The start message** for the next session, kept current at the top of
   `HANDOFF.md` ("End of every session").

Update `HANDOFF.md` and push before handing these over.
