/-
CI pipelines (modules/ci), as a specification. A workflow is jobs, each
naming the jobs it needs and whether it holds a write permission.
`Workflow.sound` is the rule: every job it needs is declared, the needs
have no cycle (the jobs can be run in some order), and a workflow a pull
request can start gives no job a write permission, so a contributor's
branch can never publish or push. ../default.nix renders every declared
workflow and has Lean decide it.
-/
namespace Kagamizo.Ci

structure Job where
  name : String
  needs : List String
  writes : Bool
  deriving Repr

structure Workflow where
  name : String
  pullRequest : Bool
  jobs : List Job
  deriving Repr

def Workflow.names (w : Workflow) : List String := w.jobs.map (·.name)

/-- Every job a job needs is one of the workflow's. -/
def Workflow.closed (w : Workflow) : Bool :=
  w.jobs.all fun j => j.needs.all w.names.contains

/-- One pass of running: the jobs not yet run whose needs have all run. -/
def Workflow.step (w : Workflow) (done : List String) : List String :=
  done ++ (w.jobs.filter fun j => !done.contains j.name && j.needs.all done.contains).map (·.name)

/-- After as many passes as there are jobs, every job has run: no cycle. -/
def Workflow.acyclic (w : Workflow) : Bool :=
  let done := (List.range w.jobs.length).foldl (fun d _ => w.step d) []
  w.jobs.all fun j => done.contains j.name

/-- A pull request starts nothing that writes. -/
def Workflow.prSafe (w : Workflow) : Bool :=
  !w.pullRequest || w.jobs.all (!·.writes)

def Workflow.sound (w : Workflow) : Bool := w.closed && w.acyclic && w.prSafe

/-- A sound workflow a pull request can start has no job that writes. -/
theorem pr_never_writes (w : Workflow) (h : w.sound = true) (hp : w.pullRequest = true) :
    ∀ j ∈ w.jobs, j.writes = false := by
  intro j hj
  simp only [Workflow.sound, Workflow.prSafe, hp, Bool.not_true, Bool.false_or,
    Bool.and_eq_true, List.all_eq_true] at h
  simpa using h.2 j hj

/-- In a sound workflow, every need names a declared job. -/
theorem needs_declared (w : Workflow) (h : w.sound = true) :
    ∀ j ∈ w.jobs, ∀ n ∈ j.needs, n ∈ w.names := by
  intro j hj n hn
  simp only [Workflow.sound, Workflow.closed, Bool.and_eq_true, List.all_eq_true] at h
  simpa using h.1.1 j hj n hn

end Kagamizo.Ci
