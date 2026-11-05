/-
Money flows between held accounts (modules/money/_flows.nix). A flow is
typed by the owners of its two accounts and by what it is between them;
the rules: an inter-entity flow is booked (a contribution into a company or
a draw out of it), a personal flow stays with one owner, and nothing is
executable without the owner's dated approval. ../_flows.nix renders the
declarations and Lean decides them.
-/
namespace Kagamizo.Money

inductive FlowKind where
  | personal
  | contribution
  | draw
  | transfer
  | sweep
  deriving DecidableEq, Repr

structure Flow where
  name : String
  fromOwner : String
  toOwner : String
  kind : FlowKind
  /-- approvedBy is a date. -/
  approved : Bool
  deriving Repr

/-- Between two owners, money is booked: a contribution or a draw. -/
def FlowKind.booksBetweenEntities : FlowKind → Bool
  | .contribution | .draw => true
  | _ => false

/-- Booked right: contribution or draw exactly when the owners differ. -/
def Flow.booked (f : Flow) : Bool :=
  (f.fromOwner != f.toOwner) == f.kind.booksBetweenEntities

/-- Executable: approved, and booked right. -/
def Flow.executable (f : Flow) : Bool := f.approved && f.booked

/-- A flow between different owners that is booked is a contribution or a draw. -/
theorem inter_entity_is_booked (f : Flow) (h : f.booked = true) (hne : f.fromOwner != f.toOwner) :
    f.kind = .contribution ∨ f.kind = .draw := by
  unfold Flow.booked at h
  rw [hne] at h
  cases hk : f.kind <;> simp [hk, FlowKind.booksBetweenEntities] at h <;> simp

/-- A personal flow that is booked stays within one owner. -/
theorem personal_stays_home (f : Flow) (h : f.booked = true) (hp : f.kind = .personal) :
    f.fromOwner = f.toOwner := by
  unfold Flow.booked at h
  rw [hp] at h
  simp [FlowKind.booksBetweenEntities] at h
  exact h

/-- Without approval, a flow is never executable. -/
theorem unapproved_never_executable (f : Flow) (h : f.approved = false) :
    f.executable = false := by
  simp [Flow.executable, h]

end Kagamizo.Money
