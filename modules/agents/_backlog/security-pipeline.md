# security: security in every pipeline

Read CLAUDE.md first. Kind: security-check (review and upkeep pass it; the owner signs off).

Add these to CI and to the pre-commit hook, as declared checks:
1. Code review: Alibaba's open-code-review (Apache-2, Go), run unmodified as its own process in CI on every change, pinned by commit and wrapped by the least Nix. Its findings gate the merge.
2. Dependencies: cargo-audit and cargo-deny on every Rust crate's lockfile, plus advisories for every pinned flake input.
3. Secrets: a scanner over the tree and every commit (a Rust one, gitleaks' rules as data).
4. Error tracking for our services: prefer the services' own logs on the status page. Sentry self-hosted and Bugsink (Python) are not adopted unless a team shows the need; record why.
5. Penetration tests of what runs behind Access (agents, code, chat, harness, status), scheduled, with results as typed findings.

Lean proves every check runs on every pipeline that can merge.
