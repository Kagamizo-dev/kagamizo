# upkeep: burn down the language exceptions

Read CLAUDE.md first. Kind: code (review passes it; the owner signs off).

`checks.languages` lists 130 dated exceptions and 219 inline-code markers. Each week, close the exceptions you own (`modules/repo/_json/language-exceptions.json`, owner upkeep), largest first:
- move a `writeShellApplication` wrapper into a Rust binary (a clap CLI in a crate beside the module);
- move a `runCommand` check onto `config.kagamizo.leanCheck` or a Rust builder;
- delete the entry and lower `modules/repo/_json/language-baseline.json` by what it held.

Never raise the baseline. Each closed file is its own commit. Start with modules/dsh/dispatch.nix, the tool the teams themselves run.
