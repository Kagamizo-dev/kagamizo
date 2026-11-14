/-
The plan module's paper: one typed plan, the source of truth for the work.
Checked by checks.paper-plan (modules/repo/papers.nix).
-/
open Kagamizo.Paper

def paper : Paper := {
  module := "plan",
  title := "One plan as a typed value: goals, tracks, items and the owner's decisions, proved coherent",
  abstract := "The plan module is the authority for what is built, in what order, by which team, and what waits on the owner. Goals, tracks, items and decisions are typed Nix declarations; Lean decides the plan is coherent (dependencies exist and have an order, an item waiting on the owner names an open decision, every open decision blocks something, every team brief belongs to one item); and the plan renders itself as Markdown and as the Plan card of the shell.",
  authors := ["upkeep"],
  date := "2026-11-07",
  sections := [
    { kind := .purpose,
      body := "By 2026-11-07 the work was planned in many places at once: dated sections of HANDOFF.md, the teams' backlog, the Cloudflare gaps, every paper's gaps section and two approved plans, with the same item often in three of them and some long since done. Nobody, owner or agent, could say from one place what is next, what is blocked, and on what. The owner asked for one planning app as the source of authority and truth for tracking and plans. This module is it: every piece of work is one item, in one track, in one order, and the questions only the owner answers are typed decisions linked to what they block.",
      cites := ["dolstra-thesis"] },
    { kind := .lifecycle,
      body := "Declared: plan.goals (what the owner is after), plan.tracks (a stream of work per app, owned by a team), plan.items (each with its track, order, status, blocker, dependencies and the team brief that dispatches it) and plan.decisions (open, or answered with a date). Changed: a new item, a status, an answer to a decision is a commit to modules/plan, of kind code, reviewed by review; a session ends by moving what it finished to done. Read: the Plan card in the shell, the generated PLAN.md (packages.plan), and the teams, whose briefs each belong to one item. Retired: a finished track stays as done items until its goal is met, then its items are removed with a note in HANDOFF.md.",
      cites := ["dolstra-thesis"] },
    { kind := .pipeline,
      body := "checks.plan renders every track, item and decision, and every brief in the teams' backlog, as Lean facts, and decides plan_sound by the kernel on every push. The Nix types already refuse an unknown track, team, decision, status or brief; Lean adds what the types cannot: dependencies name real items and have an order, waiting on the owner means an open decision, and the backlog and the plan agree one to one. packages.plan builds the Markdown, and the shell's build carries the Plan card's view, so what the owner reads is what was checked. The GitHub issues still come from the backlog; rendering them from the plan is the plan's own next item.",
      cites := ["lean4"] },
    { kind := .agents,
      body := "upkeep owns the module and keeps it current at the end of every session; every team reads its track, and its briefs are items of it. design owns how the plan is shown (the Plan card, and later the board view laid out like Linear). The owner answers decisions; an answer is recorded with its date in the decision itself, which unblocks the items that named it. No team changes another team's track without review, and nothing in the plan spends money or applies infrastructure: an item that would is blocked on a decision until the owner answers.",
      cites := ["dolstra-thesis"] },
    { kind := .tools,
      body := "packages.plan writes the plan as Markdown: the goals, the decisions waiting on the owner, the decided ones, and every track's items in order with their status, blocker, brief and dependencies. The Plan card in the shell opens the module's page, which shows what waits on the owner first and then every track. checks.plan is the tool that keeps it honest. The dispatch tool (modules/dsh) runs an item's brief as a job for its team, so the plan and the work it dispatches are the same declarations.",
      cites := ["dolstra-thesis"] },
    { kind := .data,
      body := "The plan's data is its declarations: eight goals, nineteen tracks, close to two hundred items and nearly thirty decisions by the end of 2026-11-07 (`nix build .#plan` prints the current count), gathered from HANDOFF.md, the backlog and its briefs, the Cloudflare gaps, every paper's gaps, and the plans of 2026-11-04 and 2026-11-07, then deduplicated. It holds no secret and nothing personal beyond what the public repository already says; decisions record the owner's answers in words, never a value. Each item may cite where it was first planned.",
      cites := ["dolstra-thesis"] },
    { kind := .design,
      body := "Nix types the plan so a misspelt track, team, status or brief fails evaluation; an item's order is its place in its track's list, so reordering is moving a line. Lean (_lean/Plan.lean) holds the rules: itemOk checks an item's track, dependencies, decision and that a done item is not blocked; ordered settles items round by round, taking every item whose dependencies are all taken, and succeeds when everything is taken, which is exactly the absence of a dependency cycle; sound adds unique ids, every open decision blocking something, and every backlog brief belonging to exactly one item. Tracks map one to one to the apps and their teams, which is where the repository is heading: every app a module, every module a team.",
      cites := ["lean4", "kahn-toposort"] },
    { kind := .guarantees,
      body := "checks.plan decides plan_sound for the declared plan: ids are unique; every item's track and dependencies exist; there is an order to do every item in; an item blocked on the owner names a decision that is still open; every open decision blocks at least one item; and every brief in the teams' backlog belongs to exactly one item. The theorem waits_on_open proves, for any item that passes itemOk and is blocked on the owner, that its decision is among the open ones, so nothing ever waits on a question already answered.",
      cites := ["lean4"] },
    { kind := .performance,
      body := "No perf target is declared. The kernel decides the plan's soundness over about two hundred items in seconds as part of the check; the settling rounds are bounded by the number of items, and the longest chain of dependencies today is four items. What would move it is the plan's size: past a few thousand items, the check would move from the kernel's decide to an evaluated guard, as the papers' check already does for long prose.",
      cites := ["kahn-toposort"] },
    { kind := .priorWork,
      body := "The order check is Kahn's topological sort: repeatedly take the items with no unmet dependency; a graph has an order exactly when this takes everything. Nix's purely functional model, after Dolstra, is why the plan is a value built from declarations and checked before it is used, and Lean 4 decides its soundness by the kernel as the repository's other rules are decided. Project boards such as Linear are the presentation the owner chose for the board view; here the board is a view of the typed plan rather than its store.",
      cites := ["kahn-toposort", "dolstra-thesis", "lean4"] },
    { kind := .gaps,
      body := "The GitHub issues and the Projects board still render from the teams' backlog, not from the plan; rendering them from the plan is the plan's own next item. The board view laid out like Linear waits on design and credit. An item's status is set by hand at the end of a session rather than from the work's own evidence (a merged change, a passing check). Blockers are a closed list; a blocker on another team is expressed as a dependency, and an item cannot yet say it waits on a date.",
      cites := ["lean4"] }
  ],
  citations := [
    { key := "kahn-toposort", title := "Topological sorting of large networks", authors := ["Arthur B. Kahn"], year := 1962,
      source := .doi "10.1145/368996.369025" },
    { key := "dolstra-thesis", title := "The Purely Functional Software Deployment Model", authors := ["Eelco Dolstra"], year := 2006,
      source := .url "https://edolstra.github.io/pubs/phd-thesis.pdf" },
    { key := "lean4", title := "The Lean 4 Theorem Prover and Programming Language", authors := ["Leonardo de Moura", "Sebastian Ullrich"], year := 2021,
      source := .doi "10.1007/978-3-030-79876-5_37" }
  ],
  theorems := ["waits_on_open"],
  perf := [],
  checks := ["plan", "paper-plan"],
  packages := ["plan"],
  agents := ["upkeep", "design", "review"]
}
