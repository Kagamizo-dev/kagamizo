/-
Delegated work never spends past what its owner is allotted. Each unit has
a hard cap in cents (the runner stops the moment the provider's reported
cost would pass it); each owner agent has a monthly share of its key
(../../agents: budgetUsdPerMonth). Lean decides, over every declared unit,
that each cap fits its owner's share and that one owner's caps together do.
-/
namespace Kagamizo.Unit

structure Unit where
  id : String
  owner : String
  maxCents : Nat
  maxSteps : Nat

structure Share where
  owner : String
  cents : Nat

def shareOf (ss : List Share) (o : String) : Nat :=
  ((ss.find? (·.owner == o)).map (·.cents)).getD 0

def spentBy (us : List Unit) (o : String) : Nat :=
  ((us.filter (·.owner == o)).map (·.maxCents)).sum

def within (ss : List Share) (us : List Unit) : Bool :=
  us.all (fun u => decide (u.maxCents ≤ shareOf ss u.owner) && decide (u.maxSteps > 0)) &&
  ss.all (fun s => decide (spentBy us s.owner ≤ s.cents))

/-- In a declared set within its shares, no single unit can outspend its
owner's share. -/
theorem unit_within (ss : List Share) (us : List Unit) (h : within ss us = true)
    (u : Unit) (hu : u ∈ us) : u.maxCents ≤ shareOf ss u.owner := by
  simp only [within, Bool.and_eq_true] at h
  have := List.all_eq_true.mp h.1 u hu
  simp only [Bool.and_eq_true, decide_eq_true_eq] at this
  exact this.1

-- What the rule refuses, on stand-ins.
example : within [{ owner := "pm", cents := 100 }]
    [{ id := "a", owner := "pm", maxCents := 150, maxSteps := 5 }] = false := by decide
example : within [{ owner := "pm", cents := 100 }]
    [{ id := "a", owner := "pm", maxCents := 60, maxSteps := 5 },
     { id := "b", owner := "pm", maxCents := 60, maxSteps := 5 }] = false := by decide

end Kagamizo.Unit
