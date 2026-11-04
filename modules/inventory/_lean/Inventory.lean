/-
The inventory's ledger rules. The items themselves are private (a document
in the owner's vault, kept by statestore), so Lean never sees them: it
proves the operations the Rust CLI (../_src) runs on every item, over the
same representation, a quantity in whole hundredths (a Nat):

  * `use` never takes more than there is: it refuses, or leaves the
    difference, never a negative stock;
  * `restock` only grows the stock;
  * an item is low exactly when its stock is at or below its reorder point,
    and using some of a low item keeps it low.

../default.nix appends the declared schema (categories, places, currencies)
and Lean decides it is well formed: non-empty, no duplicates.
-/
namespace Kagamizo.Inventory

/-- Take `n` hundredths from a stock of `q`; none when there is not enough. -/
def use (q n : Nat) : Option Nat :=
  if n ≤ q then some (q - n) else none

def restock (q n : Nat) : Nat := q + n

def low (q reorderAt : Nat) : Bool := decide (q ≤ reorderAt)

theorem use_within (q n r : Nat) (h : use q n = some r) : r ≤ q ∧ r + n = q := by
  unfold use at h
  split at h
  · cases h; omega
  · contradiction

theorem use_refuses_overdraw (q n : Nat) (h : q < n) : use q n = none := by
  unfold use
  simp [Nat.not_le.mpr h]

theorem restock_grows (q n : Nat) : q ≤ restock q n := by
  unfold restock; omega

theorem low_stays_low (q n r reorderAt : Nat) (hl : low q reorderAt = true)
    (h : use q n = some r) : low r reorderAt = true := by
  have := use_within q n r h
  simp only [low, decide_eq_true_eq] at *
  omega

/-- A schema list is usable: something to choose, nothing twice. -/
def wellFormed (xs : List String) : Bool := !xs.isEmpty && xs.eraseDups.length == xs.length

example : wellFormed ["a", "a"] = false := by decide
example : wellFormed [] = false := by decide

end Kagamizo.Inventory
