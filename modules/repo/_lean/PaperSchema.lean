/-
The module paper (modules/repo/papers.nix; the owner's rule, 2026-11-06):
every module justifies its existence in a paper written as Lean, which
replaces its README. The paper is a typed value, so a missing section, an
uncited claim or a theorem the paper does not explain fails the build.

A module's paper is `modules/<m>/_lean/Paper.lean`, a `def paper : Paper`.
../papers.nix appends to it the facts it renders from the repository (the
module's theorems, its perf targets, every check, package and team) and the
theorem `paper.wellFormed facts = true`, decided by the kernel. So the paper
can name nothing that does not exist, and must explain everything the
module proves and measures.
-/
namespace Kagamizo.Paper

/-- The sections every paper has, in order. Each is the full account of
its subject, not a summary. -/
inductive Kind where
  /-- Why the module exists: the problem, and what would break without it. -/
  | purpose
  /-- Its full life cycle: how it is declared, built, deployed, run,
  changed and retired, and who does each. -/
  | lifecycle
  /-- The pipeline it is part of: the checks that gate it, what builds it
  and where it deploys. -/
  | pipeline
  /-- The agents (teams) that run, maintain and review it, with their
  roles and grants. -/
  | agents
  /-- The tools it exposes or uses, and what each may do. -/
  | tools
  /-- The data and datasets it reads and writes: their sources, schemas,
  cadence and licences. -/
  | data
  /-- The design: its types, its Rust, its Nix, and why this design. -/
  | design
  /-- What its Lean theorems guarantee, one by one. -/
  | guarantees
  /-- Its performance: what is measured, the method, and what moves it. -/
  | performance
  /-- The prior work it builds on or departs from, cited. -/
  | priorWork
  /-- What it does not do yet, and the plan to close each gap. -/
  | gaps
  deriving DecidableEq, Repr

def Kind.all : List Kind :=
  [.purpose, .lifecycle, .pipeline, .agents, .tools, .data, .design,
   .guarantees, .performance, .priorWork, .gaps]

/-- Where a cited work can be found: a persistent identifier first. -/
inductive Source where
  | arxiv (id : String)
  | doi (id : String)
  | url (u : String)
  deriving DecidableEq, Repr

def Source.nonempty : Source → Bool
  | .arxiv i => !i.isEmpty
  | .doi i => !i.isEmpty
  | .url u => u.startsWith "https://"

structure Citation where
  key : String
  title : String
  authors : List String
  year : Nat
  source : Source
  deriving DecidableEq, Repr

structure Section where
  kind : Kind
  body : String
  /-- The citation keys this section rests on. -/
  cites : List String := []
  deriving DecidableEq, Repr

structure Paper where
  module : String
  title : String
  abstract : String
  /-- The teams that wrote it (agents.charters names). -/
  authors : List String
  date : String
  sections : List Section
  citations : List Citation
  /-- The module's theorems this paper explains: all of them. -/
  theorems : List String
  /-- The module's perf targets: all of them. -/
  perf : List String
  /-- The checks that gate it (any check in the flake). -/
  checks : List String
  /-- The packages it builds or wraps. -/
  packages : List String
  /-- The teams that run, maintain or review it. -/
  agents : List String
  deriving Repr

/-- What the repository says about the module, rendered by ../papers.nix. -/
structure Facts where
  module : String
  teams : List String
  theorems : List String
  perf : List String
  checks : List String
  packages : List String
  deriving Repr

/-- The shortest body a section may have: a paragraph, not a line. -/
def minBody : Nat := 280

/-- The shortest abstract. -/
def minAbstract : Nat := 160

def subset (xs ys : List String) : Bool := xs.all ys.contains

def keys (p : Paper) : List String := p.citations.map (·.key)

def section? (p : Paper) (k : Kind) : Option Section :=
  p.sections.find? (·.kind == k)

/-- Every required section is there, and is a paragraph or more. -/
def complete (p : Paper) : Bool :=
  Kind.all.all fun k =>
    match section? p k with
    | some s => decide (minBody ≤ s.body.length)
    | none => false

/-- Every citation is used, every use is a citation, prior work cites at
least two works, and every source is a persistent id or an https link. -/
def cited (p : Paper) : Bool :=
  decide (2 ≤ p.citations.length) &&
  p.citations.all (fun c => c.source.nonempty && !c.title.isEmpty && !c.authors.isEmpty) &&
  p.sections.all (fun s => subset s.cites (keys p)) &&
  (keys p).all (fun k => p.sections.any (·.cites.contains k)) &&
  (match section? p .priorWork with
   | some s => decide (2 ≤ s.cites.length)
   | none => false)

/-- The paper explains exactly the module's theorems and perf targets, and
names only checks, packages and teams that exist. -/
def faithful (p : Paper) (f : Facts) : Bool :=
  p.module == f.module &&
  subset p.theorems f.theorems && subset f.theorems p.theorems &&
  subset p.perf f.perf && subset f.perf p.perf &&
  subset p.checks f.checks && subset p.packages f.packages &&
  !p.authors.isEmpty && subset p.authors f.teams && subset p.agents f.teams

/-- Everything wrong with a paper, each named, so the writer can fix it. -/
def Paper.problems (p : Paper) (f : Facts) : List String :=
  let missingIn (what : String) (xs ys : List String) :=
    (xs.filter (!ys.contains ·)).map (s!"{what}: {·}")
  (if minAbstract ≤ p.abstract.length then [] else [s!"abstract: {p.abstract.length} characters, at least {minAbstract}"]) ++
  (if p.title.isEmpty then ["title: empty"] else []) ++
  (Kind.all.filterMap fun k =>
    match section? p k with
    | some s => if minBody ≤ s.body.length then none
        else some s!"section {repr k}: {s.body.length} characters, at least {minBody}"
    | none => some s!"section {repr k}: missing") ++
  (if 2 ≤ p.citations.length then [] else ["citations: fewer than two"]) ++
  (p.citations.filter (fun c => !(c.source.nonempty && !c.title.isEmpty && !c.authors.isEmpty))).map
    (s!"citation {·.key}: needs a title, authors and an arXiv id, DOI or https link") ++
  (p.sections.flatMap fun s => missingIn s!"section {repr s.kind} cites an unknown key" s.cites (keys p)) ++
  ((keys p).filter (fun k => !p.sections.any (·.cites.contains k))).map (s!"citation {·}: never cited") ++
  (match section? p .priorWork with
   | some s => if 2 ≤ s.cites.length then [] else ["priorWork: cites fewer than two works"]
   | none => []) ++
  (if p.module == f.module then [] else [s!"module: {p.module}, but the file is in {f.module}"]) ++
  missingIn "theorem not in the module" p.theorems f.theorems ++
  missingIn "theorem not explained" f.theorems p.theorems ++
  missingIn "perf target not in the module" p.perf f.perf ++
  missingIn "perf target not explained" f.perf p.perf ++
  missingIn "no such check" p.checks f.checks ++
  missingIn "no such package" p.packages f.packages ++
  (if p.authors.isEmpty then ["authors: none"] else []) ++
  missingIn "no such team (author)" p.authors f.teams ++
  missingIn "no such team (agent)" p.agents f.teams

def Paper.wellFormed (p : Paper) (f : Facts) : Bool :=
  (p.problems f).isEmpty

/-- A complete paper has every kind of section. -/
theorem complete_has (p : Paper) (h : complete p = true) (k : Kind)
    (hk : k ∈ Kind.all) : (section? p k).isSome := by
  unfold complete at h
  rw [List.all_eq_true] at h
  have := h k hk
  cases hs : section? p k with
  | none => simp [hs] at this
  | some _ => rfl

end Kagamizo.Paper

/-! The baseline: modules without a paper may only become fewer. -/
namespace Kagamizo.Papers

def withinBaseline (missing : List String) (baseline : Nat) : Bool :=
  decide (missing.length ≤ baseline)

end Kagamizo.Papers
