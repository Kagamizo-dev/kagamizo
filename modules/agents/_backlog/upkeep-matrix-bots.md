# upkeep: the teams' Matrix bots

Read CLAUDE.md first. Kind: code.

chat.jingzo.org runs tuwunel and Element on jingzo-host (modules/hetzner/_chat.nix). matrix-seed registers `@zach` and `@agents`, with passwords stored in Kagamizo-Host-State. No bot exists yet.

1. Write a Rust crate `modules/agents/_matrix` on matrix-rust-sdk (MIT or Apache-2; record it in an adoptions table with its licence read at the pinned commit). It runs on the host as one service, signed in as `@agents`, and manages:
   - one room per chartered team (`agents.charters`), named after the team, with its goal as the topic;
   - an `#owner` room for what needs your tap.
2. Each team's room carries the team's work:
   - when a `dispatch` job starts and ends, with its branch and result;
   - each lifecycle review the team owes or passed;
   - the team's spend from `openrouter usage`.
3. A message you post in a team's room becomes a backlog item for that team. It takes kind `research-signal`, `page`, `code` or `world` from a leading keyword, and lands as a typed request the session reads, never executed directly.
4. Lean (`config.kagamizo.leanCheck`) proves every chartered team has exactly one room, and that no bot posts outside its room and `#owner`.

No inline shell: the service runs the binary directly.
