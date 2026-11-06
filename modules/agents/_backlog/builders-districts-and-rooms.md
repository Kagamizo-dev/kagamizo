# builders: districts and rooms from the declarations

Read CLAUDE.md first. Kind: world-content (proposer builders; twin passes it).

Generate the twin's layout from declarations, in Nix, as a Tiled map that rs-tiled reads.
- One district per organization area's entity.
- One room per chartered team (`agents.charters`), labelled with the team's goal and project manager.
- One building per module with a perf target.

Write it to `modules/twin/_json/layout.tmj`, rendered by `packages.twin-layout`. Lean (`kagamizo.leanCheck`) proves every chartered team has exactly one room inside its entity's district.
