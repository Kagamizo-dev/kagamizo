/-
The repository's languages (modules/repo/languages.nix): the code we author
is Rust, Lean or Nix, and every file that breaks that today is a dated
exception owned by a team. ../languages.nix renders the exceptions and the
baseline after this file; Lean decides that every exception has a declared
owner and a date, and that neither the exceptions nor their inline-code
markers exceed the baseline, so the backlog can only shrink.
-/
namespace Kagamizo.Languages

structure Exception where
  path : String
  owner : String
  dated : Bool
  markers : Nat
  deriving DecidableEq, Repr

structure Baseline where
  exceptions : Nat
  markers : Nat
  deriving DecidableEq, Repr

/-- Every exception names a declared team and lapses on a date. -/
def sound (teams : List String) (es : List Exception) : Bool :=
  es.all fun e => teams.contains e.owner && e.dated

/-- The inline-code markers the exceptions still allow. -/
def markerTotal (es : List Exception) : Nat :=
  es.foldl (fun n e => n + e.markers) 0

/-- The backlog stays within the baseline, in files and in markers. -/
def withinBaseline (b : Baseline) (es : List Exception) : Bool :=
  decide (es.length ≤ b.exceptions) && decide (markerTotal es ≤ b.markers)

/-- Closing an exception never breaks the baseline: dropping one keeps the
file count within it. -/
theorem drop_keeps_count (b : Baseline) (e : Exception) (es : List Exception)
    (h : (e :: es).length ≤ b.exceptions) : es.length ≤ b.exceptions := by
  simp at h
  omega

end Kagamizo.Languages
