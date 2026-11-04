/-
What the agents may spend (modules/agents/tiers.nix): every task runs on
the cheapest tier that can do it, and the tiers that cost nothing (rules,
a small model on the host) are the only ones a rank-0 or rank-1 task may
reach. The OpenRouter keys' caps, per month, add up to no more than the
card that pays them. ../tiers.nix renders the declarations after this file
and Lean decides both.
-/
namespace Kagamizo.Budget

structure Tier where
  name : String
  rank : Nat
  paid : Bool
  deriving DecidableEq, Repr

structure Task where
  kind : String
  tier : Tier
  deriving DecidableEq, Repr

/-- A task on a rank-0 or rank-1 tier never costs anything. -/
def Task.frugal (t : Task) : Bool := t.tier.rank ≥ 2 || !t.tier.paid

structure Key where
  name : String
  monthlyUsd : Nat
  deriving DecidableEq, Repr

def keysWithin (keys : List Key) (cardMonthlyUsd : Nat) : Bool :=
  (keys.map Key.monthlyUsd).sum ≤ cardMonthlyUsd

theorem le_sum_of_mem : ∀ {l : List Nat} {x : Nat}, x ∈ l → x ≤ l.sum
  | [], _, h => nomatch h
  | y :: ys, x, h => by
    simp only [List.sum_cons]
    rcases List.mem_cons.mp h with rfl | h'
    · exact Nat.le_add_right _ _
    · exact Nat.le_trans (le_sum_of_mem h') (Nat.le_add_left _ _)

/-- When the caps fit the card together, each one fits alone: no single key
can ever drain more than the card allows. -/
theorem within_means_each (keys : List Key) (card : Nat)
    (h : keysWithin keys card = true) : ∀ k ∈ keys, k.monthlyUsd ≤ card := by
  intro k hk
  have hs : (keys.map Key.monthlyUsd).sum ≤ card := by
    simpa [keysWithin] using h
  exact Nat.le_trans (le_sum_of_mem (List.mem_map_of_mem hk)) hs

/-- A frugal task on a paid tier has rank at least 2: the paid tiers are
reachable only from rank 2 up. -/
theorem frugal_paid_rank (t : Task) (h : t.frugal = true) (hp : t.tier.paid = true) :
    t.tier.rank ≥ 2 := by
  simp [Task.frugal, hp] at h
  exact h

end Kagamizo.Budget
