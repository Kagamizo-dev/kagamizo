/-
The trading limits (modules/trading/limits.nix), as the owner set them on
2026-11-02 and extended for event contracts on 2026-11-04: defined-risk
trades only (a long option, a debit spread, an event contract bought
outright, or spot crypto bought with cash (2026-11-08), each losing at most
what was paid), a seed, the most one trade
may lose, one open position, a stop for the day and a take-profit for the
day. `admissible` is the rule every proposal is held to before Public's
preflight; the theorems are what it guarantees, whatever the strategy
proposes. ../limits.nix renders the declared limits after this file and
Lean decides they are sane.
-/
namespace Kagamizo.Risk

/-- What a trade may be: each has a known worst case at entry. An event
contract bought YES or NO settles at 1 or 0, so it loses at most its
price. -/
inductive Kind where
  | longCall
  | longPut
  | debitSpread
  | eventYes
  | eventNo
  /-- Spot crypto bought with cash (no margin, never short): it loses at
  most the amount paid and its fee. -/
  | cryptoLong
  deriving DecidableEq, Repr

structure Limits where
  seedUsd : Nat
  maxPremiumUsd : Nat
  /-- The most one event-contract order may cost (price × quantity); the
  rendered sanity check keeps it within maxPremiumUsd, so an order within
  it is within the cap. -/
  maxContractPriceUsd : Nat
  maxOpenPositions : Nat
  dailyLossStopUsd : Nat
  /-- Once the day has gained this much, nothing more is proposed. -/
  dailyTakeProfitUsd : Nat
  allowed : List Kind
  deriving Repr

/-- A proposed order: its kind and its worst case, the premium paid (a
long option, a debit spread or a bought event contract can lose no more
than its cost). -/
structure Order where
  kind : Kind
  maxLossUsd : Nat
  deriving Repr

/-- Where the day stands when the order is proposed. -/
structure Day where
  openPositions : Nat
  lossUsd : Nat
  gainUsd : Nat
  deriving Repr

def admissible (l : Limits) (d : Day) (o : Order) : Bool :=
  l.allowed.contains o.kind
  && o.maxLossUsd ≤ l.maxPremiumUsd
  && d.openPositions < l.maxOpenPositions
  && d.lossUsd < l.dailyLossStopUsd
  && d.gainUsd < l.dailyTakeProfitUsd

/-- The five conjuncts of an admissible order, as propositions. -/
theorem admissible_parts (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) :
    o.kind ∈ l.allowed ∧ o.maxLossUsd ≤ l.maxPremiumUsd ∧
    d.openPositions < l.maxOpenPositions ∧ d.lossUsd < l.dailyLossStopUsd ∧
    d.gainUsd < l.dailyTakeProfitUsd := by
  simp only [admissible, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨⟨⟨hk, hc⟩, hp⟩, hl⟩, hg⟩ := h
  exact ⟨List.contains_iff_mem.mp hk, hc, hp, hl, hg⟩

/-- An admissible order can lose at most the premium cap. -/
theorem admissible_loss_capped (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) : o.maxLossUsd ≤ l.maxPremiumUsd :=
  (admissible_parts l d o h).2.1

/-- An admissible order is of an allowed kind. -/
theorem admissible_allowed (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) : o.kind ∈ l.allowed :=
  (admissible_parts l d o h).1

/-- Even if an admissible order then loses everything, the day's loss stays
under the stop plus one premium cap: the stop bounds what was lost before,
the cap bounds the order. -/
theorem day_loss_bounded (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) :
    d.lossUsd + o.maxLossUsd < l.dailyLossStopUsd + l.maxPremiumUsd := by
  have := admissible_parts l d o h
  omega

/-- Once the stop is reached, nothing is admissible. -/
theorem stopped_day_refuses (l : Limits) (d : Day) (o : Order)
    (hs : l.dailyLossStopUsd ≤ d.lossUsd) : admissible l d o = false := by
  unfold admissible
  have : (d.lossUsd < l.dailyLossStopUsd) = False := by
    simp; omega
  simp [this]

/-- Once the take-profit is reached, nothing is admissible: a day that has
made its gain is over, whatever the edge. -/
theorem taken_profit_day_refuses (l : Limits) (d : Day) (o : Order)
    (ht : l.dailyTakeProfitUsd ≤ d.gainUsd) : admissible l d o = false := by
  unfold admissible
  have : (d.gainUsd < l.dailyTakeProfitUsd) = False := by
    simp; omega
  simp [this]

/-- So an admissible order was proposed on a day still under its
take-profit: the day's gain before it is below the declared cap. -/
theorem admissible_under_take_profit (l : Limits) (d : Day) (o : Order)
    (h : admissible l d o = true) : d.gainUsd < l.dailyTakeProfitUsd :=
  (admissible_parts l d o h).2.2.2.2

/-- With one position open and the limit one, nothing more is admissible. -/
theorem full_book_refuses (l : Limits) (d : Day) (o : Order)
    (hp : l.maxOpenPositions ≤ d.openPositions) : admissible l d o = false := by
  unfold admissible
  have : (d.openPositions < l.maxOpenPositions) = False := by
    simp; omega
  simp [this]

end Kagamizo.Risk
