# upkeep: make the legal record's renders deterministic

Read CLAUDE.md first. Kind: code (review passes it; the owner signs off).

The cache workflow rebuilds every perf target with `nix build --rebuild` to time it. On 2026-11-06 (cache run 42141701753) `checks.legal-record` failed that rebuild: "may not be deterministic: output ... differs". The renders are in modules/legal/documents.nix:172 (`typst compile ... --input data=/data.json`).

1. Build the check twice locally with `nix build --rebuild .#checks.x86_64-linux.legal-record --keep-failed`, and diff the two outputs to find what differs. Typst PDFs embed a creation date and a document ID.
2. Pin both from the declarations: `--creation-timestamp` from a fixed epoch, and the document's identifier from its content.
3. Show `--rebuild` passing three times in a row.

The fix moves the typst call out of the shell and into a Rust builder, like `config.kagamizo.leanCheck`. That closes or shrinks modules/legal/documents.nix's language exception; lower the baseline by what it held.
