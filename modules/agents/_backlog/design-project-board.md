# design: a project board on the status page

Read CLAUDE.md first. Kind: page.

The owner wants the status page to work like Linear for now, until the Minecraft twin takes over.

- The board is built from declarations:
  - `agents.backlog` items are cards;
  - `agents.lifecycle` gives each card its stages: proposed, in review, signed off, done;
  - each team is a lane;
  - each card shows its brief, branch, reviews and CI result.
- Notes live as Markdown files in the repo (modules/agents/_notes), linked from cards, in Obsidian's style: wiki links and backlinks rendered by a Rust renderer.

Adopt rather than build:
- Map an open-licensed Linear-like tracker with REA first (Plane is AGPL-3, Huly is EPL-2: record each licence as read) and take its information design.
- Running one as its own process is acceptable only if it is Rust; otherwise the board is our renderer.

Pass the page check.
