/-
The repo module's paper: the rules every file and every module of the
repository is held to. Checked by checks.paper-repo (../papers.nix).
-/
open Kagamizo.Paper

def paper : Paper := {
  module := "repo",
  title := "Holding a repository to its languages, its proofs and its papers",
  abstract := "The repo module is the repository's own constitution, made executable. It holds every file to the owner's language rule (Rust, Lean or Nix), runs every Lean proof through one shell-free builder, lints every commit message, and requires every module to justify itself in a typed Lean paper. Each rule is a check that fails the build, and each backlog of violations is a ratchet that Lean proves can only shrink.",
  authors := ["upkeep"],
  date := "2026-11-06",
  sections := [
    { kind := .purpose,
      body := "A repository that agents change every day drifts unless its rules are mechanical. The owner's rules are: the code we author is Rust, Lean or Nix, with no inline code in Nix strings (2026-11-05); every module explains itself in a Lean paper (2026-11-06); commit messages follow one convention. Prose in CLAUDE.md states them, but prose is not enforced, and an agent that has not read it, or misreads it, would break them silently. This module turns each rule into a check, so the build itself refuses a file in the wrong language, a module without a paper, or a commit with a malformed message, and it records today's violations as dated debts that can only be paid down.",
      cites := ["knuth-literate"] },
    { kind := .lifecycle,
      body := "Declared: the policy is data (_json/language-policy.json: data formats, exact names, skipped paths, inline-code markers) plus typed options (repo.languages.*); the exceptions and both baselines are JSON the Nix module imports. Built: lang-scan, lean-check and commit-lint are Rust crates built by buildRustPackage, with the policy and nixfmt's path fixed at build time. Run: in CI as flake checks on every push, and locally as the pre-commit hook (lang-scan symlinked as .git/hooks/pre-commit by `lang-scan install-hook`, installed by the session-start hook). Changed: a new rule is a code change of kind code, reviewed by review and security. Retired: an exception closes when its file is rewritten in Rust and its entry deleted, and the baseline is lowered in the same commit; a paper's baseline drops by one as each module gains its paper.",
      cites := ["dolstra-thesis"] },
    { kind := .pipeline,
      body := "Every push runs `nix flake check` in CI, which builds checks.languages (lang-scan over the whole tree as the derivation's own builder: $out exists only if the tree holds), checks.languages-ratchet (Lean over the exceptions and baseline), checks.papers (Lean: the modules without a paper stay within the baseline), checks.paper-<module> for every module with a paper, and checks.commit-lint (the linter's self-test). statix, deadnix and formatting lint the Nix. The same lang-scan binary runs as the pre-commit hook, followed by nixfmt --check on the staged Nix files, so a violation is refused before it is committed. Nothing in this module deploys: its outputs are checks and the tools they run.",
      cites := ["sadowski-static-analysis"] },
    { kind := .agents,
      body := "upkeep owns the module and writes its changes, as kind code: review and security review them before merge, and the owner signs off on nothing here because no rule in it spends money or touches an account. Every team is bound by it: each exception names the team that owes its rewrite (owner) and the date it lapses (until), and each module paper names the teams that wrote it (authors) and run it (agents), which Lean checks against agents.charters. governance-jingzo audits that the baselines only fall. The harness (dsh) cannot build Nix, so the gate session runs these checks on every team's branch before it commits the work under the team's name.",
      cites := ["sadowski-static-analysis"] },
    { kind := .tools,
      body := "lang-scan: `check <root>` walks the tree (skipping .git whatever its kind, and the declared skip names), classifies each file by extension or exact name as code, data or a violation, counts inline-code markers in Nix files, and fails naming each uncovered violation, each exception that grew past its count, and each stale exception; `baseline <root>` prints today's violations as exceptions JSON; `install-hook` links the hook. lean-check: the builder of every Lean proof check, which joins a source file and its rendered facts, runs Lean, and creates $out only if every theorem holds; exposed as config.kagamizo.leanCheck. commit-lint: checks one message or a range against the convention. None of them reads a secret or reaches the network.",
      cites := ["lean4"] },
    { kind := .data,
      body := "language-policy.json: the data extensions (json, toml, md, lock files and the like), exact file names, skipped directories and the inline-code markers (shell builders, script and style tags, Python heredocs). language-exceptions.json: path to language, marker count, owning team, lapse date and replacement, 130 entries on 2026-11-06. language-baseline.json: the most exceptions and markers allowed (130 and 219). paper-baseline.json: the most modules without a paper (61 of 62). All are written by agents through reviewed commits, read only at evaluation, and carry no secret or personal data; the repository is public.",
      cites := ["dolstra-thesis"] },
    { kind := .design,
      body := "Rules are data and typed options, checks are Rust or Lean, and Nix only wires them: the language rule applied to itself. lang-scan runs as the derivation's builder directly (derivation { builder = lang-scan; args = [check self]; }) so no shell exists between Nix and the check, and the same binary is the hook, so CI and the commit agree by construction. Lean checks share one builder that concatenates a module's Lean source with facts rendered from its declarations and decides them with decide +kernel: the module states its rules once in Lean, and the facts are generated, never hand-copied. A paper is a typed Lean value rather than Markdown so that completeness, citation and faithfulness to the module are decidable properties of the build, not matters of review.",
      cites := ["gonthier-reflection", "lean4"] },
    { kind := .guarantees,
      body := "drop_keeps_count (Languages.lean): closing an exception never breaks the file-count baseline, so paying down debt is always admissible. languages_ratchet (rendered): every exception names a declared team and a date, and the exceptions and markers stay within the baseline. complete_has (PaperSchema.lean): a complete paper has a section of every required kind, so purpose, life cycle, pipeline, agents, tools, data, design, guarantees, performance, prior work and gaps are all present. paper_well_formed (rendered per paper): the paper is complete, every citation is used and resolvable, and it explains exactly the module's theorems and perf targets. papers_within_baseline (rendered): modules without a paper never exceed the baseline.",
      cites := ["gonthier-reflection"] },
    { kind := .performance,
      body := "Three targets are measured by rebuilding from scratch (modules/perf): languages, a walk and read of every file, linear in the tree's size and dominated by reading the Nix files to count markers; languages-ratchet, Lean deciding a list of 130 exceptions, linear in their number; papers, Lean deciding a list of module names. A paper check is evaluated by Lean's interpreter (#guard), not decided by the kernel: the kernel's String.length over a paper's prose exhausted the build's memory. Its cost moves with the paper's length and with list membership over the flake's check and package names. The schema's own theorems, such as complete_has, stay kernel-checked; only the per-paper Bool is evaluated, which puts the interpreter in the trusted base for that one fact.",
      cites := ["lean4"] },
    { kind := .priorWork,
      body := "Literate programming (Knuth) made the program and its explanation one artifact; here the explanation is a typed value the build checks, not a document woven from the source. Google's experience with static analysis (Sadowski et al.) is that checks succeed when they run in the developer's workflow, report few false positives and are fixable; hence the hook and the per-file messages naming the fix. Nix (Dolstra) and NixOS (Dolstra, Löh, Pierron) give the hermetic, purely functional builds that let a check be a derivation whose existence is the proof. Lean 4 (de Moura and Ullrich) and proof by reflection (Gonthier) let decidable properties of rendered facts be settled by the kernel. RustBelt (Jung et al.) grounds the choice of Rust for the tools that implement the rules. Conventional Commits defines the message format commit-lint enforces.",
      cites := ["knuth-literate", "sadowski-static-analysis", "dolstra-thesis", "nixos-jfp", "lean4", "gonthier-reflection", "rustbelt", "conventional-commits"] },
    { kind := .gaps,
      body := "Papers are typed Lean values but not yet rendered: Verso (Lean's document system, whose manual genre has a bibliography) is to be pinned so each paper also builds as a page with its citations, and the strategy papers move to it from Typst, closing research/_paper.py. Theorems are found by a pattern over the module's Lean files (a declaration at the start of a line), not by elaborating them, so one declared mid-line or inside a block comment is misread; elaborating each module's Lean and listing its declarations closes that. Checks are not yet attributed to modules, so a paper must name only existing checks rather than all of its own. 130 language exceptions remain, owned by their teams, the trading path's Python first.",
      cites := ["lean4"] }
  ],
  citations := [
    { key := "knuth-literate", title := "Literate Programming", authors := ["Donald E. Knuth"], year := 1984, source := .doi "10.1093/comjnl/27.2.97" },
    { key := "sadowski-static-analysis", title := "Lessons from Building Static Analysis Tools at Google", authors := ["Caitlin Sadowski", "Edward Aftandilian", "Alex Eagle", "Liam Miller-Cushon", "Ciera Jaspan"], year := 2018, source := .doi "10.1145/3188720" },
    { key := "dolstra-thesis", title := "The Purely Functional Software Deployment Model", authors := ["Eelco Dolstra"], year := 2006, source := .url "https://edolstra.github.io/pubs/phd-thesis.pdf" },
    { key := "nixos-jfp", title := "NixOS: A purely functional Linux distribution", authors := ["Eelco Dolstra", "Andres Löh", "Nicolas Pierron"], year := 2010, source := .doi "10.1017/S0956796810000195" },
    { key := "lean4", title := "The Lean 4 Theorem Prover and Programming Language", authors := ["Leonardo de Moura", "Sebastian Ullrich"], year := 2021, source := .doi "10.1007/978-3-030-79876-5_37" },
    { key := "gonthier-reflection", title := "Formal Proof—The Four-Color Theorem", authors := ["Georges Gonthier"], year := 2008, source := .url "https://www.ams.org/notices/200811/tx081101382p.pdf" },
    { key := "rustbelt", title := "RustBelt: Securing the Foundations of the Rust Programming Language", authors := ["Ralf Jung", "Jacques-Henri Jourdan", "Robbert Krebbers", "Derek Dreyer"], year := 2018, source := .doi "10.1145/3158154" },
    { key := "conventional-commits", title := "Conventional Commits 1.0.0", authors := ["The Conventional Commits contributors"], year := 2019, source := .url "https://www.conventionalcommits.org/en/v1.0.0/" }
  ],
  theorems := ["drop_keeps_count", "complete_has"],
  perf := ["languages", "languages-ratchet", "papers"],
  checks := ["languages", "languages-ratchet", "papers", "paper-repo", "commit-lint", "statix", "deadnix", "formatting"],
  packages := ["lang-scan", "lean-check"],
  agents := ["upkeep", "review", "security", "governance-jingzo"]
}
