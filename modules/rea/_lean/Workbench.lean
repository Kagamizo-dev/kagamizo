/-
The reverse-engineering workbench (../workbench.nix): what may be taken
apart, and where the tools go. The Nix types already confine a subject to a
declared owner and to the allowed purposes (interoperability, porting,
repair, security research, the catalog: none for defeating DRM, anti-cheat
or a licence check). Lean adds what a type cannot say alone: every subject
has a purpose; a device or a service is the owner's own, never someone
else's; and every tool goes only on our own images.
-/
namespace Kagamizo.Workbench

inductive Kind where
  | software | device | protocol | service
  deriving DecidableEq, Repr

inductive Licence where
  | owned | licensed | openSource
  deriving DecidableEq, Repr

structure Subject where
  name : String
  kind : Kind
  owner : String
  licence : Licence
  /-- How many declared purposes it has. -/
  purposes : Nat
  deriving DecidableEq, Repr

structure Tool where
  name : String
  targets : List String
  deriving DecidableEq, Repr

/-- A subject may be worked on: it has a purpose, and a device or a service
is owned by its declared owner (a service of someone else's is never a
subject). -/
def allowed (s : Subject) : Bool :=
  decide (0 < s.purposes) &&
  (if s.kind == .device || s.kind == .service then s.licence == .owned else true)

def sound (subjects : List Subject) (tools : List Tool) (images : List String) : Bool :=
  subjects.all allowed && tools.all fun t => !t.targets.isEmpty && t.targets.all images.contains

/-- An allowed service is the owner's own. -/
theorem service_is_owned (s : Subject) (h : allowed s = true) (hk : s.kind = .service) :
    s.licence = .owned := by
  unfold allowed at h
  simp [hk] at h
  exact h.2

/-- An allowed device is the owner's own. -/
theorem device_is_owned (s : Subject) (h : allowed s = true) (hk : s.kind = .device) :
    s.licence = .owned := by
  unfold allowed at h
  simp [hk] at h
  exact h.2

end Kagamizo.Workbench
