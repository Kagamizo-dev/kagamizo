/-
Who owns what (modules/organization/areas.nix): every area of work is an
entity's mailbox role, owned by one agent team of that entity, reviewed by
others, and signed off by the entity's controller. ../areas.nix renders
the declarations after this file; Lean decides that no team reviews its
own work, that an area proposes only what its owner may, and that every
change class someone may merge has an area that owns it.
-/
namespace Kagamizo.Areas

structure Area where
  entity : String
  mailbox : String
  owner : Option String
  reviewers : List String
  classes : List String
  /-- The owner's own change classes (modules/governance): what it may propose. -/
  ownerClasses : List String
  deriving DecidableEq, Repr

/-- No team reviews what it owns. -/
def Area.separated (a : Area) : Bool :=
  match a.owner with
  | some o => !a.reviewers.contains o
  | none => true

/-- An area proposes only what its owner may. -/
def Area.scoped (a : Area) : Bool := a.classes.all a.ownerClasses.contains

/-- A class is covered when some area owns it. -/
def covered (areas : List Area) (cls : String) : Bool :=
  areas.any fun a => a.owner.isSome && a.classes.contains cls

/-- A separated area with an owner never names that owner among its reviewers. -/
theorem separated_owner_not_reviewer (a : Area) (o : String) (ho : a.owner = some o)
    (h : a.separated = true) : o ∉ a.reviewers := by
  unfold Area.separated at h
  rw [ho] at h
  simpa using h

/-- A scoped area's every class is one its owner may propose. -/
theorem scoped_sub (a : Area) (h : a.scoped = true) : ∀ c ∈ a.classes, c ∈ a.ownerClasses := by
  intro c hc
  have := List.all_eq_true.mp h c hc
  simpa using this

end Kagamizo.Areas
