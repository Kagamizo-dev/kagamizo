# twin: the Pumpkin server on jingzo-host

Read CLAUDE.md first. Kind: world (proposer twin; review and builders pass it; the owner signs off).

Pumpkin is adopted (`twin.adoptions.pumpkin`: Pumpkin-MC/Pumpkin at 6361843f, GPL-3, protocol 26.3), to run unmodified as its own process.

1. Package it with Nix from that commit (`rustPlatform.buildRustPackage`, its Cargo.lock), in `modules/twin/server.nix`.
2. Run it on jingzo-host as a NixOS service in `modules/twin/_server.nix`, imported by modules/hetzner/host.nix. It listens on 127.0.0.1 only, keeps its world in /var/lib/twin, runs offline-mode, and uses a whitelist of the declared agents' bot names.
3. Add a Rust stats reader in `modules/twin/_stats`. It reads players online, tick time and world size from the server's query or RCON port, and writes JSON for the status page.
4. Port Pumpkin's `crates/pumpkin-world` tests into a check, as its adoption records.

No shell in Nix strings: builders are Rust binaries (see `config.kagamizo.leanCheck` and `checks.languages` for the pattern). The pre-commit hook and checks.languages must pass with no new exception.
