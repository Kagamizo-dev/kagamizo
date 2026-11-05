/-
The universe is bounded. Every recurring cost is drawn on exactly one
Mercury card (../default.nix renders the cards, each normalised to cents per
month); the draw on a card is what actually bills it — the OpenRouter keys'
caps, an infrastructure budget, or the subscription the card is for. Lean
decides that every card's draw fits its limit, so nothing is committed that
a card does not cover, and the sum of the limits is the whole monthly
ceiling the report prints.
-/
namespace Kagamizo.Cost

structure Card where
  name : String
  limitCents : Nat
  drawCents : Nat

def fits (c : Card) : Bool := decide (c.drawCents ≤ c.limitCents)

def bounded (cards : List Card) : Bool := cards.all fits

def ceilingCents (cards : List Card) : Nat := (cards.map (·.limitCents)).sum

def committedCents (cards : List Card) : Nat := (cards.map (·.drawCents)).sum

/-- When every card is within its limit, the total committed never exceeds
the total ceiling: the universe cannot cost more than the cards allow. -/
theorem committed_within_ceiling (cards : List Card) (h : bounded cards = true) :
    committedCents cards ≤ ceilingCents cards := by
  unfold committedCents ceilingCents
  induction cards with
  | nil => simp
  | cons c rest ih =>
    simp only [bounded, List.all_cons, Bool.and_eq_true] at h
    simp only [List.map_cons, List.sum_cons]
    have hc : c.drawCents ≤ c.limitCents := by
      have := h.1; unfold fits at this; exact decide_eq_true_iff.mp this
    exact Nat.add_le_add hc (ih h.2)

-- A card drawn past its limit is refused.
example : bounded [{ name := "x", limitCents := 100, drawCents := 150 }] = false := by decide
example : bounded [{ name := "x", limitCents := 200, drawCents := 125 }] = true := by decide

end Kagamizo.Cost
