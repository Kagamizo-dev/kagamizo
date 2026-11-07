/-
Performance records (modules/perf). Every measured target carries a
record: the best time known for it, in milliseconds, and the tolerance a
new measurement may exceed it by before the build fails. A measurement is
`fine` when it is within the record's tolerance, and `beats` when it is
faster than the record; ../default.nix renders the committed records and
the last measurements into `declared` and has Lean decide the rule for
every one. The lemmas say what the rule guarantees for any record, in the
Mathlib style: a definition, then its consequences as separate theorems.
-/
namespace Kagamizo.Perf

/-- A measured target: what it is, its best known time, how much slower a
measurement may be, and the latest measurement. Times in milliseconds. -/
structure Record where
  target : String
  module : String
  kind : String
  recordMs : Nat
  tolerancePercent : Nat
  measuredMs : Nat
  deriving Repr, DecidableEq

/-- The most a measurement may take and still be within tolerance. -/
def Record.limitMs (r : Record) : Nat := r.recordMs + r.recordMs * r.tolerancePercent / 100

/-- The rule: the latest measurement is within the record's tolerance. -/
def Record.fine (r : Record) : Bool := r.measuredMs ≤ r.limitMs

/-- A measurement that beats the record (the record is then moved). -/
def Record.beats (r : Record) : Bool := r.measuredMs < r.recordMs

/-- A record is never below 1 ms, so a tolerance of 0 is a real bound. -/
def Record.sane (r : Record) : Bool := r.recordMs > 0 && r.tolerancePercent ≤ 100

/-- Within tolerance means at most record × (1 + tolerance). -/
theorem fine_le (r : Record) (h : r.fine = true) : r.measuredMs ≤ r.limitMs := by
  simpa [Record.fine] using h

/-- Beating the record is within tolerance. -/
theorem beats_fine (r : Record) (h : r.beats = true) : r.fine = true := by
  simp only [Record.beats, decide_eq_true_eq] at h
  simp only [Record.fine, Record.limitMs, decide_eq_true_eq]
  omega

/-- With zero tolerance, within tolerance is exactly "no slower than the record". -/
theorem fine_zero (r : Record) (h0 : r.tolerancePercent = 0) :
    r.fine = true ↔ r.measuredMs ≤ r.recordMs := by
  simp [Record.fine, Record.limitMs, h0]

end Kagamizo.Perf
