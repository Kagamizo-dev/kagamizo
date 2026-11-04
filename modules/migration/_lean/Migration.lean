/-
Leaving a provider (modules/migration). An account being retired holds
classes of data, each moved to a destination and checked, and dependants
(logins, autopays, deposits, 2FA) that move elsewhere first. It may be
closed only when every class is verified and every dependant moved; the
theorems say what that rule guarantees for any account, and ../default.nix
has Lean decide it for every declared one.
-/
namespace Kagamizo.Migration

inductive State where
  | declared
  | exported
  | imported
  | verified
  deriving DecidableEq, Repr

inductive Destination where
  | protonMail
  | protonContacts
  | protonCalendar
  | protonDrive
  | protonPass
  | ledger
  | inventory
  | reDeclared
  | nowhere
  deriving DecidableEq, Repr

structure Dependant where
  kind : String
  done : Bool
  deriving Repr

structure Source where
  account : String
  closed : Bool
  classes : List (String × State × Destination)
  dependants : List Dependant
  deriving Repr

def Source.emptied (s : Source) : Bool :=
  s.classes.all (fun c => c.2.1 == .verified) && s.dependants.all (·.done)

/-- The rule: closed only when emptied. -/
def Source.closedRightly (s : Source) : Bool := !s.closed || s.emptied

/-- A closed account had every class verified. -/
theorem closed_verified (s : Source) (h : s.closedRightly = true) (hc : s.closed = true) :
    ∀ c ∈ s.classes, c.2.1 = .verified := by
  intro c hm
  simp only [Source.closedRightly, hc, Bool.not_true, Bool.false_or, Source.emptied,
    Bool.and_eq_true, List.all_eq_true, beq_iff_eq] at h
  exact h.1 c hm

/-- A closed account had every dependant moved. -/
theorem closed_dependants_moved (s : Source) (h : s.closedRightly = true) (hc : s.closed = true) :
    ∀ d ∈ s.dependants, d.done = true := by
  intro d hm
  simp only [Source.closedRightly, hc, Bool.not_true, Bool.false_or, Source.emptied,
    Bool.and_eq_true, List.all_eq_true] at h
  exact h.2 d hm

end Kagamizo.Migration
