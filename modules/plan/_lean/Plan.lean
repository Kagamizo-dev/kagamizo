/-
The plan (../plan.nix): the one source of truth for what is being built,
in what order, by which team, and what waits on the owner. Lean decides it
is coherent: every item's track and dependencies exist; the dependencies
have no cycle, so there is an order to do everything in; an item waiting
on the owner's decision names an open decision; every open decision
blocks something; every brief in the teams' backlog belongs to exactly one
item, so nothing is dispatched that the plan does not hold.
-/
namespace Kagamizo.Plan

inductive Status where
  | queued | active | done
  deriving DecidableEq, Repr

inductive Blocked where
  | none | ownerDecision | ownerAction | credit | hardware | upstream
  deriving DecidableEq, Repr

structure Item where
  id : String
  track : String
  status : Status
  blocked : Blocked
  decision : String
  deps : List String
  backlog : String
  deriving DecidableEq, Repr

structure Decision where
  id : String
  isOpen : Bool
  deriving DecidableEq, Repr

def unique : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && unique xs

/-- Take, round by round, every item whose dependencies are all taken. -/
def settle (items : List Item) : Nat → List String → List String
  | 0, taken => taken
  | n + 1, taken =>
    let next := (items.filter fun i => !taken.contains i.id && i.deps.all taken.contains).map (·.id)
    if next.isEmpty then taken else settle items n (taken ++ next)

/-- There is an order to do everything in: settling takes every item. -/
def ordered (items : List Item) : Bool :=
  (settle items items.length []).length == items.length

def itemOk (tracks : List String) (decisions : List Decision) (ids : List String) (i : Item) : Bool :=
  tracks.contains i.track &&
  i.deps.all ids.contains &&
  (i.blocked != .ownerDecision || decisions.any fun d => d.id == i.decision && d.isOpen) &&
  (i.decision.isEmpty || decisions.any (·.id == i.decision)) &&
  (i.status != .done || i.blocked == .none)

def sound (tracks : List String) (decisions : List Decision) (items : List Item) (backlog : List String) : Bool :=
  let ids := items.map (·.id)
  unique ids && unique (decisions.map (·.id)) &&
  items.all (itemOk tracks decisions ids) &&
  ordered items &&
  decisions.all (fun d => !d.isOpen || items.any (·.decision == d.id)) &&
  backlog.all (fun b => (items.filter (·.backlog == b)).length == 1)

/-- In a sound plan, an item waiting on the owner names a decision that is
still open: nothing waits on a question already answered. -/
theorem waits_on_open (tracks : List String) (decisions : List Decision) (ids : List String) (i : Item)
    (h : itemOk tracks decisions ids i = true) (hb : i.blocked = .ownerDecision) :
    decisions.any (fun d => d.id == i.decision && d.isOpen) = true := by
  unfold itemOk at h
  simp [hb] at h
  simp [h]

end Kagamizo.Plan
