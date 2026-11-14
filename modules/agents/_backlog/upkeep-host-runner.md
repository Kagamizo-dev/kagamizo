# upkeep: run the teams' jobs on jingzo-host

Read CLAUDE.md first. Kind: code.

The research team's data (weather, Kalshi, flights, satellite) is reachable from jingzo-host, not from a cloud session, whose allowlist is closed. Make the host run backlog items:
1. A Rust service `modules/agents/_runner` on the host:
   - it takes a typed request (team, topic, brief) from a request file committed under `.github/agents.request`, or later from Matrix (upkeep/matrix-bots);
   - it runs that team's dsh headless profile in a worktree under /var/lib/dsh/work, with the team's model and key, and the sandbox and tool allowlist declared for the team;
   - it pushes the branch `agents/<team>/<topic>` with the GitHub App's token.
2. CI gates the branch like any other: the checks, the language rule and the team's lifecycle reviews.
3. Declare the schedule for the research team's daily jobs (paper days, backtests) as timers, each a typed item, never a shell script.
