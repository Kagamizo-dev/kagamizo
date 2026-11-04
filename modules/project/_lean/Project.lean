/-
The project as typed data: epics, the owner's decisions and the gaps
(../_data/*.json, typed by ../default.nix). Lean decides over the rendered
facts that the plan is coherent:

  * every blocker names a declared epic or decision;
  * no epic waits on itself, however far round (the graph is acyclic);
  * a done epic's blockers are all done (epics) or answered (decisions);
  * a blocked epic has an open blocker;
  * every answer is one of its decision's options;
  * every gap names an epic that closes it, and that epic is not done.
-/
namespace Kagamizo.Project

inductive Status where
  | proposed | approved | inProgress | blocked | done | paused
  deriving DecidableEq, Repr

structure Epic where
  id : String
  status : Status
  blockedOn : List String

structure Decision where
  id : String
  answered : Bool
  /-- The answer is null or one of the options. -/
  valid : Bool

structure Gap where
  id : String
  closesWith : String

def epicOf (es : List Epic) (id : String) : Option Epic := es.find? (·.id == id)
def decisionOf (ds : List Decision) (id : String) : Option Decision := ds.find? (·.id == id)

def known (es : List Epic) (ds : List Decision) (id : String) : Bool :=
  (epicOf es id).isSome || (decisionOf ds id).isSome

/-- A blocker is settled: a done epic, or an answered decision. -/
def settled (es : List Epic) (ds : List Decision) (id : String) : Bool :=
  match epicOf es id with
  | some e => e.status == .done
  | none => match decisionOf ds id with
    | some d => d.answered
    | none => false

def deps (es : List Epic) (id : String) : List String :=
  ((epicOf es id).map (·.blockedOn)).getD []

/-- Everything reachable from `xs` in at most `n` steps. -/
def reach (es : List Epic) : Nat → List String → List String
  | 0, _ => []
  | n + 1, xs => xs ++ reach es n (xs.flatMap (deps es))

/-- Paths longer than the number of epics would repeat one, so that many
steps is enough to find any cycle. -/
def acyclic (es : List Epic) : Bool :=
  es.all fun e => !(reach es es.length e.blockedOn).contains e.id

def coherent (es : List Epic) (ds : List Decision) (gs : List Gap) : Bool :=
  es.all (fun e => e.blockedOn.all (known es ds)) &&
  acyclic es &&
  es.all (fun e => e.status != .done || e.blockedOn.all (settled es ds)) &&
  es.all (fun e => e.status != .blocked || e.blockedOn.any (fun b => !settled es ds b)) &&
  ds.all (·.valid) &&
  gs.all (fun g => match epicOf es g.closesWith with
    | some e => e.status != .done
    | none => false)

-- What the rules refuse, on stand-ins.

/-- Two epics waiting on each other. -/
example : acyclic [{ id := "a", status := .approved, blockedOn := ["b"] },
                   { id := "b", status := .approved, blockedOn := ["a"] }] = false := by
  decide

/-- An epic done before its blocker. -/
example : coherent [{ id := "a", status := .done, blockedOn := ["b"] },
                    { id := "b", status := .approved, blockedOn := [] }] [] [] = false := by
  decide

/-- A blocker nobody declared. -/
example : coherent [{ id := "a", status := .approved, blockedOn := ["ghost"] }] [] [] = false := by
  decide

/-- A gap whose closing epic is already done. -/
example : coherent [{ id := "a", status := .done, blockedOn := [] }] []
    [{ id := "g", closesWith := "a" }] = false := by
  decide

end Kagamizo.Project
