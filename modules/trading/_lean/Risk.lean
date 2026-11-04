/-
The trading limits (modules/trading/limits.nix), as the owner set them on
2026-11-02: defined-risk options only, a seed, the most one trade may lose,
one open position, and a stop for the day. `admissible` is the rule every
proposal is held to before Public's preflight; the theorems are what it
guarantees, whatever the strategy proposes. ../limits.nix renders the
declared limits after this file and Lean decides they are sane.
-/
namespace Kagamizo.Risk

/-- What a trade may be: each has a known worst case at entry. -/
inductive Kind where
  | longCall
  | longPut
  | debitSpread
  deriving DecidableEq, Repr

structure Limits where
  seedUsd : Nat
  maxPremiumUsd : Nat
  maxOpenPositions : Nat
  dailyLossStopUsd : Nat
  allowed : List Kind
  deriving Repr

/-- A proposed order: its kind and its worst case, the premium paid (a
long option or a debit spread can lose no more than its cost). -/
structure Order where
  kind : Kind
  maxLossUsd : Nat
  deriving Repr

/-- Where the day stands when the order is proposed. -/
structure Day where
  openPositions : Nat
  lossUsd : Nat
  deriving Repr

def admissible (l : Limits) (d : Day) (o : Order) : Bool :=
  l.allowed.contains o.kind
  && o.maxLossUsd ≤ l.maxPremiumUsd
  && d.openPositions < l.maxOpenPositions
  && d.lossUsd < l.dailyLossStopUsd

/-- An admissible order can lose at most the premium cap. -/
theorem admissible_loss_capped (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) : o.maxLossUsd ≤ l.maxPremiumUsd := by
  unfold admissible at h
  have h1 := (Bool.and_eq_true _ _).mp h |>.1
  have h2 := (Bool.and_eq_true _ _).mp h1 |>.1
  have h3 := (Bool.and_eq_true _ _).mp h2 |>.2
  exact of_decide_eq_true h3

/-- An admissible order is of an allowed kind. -/
theorem admissible_allowed (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) : o.kind ∈ l.allowed := by
  unfold admissible at h
  have h1 := (Bool.and_eq_true _ _).mp h |>.1
  have h2 := (Bool.and_eq_true _ _).mp h1 |>.1
  have h3 := (Bool.and_eq_true _ _).mp h2 |>.1
  exact List.contains_iff_mem.mp h3

/-- Even if an admissible order then loses everything, the day's loss stays
under the stop plus one premium cap: the stop bounds what was lost before,
the cap bounds the order. -/
theorem day_loss_bounded (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) :
    d.lossUsd + o.maxLossUsd < l.dailyLossStopUsd + l.maxPremiumUsd := by
  unfold admissible at h
  have h1 := (Bool.and_eq_true _ _).mp h
  have h2 := (Bool.and_eq_true _ _).mp h1.1
  have h3 := (Bool.and_eq_true _ _).mp h2.1
  have hloss : d.lossUsd < l.dailyLossStopUsd := of_decide_eq_true h1.2
  have hcap : o.maxLossUsd ≤ l.maxPremiumUsd := of_decide_eq_true h3.2
  omega

/-- Once the stop is reached, nothing is admissible. -/
theorem stopped_day_refuses (l : Limits) (d : Day) (o : Order)
    (hs : l.dailyLossStopUsd ≤ d.lossUsd) : admissible l d o = false := by
  unfold admissible
  have : (d.lossUsd < l.dailyLossStopUsd) = False := by
    simp; omega
  simp [this]

/-- With one position open and the limit one, nothing more is admissible. -/
theorem full_book_refuses (l : Limits) (d : Day) (o : Order)
    (hp : l.maxOpenPositions ≤ d.openPositions) : admissible l d o = false := by
  unfold admissible
  have : (d.openPositions < l.maxOpenPositions) = False := by
    simp; omega
  simp [this]

end Kagamizo.Risk
